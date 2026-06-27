extends Weapon
class_name MeleeWeapon

## Concrete implementation for Melee Weapons (e.g., 1H Sword, 2H Axe).
## Handles instant swings and collision/hurtbox checks.

@export var hurtbox: Area3D
@export var damage: float = 25.0

var hit_enemies: Array[Node3D] = []

func _ready() -> void:
	if not hurtbox:
		# Fallback to finding a child Area3D
		for child in get_children():
			if child is Area3D:
				hurtbox = child
				break

func setup(owner_body: CharacterBody3D, blender: PoseBlendComponent, _camera: Camera3D) -> void:
	owner_character = owner_body
	pose_blender = blender
	camera = _camera
	if pose_blender:
		if definition:
			pose_blender.set_weapon(definition)
		else:
			# Fallback: use blender's active weapon or trigger legacy creation
			if not pose_blender.active_weapon:
				pose_blender.set_weapon(null)
			definition = pose_blender.active_weapon

func primary_pressed() -> void:
	if not pose_blender:
		return
		
	if not pose_blender.is_attacking:
		hit_enemies.clear()
		
		# Determine attack type based on whether the owner is airborne
		var attack_type = &"regular"
		if owner_character:
			owner_character._force_update_is_on_floor()
			if not owner_character.is_on_floor():
				attack_type = &"downward"
		pose_blender.start_attack(attack_type)
		attack_started.emit(attack_type)

func update_weapon(_delta: float) -> void:
	if not pose_blender or not hurtbox:
		return
		
	if pose_blender.is_strike_active():
		var targets = []
		targets.append_array(hurtbox.get_overlapping_bodies())
		targets.append_array(hurtbox.get_overlapping_areas())
		
		for target in targets:
			if target == owner_character:
				continue
				
			var target_node = target
			if target_node and not target_node.has_method("take_damage"):
				if target_node.has_node("Hitbox"):
					target_node = target_node.get_node("Hitbox")
				elif target_node.has_node("Hittable"):
					target_node = target_node.get_node("Hittable")
				elif "hittable" in target_node and target_node.hittable:
					target_node = target_node.hittable
					
			if target_node and target_node not in hit_enemies and target_node.has_method("take_damage"):
				hit_enemies.append(target_node)
				if is_multiplayer_authority():
					var hit_pos = hurtbox.global_position
					var hit_normal = (target_node.global_position - global_position).normalized()
					_damage_target(target_node, damage, hit_pos, hit_normal)


func _damage_target(target: Node, dmg: float, hit_pos: Vector3, hit_normal: Vector3) -> void:
	if !multiplayer.is_server():
		return
	if target and not target.has_method("take_damage"):
		if target.has_node("Hitbox"):
			target = target.get_node("Hitbox")
		elif target.has_node("Hittable"):
			target = target.get_node("Hittable")
		elif "hittable" in target and target.hittable:
			target = target.hittable
			
	if not target or not target.has_method("take_damage"):
		return
	
	var is_rpc = false
	if target.has_method("get_rpc_config"):
		is_rpc = target.get_rpc_config().has(&"take_damage")
		
	if target is Area3D:
		if is_rpc:
			target.take_damage.rpc(int(dmg), self, hit_pos, hit_normal)
		else:
			target.take_damage(int(dmg), self, hit_pos, hit_normal)
	else:
		if is_rpc:
			target.take_damage.rpc(dmg, hit_pos, hit_normal)
		else:
			target.take_damage(dmg, hit_pos, hit_normal)
