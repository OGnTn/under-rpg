extends CharacterBody3D
class_name Player

## FPS Movement, Looking, and Perspective Controller
## Implements basic movement, looking, mouse capture, and perspective switching.

# Movement Settings
@export_group("Movement")
@export var speed: float = 5.0
@export var acceleration: float = 15.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# Node References
@onready var camera: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = %SpringArm3D
@onready var arm_container: Node3D = %ViewModel.get_node("ArmContainer")
@onready var animation_tree: AnimationTree = %AnimationTree

var inventory: Inventory:
	get:
		return get_node_or_null("Inventory")

## First/third person toggle
@export_group("Perspective")
@export var is_third_person: bool = false:
	set(val):
		if is_third_person != val:
			is_third_person = val
			_apply_perspective()
@export var third_person_distance: float = 3.0
@export var shoulder_offset: Vector3 = Vector3(0.4, 0.0, 0.0)

# Physics & Tracking
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var body_global_yaw: float = 0.0
var body_yaw_initialized: bool = false

func _enter_tree() -> void:
	# Authority must be set here (not _ready) because _enter_tree fires
	# top-down (parent → children), while _ready fires bottom-up.
	#if name.is_valid_int():
	#	%PlayerInput.set_multiplayer_authority(name.to_int())
	pass

func _ready() -> void:
	await get_tree().process_frame
	set_multiplayer_authority(1, true)
	%PlayerInput.set_multiplayer_authority(name.to_int())
	%MultiplayerSynchronizer.set_multiplayer_authority(name.to_int())
	%MultiplayerSpawner.set_multiplayer_authority(name.to_int())
	$RollbackSynchronizer.process_settings()
	DisplayServer.window_set_title(name)
	
	if not %PlayerInput.is_multiplayer_authority():
		camera.current = false
		if has_node("CanvasLayer"):
			%UICanvas.visible = false
		set_process_input(false)
		set_process_unhandled_input(false)
		%character_model.visible = true
		arm_container.visible = true
		return
		
	camera.current = true
	# Capture the mouse by default
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Apply initial perspective state
	_apply_perspective()

func _force_update_is_on_floor():
	var old_velocity = velocity
	velocity = Vector3.ZERO
	move_and_slide()
	velocity = old_velocity

func _input(event: InputEvent) -> void:
	if not %PlayerInput.is_multiplayer_authority():
		return
		
	# Handle mouse looking
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Rotate character body horizontally (yaw)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Rotate vertically (pitch) — spring arm handles it for both perspectives if present
		if spring_arm:
			spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
			spring_arm.rotation.x = clamp(spring_arm.rotation.x, -deg_to_rad(85), deg_to_rad(85))
		else:
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(85), deg_to_rad(85))
	
	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Toggle first/third person perspective
	if event.is_action_pressed("toggle_perspective"):
		_toggle_perspective()


func _physics_process(delta: float) -> void:
	# Smoothly turn body in place or when moving
	var model = get_node_or_null("ViewModel/character_model")
	if model:
		if not body_yaw_initialized:
			body_global_yaw = global_rotation.y + PI
			body_yaw_initialized = true
			
		var parent_global_yaw = global_rotation.y
		var angle_diff = wrapf(parent_global_yaw - (body_global_yaw - PI), -PI, PI)
		angle_diff = clamp(angle_diff, -deg_to_rad(75.0), deg_to_rad(75.0))
		body_global_yaw = parent_global_yaw + PI - angle_diff
		
		var is_moving = velocity.length() > 0.1
		var turn_speed = 10.0 if is_moving else 4.0
		body_global_yaw = lerp_angle(body_global_yaw, parent_global_yaw + PI, turn_speed * delta)
		model.rotation.y = body_global_yaw - parent_global_yaw
	
func _rollback_tick(delta, tick, is_fresh):
	if multiplayer.is_server():
		# Apply gravity
		if not is_on_floor():
			velocity.y -= gravity * delta
	
		# Handle jump
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
	
		# Get input direction
		var input_dir: Vector2 = %PlayerInput.movement
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Apply movement with smooth acceleration/deceleration
		if direction:
			velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
			velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
		velocity *= NetworkTime.physics_factor
		move_and_slide()
		velocity /= NetworkTime.physics_factor

func _toggle_perspective() -> void:
	is_third_person = !is_third_person

func _apply_perspective() -> void:
	if not %PlayerInput.is_multiplayer_authority():
		return
	if not spring_arm:
		return
		
	var model = get_node_or_null("ViewModel/character_model")
	var base_eye_pos := Vector3(0.0, 1.8476624, 0.10041666)
	
	if is_third_person:
		spring_arm.position = base_eye_pos + shoulder_offset
		spring_arm.spring_length = third_person_distance
		# Reset camera local transform — spring arm handles orbit
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		# Show character model
		if model:
			model.visible = true
	else:
		spring_arm.position = base_eye_pos
		spring_arm.spring_length = 0.0
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		# Hide character model, show first-person arms
		if model:
			model.visible = false
		arm_container.visible = true
