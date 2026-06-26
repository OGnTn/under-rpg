extends Node3D
class_name SwayBobController

## Handles view model sway and bobbing calculations for the first-person arms.

# Weapon Sway & Bobbing Settings
@export_group("Weapon Sway & Bob")
@export var sway_amount: float = 0.03
@export var sway_speed: float = 5.0
@export var bob_amount_x: float = 0.015
@export var bob_amount_y: float = 0.01
@export var bob_speed: float = 12.0

var player: Player:
	get:
		return get_node("../..") as Player
var camera: Camera3D:
	get:
		return player.camera
var spring_arm: SpringArm3D:
	get:
		return player.spring_arm

var mouse_input: Vector2 = Vector2.ZERO
var bob_time: float = 0.0
var was_on_floor: bool = true

func _ready() -> void:
	if not is_multiplayer_authority():
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input += event.relative

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Detect landing impact to apply a visual dip/shake
	var is_on_floor = player.is_on_floor()
	if is_on_floor and not was_on_floor:
		mouse_input.y += 12.0
	was_on_floor = is_on_floor

	_update_arms(delta)

func _update_arms(delta: float) -> void:
	# Use spring arm position as head reference (works for both FPS and TPS)
	var head_pos: Vector3
	var pitch: float
	if spring_arm:
		head_pos = spring_arm.position
		pitch = spring_arm.rotation.x + camera.rotation.x
	else:
		head_pos = camera.position
		pitch = camera.rotation.x
	
	# Calculate the base position of ArmContainer so it pivots around the head_pos (eye-level)
	# even though the ArmContainer's origin is at (0, 0, 0)
	var base_container_pos = head_pos - head_pos.rotated(Vector3.RIGHT, pitch)
	
	# Calculate weapon sway based on recent mouse input
	var target_sway_x = -mouse_input.x * sway_amount * 0.005
	var target_sway_y = mouse_input.y * sway_amount * 0.005
	
	# Decay accumulated mouse input over time
	mouse_input = mouse_input.lerp(Vector2.ZERO, sway_speed * delta)
	
	# Calculate walking bobbing based on movement speed
	var target_bob_x = 0.0
	var target_bob_y = 0.0
	
	var horizontal_speed = Vector3(player.velocity.x, 0, player.velocity.z).length()
	if player.is_on_floor() and horizontal_speed > 0.1:
		bob_time += delta * bob_speed * (horizontal_speed / player.speed)
		target_bob_x = cos(bob_time) * bob_amount_x
		target_bob_y = sin(bob_time * 2.0) * bob_amount_y
	else:
		bob_time = move_toward(bob_time, 0.0, delta * bob_speed)
	
	# Combine sway and bobbing into local offset vector
	var local_offset = Vector3(target_sway_x + target_bob_x, target_sway_y + target_bob_y, 0.0)
	
	# Rotate the local offset to match camera's pitch
	var oriented_offset = camera.transform.basis * local_offset
	
	# Apply updated position and vertical look rotation
	position = base_container_pos + oriented_offset
	rotation.x = pitch
	
	# Apply a subtle sway rotation (yaw and roll)
	rotation.y = lerp_angle(rotation.y, -target_sway_x * 2.0, 10.0 * delta)
	rotation.z = lerp_angle(rotation.z, target_sway_x * 1.0, 10.0 * delta)
