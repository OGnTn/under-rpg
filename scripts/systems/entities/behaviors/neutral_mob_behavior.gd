class_name NeutralMobBehavior extends Node

@export var state_chart: StateChart
@export var controller: CharacterBody3D
@export var hittable: Hittable
@export var anim_tree: AnimationTree

@export var wander_radius: float = 10.0
@export var flee_distance: float = 15.0
@export var flee_speed_multiplier: float = 2.0

var original_speed: float = 0.0

func _ready():
	if controller:
		original_speed = controller.movement_speed
	
	if hittable:
		hittable.hit.connect(_on_hit)

func _on_hit(_amount: int, source: Node3D, _pos: Vector3, _normal: Vector3):
	# Only the server controls NPC AI state
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		state_chart.send_event("Damaged")
		if source:
			_flee_from_source(source.global_position)

var flee_target_position: Vector3

func _flee_from_source(source_pos: Vector3):
	if !controller: return
	
	var away_vector = controller.global_position - source_pos
	away_vector.y = 0 # Ignore vertical difference mostly
	var direction = away_vector.normalized()
	flee_target_position = controller.global_position + direction * flee_distance
	
	# Set movement target
	if controller.has_method("set_movement_target"):
		controller.set_movement_target(flee_target_position)

func _on_wander_state_entered():
	if !controller: return
	# AI only runs on the server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	controller.movement_speed = original_speed
	_pick_random_wander_target()

func _pick_random_wander_target():
	var random_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var target_pos = controller.global_position + random_dir * randf_range(2.0, wander_radius)
	if controller.has_method("set_movement_target"):
		controller.set_movement_target(target_pos)

func _on_target_reached():
	# AI only runs on the server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	state_chart.send_event("TargetReached")

func _on_flee_state_entered():
	if !controller: return
	# AI only runs on the server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	controller.movement_speed = original_speed * flee_speed_multiplier
	
func _on_flee_state_exited():
	if !controller: return
	# AI only runs on the server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	controller.movement_speed = original_speed

func freeze():
	state_chart.process_mode = Node.PROCESS_MODE_DISABLED
	
func unfreeze():
	state_chart.process_mode = Node.PROCESS_MODE_INHERIT
