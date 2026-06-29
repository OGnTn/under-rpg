extends Node
class_name PlayerEquipmentController

## Coordinates player equipment, active weapon input, and armor visuals.

enum ArmorSlot { HELMET, CHEST, BOOTS }

@export var weapon_socket_path: NodePath = NodePath("../ViewModel/ArmContainer/ArmPivot/Arm")
@export var pose_blender_path: NodePath = NodePath("../PoseBlendComponent")
@export var inventory_path: NodePath = NodePath("../Inventory")

@export var equipped_item_path: String = "":
	set(value):
		if equipped_item_path == value:
			return
		equipped_item_path = value
		_on_weapon_path_changed()

@export var equipped_helmet_path: String = "":
	set(value):
		if equipped_helmet_path == value:
			return
		equipped_helmet_path = value
		_apply_armor_visuals()

@export var equipped_chest_path: String = "":
	set(value):
		if equipped_chest_path == value:
			return
		equipped_chest_path = value
		_apply_armor_visuals()

@export var equipped_boots_path: String = "":
	set(value):
		if equipped_boots_path == value:
			return
		equipped_boots_path = value
		_apply_armor_visuals()

var active_weapon: Weapon
var equipped_item_node: Node3D

@onready var player: Player = get_parent() as Player
@onready var inventory: Inventory = get_node_or_null(inventory_path) as Inventory
@onready var pose_blender: PoseBlendComponent = get_node_or_null(pose_blender_path) as PoseBlendComponent
@onready var weapon_socket: Node3D = get_node_or_null(weapon_socket_path) as Node3D

func _ready() -> void:
	await get_tree().process_frame
	_connect_weapon_socket()
	var initial_item_path := equipped_item_path
	_connect_inventory()
	if equipped_item_path == initial_item_path:
		_on_weapon_path_changed()
	_apply_armor_visuals()
	_refresh_active_weapon()
	set_process_unhandled_input(is_multiplayer_authority())

func equip_item(path: String) -> void:
	equipped_item_path = path

func apply_equipped_item_path(path: String) -> void:
	equip_item(path)

func clear_item() -> void:
	equip_item("")

func equip_armor(slot: ArmorSlot, path: String) -> void:
	match slot:
		ArmorSlot.HELMET:
			equipped_helmet_path = path
		ArmorSlot.CHEST:
			equipped_chest_path = path
		ArmorSlot.BOOTS:
			equipped_boots_path = path

func clear_armor() -> void:
	equipped_helmet_path = ""
	equipped_chest_path = ""
	equipped_boots_path = ""

func apply_helmet_path(path: String) -> void:
	equip_armor(ArmorSlot.HELMET, path)

func apply_chest_path(path: String) -> void:
	equip_armor(ArmorSlot.CHEST, path)

func apply_boots_path(path: String) -> void:
	equip_armor(ArmorSlot.BOOTS, path)

func get_active_weapon() -> Weapon:
	return active_weapon

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_call_weapon_rpc(&"press_primary")
	elif event.is_action_released("attack"):
		_call_weapon_rpc(&"release_primary")

	if event.is_action_pressed("next_weapon"):
		_switch_hotbar_selection(1)
	elif event.is_action_pressed("prev_weapon"):
		_switch_hotbar_selection(-1)

	if event.is_action_pressed("ui_cancel"):
		_call_weapon_rpc(&"cancel")

func _physics_process(delta: float) -> void:
	if active_weapon:
		active_weapon.tick(delta)

func _connect_weapon_socket() -> void:
	if not weapon_socket:
		return
	if not weapon_socket.child_entered_tree.is_connected(_on_weapon_socket_changed):
		weapon_socket.child_entered_tree.connect(_on_weapon_socket_changed)
	if not weapon_socket.child_exiting_tree.is_connected(_on_weapon_socket_changed):
		weapon_socket.child_exiting_tree.connect(_on_weapon_socket_changed)

func _connect_inventory() -> void:
	if not inventory:
		return
	if not inventory.equipment_updated.is_connected(_sync_armor_from_inventory):
		inventory.equipment_updated.connect(_sync_armor_from_inventory)
	if is_multiplayer_authority():
		if not inventory.hotbar_selection_updated.is_connected(_on_hotbar_selection_updated):
			inventory.hotbar_selection_updated.connect(_on_hotbar_selection_updated)
		_on_hotbar_selection_updated(inventory.get_hotbar_selection())
		_sync_armor_from_inventory()

func _on_weapon_path_changed() -> void:
	if _uses_multiplayer_spawning() and not is_multiplayer_authority():
		call_deferred("_refresh_active_weapon")
		return
	_apply_weapon_path(equipped_item_path)

func _apply_weapon_path(path: String) -> void:
	_clear_equipped_weapon()
	_hide_socket_weapons()

	if path.is_empty() or not weapon_socket:
		_refresh_active_weapon()
		return

	var item := load(path) as InventoryItem
	if not item or not item.scene:
		_refresh_active_weapon()
		return

	var instance := item.scene.instantiate() as Node3D
	if not instance:
		_refresh_active_weapon()
		return

	instance.name = "Weapon"
	instance.visible = true
	instance.set_multiplayer_authority(get_multiplayer_authority())
	if "item_resource" in instance:
		instance.item_resource = item

	weapon_socket.add_child(instance)
	equipped_item_node = instance
	_refresh_active_weapon()

func _clear_equipped_weapon() -> void:
	if is_instance_valid(equipped_item_node):
		equipped_item_node.get_parent().remove_child(equipped_item_node)
		equipped_item_node.queue_free()
	equipped_item_node = null

func _hide_socket_weapons() -> void:
	if not weapon_socket:
		return
	for child in weapon_socket.get_children():
		if child is Weapon:
			child.visible = false

func _refresh_active_weapon() -> void:
	active_weapon = null
	if weapon_socket:
		for child in weapon_socket.get_children():
			if child is Weapon and child.visible:
				active_weapon = child
				break

	if active_weapon:
		if not active_weapon.item_resource and not equipped_item_path.is_empty():
			active_weapon.item_resource = load(equipped_item_path)
		active_weapon.setup(player, pose_blender)
	elif pose_blender:
		pose_blender.clear_animations()

func _call_weapon_rpc(method: StringName) -> void:
	if not active_weapon:
		return
	if multiplayer.has_multiplayer_peer():
		active_weapon.rpc(method)
	else:
		active_weapon.call(method)

func _switch_hotbar_selection(direction: int) -> void:
	if not inventory:
		return
	var new_selection = (inventory.hotbar_selection + direction) % inventory.hotbar_size
	if new_selection < 0:
		new_selection = inventory.hotbar_size - 1
	inventory.handle_hotbar_select(new_selection)

func _on_hotbar_selection_updated(item_stack: ItemStack) -> void:
	if item_stack and not item_stack.is_empty() and item_stack.item.scene:
		equip_item(item_stack.item.resource_path)
	else:
		clear_item()

func _sync_armor_from_inventory() -> void:
	if not inventory or not is_multiplayer_authority():
		return

	var helmet_stack = inventory.equipment_container[0]
	var chest_stack = inventory.equipment_container[1]
	var boots_stack = inventory.equipment_container[2]

	equip_armor(ArmorSlot.HELMET, _item_path_from_stack(helmet_stack))
	equip_armor(ArmorSlot.CHEST, _item_path_from_stack(chest_stack))
	equip_armor(ArmorSlot.BOOTS, _item_path_from_stack(boots_stack))

func _item_path_from_stack(item_stack: ItemStack) -> String:
	if item_stack and not item_stack.is_empty() and item_stack.item:
		return item_stack.item.resource_path
	return ""

func _apply_armor_visuals() -> void:
	if not player:
		return

	var model = player.get_node_or_null("ViewModel/character_model")
	if not model:
		return

	_replace_slot_visual(model.find_child("slot_helmet", true, false), equipped_helmet_path)
	_replace_slot_visual(model.find_child("slot_chest", true, false), equipped_chest_path)
	_replace_slot_visual(model.find_child("slot_foot_l", true, false), equipped_boots_path)
	_replace_slot_visual(model.find_child("slot_foot_r", true, false), equipped_boots_path)

func _replace_slot_visual(slot: Node, path: String) -> void:
	if not slot:
		return
	for child in slot.get_children():
		child.queue_free()

	if path.is_empty():
		return

	var item := load(path) as EquipmentItem
	if item and item.scene:
		slot.add_child(item.scene.instantiate())

func _on_weapon_socket_changed(_node: Node) -> void:
	call_deferred("_refresh_active_weapon")

func _uses_multiplayer_spawning() -> bool:
	return multiplayer.has_multiplayer_peer()
