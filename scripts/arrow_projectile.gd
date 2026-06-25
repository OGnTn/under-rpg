extends Node3D
class_name ArrowProjectile

## Simple ray-stepped projectile for fast arrows.

@export var gravity: float = 9.8
@export var stick_on_hit: bool = true

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var shooter: Node
var lifetime: float = 5.0
var _stuck: bool = false

func launch(direction: Vector3, speed: float, shot_damage: float, shot_owner: Node, shot_lifetime: float = 5.0) -> void:
	velocity = direction.normalized() * speed
	damage = shot_damage
	shooter = shot_owner
	lifetime = shot_lifetime
	_face_velocity()

func _physics_process(delta: float) -> void:
	if _stuck:
		return
	
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	
	var previous_position := global_position
	velocity.y -= gravity * delta
	var next_position := previous_position + velocity * delta
	
	var query := PhysicsRayQueryParameters3D.create(previous_position, next_position)
	var excludes: Array[RID] = []
	if shooter is CollisionObject3D:
		excludes.append(shooter.get_rid())
	query.exclude = excludes
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var space_state := get_world_3d().direct_space_state
	var hit := space_state.intersect_ray(query)
	var safety_counter := 0
	while not hit.is_empty() and safety_counter < 32:
		safety_counter += 1
		if _is_valid_hit(hit.collider):
			_on_hit(hit)
			return
		else:
			excludes.append(hit.rid)
			query.exclude = excludes
			hit = space_state.intersect_ray(query)
	
	global_position = next_position
	_face_velocity()

func _is_valid_hit(collider: Node) -> bool:
	if not collider:
		return false
	
	if not collider is Area3D:
		# Physics bodies (e.g. solid walls, floors) are always valid hits.
		return true
		
	# Area3D is only a valid hit if it resolves to a node that has a take_damage method.
	var target_node = collider
	if not target_node.has_method("take_damage"):
		if target_node.has_node("Hitbox"):
			target_node = target_node.get_node("Hitbox")
		elif target_node.has_node("Hittable"):
			target_node = target_node.get_node("Hittable")
		elif "hittable" in target_node and target_node.hittable:
			target_node = target_node.hittable
			
	return target_node != null and target_node.has_method("take_damage")

func _on_hit(hit: Dictionary) -> void:
	global_position = hit.position
	var collider: Object = hit.collider
	
	var target_node = collider
	if target_node and not target_node.has_method("take_damage"):
		if target_node.has_node("Hitbox"):
			target_node = target_node.get_node("Hitbox")
		elif target_node.has_node("Hittable"):
			target_node = target_node.get_node("Hittable")
		elif "hittable" in target_node and target_node.hittable:
			target_node = target_node.hittable
			
	if shooter and shooter.is_multiplayer_authority() and target_node and target_node.has_method("take_damage"):
		var normal: Vector3 = hit.normal if hit.has("normal") else -velocity.normalized()
		_damage_target(target_node, damage, hit.position, normal)
	
	if stick_on_hit:
		_stuck = true
		set_physics_process(false)
	else:
		queue_free()

func _damage_target(target: Node, dmg: float, hit_pos: Vector3, hit_normal: Vector3) -> void:
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
			target.take_damage.rpc(int(dmg), shooter, hit_pos, hit_normal)
		else:
			target.take_damage(int(dmg), shooter, hit_pos, hit_normal)
	else:
		if is_rpc:
			target.take_damage.rpc(dmg, hit_pos, hit_normal)
		else:
			target.take_damage(dmg, hit_pos, hit_normal)

func _face_velocity() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var direction := velocity.normalized()
	global_basis = Basis.looking_at(direction, Vector3.UP)
