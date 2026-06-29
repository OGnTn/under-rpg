extends Node
class_name MineableComponent

signal health_changed(old_value: int, new_value: int)
signal health_depleted()

@export var max_hits: int = 5
@export var destroy_parent_on_depletion: bool = true

@onready var current_hits: int = max_hits:
	set(value):
		var old_value = current_hits
		current_hits = clampi(value, 0, max_hits)
		if old_value != current_hits:
			health_changed.emit(old_value, current_hits)
		if old_value > 0 and current_hits <= 0:
			health_depleted.emit()

func _ready() -> void:
	current_hits = max_hits
	
	# Find sibling Hittable to connect to
	for child in get_parent().get_children():
		if child is Hittable:
			child.hit.connect(_on_hittable_hit)

func _on_hittable_hit(damage: int, damage_source: Node3D, _pos: Vector3, _normal: Vector3) -> void:
	if not _can_mutate():
		return

	var tool_compat = get_parent().find_child("ToolCompatibilityComponent", true, false)
	if tool_compat and not tool_compat.is_compatible(damage_source):
		return

	take_hit()

func take_hit() -> void:
	if not _can_mutate():
		return
	if current_hits <= 0:
		return
	current_hits -= 1
	
	if current_hits <= 0:
		if destroy_parent_on_depletion:
			get_parent().queue_free()

func _can_mutate() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
