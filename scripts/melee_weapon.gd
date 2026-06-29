extends Weapon
class_name MeleeWeapon

## Swing weapon that owns melee hit windows and damage.

@export var hurtbox: Area3D
@export var damage: float = 25.0

var hit_enemies: Array[Hittable] = []
var current_attack: WeaponAttackDefinition
var hit_window_active: bool = false
var is_attacking: bool = false

func _ready() -> void:
	if not hurtbox:
		for child in get_children():
			if child is Area3D:
				hurtbox = child
				break

func _setup_weapon() -> void:
	if not definition:
		definition = _create_fallback_definition()
	if pose_blender and not pose_blender.animation_finished.is_connected(_on_pose_animation_finished):
		pose_blender.animation_finished.connect(_on_pose_animation_finished)

func _press_primary() -> void:
	if not pose_blender or is_attacking:
		return

	var attack_name := &"regular"
	if owner_character and not owner_character.is_on_floor():
		attack_name = &"downward"

	var attack := get_attack(attack_name)
	if not attack:
		return

	current_attack = attack
	is_attacking = true
	hit_window_active = false
	hit_enemies.clear()

	pose_blender.play_pose(current_attack.attack_name)
	attack_started.emit(current_attack.attack_name)

func _cancel() -> void:
	_finish_attack()
	if pose_blender:
		pose_blender.stop_pose()

func _tick(_delta: float) -> void:
	if not is_attacking or not current_attack or not pose_blender:
		return

	_update_hit_window()
	if hit_window_active and hurtbox and is_multiplayer_authority():
		_damage_overlapping_targets()

func _update_hit_window() -> void:
	if not pose_blender.is_pose_playing():
		hit_window_active = false
		return

	var progress := pose_blender.get_progress()
	hit_window_active = progress >= current_attack.strike_start and progress < current_attack.strike_end

func _damage_overlapping_targets() -> void:
	var targets: Array = []
	targets.append_array(hurtbox.get_overlapping_bodies())
	targets.append_array(hurtbox.get_overlapping_areas())

	for target in targets:
		if DamageResolver.is_target_owned_by(target, owner_character):
			continue

		var target_node := DamageResolver.resolve_hittable(target)
		if not target_node or target_node in hit_enemies:
			continue

		hit_enemies.append(target_node)
		var hit_pos := hurtbox.global_position
		var hit_normal := (target_node.global_position - global_position).normalized()
		_damage_target(target_node, damage, hit_pos, hit_normal)

func _damage_target(target: Hittable, dmg: float, hit_pos: Vector3, hit_normal: Vector3) -> void:
	DamageResolver.emit_hit(target, int(dmg), self, hit_pos, hit_normal)

func _on_pose_animation_finished(animation_name: StringName) -> void:
	if current_attack and animation_name == current_attack.attack_name:
		_finish_attack()

func _finish_attack() -> void:
	if not is_attacking:
		return
	is_attacking = false
	hit_window_active = false
	current_attack = null
	attack_completed.emit()

func _create_fallback_definition() -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.weapon_name = &"legacy_sword"
	weapon.hurtbox_path = NodePath("Hurtbox")
	weapon.rest_animation = &"r_rest"
	weapon.rest_position = Vector3(0.6, 1.3, -0.8)
	weapon.rest_rotation = Vector3.ZERO
	weapon.default_attack = &"regular"
	weapon.attacks = [
		_create_attack(&"regular", &"r_windup", &"r_strike"),
		_create_attack(&"downward", &"u_windup", &"u_strike")
	]
	return weapon

func _create_attack(attack_name: StringName, windup_animation: StringName, strike_animation: StringName) -> WeaponAttackDefinition:
	var attack := WeaponAttackDefinition.new()
	attack.attack_name = attack_name
	attack.strike_start = 0.25
	attack.strike_end = 0.5
	attack.strike_event_time = 0.5
	attack.pose_keys = [
		_create_pose_key(0.0, &"r_rest"),
		_create_pose_key(0.25, windup_animation),
		_create_pose_key(0.5, strike_animation),
		_create_pose_key(1.0, &"r_rest")
	]
	return attack

func _create_pose_key(progress: float, animation_name: StringName) -> WeaponPoseKey:
	var key := WeaponPoseKey.new()
	key.progress = progress
	key.animation_name = animation_name
	key.load_from_animation = true
	return key
