extends CharacterBody3D
class_name Player

## Server-Authoritative FPS Character Controller
##
## Architecture:
##   Server (peer 1) owns all player nodes, processes physics with move_and_slide().
##   Host player reads Input directly - zero latency.
##   Remote clients send input via unreliable RPC; server processes it.
##   MultiplayerSynchronizer replicates position/rotation/velocity/animation to all peers.
##   Non-authority peers receive synced state and update visuals only.

# ============================================================================
# SECTION 1: Exports & Variables
# ============================================================================

# -- Network identity ---------------------------------------------------------
## Which client peer "owns" this character (set by GameManager on spawn).
@export var owning_peer_id: int = 0

# -- Movement -----------------------------------------------------------------
@export_group("Movement")
@export var speed: float = 5.0
@export var acceleration: float = 15.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# -- Weapon Sway & Bob -------------------------------------------------------
@export_group("Weapon Sway & Bob")
@export var sway_amount: float = 0.03
@export var sway_speed: float = 5.0
@export var bob_amount_x: float = 0.015
@export var bob_amount_y: float = 0.01
@export var bob_speed: float = 12.0

# -- Perspective --------------------------------------------------------------
@export_group("Perspective")
@export var is_third_person: bool = false:
	set(val):
		if is_third_person != val:
			is_third_person = val
			_apply_perspective()
@export var third_person_distance: float = 3.0
@export var shoulder_offset: Vector3 = Vector3(0.4, 0.0, 0.0)

# -- Equipment paths (synced via MultiplayerSynchronizer) ----------------------
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

# -- Animation sync (written by server, read by all) ---------------------------
var synced_blend_position: Vector2 = Vector2.ZERO
var synced_is_attacking: bool = false
var synced_body_yaw: float = 0.0
var synced_position: Vector3 = Vector3.ZERO  # target position for smooth interpolation

# -- Node references ----------------------------------------------------------
@onready var camera: Camera3D = $ViewModel/Camera3D
@onready var spring_arm: SpringArm3D = $ViewModel/SpringArm3D
@onready var arm_container: Node3D = $ViewModel/ArmContainer
@onready var arm_pivot: Node3D = $ViewModel/ArmContainer/ArmPivot
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var pose_blend_component: Node = $PoseBlendComponent
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var inventory: Inventory = $Inventory

# -- Runtime state ------------------------------------------------------------
var active_weapon: Weapon
var equipped_item_node: Node3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_input: Vector2 = Vector2.ZERO
var bob_time: float = 0.0
var hit_enemies: Array[Node3D] = []
var body_global_yaw: float = 0.0
var body_yaw_initialized: bool = false

# -- Input accumulators (for RPC batching) ------------------------------------
var _input_direction: Vector3 = Vector3.ZERO
var _input_jump: bool = false
var _input_yaw_delta: float = 0.0
var _input_pitch_delta: float = 0.0
var _input_attack_pressed: bool = false
var _input_attack_released: bool = false
var _input_scroll: int = 0
var _input_toggle_perspective: bool = false
var _input_cancel: bool = false

# -- Server-side remote input cache -------------------------------------------
var _remote_direction: Vector3 = Vector3.ZERO
var _remote_jump: bool = false
var _remote_yaw_delta: float = 0.0
var _remote_pitch_delta: float = 0.0
var _remote_attack_pressed: bool = false
var _remote_attack_released: bool = false
var _remote_scroll: int = 0
var _remote_toggle_perspective: bool = false

# -- Convenience --------------------------------------------------------------
var _is_local_player: bool:
	get:
		return owning_peer_id == multiplayer.get_unique_id()

# ============================================================================
# SECTION 2: Lifecycle
# ============================================================================

func _ready() -> void:
	# Set up network synchronization when multiplayer is active
	if multiplayer.has_multiplayer_peer():
		_setup_network_sync()
	
	if inventory:
		inventory.equipment_updated.connect(_update_equipment_visuals)
		_update_equipment_visuals()
		inventory.hotbar_selection_updated.connect(_on_hotbar_selection_updated)
		_on_hotbar_selection_updated(inventory.get_hotbar_selection())
	
	if pose_blend_component:
		pose_blend_component.strike_landed.connect(_on_strike_landed)
	
	if not _is_local_player:
		_setup_remote_player()
		return
	
	# --- LOCAL PLAYER SETUP ---
	if spring_arm and camera.get_parent() != spring_arm:
		var init_pitch = camera.rotation.x
		camera.get_parent().remove_child(camera)
		spring_arm.add_child(camera)
		spring_arm.rotation.x = init_pitch
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
	
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_inputs()
	_apply_perspective()


func _setup_remote_player() -> void:
	"""Configure this player node as a remote (not owned by us)."""
	if camera:
		camera.current = false
	if has_node("UICanvas"):
		$UICanvas.visible = false
	# Keep ArmContainer visible so remote players' weapons/equipment are shown
	# in third-person. Arms won't animate (no _update_arms call for remotes).
	if has_node("ViewModel/character_model"):
		$ViewModel/character_model.visible = true
	set_process_input(false)
	set_process_unhandled_input(false)


func _setup_network_sync() -> void:
	"""Create and configure a MultiplayerSynchronizer for server-authoritative sync."""
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetworkSync"
	
	# Godot 4.4+ uses SceneReplicationConfig with NodePath ":" prefix for root properties
	var config := SceneReplicationConfig.new()
	# Position & rotation — sync target values, client interpolates smoothly
	config.add_property(NodePath(":synced_position"))
	config.add_property(NodePath(":synced_body_yaw"))
	# Animation state
	config.add_property(NodePath(":synced_blend_position"))
	config.add_property(NodePath(":synced_is_attacking"))
	config.add_property(NodePath(":equipped_item_path"))
	config.add_property(NodePath(":equipped_helmet_path"))
	config.add_property(NodePath(":equipped_chest_path"))
	config.add_property(NodePath(":equipped_boots_path"))
	sync.replication_config = config
	
	add_child(sync)
	print("[Player] MultiplayerSynchronizer created for peer %d" % owning_peer_id)


func _on_strike_landed() -> void:
	pass  # Reserved for future audio/visual effects


func _setup_inputs() -> void:
	var inputs = {
		"move_forward": KEY_W, "move_backward": KEY_S,
		"move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "attack": MOUSE_BUTTON_LEFT,
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
	
	if not InputMap.has_action("toggle_perspective"):
		InputMap.add_action("toggle_perspective")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event("toggle_perspective", ev)

# ============================================================================
# SECTION 3: Input Events (local player only)
# ============================================================================

func _input(event: InputEvent) -> void:
	if not _is_local_player:
		return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if spring_arm:
			spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
			spring_arm.rotation.x = clamp(spring_arm.rotation.x, -deg_to_rad(85), deg_to_rad(85))
		else:
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(85), deg_to_rad(85))
		mouse_input += event.relative
		_input_yaw_delta += -event.relative.x * mouse_sensitivity
		_input_pitch_delta += -event.relative.y * mouse_sensitivity


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player:
		return
	
	if event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_input_attack_pressed = true
	
	if event.is_action_released("attack"):
		_input_attack_released = true
	
	if event.is_action_pressed("next_weapon"):
		_input_scroll += 1
	elif event.is_action_pressed("prev_weapon"):
		_input_scroll -= 1
	
	if event.is_action_pressed("ui_cancel"):
		_input_cancel = true
	
	if event.is_action_pressed("toggle_perspective"):
		_input_toggle_perspective = true

# ============================================================================
# SECTION 4: Authority Physics (server-side)
# ============================================================================

func _physics_process(delta: float) -> void:
	var direction: Vector3
	var wants_jump: bool
	
	if _is_local_player and multiplayer.is_server():
		# HOST'S OWN CHARACTER: read Input directly (zero latency)
		_process_local_attack_input()
		_process_local_misc_input()
		direction = _get_local_direction()
		wants_jump = Input.is_action_just_pressed("jump")
		_input_yaw_delta = 0.0
		_input_pitch_delta = 0.0
	
	elif multiplayer.is_server():
		# SERVER processing remote player's input (from RPC queue)
		_process_remote_attack_input()
		_process_remote_misc_input()
		direction = _remote_direction
		_remote_direction = Vector3.ZERO  # consume — reset so player stops if no new input
		wants_jump = _remote_jump
		_remote_jump = false
		var yd = _remote_yaw_delta
		var pd = _remote_pitch_delta
		_remote_yaw_delta = 0.0
		_remote_pitch_delta = 0.0
		rotate_y(yd)
		if spring_arm:
			spring_arm.rotate_x(pd)
			spring_arm.rotation.x = clamp(spring_arm.rotation.x, -deg_to_rad(85), deg_to_rad(85))
	
	else:
		# NON-AUTHORITY CLIENT
		if _is_local_player:
			_collect_input_for_server()
			_send_input_to_server()
		_update_visuals_from_sync(delta)
		return
	
	# --- AUTHORITY MOVEMENT (server only from here down) ---
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if wants_jump and is_on_floor():
		velocity.y = jump_velocity
	
	if direction:
		velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
	
	var was_on_floor := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_on_floor:
		_on_landed()
	
	# Update synced animation state (MultiplayerSynchronizer will replicate)
	var local_vel := transform.basis.inverse() * velocity
	synced_blend_position = Vector2(
		clamp(local_vel.x / speed, -1.0, 1.0),
		clamp(-local_vel.z / speed, -1.0, 1.0)
	)
	synced_body_yaw = rotation.y
	synced_position = global_position  # target for client interpolation
	
	_update_arms(delta)
	_update_active_weapon_driver(delta)
	_update_movement_animation(delta)
	_update_body_model_rotation(delta)

# ============================================================================
# SECTION 5: Non-Authority Client Logic
# ============================================================================

func _collect_input_for_server() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	_input_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	_input_jump = Input.is_action_just_pressed("jump")


func _send_input_to_server() -> void:
	if not multiplayer.multiplayer_peer:
		return
	
	# Always send — even idle input — so the server always has fresh state.
	# Unreliable UDP means dropped packets won't leave stale movement.
	_submit_input.rpc_id(1,
		_input_direction, _input_jump, _input_yaw_delta, _input_pitch_delta,
		_input_attack_pressed, _input_attack_released, _input_scroll,
		_input_toggle_perspective
	)
	
	_input_jump = false
	_input_yaw_delta = 0.0
	_input_pitch_delta = 0.0
	_input_attack_pressed = false
	_input_attack_released = false
	_input_scroll = 0
	_input_toggle_perspective = false


func _update_visuals_from_sync(delta: float) -> void:
	# Smoothly interpolate toward server-authoritative position (eliminates jitter)
	const LERP_SPEED := 25.0
	global_position = global_position.lerp(synced_position, clamp(delta * LERP_SPEED, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, synced_body_yaw, clamp(delta * LERP_SPEED, 0.0, 1.0))
	
	# Smooth animation blend (lerp toward target to avoid snapping)
	var current_blend := Vector2.ZERO
	if animation_tree:
		current_blend = animation_tree.get("parameters/idle-run/blend_position")
	var smooth_blend := current_blend.lerp(synced_blend_position, clamp(delta * 15.0, 0.0, 1.0))
	if animation_tree:
		animation_tree.set("parameters/idle-run/blend_position", smooth_blend)
	
	_update_body_model_rotation(delta)
	# Always drive weapon animations so remote players' attacks are visible
	_update_active_weapon_driver(delta)
	if _is_local_player:
		_update_arms(delta)

# ============================================================================
# SECTION 6: Shared Visual Updates
# ============================================================================

func _update_arms(delta: float) -> void:
	var head_pos: Vector3
	var pitch: float
	if spring_arm:
		head_pos = spring_arm.position
		pitch = spring_arm.rotation.x + camera.rotation.x
	else:
		head_pos = camera.position
		pitch = camera.rotation.x
	
	var base_container_pos = head_pos - head_pos.rotated(Vector3.RIGHT, pitch)
	var target_sway_x = -mouse_input.x * sway_amount * 0.005
	var target_sway_y = mouse_input.y * sway_amount * 0.005
	mouse_input = mouse_input.lerp(Vector2.ZERO, sway_speed * delta)
	
	var target_bob_x := 0.0
	var target_bob_y := 0.0
	var horizontal_speed := Vector3(velocity.x, 0, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.1:
		bob_time += delta * bob_speed * (horizontal_speed / speed)
		target_bob_x = cos(bob_time) * bob_amount_x
		target_bob_y = sin(bob_time * 2.0) * bob_amount_y
	else:
		bob_time = move_toward(bob_time, 0.0, delta * bob_speed)
	
	var local_offset := Vector3(target_sway_x + target_bob_x, target_sway_y + target_bob_y, 0.0)
	var oriented_offset := camera.transform.basis * local_offset
	arm_container.position = base_container_pos + oriented_offset
	arm_container.rotation.x = pitch
	arm_container.rotation.y = lerp_angle(arm_container.rotation.y, -target_sway_x * 2.0, 10.0 * delta)
	arm_container.rotation.z = lerp_angle(arm_container.rotation.z, target_sway_x * 1.0, 10.0 * delta)


func _update_active_weapon_driver(delta: float) -> void:
	if active_weapon:
		active_weapon.update_weapon(delta, camera)
	if pose_blend_component:
		pose_blend_component._physics_process(delta)


func _update_movement_animation(_delta: float) -> void:
	if not animation_tree:
		return
	animation_tree.set("parameters/idle-run/blend_position", synced_blend_position)


func _update_body_model_rotation(delta: float) -> void:
	var model := get_node_or_null("ViewModel/character_model")
	if not model:
		return
	if not body_yaw_initialized:
		body_global_yaw = global_rotation.y + PI
		body_yaw_initialized = true
	var parent_global_yaw := global_rotation.y
	var angle_diff := wrapf(parent_global_yaw - (body_global_yaw - PI), -PI, PI)
	angle_diff = clamp(angle_diff, -deg_to_rad(75.0), deg_to_rad(75.0))
	body_global_yaw = parent_global_yaw + PI - angle_diff
	var is_moving := velocity.length() > 0.1
	var turn_speed := 10.0 if is_moving else 4.0
	body_global_yaw = lerp_angle(body_global_yaw, parent_global_yaw + PI, turn_speed * delta)
	model.rotation.y = body_global_yaw - parent_global_yaw


func _on_landed() -> void:
	mouse_input.y += 12.0

# ============================================================================
# SECTION 7: Input Helpers
# ============================================================================

func _get_local_direction() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	return (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()


func _process_local_attack_input() -> void:
	if _input_attack_pressed:
		if active_weapon:
			active_weapon.primary_pressed()
		_input_attack_pressed = false
	if _input_attack_released:
		if active_weapon:
			active_weapon.primary_released()
		_input_attack_released = false


func _process_local_misc_input() -> void:
	if _input_scroll != 0:
		_switch_weapon(_input_scroll)
		_input_scroll = 0
	if _input_cancel:
		if active_weapon:
			active_weapon.cancel()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_input_cancel = false
	if _input_toggle_perspective:
		_toggle_perspective()
		_input_toggle_perspective = false


func _process_remote_attack_input() -> void:
	if _remote_attack_pressed:
		if active_weapon:
			active_weapon.primary_pressed()
		_remote_attack_pressed = false
	if _remote_attack_released:
		if active_weapon:
			active_weapon.primary_released()
		_remote_attack_released = false


func _process_remote_misc_input() -> void:
	if _remote_scroll != 0:
		_switch_weapon(_remote_scroll)
		_remote_scroll = 0
	if _remote_toggle_perspective:
		_toggle_perspective()
		_remote_toggle_perspective = false

# ============================================================================
# SECTION 8: RPCs
# ============================================================================

@rpc("unreliable", "any_peer")
func _submit_input(
	direction: Vector3,
	jump: bool,
	yaw_delta: float,
	pitch_delta: float,
	attack_pressed: bool,
	attack_released: bool,
	scroll: int,
	toggle_perspective: bool
) -> void:
	if not multiplayer.is_server():
		return
	_remote_direction = direction
	if jump:
		_remote_jump = true
	_remote_yaw_delta += yaw_delta
	_remote_pitch_delta += pitch_delta
	if attack_pressed:
		_remote_attack_pressed = true
	if attack_released:
		_remote_attack_released = true
	_remote_scroll += scroll
	if toggle_perspective:
		_remote_toggle_perspective = true


## Client → Server: request to equip a weapon/item in hand.
@rpc("any_peer", "reliable")
func _request_equip_item(item_path: String) -> void:
	if not multiplayer.is_server():
		return
	equipped_item_path = item_path


## Client → Server: request to equip armor.
@rpc("any_peer", "reliable")
func _request_equip_armor(helmet_path: String, chest_path: String, boots_path: String) -> void:
	if not multiplayer.is_server():
		return
	equipped_helmet_path = helmet_path
	equipped_chest_path = chest_path
	equipped_boots_path = boots_path

# ============================================================================
# SECTION 9: Equipment & Weapon Management
# ============================================================================

func _update_active_weapon() -> void:
	active_weapon = null
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
	if not _is_local_player:
		return
	
	var path := ""
	if item_stack and not item_stack.is_empty() and item_stack.item.scene:
		path = item_stack.item.resource_path
	
	# In multiplayer, send equip request to server so the synchronizer
	# broadcasts to all peers (including back to us — overwriting local set).
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_equip_item.rpc_id(1, path)
	else:
		equipped_item_path = path


func _apply_equipped_item_path() -> void:
	if is_instance_valid(equipped_item_node):
		equipped_item_node.queue_free()
		equipped_item_node = null
	var arm_node = arm_pivot.get_node("Arm")
	if arm_node:
		for child in arm_node.get_children():
			if child is Weapon:
				child.visible = false
	if equipped_item_path != "":
		var item = load(equipped_item_path) as InventoryItem
		if item and item.scene:
			var instance = item.scene.instantiate()
			if instance:
				arm_node.add_child(instance)
				instance.visible = true
				if "item_resource" in instance:
					instance.item_resource = item
				instance.name = item.scene.get_state().get_node_name(0)
				equipped_item_node = instance
	_update_active_weapon()


func _switch_weapon(direction: int) -> void:
	if not _is_local_player:
		return
	if inventory:
		var new_selection = (inventory.hotbar_selection + direction) % inventory.hotbar_size
		if new_selection < 0:
			new_selection = inventory.hotbar_size - 1
		inventory.handle_hotbar_select(new_selection)


func _update_equipment_visuals() -> void:
	if not _is_local_player:
		return
	var h = inventory.equipment_container[0]
	var c = inventory.equipment_container[1]
	var f = inventory.equipment_container[2]
	var hp = h.item.resource_path if (h and not h.is_empty() and h.item) else ""
	var cp = c.item.resource_path if (c and not c.is_empty() and c.item) else ""
	var fp = f.item.resource_path if (f and not f.is_empty() and f.item) else ""
	
	# In multiplayer, route through server so the synchronizer broadcasts to all
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_equip_armor.rpc_id(1, hp, cp, fp)
	else:
		equipped_helmet_path = hp
		equipped_chest_path = cp
		equipped_boots_path = fp


func _apply_equipment_visuals_from_paths() -> void:
	var model = get_node_or_null("ViewModel/character_model")
	if not model:
		return
	_attach_equipment(model, "slot_helmet", equipped_helmet_path)
	_attach_equipment(model, "slot_chest", equipped_chest_path)
	_attach_equipment_to_both_feet(model, "slot_foot_l", "slot_foot_r", equipped_boots_path)


func _attach_equipment(model: Node, slot_name: String, path: String) -> void:
	var slot = model.find_child(slot_name, true, false)
	if not slot:
		return
	for child in slot.get_children():
		child.queue_free()
	if path != "":
		var item = load(path) as EquipmentItem
		if item and item.scene:
			slot.add_child(item.scene.instantiate())


func _attach_equipment_to_both_feet(model: Node, sl: String, sr: String, path: String) -> void:
	for s in [sl, sr]:
		var slot = model.find_child(s, true, false)
		if slot:
			for child in slot.get_children():
				child.queue_free()
			if path != "":
				var item = load(path) as EquipmentItem
				if item and item.scene:
					slot.add_child(item.scene.instantiate())

# ============================================================================
# SECTION 10: Perspective Toggle
# ============================================================================

func _toggle_perspective() -> void:
	is_third_person = !is_third_person


func _apply_perspective() -> void:
	if not _is_local_player:
		return
	if not spring_arm:
		return
	var model = get_node_or_null("ViewModel/character_model")
	var base_eye_pos := Vector3(0.0, 1.8476624, 0.10041666)
	if is_third_person:
		spring_arm.position = base_eye_pos + shoulder_offset
		spring_arm.spring_length = third_person_distance
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		if model:
			model.visible = true
	else:
		spring_arm.position = base_eye_pos
		spring_arm.spring_length = 0.0
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		if model:
			model.visible = false
		arm_container.visible = true
