extends Node
class_name PlayerEquipmentController

## Manages player weapons, hotbar selection, active weapon trigger,
## and equipping armor visuals (helmet, chest, boots).

var player: Player:
	get:
		return get_parent() as Player
var inventory: Inventory:
	get:
		return get_node("../Inventory") as Inventory
var pose_blend_component: Node:
	get:
		return get_node("../PoseBlendComponent")
var arm_pivot: Node3D:
	get:
		return get_node("../ViewModel/ArmContainer/ArmPivot") as Node3D

# Synchronized properties replicated by MultiplayerSynchronizer
@export var equipped_item_path: String = "":
	set(val):
		if equipped_item_path != val:
			equipped_item_path = val
			apply_equipped_item_path(val)

@export var equipped_helmet_path: String = "":
	set(val):
		if equipped_helmet_path != val:
			equipped_helmet_path = val
			_apply_equipment_visuals_from_paths()

@export var equipped_chest_path: String = "":
	set(val):
		if equipped_chest_path != val:
			equipped_chest_path = val
			_apply_equipment_visuals_from_paths()

@export var equipped_boots_path: String = "":
	set(val):
		if equipped_boots_path != val:
			equipped_boots_path = val
			_apply_equipment_visuals_from_paths()

var active_weapon: Weapon = null
var equipped_item_node: Node3D = null

func _ready() -> void:
	# Wait for a frame to ensure all nodes are fully ready
	await get_tree().process_frame
	
	# Apply initial paths
	apply_equipped_item_path(equipped_item_path)
	_apply_equipment_visuals_from_paths()

	if inventory:
		inventory.equipment_updated.connect(_update_equipment_visuals)

	if not is_multiplayer_authority():
		set_process_input(false)
		set_process_unhandled_input(false)
		return

	if inventory:
		inventory.hotbar_selection_updated.connect(_on_hotbar_selection_updated)
		_on_hotbar_selection_updated(inventory.get_hotbar_selection())

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Handle weapon trigger
	if event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if active_weapon:
			active_weapon.primary_pressed()
	
	if event.is_action_released("attack"):
		if active_weapon:
			active_weapon.primary_released()

	# Handle weapon switching
	if event.is_action_pressed("next_weapon"):
		_switch_weapon(1)
	elif event.is_action_pressed("prev_weapon"):
		_switch_weapon(-1)

	# Cancel active weapon
	if event.is_action_pressed("ui_cancel"):
		if active_weapon:
			active_weapon.cancel()

func _physics_process(delta: float) -> void:
	if active_weapon:
		active_weapon.update_weapon(delta, player.camera)

func _update_active_weapon() -> void:
	active_weapon = null
	
	# Find the active weapon among the children of the Arm node
	if arm_pivot:
		var arm_node = arm_pivot.get_node("Arm")
		if arm_node:
			for child in arm_node.get_children():
				if child is Weapon and child.visible:
					active_weapon = child
					break
				
	if active_weapon:
		active_weapon.setup(player, pose_blend_component)
	elif pose_blend_component:
		pose_blend_component.set_weapon(pose_blend_component.weapon_definition)

func _on_hotbar_selection_updated(item_stack: ItemStack) -> void:
	if not is_multiplayer_authority():
		return
	if item_stack and not item_stack.is_empty() and item_stack.item.scene:
		equipped_item_path = item_stack.item.resource_path
	else:
		equipped_item_path = ""

func apply_equipped_item_path(path: String) -> void:
	# 1. Unequip/destroy previous equipped node
	if is_instance_valid(equipped_item_node):
		equipped_item_node.queue_free()
		equipped_item_node = null
		
	# 2. Hide all static weapon nodes (Sword, Bow, Wand) so they don't get in the way
	if arm_pivot:
		var arm_node = arm_pivot.get_node("Arm")
		if arm_node:
			for child in arm_node.get_children():
				if child is Weapon:
					child.visible = false
				
		# 3. If path is not empty, load and instantiate the scene
		if path != "":
			var item = load(path) as InventoryItem
			if item and item.scene:
				var instance = item.scene.instantiate()
				if instance:
					# Add to Arm
					arm_node.add_child(instance)
					# Make sure it's visible
					instance.visible = true
					# Set item_resource property
					if "item_resource" in instance:
						instance.item_resource = item
					# Set name to match the scene name (e.g. "Sword", "Bow", "Wand", "StoneAxe")
					instance.name = item.scene.get_state().get_node_name(0)
					# Keep track of it
					equipped_item_node = instance
				
	_update_active_weapon()

func _switch_weapon(direction: int) -> void:
	if not is_multiplayer_authority():
		return
	if inventory:
		var new_selection = (inventory.hotbar_selection + direction) % inventory.hotbar_size
		if new_selection < 0:
			new_selection = inventory.hotbar_size - 1
		inventory.handle_hotbar_select(new_selection)

func _update_equipment_visuals() -> void:
	if not is_multiplayer_authority():
		return
		
	var helmet_stack = inventory.equipment_container[0]
	var chest_stack = inventory.equipment_container[1]
	var feet_stack = inventory.equipment_container[2]
	
	equipped_helmet_path = helmet_stack.item.resource_path if (helmet_stack and not helmet_stack.is_empty() and helmet_stack.item) else ""
	equipped_chest_path = chest_stack.item.resource_path if (chest_stack and not chest_stack.is_empty() and chest_stack.item) else ""
	equipped_boots_path = feet_stack.item.resource_path if (feet_stack and not feet_stack.is_empty() and feet_stack.item) else ""

func apply_helmet_path(_path: String) -> void:
	_apply_equipment_visuals_from_paths()

func apply_chest_path(_path: String) -> void:
	_apply_equipment_visuals_from_paths()

func apply_boots_path(_path: String) -> void:
	_apply_equipment_visuals_from_paths()

func _apply_equipment_visuals_from_paths() -> void:
	var model = player.get_node_or_null("ViewModel/character_model")
	if not model:
		return
		
	# Find slots
	var slot_helmet = model.find_child("slot_helmet", true, false)
	var slot_chest = model.find_child("slot_chest", true, false)
	var slot_foot_l = model.find_child("slot_foot_l", true, false)
	var slot_foot_r = model.find_child("slot_foot_r", true, false)
	
	# Update helmet slot
	if slot_helmet:
		for child in slot_helmet.get_children():
			child.queue_free()
		if equipped_helmet_path != "":
			var item = load(equipped_helmet_path) as EquipmentItem
			if item and item.scene:
				var inst = item.scene.instantiate()
				slot_helmet.add_child(inst)
				
	# Update chest slot
	if slot_chest:
		for child in slot_chest.get_children():
			child.queue_free()
		if equipped_chest_path != "":
			var item = load(equipped_chest_path) as EquipmentItem
			if item and item.scene:
				var inst = item.scene.instantiate()
				slot_chest.add_child(inst)
				
	# Update feet slots
	if slot_foot_l:
		for child in slot_foot_l.get_children():
			child.queue_free()
		if equipped_boots_path != "":
			var item = load(equipped_boots_path) as EquipmentItem
			if item and item.scene:
				var inst = item.scene.instantiate()
				slot_foot_l.add_child(inst)
				
	if slot_foot_r:
		for child in slot_foot_r.get_children():
			child.queue_free()
		if equipped_boots_path != "":
			var item = load(equipped_boots_path) as EquipmentItem
			if item and item.scene:
				var inst = item.scene.instantiate()
				slot_foot_r.add_child(inst)
