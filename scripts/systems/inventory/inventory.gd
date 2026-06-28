# inventory.gd
# BEHAVIOR: Manages the collection of ItemStacks. Handles all data manipulation.
class_name Inventory extends Node

@export var inventory_size = 20
@export var hotbar_size = 5

@export_group("Testing")
@export var testing_fill_inventory_on_start := false
@export_dir var testing_item_scan_dir := "res://resources/items"

# NEW: The allowed item types for the hotbar are now a single export variable.
# You can configure this in the Inspector for your Inventory node.
@export_flags("Weapon", "Consumable", "Tool", "Armor", "Quest Item", "Placeable") var allowed_hotbar_types: int = \
	InventoryItem.Type.WEAPON | InventoryItem.Type.CONSUMABLE | InventoryItem.Type.TOOL

var inventory_container: Array[ItemStack]
var hotbar_container: Array[ItemStack]
var equipment_container: Array[ItemStack]

var hotbar_selection: int = 0

# Signal to notify UI or other systems that the inventory has changed.
signal inventory_updated
signal hotbar_selection_updated(item_stack: ItemStack)
signal equipment_updated

func _ready() -> void:
	# Use resize and then fill. This is safer than appending in _init.
	inventory_container.resize(inventory_size) # [cite: 1]
	for i in range(inventory_size):
		inventory_container[i] = ItemStack.new()
	hotbar_container.resize(hotbar_size) # [cite: 1]
	for i in range(hotbar_size):
		hotbar_container[i] = ItemStack.new()
	equipment_container.resize(3)
	for i in range(3):
		equipment_container[i] = ItemStack.new()

	if testing_fill_inventory_on_start:
		_fill_inventory_for_testing()

func _fill_inventory_for_testing() -> void:
	var item_paths := _find_inventory_item_paths(testing_item_scan_dir)
	item_paths.sort()

	var items_to_add = min(inventory_size, item_paths.size())
	for i in range(items_to_add):
		var item := load(item_paths[i]) as InventoryItem
		if item != null:
			obtain_item(ItemStack.new(item, 1))

func _find_inventory_item_paths(scan_dir: String) -> PackedStringArray:
	var item_paths := PackedStringArray()
	var dir := DirAccess.open(scan_dir)
	if dir == null:
		push_warning("Could not open testing item scan directory: %s" % scan_dir)
		return item_paths

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var path := scan_dir.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				item_paths.append_array(_find_inventory_item_paths(path))
		elif file_name.get_extension() == "tres":
			var item := load(path) as InventoryItem
			if item != null:
				item_paths.append(path)
		file_name = dir.get_next()
	dir.list_dir_end()

	return item_paths

# The main function for adding an item to the main inventory.
# Returns the ItemStack that couldn't be added, if any.
func obtain_item(item_stack_to_add: ItemStack) -> ItemStack: # [cite: 3]
	#print("Obtaining item " + str(item_stack_to_add))
	if item_stack_to_add.is_empty(): # [cite: 3]
		print("Invalid ItemStack")
		return null

	# --- First Pass: Add to existing, non-full stacks in main inventory ---
	for slot: ItemStack in inventory_container:
		if !slot.is_empty() and !slot.is_full() and slot.item == item_stack_to_add.item: # [cite: 3]
			var space_left = slot.get_space_left() # [cite: 3]
			if item_stack_to_add.count <= space_left:
				slot.count += item_stack_to_add.count # [cite: 4]
				item_stack_to_add.empty_slot()
				emit_signal("inventory_updated")
				return null # All items were added
			else:
				slot.count += space_left # [cite: 5]
				item_stack_to_add.count -= space_left # [cite: 5]

	# --- Second Pass: Add to empty slots in main inventory ---
	for slot: ItemStack in inventory_container:
		if slot.is_empty(): # [cite: 3]
			slot.item = item_stack_to_add.item # [cite: 6]
			slot.count = item_stack_to_add.count # [cite: 6]
			
			# Signal that we obtained this item (for crafting unlocks etc)
			emit_signal("item_obtained", slot.item)
			
			item_stack_to_add.empty_slot()
			emit_signal("inventory_updated")
			return null # All items were added

	# If we get here, the inventory is full. Return the remainder.
	emit_signal("inventory_updated")
	return item_stack_to_add # [cite: 7]

# 2. Add a helper to get the currently active stack easily
func get_hotbar_selection() -> ItemStack:
	if hotbar_selection >= 0 and hotbar_selection < hotbar_container.size():
		return hotbar_container[hotbar_selection]
	return null

# 3. Update your selection handler to emit the signal
func handle_hotbar_select(i):
	print("New hotbar selection: " + str(i))
	hotbar_selection = i
	print(str(multiplayer.get_unique_id()) + "Is hotbar empty? " + str(get_hotbar_selection().is_empty()))
	# Emit the signal so the player model knows to switch meshes
	hotbar_selection_updated.emit(get_hotbar_selection())

# Handles left-click actions for a given slot in either container.
func handle_left_click(slot_idx: int, cursor_stack: ItemStack, is_hotbar: bool):
	if is_multiplayer_authority():
		var target_container = hotbar_container if is_hotbar else inventory_container
		var target_slot = target_container[slot_idx]
		
		# Execute Logic Locally
		_logic_left_click(target_slot, cursor_stack, is_hotbar)
		
		# If we are the server, we must sync the slot change to all clients
		if multiplayer.is_server():
			client_update_slot.rpc(slot_idx, target_slot.serialize(), is_hotbar)
			
	else:
		# Request Server to handle it
		server_handle_left_click.rpc_id(get_multiplayer_authority(), slot_idx, cursor_stack.serialize(), is_hotbar)

func _logic_left_click(target_slot: ItemStack, cursor_stack: ItemStack, is_hotbar: bool):
	# --- Check if the item is allowed in the hotbar before any action ---
	if is_hotbar and !cursor_stack.is_empty():
		if not (cursor_stack.item.item_types & allowed_hotbar_types):
			return # Abort the operation if item is not allowed.

	# --- BEHAVIOR 1: COMBINE/TOP-OFF STACKS ---
	if !cursor_stack.is_empty() and !target_slot.is_empty() and \
	   target_slot.item == cursor_stack.item and not target_slot.is_full():
		var space_left = target_slot.get_space_left()
		var amount_to_move = min(cursor_stack.count, space_left)
		target_slot.count += amount_to_move
		cursor_stack.count -= amount_to_move
		if cursor_stack.count <= 0:
			cursor_stack.empty_slot()

	# --- BEHAVIOR 2: SWAP STACKS ---
	else:
		# If swapping, ensure the item on the cursor can be placed in the hotbar.
		if is_hotbar and !cursor_stack.is_empty():
			if not (cursor_stack.item.item_types & allowed_hotbar_types):
				return # Don't allow swapping a restricted item into the hotbar

		var temp_item = target_slot.item
		var temp_count = target_slot.count
		target_slot.item = cursor_stack.item
		target_slot.count = cursor_stack.count
		cursor_stack.item = temp_item
		cursor_stack.count = temp_count

	emit_signal("inventory_updated")

# Handles right-click actions for a given slot in either container.
func handle_right_click(slot_idx: int, cursor_stack: ItemStack, is_hotbar: bool):
	if is_multiplayer_authority():
		var target_container = hotbar_container if is_hotbar else inventory_container
		var target_slot = target_container[slot_idx]
		
		_logic_right_click(target_slot, cursor_stack, is_hotbar)
		
		if multiplayer.is_server():
			client_update_slot.rpc(slot_idx, target_slot.serialize(), is_hotbar)
	else:
		server_handle_right_click.rpc_id(get_multiplayer_authority(), slot_idx, cursor_stack.serialize(), is_hotbar)

func _logic_right_click(target_slot: ItemStack, cursor_stack: ItemStack, is_hotbar: bool):
	var changed = false

	# --- BEHAVIOR 1: PICK UP HALF (if cursor is empty) ---
	if cursor_stack.is_empty():
		if target_slot.is_empty() or target_slot.count <= 1:
			return
		var amount_to_pick_up = int(ceil(target_slot.count / 2.0))
		cursor_stack.item = target_slot.item
		cursor_stack.count = amount_to_pick_up
		target_slot.count -= amount_to_pick_up
		changed = true

	# --- BEHAVIOR 2: DROP ONE (if cursor has an item) ---
	else:
		# Check if the target is empty, or has the same item with space
		if target_slot.is_empty() or (target_slot.item == cursor_stack.item and not target_slot.is_full()):
			# Check if item is allowed in hotbar
			if is_hotbar:
				if not (cursor_stack.item.item_types & allowed_hotbar_types):
					return # Abort if not allowed

			if target_slot.is_empty():
				target_slot.item = cursor_stack.item
			target_slot.count += 1
			cursor_stack.count -= 1
			changed = true
			if cursor_stack.count <= 0:
				cursor_stack.empty_slot()

	if changed:
		emit_signal("inventory_updated")

# --- RPCs for Networking ---

signal cursor_updated(new_stack: ItemStack)

@rpc("any_peer", "call_remote", "reliable")
func server_handle_left_click(slot_idx: int, cursor_data: Dictionary, is_hotbar: bool):
	if not multiplayer.is_server(): return
	var cursor_stack = ItemStack.deserialize(cursor_data)
	if cursor_stack == null: cursor_stack = ItemStack.new()
	
	var target_container = hotbar_container if is_hotbar else inventory_container
	var target_slot = target_container[slot_idx]
	
	_logic_left_click(target_slot, cursor_stack, is_hotbar)
	
	# Sync Slot to everyone
	client_update_slot.rpc(slot_idx, target_slot.serialize(), is_hotbar)
	
	# Sync Cursor back to caller
	var caller_id = multiplayer.get_remote_sender_id()
	client_update_cursor.rpc_id(caller_id, cursor_stack.serialize())

@rpc("any_peer", "call_remote", "reliable")
func server_handle_right_click(slot_idx: int, cursor_data: Dictionary, is_hotbar: bool):
	if not multiplayer.is_server(): return
	var cursor_stack = ItemStack.deserialize(cursor_data)
	if cursor_stack == null: cursor_stack = ItemStack.new()
	
	var target_container = hotbar_container if is_hotbar else inventory_container
	var target_slot = target_container[slot_idx]
	
	_logic_right_click(target_slot, cursor_stack, is_hotbar)
	
	client_update_slot.rpc(slot_idx, target_slot.serialize(), is_hotbar)
	var caller_id = multiplayer.get_remote_sender_id()
	client_update_cursor.rpc_id(caller_id, cursor_stack.serialize())

@rpc("authority", "call_remote", "reliable")
func client_update_slot(slot_idx: int, stack_data: Dictionary, is_hotbar: bool):
	var stack = ItemStack.deserialize(stack_data)
	if is_hotbar:
		hotbar_container[slot_idx] = stack if stack else ItemStack.new()
	else:
		inventory_container[slot_idx] = stack if stack else ItemStack.new()
	emit_signal("inventory_updated")

@rpc("authority", "call_local", "reliable")
func client_update_cursor(cursor_data: Dictionary):
	var stack = ItemStack.deserialize(cursor_data)
	if stack == null: stack = ItemStack.new()
	emit_signal("cursor_updated", stack)

# --- CRAFTING HELPERS ---

signal item_obtained(item: InventoryItem) # [cite: new]

func get_item_count(item: InventoryItem) -> int:
	var total = 0
	# Check inventory
	for slot in inventory_container:
		if !slot.is_empty() and slot.item == item:
			total += slot.count
	# Check hotbar
	for slot in hotbar_container:
		if !slot.is_empty() and slot.item == item:
			total += slot.count
	return total

func consume_item(item: InventoryItem, amount: int) -> int:
	var to_remove = amount
	
	# Pass 1: Remove from Inventory
	for slot in inventory_container:
		if to_remove <= 0: break
		if !slot.is_empty() and slot.item == item:
			var taken = min(slot.count, to_remove)
			slot.count -= taken
			to_remove -= taken
			if slot.count <= 0:
				slot.empty_slot()
				
	# Pass 2: Remove from Hotbar
	for slot in hotbar_container:
		if to_remove <= 0: break
		if !slot.is_empty() and slot.item == item:
			var taken = min(slot.count, to_remove)
			slot.count -= taken
			to_remove -= taken
			if slot.count <= 0:
				slot.empty_slot()
				
	emit_signal("inventory_updated")
	return amount - to_remove # Returns amount actually removed

# --- EQUIPMENT HANDLERS ---

func handle_equipment_click(slot_idx: int, cursor_stack: ItemStack):
	if is_multiplayer_authority():
		_logic_equipment_click(slot_idx, cursor_stack)
		if multiplayer.is_server():
			client_update_equipment_slot.rpc(slot_idx, equipment_container[slot_idx].serialize())
	else:
		server_handle_equipment_click.rpc_id(get_multiplayer_authority(), slot_idx, cursor_stack.serialize())

func handle_equipment_right_click(slot_idx: int):
	if is_multiplayer_authority():
		_logic_equipment_right_click(slot_idx)
		if multiplayer.is_server():
			client_update_equipment_slot.rpc(slot_idx, equipment_container[slot_idx].serialize())
	else:
		server_handle_equipment_right_click.rpc_id(get_multiplayer_authority(), slot_idx)

func _logic_equipment_click(slot_idx: int, cursor_stack: ItemStack):
	# Check if item can be placed in this slot
	if not cursor_stack.is_empty():
		if not cursor_stack.item.is_type(InventoryItem.Type.ARMOR):
			return
		if not is_item_allowed_in_equipment_slot(cursor_stack.item, slot_idx):
			return

	var target_slot = equipment_container[slot_idx]
	var temp_item = target_slot.item
	var temp_count = target_slot.count
	target_slot.item = cursor_stack.item
	target_slot.count = cursor_stack.count
	cursor_stack.item = temp_item
	cursor_stack.count = temp_count

	emit_signal("equipment_updated")
	emit_signal("inventory_updated")

func _logic_equipment_right_click(slot_idx: int):
	var target_slot = equipment_container[slot_idx]
	if target_slot.is_empty():
		return
		
	var remainder = obtain_item(target_slot)
	if remainder == null or remainder.is_empty():
		equipment_container[slot_idx] = ItemStack.new()
		emit_signal("equipment_updated")
		emit_signal("inventory_updated")

func is_item_allowed_in_equipment_slot(item: InventoryItem, slot_idx: int) -> bool:
	if not (item is EquipmentItem):
		return false
	return item.slot_type == slot_idx

@rpc("any_peer", "call_remote", "reliable")
func server_handle_equipment_click(slot_idx: int, cursor_data: Dictionary):
	if not multiplayer.is_server(): return
	var cursor_stack = ItemStack.deserialize(cursor_data)
	if cursor_stack == null: cursor_stack = ItemStack.new()
	
	_logic_equipment_click(slot_idx, cursor_stack)
	
	client_update_equipment_slot.rpc(slot_idx, equipment_container[slot_idx].serialize())
	var caller_id = multiplayer.get_remote_sender_id()
	client_update_cursor.rpc_id(caller_id, cursor_stack.serialize())

@rpc("any_peer", "call_remote", "reliable")
func server_handle_equipment_right_click(slot_idx: int):
	if not multiplayer.is_server(): return
	_logic_equipment_right_click(slot_idx)
	client_update_equipment_slot.rpc(slot_idx, equipment_container[slot_idx].serialize())

@rpc("authority", "call_local", "reliable")
func client_update_equipment_slot(slot_idx: int, stack_data: Dictionary):
	var stack = ItemStack.deserialize(stack_data)
	equipment_container[slot_idx] = stack if stack else ItemStack.new()
	emit_signal("equipment_updated")
	emit_signal("inventory_updated")
