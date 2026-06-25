extends Button

# Signal emitted when clicked, passing the recipe
signal recipe_clicked(recipe: CraftingRecipe)

var recipe: CraftingRecipe
var is_craftable: bool = false
var is_unlocked: bool = false

@onready var icon_rect: TextureRect = %OutputIcon
@onready var name_label: Label = %RecipeName
# We will use this to show ingredients?
# For now, let's keep it simple: Icon + Name. 
# Hovering could show details, or we can list ingredients in the card.
# The user request said: "left side the input items and quantities in item cells and the right side the output item(s)"

@export var item_cell_scene: PackedScene

func setup(_recipe: CraftingRecipe, _item_cell_scene: PackedScene):
	recipe = _recipe
	item_cell_scene = _item_cell_scene
	
	# Clear existing grids
	for child in %InputContainer.get_children():
		child.queue_free()
	for child in %OutputContainer.get_children():
		child.queue_free()
		
	# Setup Ingreidents
	for ing in recipe.ingredients:
		var cell = item_cell_scene.instantiate()
		%InputContainer.add_child(cell)
		# We need to manually set the data on the cell since it expects an ItemStack usually
		# Or we can create a fake ItemStack
		var stack = ItemStack.new(ing.item, ing.quantity)
		# Force cell to ignore mouse so the button behind it gets the click
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if cell.has_method("set_item_stack_directly"):
			cell.set_item_stack_directly(stack)
		else:
			# Fallback if I haven't modified ItemCell yet to accept direct setting or if public prop works
			cell.item_stack = stack
			cell.update_item_stack()
			
	# Setup Results
	for res in recipe.results:
		var cell = item_cell_scene.instantiate()
		%OutputContainer.add_child(cell)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stack = ItemStack.new(res.item, res.quantity)
		cell.item_stack = stack
		cell.update_item_stack()
	
	name_label.text = recipe.name

func update_state(_can_craft: bool, _unlocked: bool):
	is_craftable = _can_craft
	is_unlocked = _unlocked
	
	disabled = !is_unlocked
	
	if is_craftable:
		modulate = Color(1, 1, 1, 1) # Normal
		get_parent().get_node("HBoxContainer").modulate = Color(1, 1, 1, 1)
	elif is_unlocked:
		modulate = Color(0.7, 0.7, 0.7, 1)
		# We want the content to look greyed out too
		get_parent().get_node("HBoxContainer").modulate = Color(0.5, 0.5, 0.5, 1)
	else:
		modulate = Color(0.3, 0.3, 0.3, 0.5)
		get_parent().get_node("HBoxContainer").modulate = Color(0.3, 0.3, 0.3, 0.5)

func _pressed():
	recipe_clicked.emit(recipe)
