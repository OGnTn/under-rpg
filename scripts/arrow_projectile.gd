extends Node3D
class_name ArrowProjectile

## Simple ray-stepped projectile for fast arrows.

@export var gravity: float = 9.8
@export var stick_on_hit: bool = true

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var shooter: Node
var damage_source: Node3D
var lifetime: float = 5.0
var _stuck: bool = false

func launch(
	direction: Vector3,
	speed: float,
	shot_damage: float,
	shot_owner: Node,
	shot_lifetime: float = 5.0,
	shot_damage_source: Node3D = null
) -> void:
	velocity = direction.normalized() * speed
	damage = shot_damage
	shooter = shot_owner
	if shot_damage_source:
		damage_source = shot_damage_source
	else:
		damage_source = shot_owner as Node3D
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
	if DamageResolver.is_target_owned_by(collider, shooter):
		return false
	
	if not collider is Area3D:
		# Physics bodies (e.g. solid walls, floors) are always valid hits.
		return true
		
	return DamageResolver.is_hittable(collider)

func _on_hit(hit: Dictionary) -> void:
	global_position = hit.position
	var collider: Object = hit.collider
	
	var target_node := DamageResolver.resolve_hittable(collider as Node)
	if shooter and shooter.is_multiplayer_authority() and target_node:
		var normal: Vector3 = hit.normal if hit.has("normal") else -velocity.normalized()
		_damage_target(target_node, damage, hit.position, normal)
	
	if stick_on_hit:
		_stuck = true
		set_physics_process(false)
	else:
		queue_free()

func _damage_target(target: Hittable, dmg: float, hit_pos: Vector3, hit_normal: Vector3) -> void:
	DamageResolver.emit_hit(target, int(dmg), damage_source, hit_pos, hit_normal)

func _face_velocity() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var direction := velocity.normalized()
	global_basis = Basis.looking_at(direction, Vector3.UP)
