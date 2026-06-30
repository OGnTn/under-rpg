@tool
extends EditorScript

## Path to the recipe registry.
const RECIPES_PATH := "res://recipes.tres"
## Where to write the output text file.
const OUTPUT_PATH := "res://recipes_export.txt"


func _build_ingredient_list(ingredients: Array) -> String:
	var parts: Array[String] = []
	for ing in ingredients:
		if not ing or not ing.item:
			continue
		var qty: int = ing.quantity if ing.quantity > 1 else 1
		if qty > 1:
			parts.append("%dx %s" % [qty, ing.item.name])
		else:
			parts.append(ing.item.name)
	return " + ".join(parts) if not parts.is_empty() else "(nothing)"


func _run() -> void:
	var registry: Resource = load(RECIPES_PATH)
	if not registry:
		printerr("Failed to load registry at: ", RECIPES_PATH)
		return

	var string_ids: Array = registry.get_all_string_ids()
	if string_ids.is_empty():
		printerr("No recipes found in registry.")
		return

	var lines: Array[String] = []
	lines.append("=== Crafting Recipes ===\n")

	# Group by station
	var manual_recipes: Array = []
	var station_recipes: Dictionary = {}

	for id in string_ids:
		var recipe: Resource = registry.load_entry(id)
		if not recipe:
			continue
		var station: String = recipe.get("station") if recipe.get("station") else "manual"
		if station == "manual":
			manual_recipes.append(recipe)
		else:
			if not station_recipes.has(station):
				station_recipes[station] = []
			station_recipes[station].append(recipe)

	# Manual recipes
	if not manual_recipes.is_empty():
		lines.append("--- Manual Crafting (no station) ---\n")
		for recipe in manual_recipes:
			var ing_str := _build_ingredient_list(recipe.ingredients)
			var res_str := _build_ingredient_list(recipe.results)
			lines.append("%s = %s" % [ing_str, res_str])

	# Station recipes
	for station_name in station_recipes:
		lines.append("\n--- %s ---\n" % station_name.capitalize())
		for recipe in station_recipes[station_name]:
			var ing_str := _build_ingredient_list(recipe.ingredients)
			var res_str := _build_ingredient_list(recipe.results)
			lines.append("%s = %s" % [ing_str, res_str])

	var full_text := "\n".join(lines)

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if not file:
		printerr("Failed to open output file: ", OUTPUT_PATH)
		return
	file.store_string(full_text)
	file.close()

	print("Recipes exported to: ", OUTPUT_PATH)
	print(full_text)
