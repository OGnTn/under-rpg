extends Control

@export var recipe_card_scene: PackedScene
@export var item_cell_scene: PackedScene
@export var inventory: Inventory # The player inventory to check against

@onready var recipe_container: VBoxContainer = %RecipeListContainer

# Can be set to filter by station (e.g. "workbench")
var current_station_filter: String = "manual"
var external_inventory: Inventory = null

func _ready():
	CraftingManager.recipe_unlocked.connect(_on_recipe_unlocked)
	# Connect to inventory updates to refresh craftable status
	if inventory:
		inventory.inventory_updated.connect(refresh_list)
		
	refresh_list()

func set_inventory(inv: Inventory):
	if inventory:
		inventory.inventory_updated.disconnect(refresh_list)
	inventory = inv
	if inventory:
		inventory.inventory_updated.connect(refresh_list)
	refresh_list()

func set_external_inventory(inv: Inventory):
	if external_inventory:
		if external_inventory.inventory_updated.is_connected(refresh_list):
			external_inventory.inventory_updated.disconnect(refresh_list)
	
	external_inventory = inv
	
	if external_inventory:
		if !external_inventory.inventory_updated.is_connected(refresh_list):
			external_inventory.inventory_updated.connect(refresh_list)
			
	refresh_list()

func set_station_filter(station: String) -> void:
	current_station_filter = station
	refresh_list()

func _on_recipe_unlocked(_recipe):
	refresh_list()

func refresh_list():
	if !is_inside_tree(): return
	
	# Clear current list
	for child in recipe_container.get_children():
		child.queue_free()
		
	# Get all relevant recipes
	var all_recipes = CraftingManager.a_recipe_database
	var display_list = []
	
	var inventory_list: Array[Inventory] = []
	if inventory: inventory_list.append(inventory)
	if external_inventory: inventory_list.append(external_inventory)
	
	for recipe in all_recipes:
		# Filter by station: allow "manual" recipes and recipes matching current_station_filter
		if recipe.station != "manual" and recipe.station != current_station_filter:
			continue
			
		# Filter by unlock status
		if recipe not in CraftingManager.unlocked_recipes:
			continue
			
		var can_craft = CraftingManager.can_craft(recipe, inventory_list)
		display_list.append({
			"recipe": recipe,
			"can_craft": can_craft
		})
		
	# Sort: Craftable first, then others
	display_list.sort_custom(func(a, b):
		if a.can_craft and !b.can_craft: return true
		if !a.can_craft and b.can_craft: return false
		return a.recipe.name < b.recipe.name # Alphabetical fallback
	)
	
	# Instantiate cards
	for data in display_list:
		var card = recipe_card_scene.instantiate()
		recipe_container.add_child(card)
		card.get_child(0).get_child(0).setup(data.recipe, item_cell_scene)
		card.get_child(0).get_child(0).update_state(data.can_craft, true)
		card.get_child(0).get_child(0).recipe_clicked.connect(_on_recipe_card_clicked)

func _on_recipe_card_clicked(recipe: CraftingRecipe):
	var inventory_list: Array[Inventory] = []
	if inventory: inventory_list.append(inventory)
	if external_inventory: inventory_list.append(external_inventory)

	if CraftingManager.craft(recipe, inventory_list):
		# Success feedback?
		# Inventory update signal will trigger refresh_list automatically
		pass
