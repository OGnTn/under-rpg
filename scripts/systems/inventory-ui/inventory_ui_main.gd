# inventory_ui_main.gd
# BEHAVIOR: Displays the inventory state and forwards user input to the Inventory node.
extends Control

@export var inventory: Inventory
@export var external_inventory: Inventory = null
@export var picked_up_item_icon: TextureRect
@export var item_cell_scene: PackedScene
@export var crafting_ui: Control # [cite: new]

# This represents the item stack attached to the mouse cursor.
var picked_up_item_stack: ItemStack = null # [cite: 20]

signal item_dropped_outside(item_stack: ItemStack)
signal ui_shown()
signal ui_hidden()


func _ready() -> void:
	#if (!$"../../PlayerInput".is_multiplayer_authority()):
	#	$"../InventoryControl".queue_free()
	#	queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	#inventory = %Inventory
	picked_up_item_stack = ItemStack.new() # [cite: 20]
	if !inventory:
		printerr("InventoryUI: No Inventory node assigned!")
		return
		#inventory  = %Inventory
	if !inventory.is_node_ready(): # [cite: 21]
		await inventory.ready # [cite: 21]
	inventory.inventory_updated.connect(update_all_cells) # [cite: 21]
	inventory.cursor_updated.connect(_on_cursor_updated)
	
	ui_shown.connect(_on_ui_shown)
	ui_hidden.connect(_on_ui_hidden)
	if visible:
		_on_ui_shown()
	
	# Connect usage of items to unlocking logic
	if CraftingManager:
		inventory.item_obtained.connect(CraftingManager.register_item_discovery)
	
	if crafting_ui and crafting_ui.has_method("set_inventory"): # [cite: new]
		crafting_ui.set_inventory(inventory) # [cite: new]
	
	# Initial check for items already in inventory (e.g. from starting items)
	if CraftingManager:
		for stack in inventory.inventory_container:
			if !stack.is_empty():
				CraftingManager.register_item_discovery(stack.item)
		for stack in inventory.hotbar_container:
			if !stack.is_empty():
				CraftingManager.register_item_discovery(stack.item)
	
	setup_item_cells()
	setup_equipment_slots()
	update_all_cells()
	#open_external_inventory(external_inventory)

func _on_cursor_updated(new_stack: ItemStack):
	picked_up_item_stack = new_stack
	update_picked_up_item_display()

func _process(_delta: float) -> void:
	picked_up_item_icon.global_position = get_viewport().get_mouse_position() # [cite: 22]
	%ItemInfoPanelContainer.global_position = get_viewport().get_mouse_position()

func setup_item_cells():
	# Clear previous cells for safety, assuming you might re-run this
	for child in %MainGrid.get_children(): # [cite: 23]
		child.queue_free()
	for child in %HotbarGrid.get_children():
		child.queue_free()
	for child in %HotbarGridHUD.get_children():
		child.queue_free()

	# --- NEW: Setup for Main Inventory Grid ---
	for i in range(inventory.inventory_size):
		var item_cell: UIItemCell = item_cell_scene.instantiate()
		item_cell.idx = i
		item_cell.clicked.connect(_on_inventory_cell_left_clicked.bind(i))
		item_cell.right_clicked.connect(_on_inventory_cell_right_clicked.bind(i))
		item_cell.started_hovering.connect(_on_item_cell_started_hovering.bind(i, false))
		item_cell.stopped_hovering.connect(_on_item_cell_stopped_hovering)
		%MainGrid.add_child(item_cell)

	# --- NEW: Setup for Hotbar Grid ---
	for i in range(inventory.hotbar_size):
		var item_cell: UIItemCell = item_cell_scene.instantiate()
		item_cell.idx = i
		item_cell.clicked.connect(_on_hotbar_cell_left_clicked.bind(i))
		item_cell.right_clicked.connect(_on_hotbar_cell_right_clicked.bind(i))
		item_cell.started_hovering.connect(_on_item_cell_started_hovering.bind(i, true))
		item_cell.stopped_hovering.connect(_on_item_cell_stopped_hovering)
		var item_cell2: UIItemCell = item_cell.duplicate()
		%HotbarGrid.add_child(item_cell)
		%HotbarGridHUD.add_child(item_cell2)

# This function is now called whenever the inventory's data changes.
func update_all_cells(): # [cite: 24]
	# Update Main Inventory Cells
	var main_cells = %MainGrid.get_children()
	for i in range(inventory.inventory_container.size()):
		if i < main_cells.size():
			var cell: UIItemCell = main_cells[i]
			cell.item_stack = inventory.inventory_container[i]
			cell.update_item_stack()
	
	# Update Hotbar Cells
	var hotbar_cells = %HotbarGrid.get_children()
	for i in range(inventory.hotbar_container.size()):
		if i < hotbar_cells.size():
			var cell: UIItemCell = hotbar_cells[i]
			cell.item_stack = inventory.hotbar_container[i]
			cell.update_item_stack()
	var hotbar_hud_cells = %HotbarGridHUD.get_children()
	for i in range(inventory.hotbar_container.size()):
		if i < hotbar_hud_cells.size():
			var cell: UIItemCell = hotbar_hud_cells[i]
			cell.item_stack = inventory.hotbar_container[i]
			cell.update_item_stack()
	update_picked_up_item_display()
	
	# Update Equipment Cells
	var character_preview = get_node_or_null("%CharacterPreview")
	if character_preview:
		var head_slot = character_preview.get_node("%HeadSlot")
		var chest_slot = character_preview.get_node("%ChestSlot")
		var feet_slot = character_preview.get_node("%FeetSlot")
		
		if head_slot:
			head_slot.item_stack = inventory.equipment_container[0]
			head_slot.update_item_stack()
		if chest_slot:
			chest_slot.item_stack = inventory.equipment_container[1]
			chest_slot.update_item_stack()
		if feet_slot:
			feet_slot.item_stack = inventory.equipment_container[2]
			feet_slot.update_item_stack()

func update_picked_up_item_display():
	if !picked_up_item_stack.is_empty():
		picked_up_item_icon.texture = picked_up_item_stack.item.icon
		picked_up_item_icon.get_child(0).text = str(picked_up_item_stack.count)
		picked_up_item_icon.visible = true
	else:
		picked_up_item_icon.visible = false

# --- NEW: Handlers for Main Inventory ---
func _on_inventory_cell_left_clicked(idx: int):
	inventory.handle_left_click(idx, picked_up_item_stack, false) # is_hotbar is false
	update_picked_up_item_display()

func _on_inventory_cell_right_clicked(idx: int):
	inventory.handle_right_click(idx, picked_up_item_stack, false) # is_hotbar is false
	update_picked_up_item_display()

# --- NEW: Handlers for Hotbar ---
func _on_hotbar_cell_left_clicked(idx: int):
	inventory.handle_left_click(idx, picked_up_item_stack, true) # is_hotbar is true
	update_picked_up_item_display()

func _on_hotbar_cell_right_clicked(idx: int):
	inventory.handle_right_click(idx, picked_up_item_stack, true) # is_hotbar is true
	update_picked_up_item_display()

# --- NEW: Hover handler knows which container to check ---
func _on_item_cell_started_hovering(idx: int, is_hotbar: bool):
	var container = inventory.hotbar_container if is_hotbar else inventory.inventory_container
	var highlighted_stack: ItemStack = container[idx]
	if !highlighted_stack.is_empty() and picked_up_item_stack.is_empty():
		%HighlightItemName.text = highlighted_stack.item.name
		%HighlightItemIcon.texture = highlighted_stack.item.icon
		%HighlightItemCount.text = str(highlighted_stack.count)
		%HighlightItemDescription.text = highlighted_stack.item.description
		%ItemInfoPanelContainer.visible = true

func _on_item_cell_stopped_hovering(idx: int):
	%ItemInfoPanelContainer.visible = false

func toggle_inventory():
	visible = !visible
	if (visible):
		ui_shown.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner:
			focus_owner.release_focus()
		ui_hidden.emit()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func show_inventory():
	visible = true
	if (visible):
		ui_shown.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner:
			focus_owner.release_focus()
		ui_hidden.emit()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func hide_inventory():
	visible = false
	if (visible):
		ui_shown.emit()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner:
			focus_owner.release_focus()
		ui_hidden.emit()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if ($"../../PlayerInput".is_multiplayer_authority()):
		if event.is_action_pressed("toggle_inventory"):
			print("Toggling inventory")
			toggle_inventory()
		if(inventory):
			for i in range(1, inventory.hotbar_size + 1):
				if event.is_action_pressed("hotbar_" + str(i)):
					if (inventory.hotbar_selection != i - 1):
						inventory.handle_hotbar_select(i - 1)

func _unhandled_input(event: InputEvent):
	if picked_up_item_stack and picked_up_item_stack.is_empty(): # [cite: 28]
		return
	
	if event is InputEventMouseButton and event.is_pressed():
		# Check if the mouse is over any UI control. If so, don't drop the item.
		if get_viewport().gui_get_focus_owner() != null:
			return

		get_viewport().set_input_as_handled() # [cite: 29]
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			item_dropped_outside.emit(picked_up_item_stack) # [cite: 30]
			picked_up_item_stack = ItemStack.new() # [cite: 32]
			update_picked_up_item_display()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var single_item_stack = ItemStack.new(picked_up_item_stack.item, 1) # [cite: 33]
			item_dropped_outside.emit(single_item_stack)
			picked_up_item_stack.count -= 1 # [cite: 34]
			if picked_up_item_stack.count <= 0:
				picked_up_item_stack.empty_slot()
			update_picked_up_item_display()

func open_external_inventory(inv: Inventory):
	# 1. Show the UI if it isn't visible
	if not visible:
		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# 2. Assign the inventory and connect signals
	external_inventory = inv
	# Disconnect first to avoid double-connections if re-opening
	if external_inventory.inventory_updated.is_connected(update_external_cells):
		external_inventory.inventory_updated.disconnect(update_external_cells)
	external_inventory.inventory_updated.connect(update_external_cells)
	if external_inventory.cursor_updated.is_connected(_on_cursor_updated):
		external_inventory.cursor_updated.disconnect(_on_cursor_updated)
	external_inventory.cursor_updated.connect(_on_cursor_updated)
	
	# 3. Setup the grid
	setup_external_cells()
	update_external_cells()
	
	# 4. Update Crafting UI to see this chest
	if crafting_ui and crafting_ui.has_method("set_external_inventory"):
		crafting_ui.set_external_inventory(external_inventory)

func close_external_inventory():
	if external_inventory:
		if external_inventory.inventory_updated.is_connected(update_external_cells):
			external_inventory.inventory_updated.disconnect(update_external_cells)
		if external_inventory.cursor_updated.is_connected(_on_cursor_updated):
			external_inventory.cursor_updated.disconnect(_on_cursor_updated)
		external_inventory = null
		
		# Clear from Crafting UI
		if crafting_ui and crafting_ui.has_method("set_external_inventory"):
			crafting_ui.set_external_inventory(null)
	
	# Clear the external grid UI
	for child in %ExternalGrid.get_children():
		child.queue_free()

# --- RENDERING (Similar to your existing setup_item_cells) ---

func setup_external_cells():
	# Clear existing cells
	for child in %ExternalGrid.get_children():
		child.queue_free()
		
	if not external_inventory:
		return

	# Create cells for the chest
	for i in range(external_inventory.inventory_size):
		var item_cell: UIItemCell = item_cell_scene.instantiate()
		item_cell.idx = i
		# Connect to NEW specific handlers for external interaction
		item_cell.clicked.connect(_on_external_cell_left_clicked.bind(i))
		item_cell.right_clicked.connect(_on_external_cell_right_clicked.bind(i))
		# Reuse your existing hover logic
		item_cell.started_hovering.connect(_on_external_cell_started_hovering.bind(i))
		item_cell.stopped_hovering.connect(_on_item_cell_stopped_hovering)
		
		%ExternalGrid.add_child(item_cell)

func update_external_cells():
	if not external_inventory:
		return
		
	var cells = %ExternalGrid.get_children()
	for i in range(external_inventory.inventory_container.size()):
		if i < cells.size():
			var cell: UIItemCell = cells[i]
			cell.item_stack = external_inventory.inventory_container[i]
			cell.update_item_stack()

# --- INTERACTION HANDLERS ---

func _on_external_cell_left_clicked(idx: int):
	if external_inventory:
		# We pass the SHARED 'picked_up_item_stack' to the chest's inventory logic
		external_inventory.handle_left_click(idx, picked_up_item_stack, false)
		# Update the cursor visual
		update_picked_up_item_display()

func _on_external_cell_right_clicked(idx: int):
	if external_inventory:
		external_inventory.handle_right_click(idx, picked_up_item_stack, false)
		update_picked_up_item_display()

# Special hover handler to tell the existing hover logic to look at the external inventory
func _on_external_cell_started_hovering(idx: int):
	var highlighted_stack = external_inventory.inventory_container[idx]
	if !highlighted_stack.is_empty() and picked_up_item_stack.is_empty():
		%HighlightItemName.text = highlighted_stack.item.name
		%HighlightItemIcon.texture = highlighted_stack.item.icon
		%HighlightItemCount.text = str(highlighted_stack.count)
		%HighlightItemDescription.text = highlighted_stack.item.description
		%ItemInfoPanelContainer.visible = true

func _on_ui_shown() -> void:
	var character_preview = get_node_or_null("%CharacterPreview")
	if character_preview:
		if(get_node("../..") is Player):
			character_preview.initialize(get_node("../.."))

func _on_ui_hidden() -> void:
	var character_preview = get_node_or_null("%CharacterPreview")
	if character_preview:
		character_preview.cleanup()

# --- EQUIPMENT SLOTS SETUP & HANDLERS ---

func setup_equipment_slots() -> void:
	var character_preview = get_node_or_null("%CharacterPreview")
	if character_preview:
		var head_slot = character_preview.get_node("%HeadSlot")
		var chest_slot = character_preview.get_node("%ChestSlot")
		var feet_slot = character_preview.get_node("%FeetSlot")
		
		if head_slot:
			head_slot.idx = 0
			head_slot.clicked.connect(_on_equipment_slot_left_clicked.bind(0))
			head_slot.right_clicked.connect(_on_equipment_slot_right_clicked.bind(0))
			head_slot.started_hovering.connect(_on_equipment_slot_started_hovering.bind(0))
			head_slot.stopped_hovering.connect(_on_item_cell_stopped_hovering)
			
		if chest_slot:
			chest_slot.idx = 1
			chest_slot.clicked.connect(_on_equipment_slot_left_clicked.bind(1))
			chest_slot.right_clicked.connect(_on_equipment_slot_right_clicked.bind(1))
			chest_slot.started_hovering.connect(_on_equipment_slot_started_hovering.bind(1))
			chest_slot.stopped_hovering.connect(_on_item_cell_stopped_hovering)
			
		if feet_slot:
			feet_slot.idx = 2
			feet_slot.clicked.connect(_on_equipment_slot_left_clicked.bind(2))
			feet_slot.right_clicked.connect(_on_equipment_slot_right_clicked.bind(2))
			feet_slot.started_hovering.connect(_on_equipment_slot_started_hovering.bind(2))
			feet_slot.stopped_hovering.connect(_on_item_cell_stopped_hovering)

func _on_equipment_slot_left_clicked(slot_idx: int):
	inventory.handle_equipment_click(slot_idx, picked_up_item_stack)
	update_picked_up_item_display()

func _on_equipment_slot_right_clicked(slot_idx: int):
	inventory.handle_equipment_right_click(slot_idx)
	update_picked_up_item_display()

func _on_equipment_slot_started_hovering(slot_idx: int):
	var highlighted_stack = inventory.equipment_container[slot_idx]
	if !highlighted_stack.is_empty() and picked_up_item_stack.is_empty():
		%HighlightItemName.text = highlighted_stack.item.name
		%HighlightItemIcon.texture = highlighted_stack.item.icon
		%HighlightItemCount.text = str(highlighted_stack.count)
		%HighlightItemDescription.text = highlighted_stack.item.description
		%ItemInfoPanelContainer.visible = true
