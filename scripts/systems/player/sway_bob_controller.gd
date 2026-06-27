extends Node3D
class_name SwayBobController

@export_group("Sway")
@export var sway_amount: float = 0.03
@export var sway_speed: float = 5.0

@export_group("Bob")
@export var bob_amount_x: float = 0.015
@export var bob_amount_y: float = 0.01
@export var bob_speed: float = 12.0
@export var landing_kick: float = 12.0

var mouse_input: Vector2 = Vector2.ZERO
var bob_time: float = 0.0
var was_on_floor: bool = true

var player: Player:
	get:
		return get_node("../..") as Player
var camera: Camera3D:
	get:
		return player.camera
var spring_arm: SpringArm3D:
	get:
		return player.spring_arm

func _ready() -> void:
	var enabled := is_multiplayer_authority()
	set_process_input(enabled)
	set_physics_process(enabled)

func reset() -> void:
	mouse_input = Vector2.ZERO
	bob_time = 0.0
	position = Vector3.ZERO
	rotation = Vector3.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input += event.relative

func _physics_process(delta: float) -> void:
	var is_on_floor := player.is_on_floor()
	if is_on_floor and not was_on_floor:
		mouse_input.y += landing_kick
	was_on_floor = is_on_floor

	_update_transform(delta)

func _update_transform(delta: float) -> void:
	var head_pos := spring_arm.position if spring_arm else camera.position
	var pitch := _get_pitch()
	var base_position := head_pos - head_pos.rotated(Vector3.RIGHT, pitch)
	var sway := _consume_sway(delta)
	var bob := _get_bob(delta)

	position = base_position + camera.transform.basis * Vector3(sway.x + bob.x, sway.y + bob.y, 0.0)
	rotation.x = pitch
	rotation.y = lerp_angle(rotation.y, -sway.x * 2.0, 10.0 * delta)
	rotation.z = lerp_angle(rotation.z, sway.x, 10.0 * delta)

func _get_pitch() -> float:
	if spring_arm:
		return spring_arm.rotation.x + camera.rotation.x
	return camera.rotation.x

func _consume_sway(delta: float) -> Vector2:
	var sway := Vector2(
		-mouse_input.x * sway_amount * 0.005,
		mouse_input.y * sway_amount * 0.005
	)
	mouse_input = mouse_input.lerp(Vector2.ZERO, sway_speed * delta)
	return sway

func _get_bob(delta: float) -> Vector2:
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor() and horizontal_speed > 0.1:
		bob_time += delta * bob_speed * (horizontal_speed / player.speed)
		return Vector2(cos(bob_time) * bob_amount_x, sin(bob_time * 2.0) * bob_amount_y)

	bob_time = move_toward(bob_time, 0.0, delta * bob_speed)
	return Vector2.ZERO
