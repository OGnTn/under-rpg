extends Weapon
class_name ChargeWeapon

## Weapon that charges while held, then fires a projectile on release.

@export_group("Draw Settings")
@export var draw_time: float = 1.0
@export_range(0.0, 1.0) var minimum_shot_power: float = 0.15
@export var reset_speed: float = 8.0

@export_group("Projectile Settings")
@export var projectile_scene: PackedScene
@export var min_projectile_speed: float = 12.0
@export var max_projectile_speed: float = 45.0
@export var min_damage: float = 8.0
@export var max_damage: float = 35.0
@export var projectile_lifetime: float = 5.0

@export_group("Visuals & Muzzle")
@export var visuals_path: NodePath = NodePath("Visuals")
@export var blend_shape_name: StringName = &"Key 1"
@export var muzzle_path: NodePath

var draw_amount: float = 0.0
var is_drawing: bool = false
var _draw_elapsed: float = 0.0

var _visuals: MeshInstance3D
var _muzzle: Node3D

func _ready() -> void:
	if not visuals_path.is_empty():
		_visuals = get_node_or_null(visuals_path) as MeshInstance3D
	if not muzzle_path.is_empty():
		_muzzle = get_node_or_null(muzzle_path) as Node3D

func _setup_weapon() -> void:
	if not definition:
		definition = _create_fallback_definition()

func _create_fallback_definition() -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.weapon_name = &"bow"
	weapon.rest_animation = &"r_rest"
	weapon.rest_position = Vector3(0.6, 1.3, -0.8)
	weapon.rest_rotation = Vector3.ZERO
	weapon.draw_animation = &"bow_windup"
	weapon.default_attack = &"shoot"
	
	var attack := WeaponAttackDefinition.new()
	attack.attack_name = &"shoot"
	attack.strike_start = 0.0
	attack.strike_end = 0.3
	attack.strike_event_time = 0.0
	attack.duration = 0.5
	
	var k1 := WeaponPoseKey.new()
	k1.progress = 0.0
	k1.animation_name = &"bow_windup"
	k1.load_from_animation = true
	
	var k2 := WeaponPoseKey.new()
	k2.progress = 0.3
	k2.animation_name = &"bow_strike"
	k2.load_from_animation = true
	
	var k3 := WeaponPoseKey.new()
	k3.progress = 1.0
	k3.animation_name = &"r_rest"
	k3.load_from_animation = true
	
	attack.pose_keys = [k1, k2, k3]
	weapon.attacks = [attack]
	return weapon

func _press_primary() -> void:
	is_drawing = true
	_draw_elapsed = 0.0

func _release_primary() -> void:
	if not is_drawing:
		return
		
	var shot_power = clamp(draw_amount, minimum_shot_power, 1.0)
	is_drawing = false
	_draw_elapsed = 0.0
	
	if is_multiplayer_authority():
		var aim_source := get_aim_source()
		
		if aim_source:
			var launch_transform := _get_launch_transform(aim_source)
			var direction := -aim_source.global_transform.basis.z
			if multiplayer.has_multiplayer_peer():
				_fire_projectile_rpc.rpc(launch_transform, direction, shot_power)
			else:
				_fire_projectile_rpc(launch_transform, direction, shot_power)

@rpc("any_peer", "call_local", "reliable")
func _fire_projectile_rpc(launch_transform: Transform3D, direction: Vector3, shot_power: float) -> void:
	if not projectile_scene:
		return
		
	var proj := projectile_scene.instantiate()
	var parent := get_tree().current_scene
	if not parent:
		parent = get_tree().root
	parent.add_child(proj)
	
	proj.global_transform = launch_transform
	
	var speed = lerp(min_projectile_speed, max_projectile_speed, shot_power)
	var damage = lerp(min_damage, max_damage, shot_power)
	if proj.has_method("launch"):
		proj.launch(direction, speed, damage, owner_character, projectile_lifetime, self)
		
	weapon_fired.emit()
	
	if pose_blender:
		pose_blender.set_draw_amount(0.0)
		pose_blender.play_pose(&"shoot")

func _cancel() -> void:
	is_drawing = false
	_draw_elapsed = 0.0
	if pose_blender:
		pose_blender.set_draw_amount(0.0)

func _tick(delta: float) -> void:
	if is_drawing:
		var safe_draw_time = max(draw_time, 0.001)
		_draw_elapsed = min(_draw_elapsed + delta, safe_draw_time)
		draw_amount = clamp(_draw_elapsed / safe_draw_time, 0.0, 1.0)
	else:
		draw_amount = move_toward(draw_amount, 0.0, reset_speed * delta)
		
	_apply_draw_amount()
	
	if pose_blender:
		pose_blender.set_draw_amount(draw_amount)

func _apply_draw_amount() -> void:
	if _visuals and not blend_shape_name.is_empty():
		_visuals.set("blend_shapes/%s" % blend_shape_name, draw_amount)

func _get_launch_transform(aim_source: Node3D) -> Transform3D:
	var launch_transform := aim_source.global_transform
	if _muzzle:
		launch_transform.origin = _muzzle.global_position
	else:
		launch_transform.origin += -aim_source.global_transform.basis.z * 0.6
	return launch_transform
