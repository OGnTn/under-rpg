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

static func is_target_owned_by(target: Node, owner_node: Node) -> bool:
	if not target or not owner_node:
		return false
	if target == owner_node or owner_node.is_ancestor_of(target):
		return true
	return is_hittable_owned_by(resolve_hittable(target), owner_node)

static func is_hittable_owned_by(hittable: Hittable, owner_node: Node) -> bool:
	if not hittable or not owner_node:
		return false
	if hittable == owner_node or owner_node.is_ancestor_of(hittable):
		return true
	var hittable_owner := hittable.get_parent()
	if not hittable_owner:
		return false
	return hittable_owner == owner_node or owner_node.is_ancestor_of(hittable_owner)

static func get_damage_source_owner(damage_source: Node) -> Node:
	if not damage_source:
		return null
	if "owner_character" in damage_source and damage_source.owner_character is Node:
		return damage_source.owner_character as Node
	return damage_source

static func emit_hit(
	hittable: Hittable,
	damage: int,
	damage_source: Node3D,
	hit_position: Vector3,
	hit_normal: Vector3
) -> bool:
	if not hittable:
		return false
	if is_hittable_owned_by(hittable, get_damage_source_owner(damage_source)):
		return false

	var source_path := NodePath()
	if damage_source and damage_source.is_inside_tree():
		source_path = damage_source.get_path()

	if hittable.multiplayer.has_multiplayer_peer():
		hittable.receive_hit_rpc.rpc(damage, source_path, hit_position, hit_normal)
	else:
		hittable.receive_hit(damage, damage_source, hit_position, hit_normal)
	return true
