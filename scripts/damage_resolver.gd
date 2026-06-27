class_name DamageResolver
extends RefCounted

static func resolve_hittable(target: Node) -> Hittable:
	if not target:
		return null
	if target is Hittable:
		return target as Hittable
	if target.has_node("Hitbox"):
		var hitbox := target.get_node("Hitbox")
		if hitbox is Hittable:
			return hitbox as Hittable
	if target.has_node("Hittable"):
		var hittable := target.get_node("Hittable")
		if hittable is Hittable:
			return hittable as Hittable
	if "hittable" in target and target.hittable is Hittable:
		return target.hittable as Hittable
	return null

static func is_hittable(target: Node) -> bool:
	return resolve_hittable(target) != null

static func emit_hit(
	hittable: Hittable,
	damage: int,
	damage_source: Node3D,
	hit_position: Vector3,
	hit_normal: Vector3
) -> bool:
	if not hittable:
		return false

	var source_path := NodePath()
	if damage_source and damage_source.is_inside_tree():
		source_path = damage_source.get_path()

	if hittable.multiplayer.has_multiplayer_peer():
		hittable.receive_hit_rpc.rpc(damage, source_path, hit_position, hit_normal)
	else:
		hittable.receive_hit(damage, damage_source, hit_position, hit_normal)
	return true
