class_name FlyingEnemyBehavior extends Node

@export var state_chart: StateChart
@export var controller: FlyingEnemyController
@export var hittable: Node # Ref to hittable if needed for taking damage
@export var detection_area: Area3D

@export var wander_radius: float = 15.0
@export var wander_altitude_min: float = 6.0
@export var wander_altitude_max: float = 8.0

@export var circle_distance: float = 8.0
@export var circle_speed: float = 1.0 # Radians per second? Or just movement modification

@export var swoop_speed_multiplier: float = 2.0
@export var swoop_duration: float = 1.5

var target_entity: Node3D = null
var spawn_position: Vector3

func _ready() -> void:
	spawn_position = controller.global_position
	# Wait for owner to be ready to ensure controller is valid
	#await owner.ready

# --- SIGNAL CALLBACKS ---

func _on_detection_area_body_entered(body: Node3D) -> void:
	#print("FlyingEnemy: Detection Area Entered by: ", body.name, " Groups: ", body.get_groups())
	if body.is_in_group("players"): # Assuming player group
		print("FlyingEnemy: Player detected!")
		target_entity = body
		state_chart.send_event("PlayerDetected")

func _on_detection_area_body_exited(body: Node3D) -> void:
	if body == target_entity:
		print("FlyingEnemy: Player lost!")
		target_entity = null
		state_chart.send_event("PlayerLost")

# --- STATE LOGIC ---

# WANDER
func _on_wander_state_entered() -> void:
	print("FlyingEnemy: Entering Wander State")
	_pick_wander_target()

func _pick_wander_target():
	var random_offset = Vector3(
		randf_range(-wander_radius, wander_radius),
		randf_range(wander_altitude_min, wander_altitude_max), # Relative or absolute? Let's say relative to spawn Y
		randf_range(-wander_radius, wander_radius)
	)
	var target = spawn_position + random_offset
	# Ensure min altitude
	if target.y < spawn_position.y + wander_altitude_min:
		target.y = spawn_position.y + wander_altitude_min
		
	controller.set_movement_target(target)
	
	# After some time, pick new target? Or wait until reached?
	# Using verify simple timer for now via statechart delayed transition
	
func _on_wander_state_processing(_delta):
	if controller.global_position.distance_to(controller.movement_target) < 2.0:
		_pick_wander_target() # Keep wandering

@export var swoop_cooldown: float = 5.0
var _current_swoop_timer: float = 0.0

# CIRCLE
func _on_circle_state_entered() -> void:
	print("FlyingEnemy: Entering Circle State")
	_current_swoop_timer = swoop_cooldown

func _on_circle_state_physics_process(delta: float) -> void:
	if not is_instance_valid(target_entity):
		state_chart.send_event("PlayerLost")
		return
		
	# Swoop timer
	_current_swoop_timer -= delta
	if _current_swoop_timer <= 0:
		print("FlyingEnemy: Swoop Timer Reached!")
		state_chart.send_event("SwoopStart")
		return

	# Simple orbiting logic: Target position is 'circle_distance' away from player
	# We want to move perpendicular to the vector to the player
	var vector_to_player = controller.global_position.direction_to(target_entity.global_position)
	var distance_to_player = controller.global_position.distance_to(target_entity.global_position)
	
	# If too far, fly close
	if distance_to_player > circle_distance * 1.5:
		controller.set_movement_target(target_entity.global_position + Vector3(0, 4, 0)) # Aim slightly above
	else:
		# Orbit
		var orbit_tangent = vector_to_player.cross(Vector3.UP).normalized()
		var target_pos = target_entity.global_position + (vector_to_player * -1.0 * circle_distance) + (orbit_tangent * 5.0) + Vector3(0, 5, 0)
		controller.set_movement_target(target_pos)

# SWOOP
var swoop_direction: Vector3
func _on_swoop_state_entered() -> void:
	print("FlyingEnemy: Entering Swoop State")
	if not is_instance_valid(target_entity):
		state_chart.send_event("CheckConditions")
		return
		
	controller.fly_speed *= swoop_speed_multiplier
	# Aim at player's current position, maybe slightly predicted
	controller.set_movement_target(target_entity.global_position)

func _on_swoop_state_physics_process(_delta: float) -> void:
	if is_instance_valid(target_entity):
		controller.set_movement_target(target_entity.global_position)

func _on_swoop_state_exited() -> void:
	controller.fly_speed /= swoop_speed_multiplier

# RECOVER
func _on_recover_state_entered() -> void:
	print("FlyingEnemy: Entering Recover State")
	# Fly rapidy upward
	var target = controller.global_position + Vector3(0, 10, 0)
	controller.set_movement_target(target)
