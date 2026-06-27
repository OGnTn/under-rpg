extends CharacterBody3D
class_name Player

@export_group("Movement")
@export var speed: float = 5.0
@export var acceleration: float = 15.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

@export_group("Perspective")
@export var is_third_person: bool = false:
	set(value):
		if is_third_person == value:
			return
		is_third_person = value
		_apply_perspective()
@export var third_person_distance: float = 3.0
@export var shoulder_offset: Vector3 = Vector3(0.4, 0.0, 0.0)
@export var eye_position: Vector3 = Vector3(0.0, 1.8476624, 0.10041666)
@export var max_pitch_degrees: float = 85.0

@onready var camera: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = %SpringArm3D
@onready var view_model: Node3D = %ViewModel
@onready var arm_container: Node3D = %ViewModel.get_node("ArmContainer")
@onready var character_model: Node3D = %character_model
@onready var ui_canvas: CanvasLayer = %UICanvas

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var body_global_yaw: float = 0.0
var body_yaw_initialized: bool = false

var inventory: Inventory:
	get:
		return get_node_or_null("Inventory") as Inventory

func _enter_tree() -> void:
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int(), true)

func _ready() -> void:
	_configure_local_player(is_multiplayer_authority())
	_apply_perspective()

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		release_mouse()
	else:
		capture_mouse()

func set_perspective(third_person: bool) -> void:
	is_third_person = third_person

func toggle_perspective() -> void:
	set_perspective(not is_third_person)

func get_aim_camera() -> Camera3D:
	return camera

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)

	if event.is_action_pressed("ui_cancel"):
		toggle_mouse_capture()

	if event.is_action_pressed("toggle_perspective"):
		toggle_perspective()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_apply_gravity(delta)
		_apply_jump()
		_apply_movement(delta)
		move_and_slide()

	_update_character_yaw(delta)

func _configure_local_player(is_local: bool) -> void:
	camera.current = is_local
	ui_canvas.visible = is_local
	set_process_input(is_local)
	set_process_unhandled_input(is_local)

	if is_local:
		capture_mouse()
	else:
		character_model.visible = true
		arm_container.visible = true

func _apply_look(mouse_delta: Vector2) -> void:
	rotate_y(-mouse_delta.x * mouse_sensitivity)

	var pitch_delta := -mouse_delta.y * mouse_sensitivity
	if spring_arm:
		spring_arm.rotate_x(pitch_delta)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, -deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	else:
		camera.rotate_x(pitch_delta)
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

func _apply_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

func _apply_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity := direction * speed

	velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)

func _update_character_yaw(delta: float) -> void:
	if not character_model:
		return

	if not body_yaw_initialized:
		body_global_yaw = global_rotation.y + PI
		body_yaw_initialized = true

	var parent_global_yaw := global_rotation.y
	var angle_diff := wrapf(parent_global_yaw - (body_global_yaw - PI), -PI, PI)
	angle_diff = clamp(angle_diff, -deg_to_rad(75.0), deg_to_rad(75.0))
	body_global_yaw = parent_global_yaw + PI - angle_diff

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var turn_speed := 10.0 if horizontal_speed > 0.1 else 4.0
	body_global_yaw = lerp_angle(body_global_yaw, parent_global_yaw + PI, turn_speed * delta)
	character_model.rotation.y = body_global_yaw - parent_global_yaw

func _apply_perspective() -> void:
	if not is_multiplayer_authority() or not spring_arm:
		return

	spring_arm.spring_length = third_person_distance if is_third_person else 0.0
	spring_arm.position = eye_position + shoulder_offset if is_third_person else eye_position
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO

	if character_model:
		character_model.visible = is_third_person
	if arm_container:
		arm_container.visible = true
