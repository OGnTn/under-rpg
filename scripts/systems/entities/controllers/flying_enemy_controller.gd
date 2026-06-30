class_name FlyingEnemyController extends CharacterBody3D

@export var fly_speed: float = 6.0
@export var turn_speed: float = 4.0
@export var custom_up_vector: Vector3 = Vector3.UP

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

@export var animation_tree: AnimationTree

var movement_target: Vector3
var has_target: bool = false

func _ready() -> void:
	# Flying enemies might not use navmesh the same way, but keeping it for consistency if we use 3D navigation later.
	# For now, we might just move directly if navmesh is only on the floor.
	movement_target = global_position

func set_movement_target(target: Vector3):
	movement_target = target
	has_target = true

func _physics_process(delta: float) -> void:
	var is_server = not multiplayer.has_multiplayer_peer() or (multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.is_server())
	if not is_server:
		pass # Implement client-side interpolation if needed, or rely on MultiplayerSynchronizer
		return

	if not has_target:
		velocity = velocity.move_toward(Vector3.ZERO, fly_speed * delta)
		move_and_slide()
		return

	# Direct movement for flying (bypassing floor navigation for now)
	var direction = global_position.direction_to(movement_target)
	var distance = global_position.distance_to(movement_target)
	
	if distance < 1.0:
		velocity = velocity.move_toward(Vector3.ZERO, fly_speed * delta)
		# emit_signal("target_reached") if we had one
	else:
		var target_velocity = direction * fly_speed
		velocity = velocity.move_toward(target_velocity, fly_speed * delta * 2.0)
		
		# Rotate to face movement
		if velocity.length() > 0.1:
			var look_target = global_position + velocity
			var target_xform = global_transform.looking_at(look_target, custom_up_vector)
			global_transform.basis = global_transform.basis.slerp(target_xform.basis, turn_speed * delta)

	move_and_slide()
