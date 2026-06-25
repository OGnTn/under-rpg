extends CharacterBody3D
class_name Player

## FPS Movement, Looking, and Procedural Melee Attack Controller
## Implements basic movement, looking, mouse capture, weapon sway, bobbing,
## and a curve-driven melee attack pose blending system.

# Movement Settings
@export_group("Movement")
@export var speed: float = 5.0
@export var acceleration: float = 15.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# Weapon Sway & Bobbing Settings
@export_group("Weapon Sway & Bob")
@export var sway_amount: float = 0.03
@export var sway_speed: float = 5.0
@export var bob_amount_x: float = 0.015
@export var bob_amount_y: float = 0.01
@export var bob_speed: float = 12.0

# Node References
@onready var camera: Camera3D = $ViewModel/Camera3D
@onready var spring_arm: SpringArm3D = $ViewModel/SpringArm3D
@onready var arm_container: Node3D = $ViewModel/ArmContainer
@onready var arm_pivot: Node3D = $ViewModel/ArmContainer/ArmPivot
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var pose_blend_component: Node = $PoseBlendComponent
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var inventory: Inventory = $Inventory

var active_weapon: Weapon
var equipped_item_node: Node3D = null

## First/third person toggle
@export_group("Perspective")
@export var is_third_person: bool = false:
	set(val):
		if is_third_person != val:
			is_third_person = val
			_apply_perspective()
@export var third_person_distance: float = 3.0
@export var shoulder_offset: Vector3 = Vector3(0.4, 0.0, 0.0)

@export var equipped_item_path: String = "":
	set(val):
		if equipped_item_path != val:
			equipped_item_path = val
			_apply_equipped_item_path()

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

# Physics & Tracking
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_input: Vector2 = Vector2.ZERO
var bob_time: float = 0.0
var hit_enemies: Array[Node3D] = []
var body_global_yaw: float = 0.0
var body_yaw_initialized: bool = false

func _ready() -> void:
	if inventory:
		inventory.equipment_updated.connect(_update_equipment_visuals)
		_update_equipment_visuals()

	if not is_multiplayer_authority():
		camera.current = false
		if has_node("CanvasLayer"):
			$CanvasLayer.visible = false
		set_process_input(false)
		set_process_unhandled_input(false)
		if has_node("ViewModel/character_model"):
			$ViewModel/character_model.visible = true
		if has_node("ViewModel/ArmContainer"):
			$ViewModel/ArmContainer.visible = false
		return
	
	# Reparent camera under spring arm for unified FPS/TPS control
	if spring_arm and camera.get_parent() != spring_arm:
		var init_pitch = camera.rotation.x
		camera.get_parent().remove_child(camera)
		spring_arm.add_child(camera)
		spring_arm.rotation.x = init_pitch
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		
	camera.current = true
		
	# Capture the mouse by default
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Register inputs automatically if not configured in the Project Settings
	_setup_inputs()
	
	# Connect to the strike signal
	if pose_blend_component:
		pose_blend_component.strike_landed.connect(_on_strike_landed)
		
	# Apply initial perspective state
	_apply_perspective()
	
	# Connect and initialize hotbar selection
	if inventory:
		inventory.hotbar_selection_updated.connect(_on_hotbar_selection_updated)
		_on_hotbar_selection_updated(inventory.get_hotbar_selection())

func _on_strike_landed() -> void:
	# Damage is handled continuously by the hurtbox during the active swing phase,
	# but we keep this callback connected for future visual/audio strike landing effects.
	pass

func _setup_inputs() -> void:
	var inputs = {
		"move_forward": KEY_W,
		"move_backward": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"attack": MOUSE_BUTTON_LEFT,
		"next_weapon": MOUSE_BUTTON_WHEEL_DOWN,
		"prev_weapon": MOUSE_BUTTON_WHEEL_UP
	}
	for action in inputs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event
			if action in ["attack", "next_weapon", "prev_weapon"]:
				event = InputEventMouseButton.new()
				event.button_index = inputs[action]
			else:
				event = InputEventKey.new()
				event.physical_keycode = inputs[action]
			InputMap.action_add_event(action, event)
	
	# Register perspective toggle if not present
	if not InputMap.has_action("toggle_perspective"):
		InputMap.add_action("toggle_perspective")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event("toggle_perspective", ev)

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
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
		
		# Accumulate mouse motion for weapon sway
		mouse_input += event.relative

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

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if active_weapon:
			active_weapon.cancel()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Toggle first/third person perspective
	if event.is_action_pressed("toggle_perspective"):
		_toggle_perspective()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		# Apply gravity
		if not is_on_floor():
			velocity.y -= gravity * delta
	
		# Handle jump
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
	
		# Get input direction
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		# Apply movement with smooth acceleration/deceleration
		if direction:
			velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
			velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
	
		# Detect landing to apply a visual landing dip/shake
		var was_on_floor = is_on_floor()
		move_and_slide()
		if is_on_floor() and not was_on_floor:
			_on_landed()
	
	# Update arm position, rotation, sway and bobbing
	_update_arms(delta)
	
	# Update active weapon processing
	if active_weapon:
		active_weapon.update_weapon(delta, camera)
		
	# Update AnimationTree movement blend position
	_update_movement_animation(delta)
	
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

func _on_landed() -> void:
	# Simulate landing impact by adding a vertical dip to the weapon sway
	mouse_input.y += 12.0

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
	
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.1:
		bob_time += delta * bob_speed * (horizontal_speed / speed)
		target_bob_x = cos(bob_time) * bob_amount_x
		target_bob_y = sin(bob_time * 2.0) * bob_amount_y
	else:
		bob_time = move_toward(bob_time, 0.0, delta * bob_speed)
	
	# Combine sway and bobbing into local offset vector
	var local_offset = Vector3(target_sway_x + target_bob_x, target_sway_y + target_bob_y, 0.0)
	
	# Rotate the local offset to match camera's pitch
	var oriented_offset = camera.transform.basis * local_offset
	
	# Apply updated position and vertical look rotation
	arm_container.position = base_container_pos + oriented_offset
	arm_container.rotation.x = pitch
	
	# Apply a subtle sway rotation (yaw and roll) to ArmContainer
	arm_container.rotation.y = lerp_angle(arm_container.rotation.y, -target_sway_x * 2.0, 10.0 * delta)
	arm_container.rotation.z = lerp_angle(arm_container.rotation.z, target_sway_x * 1.0, 10.0 * delta)

func _update_active_weapon() -> void:
	active_weapon = null
	
	# Find the active weapon among the children of the Arm node
	var arm_node = arm_pivot.get_node("Arm")
	if arm_node:
		for child in arm_node.get_children():
			if child is Weapon and child.visible:
				active_weapon = child
				break
				
	if active_weapon:
		active_weapon.setup(self, pose_blend_component)
	elif pose_blend_component:
		pose_blend_component.set_weapon(pose_blend_component.weapon_definition)

func _on_hotbar_selection_updated(item_stack: ItemStack) -> void:
	if not is_multiplayer_authority():
		return
	if item_stack and not item_stack.is_empty() and item_stack.item.scene:
		equipped_item_path = item_stack.item.resource_path
	else:
		equipped_item_path = ""

func _apply_equipped_item_path() -> void:
	# 1. Unequip/destroy previous equipped node
	if is_instance_valid(equipped_item_node):
		equipped_item_node.queue_free()
		equipped_item_node = null
		
	# 2. Hide all static weapon nodes (Sword, Bow, Wand) so they don't get in the way
	var arm_node = arm_pivot.get_node("Arm")
	if arm_node:
		for child in arm_node.get_children():
			if child is Weapon:
				child.visible = false
				
	# 3. If path is not empty, load and instantiate the scene
	if equipped_item_path != "":
		var item = load(equipped_item_path) as InventoryItem
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

func _update_movement_animation(_delta: float) -> void:
	if not animation_tree:
		return
		
	var blend_pos := Vector2.ZERO
	if speed > 0.0:
		var local_vel := transform.basis.inverse() * velocity
		blend_pos = Vector2(
			clamp(local_vel.x / speed, -1.0, 1.0),
			clamp(-local_vel.z / speed, -1.0, 1.0)
		)
		
	animation_tree.set("parameters/idle-run/blend_position", blend_pos)

func _update_equipment_visuals() -> void:
	if not is_multiplayer_authority():
		return
		
	var helmet_stack = inventory.equipment_container[0]
	var chest_stack = inventory.equipment_container[1]
	var feet_stack = inventory.equipment_container[2]
	
	equipped_helmet_path = helmet_stack.item.resource_path if (helmet_stack and not helmet_stack.is_empty() and helmet_stack.item) else ""
	equipped_chest_path = chest_stack.item.resource_path if (chest_stack and not chest_stack.is_empty() and chest_stack.item) else ""
	equipped_boots_path = feet_stack.item.resource_path if (feet_stack and not feet_stack.is_empty() and feet_stack.item) else ""

func _apply_equipment_visuals_from_paths() -> void:
	var model = get_node_or_null("ViewModel/character_model")
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

func _toggle_perspective() -> void:
	is_third_person = !is_third_person

func _apply_perspective() -> void:
	if not is_multiplayer_authority():
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
