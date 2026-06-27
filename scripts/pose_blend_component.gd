extends AnimationPlayer
class_name PoseBlendComponent

## Procedural pose player for the view-model arm pivot.

signal marker_reached(marker_name: StringName, animation_name: StringName)

@export_group("Defaults")
@export var default_duration: float = 0.5
@export var default_curve: Curve
@export var default_enthusiasm: float = 1.0

@export_group("References")
@export var animation_root_path: NodePath = NodePath("..")
@export var target_node: Node3D

var rest_pose: Dictionary = {
	"position": Vector3(0.6, 1.3, -0.8),
	"rotation": Vector3.ZERO
}
var draw_pose: Dictionary = {}
var draw_amount: float = 0.0

var _animations: Dictionary = {}
var _resolved_poses: Dictionary = {}
var _current_animation: WeaponAttackDefinition
var _current_animation_name: StringName = &""
var _playback_time: float = 0.0
var _progress: float = 0.0
var _playing: bool = false
var _event_marker_emitted: bool = false
var _manual_pose_active: bool = false

func _ready() -> void:
	if not default_curve:
		default_curve = Curve.new()
		default_curve.add_point(Vector2(0.0, 0.0))
		default_curve.add_point(Vector2(1.0, 1.0))
	draw_pose = rest_pose.duplicate()
	_apply_pose(rest_pose)

func set_rest_pose(animation_name: StringName, fallback_position: Vector3, fallback_rotation: Vector3) -> void:
	rest_pose = _load_pose_from_animation(String(animation_name), fallback_position, fallback_rotation)
	if draw_pose.is_empty():
		draw_pose = rest_pose.duplicate()
	if not _playing and draw_amount <= 0.0:
		_apply_pose(rest_pose)

func set_draw_pose(animation_name: StringName) -> void:
	if String(animation_name).is_empty():
		draw_pose = rest_pose.duplicate()
		return
	draw_pose = _load_pose_from_animation(String(animation_name), rest_pose.position, rest_pose.rotation)

func clear_animations() -> void:
	_animations.clear()
	_resolved_poses.clear()
	stop_pose()

func add_animation_clip(animation: WeaponAttackDefinition) -> void:
	if not animation:
		return
	_animations[animation.attack_name] = animation
	_resolved_poses.erase(animation.attack_name)

func set_animation_clips(animations: Array[WeaponAttackDefinition]) -> void:
	_animations.clear()
	_resolved_poses.clear()
	for animation in animations:
		add_animation_clip(animation)

func has_pose_animation(animation_name: StringName) -> bool:
	return _animations.has(animation_name)

func play_pose(animation_name: StringName = &"", custom_blend: float = -1.0, custom_speed: float = 1.0, from_end: bool = false) -> void:
	if not _animations.has(animation_name):
		return
	_current_animation_name = animation_name
	_current_animation = _animations[animation_name] as WeaponAttackDefinition
	_playback_time = _current_animation.get_duration(default_duration) if from_end else 0.0
	_progress = 1.0 if from_end else 0.0
	_playing = true
	_event_marker_emitted = false
	animation_started.emit(animation_name)
	_update_pose_at_progress(_progress)

func play_clip(animation: WeaponAttackDefinition) -> void:
	add_animation_clip(animation)
	play_pose(animation.attack_name)

func stop_pose(keep_state: bool = false) -> void:
	var finished_name: StringName = _current_animation_name
	_playing = false
	_current_animation = null
	_current_animation_name = &""
	_playback_time = 0.0
	_progress = 0.0
	_event_marker_emitted = false
	if not keep_state:
		_apply_idle_pose()
	if not finished_name.is_empty():
		animation_finished.emit(finished_name)

func is_pose_playing() -> bool:
	return _playing

func get_current_animation_name() -> StringName:
	return _current_animation_name

func get_progress() -> float:
	return _progress

func set_draw_amount(amount: float) -> void:
	draw_amount = clamp(amount, 0.0, 1.0)
	if not _playing:
		_apply_idle_pose()

func scrub(animation_name: StringName, progress: float) -> void:
	if not _animations.has(animation_name):
		return
	_current_animation_name = animation_name
	_current_animation = _animations[animation_name] as WeaponAttackDefinition
	_progress = clamp(progress, 0.0, 1.0)
	_manual_pose_active = true
	_update_pose_at_progress(_progress)

func _physics_process(delta: float) -> void:
	if _playing:
		_advance(delta)
		return
	if _manual_pose_active:
		_manual_pose_active = false
		return
	_apply_idle_pose()

func _advance(delta: float) -> void:
	if not _current_animation:
		stop_pose()
		return

	var duration: float = _current_animation.get_duration(default_duration)
	_playback_time += delta
	var normalized_time: float = clamp(_playback_time / max(duration, 0.001), 0.0, 1.0)
	var curve: Curve = _current_animation.get_curve(default_curve)
	if curve:
		_progress = clamp(curve.sample(normalized_time), 0.0, 1.0)
	else:
		_progress = normalized_time

	if not _event_marker_emitted and _progress >= _current_animation.strike_event_time:
		_event_marker_emitted = true
		marker_reached.emit(&"event", _current_animation_name)

	_update_pose_at_progress(_progress)

	if normalized_time >= 1.0:
		stop_pose(true)
		_apply_idle_pose()

func _apply_idle_pose() -> void:
	if draw_amount > 0.0:
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

func _update_pose_at_progress(progress: float) -> void:
	if not _current_animation or not target_node:
		return

	var pose_keys := _get_resolved_pose_keys(_current_animation)
	var from_pose: Dictionary = pose_keys[0]
	var to_pose: Dictionary = pose_keys[pose_keys.size() - 1]

	if progress <= from_pose.progress:
		_apply_pose(_pose_with_enthusiasm(from_pose, _current_animation))
		return

	for i in range(pose_keys.size() - 1):
		var a: Dictionary = pose_keys[i]
		var b: Dictionary = pose_keys[i + 1]
		if progress >= a.progress and progress <= b.progress:
			from_pose = a
			to_pose = b
			break

	if progress >= to_pose.progress:
		_apply_pose(_pose_with_enthusiasm(to_pose, _current_animation))
		return

	var span: float = max(to_pose.progress - from_pose.progress, 0.0001)
	var t: float = (progress - from_pose.progress) / span
	var enthusiastic_from := _pose_with_enthusiasm(from_pose, _current_animation)
	var enthusiastic_to := _pose_with_enthusiasm(to_pose, _current_animation)
	var target_pos: Vector3 = enthusiastic_from.position.lerp(enthusiastic_to.position, t)
	var target_rot: Vector3 = _lerp_rotation(enthusiastic_from.rotation, enthusiastic_to.rotation, t)

	target_node.position = target_pos
	target_node.rotation = target_rot

func _get_resolved_pose_keys(animation: WeaponAttackDefinition) -> Array:
	var key := String(animation.attack_name)
	if _resolved_poses.has(key):
		return _resolved_poses[key]

	var resolved_keys: Array[Dictionary] = []
	for pose_key in animation.pose_keys:
		if not pose_key:
			continue
		var pose := {
			"progress": clamp(pose_key.progress, 0.0, 1.0),
			"position": pose_key.position,
			"rotation": pose_key.rotation
		}
		if pose_key.load_from_animation and not String(pose_key.animation_name).is_empty():
			var loaded_pose := _load_pose_from_animation(
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
	_resolved_poses[key] = resolved_keys
	return resolved_keys

func _sort_pose_keys(a: Dictionary, b: Dictionary) -> bool:
	return a.progress < b.progress

func _pose_with_enthusiasm(pose: Dictionary, animation: WeaponAttackDefinition) -> Dictionary:
	var enthusiasm := animation.get_enthusiasm(default_enthusiasm)
	return {
		"progress": pose.get("progress", 0.0),
		"position": rest_pose.position + (pose.position - rest_pose.position) * enthusiasm,
		"rotation": rest_pose.rotation + (pose.rotation - rest_pose.rotation) * enthusiasm
	}

func _load_pose_from_animation(
	animation_name: String,
	fallback_position: Vector3 = Vector3(0.6, 1.3, -0.8),
	fallback_rotation: Vector3 = Vector3.ZERO
) -> Dictionary:
	var pose := {
		"position": fallback_position,
		"rotation": fallback_rotation
	}

	if animation_name.is_empty() or not has_animation(animation_name) or not target_node:
		return pose

	var animation: Animation = get_animation(animation_name)
	var root: Node = get_node_or_null(animation_root_path)
	if not root:
		return pose

	var relative_path: NodePath = root.get_path_to(target_node)
	var pos_track_path: String = str(relative_path) + ":position"
	var rot_track_path: String = str(relative_path) + ":rotation"
	var pos_track: int = animation.find_track(pos_track_path, Animation.TYPE_VALUE)
	var rot_track: int = animation.find_track(rot_track_path, Animation.TYPE_VALUE)

	if pos_track != -1 and animation.track_get_key_count(pos_track) > 0:
		pose.position = animation.track_get_key_value(pos_track, 0)
	if rot_track != -1 and animation.track_get_key_count(rot_track) > 0:
		pose.rotation = animation.track_get_key_value(rot_track, 0)

	return pose

func _apply_pose(pose: Dictionary) -> void:
	if not target_node:
		return
	target_node.position = pose.position
	target_node.rotation = pose.rotation

func _lerp_rotation(rot_a: Vector3, rot_b: Vector3, t: float) -> Vector3:
	return rot_a.lerp(rot_b, t)
