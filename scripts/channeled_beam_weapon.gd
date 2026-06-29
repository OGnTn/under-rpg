extends Weapon
class_name ChanneledBeamWeapon

## Weapon that applies repeated damage while the primary action is held.

@export_group("Damage Settings")
@export var damage_per_second: float = 40.0
@export var damage_tick_rate: float = 0.1 # Apply damage every 0.1s
@export var channeled_hurtbox: Area3D

@export_group("Animations")
@export var channel_attack_name: StringName = &"shoot"

@export_group("Visuals & Muzzle")
@export var beam_visual: Node3D # E.g., a MeshInstance3D representing the cylinder beam
@export var muzzle_path: NodePath
@export var beam_range: float = 10.0 # Length of visual beam if used

var is_channeling: bool = false
var draw_amount: float = 0.0
var _tick_timer: float = 0.0
var _muzzle: Node3D

func _ready() -> void:
	if not muzzle_path.is_empty():
		_muzzle = get_node_or_null(muzzle_path) as Node3D
	if beam_visual:
		beam_visual.visible = false
	if channeled_hurtbox:
		channeled_hurtbox.monitoring = false
		channeled_hurtbox.monitorable = false

func _setup_weapon() -> void:
	if not definition:
		definition = WeaponDefinition.new()

func _press_primary() -> void:
	is_channeling = true
	_tick_timer = 0.0

func _release_primary() -> void:
	_stop_channeling()

func _cancel() -> void:
	_stop_channeling()

func _stop_channeling() -> void:
	if not is_channeling:
		return
	is_channeling = false

func _tick(delta: float) -> void:
	var attack: WeaponAttackDefinition = null
	if definition:
		attack = definition.get_attack(channel_attack_name)
		if not attack:
			attack = definition.get_default_attack()
			
	var duration := 0.25
	var strike_time := 0.0
	if attack:
		if attack.duration > 0.0:
			duration = attack.duration
		strike_time = attack.strike_event_time

	if is_channeling:
		draw_amount = min(draw_amount + delta / duration, 1.0)
	else:
		draw_amount = move_toward(draw_amount, 0.0, delta / duration)
		
	if pose_blender:
		if attack and (is_channeling or draw_amount > 0.0):
			pose_blender.scrub(attack.attack_name, draw_amount)
		else:
			pose_blender.stop_pose()
			
	var should_monitor = is_channeling and draw_amount >= strike_time
	if channeled_hurtbox and channeled_hurtbox.monitoring != should_monitor:
		channeled_hurtbox.monitoring = should_monitor
		
	if beam_visual and beam_visual.visible != should_monitor:
		beam_visual.visible = should_monitor
		
	if not is_channeling:
		return
		
	_tick_timer += delta
	if _tick_timer >= damage_tick_rate:
		_tick_timer -= damage_tick_rate
		if is_multiplayer_authority() and channeled_hurtbox and channeled_hurtbox.monitoring:
			var targets = []
			for body in channeled_hurtbox.get_overlapping_bodies():
				if not DamageResolver.is_target_owned_by(body, owner_character) and not targets.has(body):
					targets.append(body)
			for area in channeled_hurtbox.get_overlapping_areas():
				if not DamageResolver.is_target_owned_by(area, owner_character) and not targets.has(area):
					targets.append(area)
					
			var tick_damage = damage_per_second * damage_tick_rate
			for target_node in targets:
				var actual_target := DamageResolver.resolve_hittable(target_node)
				if actual_target:
					var hit_pos := actual_target.global_position
					var hit_normal = Vector3.UP
					_damage_target(actual_target, tick_damage, hit_pos, hit_normal)
					
	if _muzzle and beam_visual:
		var direction = -_muzzle.global_transform.basis.z.normalized()
		var end_point = _muzzle.global_position + direction * beam_range
		_update_beam_visual(end_point)

func _damage_target(target: Hittable, dmg: float, hit_pos: Vector3, hit_normal: Vector3) -> void:
	DamageResolver.emit_hit(target, int(dmg), self, hit_pos, hit_normal)

func _update_beam_visual(target_position: Vector3) -> void:
	if not beam_visual:
		return
		
	var start_position = _muzzle.global_position if _muzzle else global_position
	
	beam_visual.global_position = start_position.lerp(target_position, 0.5)
	
	var diff = target_position - start_position
	if diff.length_squared() > 0.001:
		beam_visual.look_at(target_position, Vector3.UP)
		
		var distance = diff.length()
		beam_visual.scale.z = distance
