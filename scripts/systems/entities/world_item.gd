extends Node
class_name WorldItem

@export_group("Static Placement")
@export var item: InventoryItem
@export var count: int = 1
@export var override_mesh: bool = true

@onready var parent: Node3D = get_parent()
@onready var mesh_instance: MeshInstance3D = parent.get_node_or_null("Visuals/MeshInstance3D")
@onready var ray_cast: RayCast3D = parent.get_node_or_null("RayCast3D")

var item_stack: ItemStack
var velocity: Vector3 = Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# If false, the item has landed and stops processing
var is_falling: bool = true

func _ready() -> void:
	if item:
		is_falling = false
		setup(ItemStack.new(item, count), Vector3.ZERO)
		set_physics_process(false)
	elif not multiplayer.is_server():
		# Request details from server for dynamically spawned items
		request_item_data.rpc_id(1)

	# Find sibling Interactable
	var interactable = parent.find_child("Interactable", true, false)
	if interactable:
		interactable.interacted.connect(pick_up)
	if !mesh_instance:
		mesh_instance = %MeshInstance3D
@rpc("any_peer", "reliable")
func request_item_data() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if item_stack and item_stack.item:
		sync_item.rpc_id(sender_id, item_stack.item.resource_path, item_stack.count, velocity, is_falling, parent.global_position)

@rpc("authority", "reliable")
func sync_item(item_path: String, item_count: int, start_velocity: Vector3, falling: bool, current_position: Vector3) -> void:
	var loaded_item = load(item_path) as InventoryItem
	setup(ItemStack.new(loaded_item, item_count), start_velocity)
	is_falling = falling
	parent.global_position = current_position
	set_physics_process(falling)

func pick_up(picker_id: int):
	sync_interact.rpc(picker_id)

@rpc("call_local", "reliable")
func sync_interact(picker_id: int):
	# Only the player who picked it adds it to their inventory
	if picker_id == multiplayer.get_unique_id():
		var player = get_tree().root.find_child(str(picker_id), true, false)
		if player:
			var inventory: Inventory = player.get_node_or_null("Inventory")
			if inventory:
				inventory.obtain_item(item_stack)
	# Free the item scene (parent node) on all clients
	parent.queue_free()

func setup(stack: ItemStack, start_velocity: Vector3):
	item_stack = stack
	velocity = start_velocity
	
	if override_mesh and item_stack and item_stack.item and item_stack.item.mesh and mesh_instance:
		mesh_instance.mesh = item_stack.item.mesh

func _physics_process(delta: float):
	if not is_falling:
		return

	# 1. Apply Gravity to Velocity
	velocity.y -= gravity * delta

	# 2. Apply Velocity to Position
	parent.global_position += velocity * delta

	# 3. Rotate the mesh slightly for visual flair (optional)
	mesh_instance.rotate_x(5.0 * delta)
	mesh_instance.rotate_z(5.0 * delta)

	# 4. Check if we hit the ground
	if velocity.y < 0: # Only check when falling down
		if ray_cast.is_colliding():
			_land()

func _land():
	is_falling = false
	
	var duration: float = parent.global_position.distance_to(ray_cast.get_collision_point())
	print(duration)
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(parent, "global_position", ray_cast.get_collision_point(), duration)
	tween.parallel().tween_property(mesh_instance, "rotation", Vector3.ZERO, duration)
	tween.tween_callback(func():
		set_physics_process(false)
		)
	
	# Snap exactly to the hit point so we don't float or clip
	#parent.global_position = ray_cast.get_collision_point()
	
	# Reset rotation if you want it upright, or leave it tumbled
	#mesh_instance.rotation = Vector3.ZERO 
	
	# PERFORMANCE OPTIMIZATION: 
	# Stop this script from running _physics_process entirely
	#set_physics_process(false)
