extends Node

signal recipe_unlocked(recipe: CraftingRecipe)

var a_recipe_database: Array[CraftingRecipe] = []
var unlocked_recipes: Array[CraftingRecipe] = []

func _ready() -> void:
	_load_all_recipes()
	
	# Connect to global player/inventory signals if possible.
	# For now, we expect other systems to call check_unlocks().
	pass

func _load_all_recipes() -> void:
	var recipe_path = "res://resources/recipes/"
	var dir = DirAccess.open(recipe_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !file_name.begins_with(".") and file_name.ends_with(".tres"):
				var recipe = load(recipe_path + file_name)
				if recipe is CraftingRecipe:
					a_recipe_database.append(recipe)
					print("Loaded recipe: " + recipe.name)
					# For debugging, unlock everything immediately or uncomment below
					# unlock_recipe(recipe) 
			file_name = dir.get_next()
	else:
		print("An error occurred when trying to access the path.")

func check_unlocks(item: InventoryItem) -> void:
	for recipe in a_recipe_database:
		if recipe in unlocked_recipes:
			continue
			
		# Check if this new item is one of the ingredients
		# Logic: If you pick up an ingredient, you unlock the recipe.
		# This is a bit generous; usually you need ALL ingredients? 
		# The prompt says: "Obtaining logs unlocks the recipe for planks". 
		# It implies getting the input unlocks it.
		# But "whenever all the input items are obtained for the first time".
		# This requires tracking "obtained_items" history.
		
		# Since we don't have persistence yet, we will just check against current inventory?
		# No, "obtained for the first time" implies a history check.
		# For this implementation without save data, I'll assume we unlock if we HAVE the item in inventory
		# OR if we have ever touched it.
		
		# For MVP: If you obtain an item that is an ingredient for a recipe, we check if you have ALL ingredients now.
		# If you have ALL ingredients (or have had them? logic is easier if we just check 'can_craft' logic but for unlocking)
		
		# Re-reading prompt: "Recipes are automatically unlocked whenever all the input items are obtained for the first time"
		# This implies I need to track "discovered_items".
		
		if _has_discovered_all_ingredients(recipe, item):
			unlock_recipe(recipe)

# Temporary memory set of discovered items
var discovered_items: Array[InventoryItem] = []

func register_item_discovery(item: InventoryItem):
	if item not in discovered_items:
		discovered_items.append(item)
		check_unlocks(item)

func _has_discovered_all_ingredients(recipe: CraftingRecipe, just_obtained: InventoryItem) -> bool:
	# Optimization: If the just_obtained item is NOT in the recipe, ignore.
	var is_relevant = false
	for ing in recipe.ingredients:
		if ing.item == just_obtained:
			is_relevant = true
			break
	
	if not is_relevant:
		return false
		
	for ing in recipe.ingredients:
		if ing.item not in discovered_items:
			return false
	return true

func unlock_recipe(recipe: CraftingRecipe):
	if recipe not in unlocked_recipes:
		unlocked_recipes.append(recipe)
		recipe_unlocked.emit(recipe)
		print("Unlocked recipe: " + recipe.name)

func craft(recipe: CraftingRecipe, inventories: Array[Inventory]) -> bool:
	if !can_craft(recipe, inventories):
		return false
	
	# Consume ingredients
	for ing in recipe.ingredients:
		var amount_needed = ing.quantity
		for inv in inventories:
			if amount_needed <= 0: break
			if inv:
				var amount_removed = _consume_item(inv, ing.item, amount_needed)
				amount_needed -= amount_removed
		
		# Sanity check: if we didn't remove enough (shouldn't happen if can_craft passed)
		if amount_needed > 0:
			printerr("Crafting error: Failed to consume enough " + ing.item.name)
		
	# Add results to PRIMARY inventory (first one in list)
	var primary_inv = inventories[0]
	if primary_inv:
		for res in recipe.results:
			var left_over = primary_inv.obtain_item(ItemStack.new(res.item, res.quantity))
			if left_over:
				# Handle dropping to ground or error? 
				pass
			
	return true

func can_craft(recipe: CraftingRecipe, inventories: Array[Inventory]) -> bool:
	for ing in recipe.ingredients:
		var total_count = 0
		for inv in inventories:
			if inv:
				total_count += inv.get_item_count(ing.item)
		
		if total_count < ing.quantity:
			return false
	return true

func _consume_item(inventory: Inventory, item: InventoryItem, amount: int) -> int:
	# Returns amount actually consumed
	return inventory.consume_item(item, amount)
