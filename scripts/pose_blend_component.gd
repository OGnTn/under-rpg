class_name PoseBlendComponent extends Node

## PoseBlendComponent
## Manages modular weapon attack poses, blend timing, and strike windows.

signal strike_landed
signal attack_event_triggered

# Attack Settings
@export_group("Attack Settings")
@export var attack_curve: Curve
@export var attack_duration: float = 0.5
@export_range(0.0, 1.0) var windup_threshold: float = 0.25
@export_range(0.0, 1.0) var strike_threshold: float = 0.5
@export var attack_enthusiasm: float = 1.0

# Weapon Data
@export_group("Weapon")
@export var weapon_definition: WeaponDefinition

# Node References
@export_group("References")
@export var target_node_path: NodePath
@export var animation_player_path: NodePath

var target_node: Node3D
var animation_player: AnimationPlayer
var active_weapon: WeaponDefinition
var active_hurtbox: Area3D

# Resolved Pose Data
var rest_pose: Dictionary = {"position": Vector3(0.6, 1.3, -0.8), "rotation": Vector3.ZERO}
var resolved_attacks: Dictionary = {}

# Draw Tracking
var is_drawing: bool = false
var draw_amount: float = 0.0
var draw_pose: Dictionary = {}

# Attack Tracking
var is_attacking: bool = false
var attack_time: float = 0.0
var current_attack_type: StringName = &"regular"
var strike_emitted: bool = false

# Channel Tracking
var channel_attack: WeaponAttackDefinition = null
var channel_progress: float = 0.0

func set_channel_state(attack: WeaponAttackDefinition, progress: float) -> void:
	channel_attack = attack
	channel_progress = progress

func _ready() -> void:
	_resolve_nodes()
	
	if not attack_curve:
		attack_curve = Curve.new()
		attack_curve.add_point(Vector2(0, 0))
		attack_curve.add_point(Vector2(1, 1))
	
	_set_weapon(weapon_definition)

func _resolve_nodes() -> void:
	if target_node_path:
		target_node = get_node_or_null(target_node_path)
	else:
		target_node = get_node_or_null("../ViewModel/ArmContainer/ArmPivot")
			
	if animation_player_path:
		animation_player = get_node_or_null(animation_player_path)
	else:
		animation_player = get_node_or_null("../AnimationPlayer")

func set_weapon(new_weapon: WeaponDefinition) -> void:
	_set_weapon(new_weapon)

func _set_weapon(new_weapon: WeaponDefinition) -> void:
	active_weapon = new_weapon if new_weapon else _create_legacy_weapon()
	weapon_definition = new_weapon
	resolved_attacks.clear()
	
	rest_pose = _load_pose_from_anim(
		String(active_weapon.rest_animation),
		active_weapon.rest_position,
		active_weapon.rest_rotation
	)
	
	if active_weapon and &"draw_animation" in active_weapon and not String(active_weapon.draw_animation).is_empty():
		draw_pose = _load_pose_from_anim(
			String(active_weapon.draw_animation),
			rest_pose.position,
			rest_pose.rotation
		)
	else:
		draw_pose = rest_pose.duplicate()
		
	_resolve_hurtbox()
	
	if not is_attacking and not is_drawing:
		_apply_pose(rest_pose)

func _create_legacy_weapon() -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.weapon_name = &"legacy_sword"
	weapon.hurtbox_path = NodePath("../ViewModel/ArmContainer/ArmPivot/Arm/Sword/Hurtbox")
	weapon.rest_animation = &"r_rest"
	weapon.rest_position = Vector3(0.6, 1.3, -0.8)
	weapon.rest_rotation = Vector3.ZERO
	weapon.default_attack = &"regular"
	weapon.attacks = [
		_create_legacy_attack(&"regular", &"r_windup", &"r_strike"),
		_create_legacy_attack(&"downward", &"u_windup", &"u_strike")
	]
	return weapon


func _create_legacy_attack(
	attack_name: StringName,
	windup_animation: StringName,
	strike_animation: StringName
) -> WeaponAttackDefinition:
	var attack := WeaponAttackDefinition.new()
	attack.attack_name = attack_name
	attack.strike_start = windup_threshold
	attack.strike_end = strike_threshold
	attack.strike_event_time = strike_threshold
	attack.pose_keys = [
		_create_pose_key(0.0, &"r_rest"),
		_create_pose_key(windup_threshold, windup_animation),
		_create_pose_key(strike_threshold, strike_animation),
		_create_pose_key(1.0, &"r_rest")
	]
	return attack

func _create_pose_key(progress: float, animation_name: StringName) -> WeaponPoseKey:
	var key := WeaponPoseKey.new()
	key.progress = progress
	key.animation_name = animation_name
	key.load_from_animation = true
	return key

func _resolve_hurtbox() -> void:
	active_hurtbox = null
	if not active_weapon or active_weapon.hurtbox_path.is_empty():
		return
	active_hurtbox = get_node_or_null(active_weapon.hurtbox_path) as Area3D

func get_hurtbox() -> Area3D:
	return active_hurtbox

func _load_pose_from_anim(
	anim_name: String,
	fallback_position: Vector3 = Vector3(0.6, 1.3, -0.8),
	fallback_rotation: Vector3 = Vector3.ZERO
) -> Dictionary:
	var pose = {
		"position": fallback_position,
		"rotation": fallback_rotation
	}
	
	if anim_name.is_empty() or not animation_player or not animation_player.has_animation(anim_name) or not target_node:
		return pose
		
	var anim := animation_player.get_animation(anim_name)
	var root_node := animation_player.get_node(animation_player.root_node)
	var relative_path := root_node.get_path_to(target_node)
	var pos_track_path := str(relative_path) + ":position"
	var rot_track_path := str(relative_path) + ":rotation"
	var pos_track := anim.find_track(pos_track_path, Animation.TYPE_VALUE)
	var rot_track := anim.find_track(rot_track_path, Animation.TYPE_VALUE)
	
	if pos_track != -1 and anim.track_get_key_count(pos_track) > 0:
		pose.position = anim.track_get_key_value(pos_track, 0)
		
	if rot_track != -1 and anim.track_get_key_count(rot_track) > 0:
		pose.rotation = anim.track_get_key_value(rot_track, 0)
		
	return pose

func set_draw_amount(amount: float) -> void:
	is_drawing = amount > 0.0
	draw_amount = amount

func set_charge_amount(amount: float) -> void:
	set_draw_amount(amount)

func start_attack(attack_type: StringName = &"regular") -> void:
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_start_attack_raw.rpc(attack_type)
	else:
		_start_attack_raw(attack_type)

@rpc("any_peer", "call_local", "reliable")
func _start_attack_raw(attack_type: StringName) -> void:
	is_attacking = true
	attack_time = 0.0
	current_attack_type = attack_type
	strike_emitted = false

func _physics_process(delta: float) -> void:
	_update_attack(delta)

func _update_attack(delta: float) -> void:
	if is_attacking:
		var attack := _get_current_attack()
		if not attack:
			is_attacking = false
			_apply_pose(rest_pose)
			return
		
		attack_time += delta
		var duration := attack.get_duration(attack_duration)
		var normalized_time := attack_time / duration
		
		if normalized_time >= 1.0:
			normalized_time = 1.0
			is_attacking = false
			
		var progress := normalized_time
		var curve := attack.get_curve(attack_curve)
		if curve:
			progress = clamp(curve.sample(normalized_time), 0.0, 1.0)
			
		if not strike_emitted and progress >= attack.strike_event_time:
			strike_emitted = true
			strike_landed.emit()
			attack_event_triggered.emit()
			
		_blend_attack_pose(progress, attack)
	elif channel_attack != null:
		_blend_attack_pose(channel_progress, channel_attack)
	elif is_drawing:
		_blend_draw_pose(draw_amount)
	else:
		_apply_pose(rest_pose)

func _blend_draw_pose(amount: float) -> void:
	if not target_node or draw_pose.is_empty():
		return
	var target_pos: Vector3 = rest_pose.position.lerp(draw_pose.position, amount)
	var target_rot: Vector3 = _lerp_rotation(rest_pose.rotation, draw_pose.rotation, amount)
	target_node.position = target_pos
	target_node.rotation = target_rot

func _get_current_attack() -> WeaponAttackDefinition:
	if not active_weapon:
		return null
	var attack := active_weapon.get_attack(current_attack_type)
	if attack:
		return attack
	return active_weapon.get_default_attack()

func _get_resolved_pose_keys(attack: WeaponAttackDefinition) -> Array:
	var key := String(attack.attack_name)
	if resolved_attacks.has(key):
		return resolved_attacks[key]
	
	var resolved_keys: Array[Dictionary] = []
	for pose_key in attack.pose_keys:
		if not pose_key:
			continue
		var pose := {
			"progress": clamp(pose_key.progress, 0.0, 1.0),
			"position": pose_key.position,
			"rotation": pose_key.rotation
		}
		if pose_key.load_from_animation and not String(pose_key.animation_name).is_empty():
			var loaded_pose := _load_pose_from_anim(
				String(pose_key.animation_name),
				pose_key.position,
				pose_key.rotation
			)
			pose.position = loaded_pose.position
			pose.rotation = loaded_pose.rotation
		resolved_keys.append(pose)
	
	if resolved_keys.is_empty():
		resolved_keys.append({
			"progress": 0.0,
			"position": rest_pose.position,
			"rotation": rest_pose.rotation
		})
		resolved_keys.append({
			"progress": 1.0,
			"position": rest_pose.position,
			"rotation": rest_pose.rotation
		})
	
	resolved_keys.sort_custom(_sort_pose_keys)
	resolved_attacks[key] = resolved_keys
	return resolved_keys

func _sort_pose_keys(a: Dictionary, b: Dictionary) -> bool:
	return a.progress < b.progress

func _blend_attack_pose(progress: float, attack: WeaponAttackDefinition) -> void:
	if not target_node:
		return
	
	var pose_keys := _get_resolved_pose_keys(attack)
	var from_pose: Dictionary = pose_keys[0]
	var to_pose: Dictionary = pose_keys[pose_keys.size() - 1]
	
	if progress <= from_pose.progress:
		_apply_pose(_pose_with_enthusiasm(from_pose, attack))
		return
	
	for i in range(pose_keys.size() - 1):
		var a: Dictionary = pose_keys[i]
		var b: Dictionary = pose_keys[i + 1]
		if progress >= a.progress and progress <= b.progress:
			from_pose = a
			to_pose = b
			break
	
	if progress >= to_pose.progress:
		_apply_pose(_pose_with_enthusiasm(to_pose, attack))
		return
	
	var span: float = max(to_pose.progress - from_pose.progress, 0.0001)
	var t = (progress - from_pose.progress) / span
	var enthusiastic_from := _pose_with_enthusiasm(from_pose, attack)
	var enthusiastic_to := _pose_with_enthusiasm(to_pose, attack)
	var target_pos: Vector3 = enthusiastic_from.position.lerp(enthusiastic_to.position, t)
	var target_rot: Vector3 = _lerp_rotation(enthusiastic_from.rotation, enthusiastic_to.rotation, t)
	
	target_node.position = target_pos
	target_node.rotation = target_rot

func _pose_with_enthusiasm(pose: Dictionary, attack: WeaponAttackDefinition) -> Dictionary:
	var enthusiasm := attack.get_enthusiasm(attack_enthusiasm)
	return {
		"progress": pose.get("progress", 0.0),
		"position": rest_pose.position + (pose.position - rest_pose.position) * enthusiasm,
		"rotation": rest_pose.rotation + (pose.rotation - rest_pose.rotation) * enthusiasm
	}

func _apply_pose(pose: Dictionary) -> void:
	if not target_node:
		return
	target_node.position = pose.position
	target_node.rotation = pose.rotation

func _lerp_rotation(rot_a: Vector3, rot_b: Vector3, t: float) -> Vector3:
	return rot_a.lerp(rot_b, t)

func is_strike_active() -> bool:
	if not is_attacking:
		return false
	var attack := _get_current_attack()
	if not attack:
		return false
	var normalized_time := attack_time / attack.get_duration(attack_duration)
	var progress := normalized_time
	var curve := attack.get_curve(attack_curve)
	if curve:
		progress = clamp(curve.sample(normalized_time), 0.0, 1.0)
	return progress >= attack.strike_start and progress < attack.strike_end
