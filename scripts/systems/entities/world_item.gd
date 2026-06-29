class_name WorldItem
extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var ray_cast: RayCast3D = $RayCast3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var item_stack: ItemStack
var velocity: Vector3 = Vector3.ZERO
#var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# If false, the item has landed and stops processing
var is_falling: bool = true

func pick_up(picker_id):
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
	# Free the item on all clients
	queue_free()

func setup(stack: ItemStack, start_velocity: Vector3):
	item_stack = stack
	velocity = start_velocity
	
	if item_stack.item.mesh:
		mesh_instance.mesh = item_stack.item.mesh
	#$Interactable.collectible_item = item_stack.item
	#$Interactable.count = item_stack.count

func _physics_process(delta: float):
	if not is_falling:
		return

	# 1. Apply Gravity to Velocity
	velocity.y -= gravity * delta

	# 2. Apply Velocity to Position
	global_position += velocity * delta

	# 3. Rotate the mesh slightly for visual flair (optional)
	mesh_instance.rotate_x(5.0 * delta)
	mesh_instance.rotate_z(5.0 * delta)

	# 4. Check if we hit the ground
	if velocity.y < 0: # Only check when falling down
		if ray_cast.is_colliding():
			_land()

func _land():
	is_falling = false
	var duration: float = global_position.distance_to(ray_cast.get_collision_point())
	print(duration)
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "global_position", ray_cast.get_collision_point(), duration)
	tween.parallel().tween_property(mesh_instance, "rotation", Vector3.ZERO, duration)
	tween.tween_callback(func():
		set_physics_process(false)
		)
	# Snap exactly to the hit point so we don't float or clip
	#global_position = ray_cast.get_collision_point()
	
	# Align to the floor normal (optional, makes it lie flat)
	# look_at_from_position(global_position, global_position + Vector3.UP, ray_cast.get_collision_normal())
	
	# Reset rotation if you want it upright, or leave it tumbled
	#mesh_instance.rotation = Vector3.ZERO 
	
	# PERFORMANCE OPTIMIZATION: 
	# Stop this script from running _physics_process entirely
	#set_physics_process(false)
