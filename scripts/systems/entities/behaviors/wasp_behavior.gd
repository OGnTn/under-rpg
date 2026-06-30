class_name WaspBehavior extends Node

@export var state_chart: StateChart
@export var controller: CharacterBody3D # The controller is FlyingEnemyController
@export var hittable: Node # Ref to hittable if needed for taking damage
@export var detection_area: Area3D

@export var wander_radius: float = 15.0
@export var wander_altitude_min: float = 0.5
@export var wander_altitude_max: float = 3.0

@export var circle_distance: float = 8.0
@export var circle_speed: float = 1.0

@export var swoop_speed_multiplier: float = 2.0
@export var swoop_duration: float = 1.5
@export var swoop_cooldown: float = 5.0

@export var attack_distance: float = 2.5
@export var attack_damage: int = 15
@export var crawl_speed: float = 2.0

var target_entity: Node3D = null
var spawn_position: Vector3
var _current_swoop_timer: float = 0.0
var _has_attacked_this_swoop: bool = false
var _original_fly_speed: float = 6.0
var _is_crawling: bool = false
var _fly_walk_blend: float = 0.0

func _ready() -> void:
	spawn_position = controller.global_position
	if "fly_speed" in controller:
		_original_fly_speed = controller.fly_speed
	if "animation_tree" in controller and controller.animation_tree:
		controller.animation_tree.active = true
		print("WaspBehavior: Activated AnimationTree.")
		_stop_direct_animation_player()
		call_deferred("_stop_direct_animation_player")

func _physics_process(delta: float) -> void:
	_update_fly_walk_blend(delta)

func _stop_direct_animation_player() -> void:
	if not controller:
		return

	var ap = controller.get_node_or_null("wasp2/AnimationPlayer") as AnimationPlayer
	if not ap and "animation_tree" in controller and controller.animation_tree:
		ap = controller.animation_tree.get_node_or_null(controller.animation_tree.anim_player) as AnimationPlayer

	if ap:
		ap.stop()
		print("WaspBehavior: Stopped AnimationPlayer playback.")

# --- SIGNAL CALLBACKS ---

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("players"):
		print("WaspBehavior: Player detected!")
		target_entity = body
		state_chart.send_event("PlayerDetected")

func _on_detection_area_body_exited(body: Node3D) -> void:
	if body == target_entity:
		print("WaspBehavior: Player lost!")
		target_entity = null
		state_chart.send_event("PlayerLost")

# --- STATE LOGIC ---

# WANDER (Flying)
func _on_wander_state_entered() -> void:
	print("WaspBehavior: Entering Wander State")
	_is_crawling = false
	if "custom_up_vector" in controller:
		controller.custom_up_vector = Vector3.UP
	_pick_wander_target()

func _pick_wander_target():
	var random_offset_xz = Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	var target = spawn_position + random_offset_xz
	var ground_y = _get_ground_height(target)
	
	# Flying wander target is above ground
	target.y = ground_y + randf_range(wander_altitude_min, wander_altitude_max)
	
	if controller.has_method("set_movement_target"):
		controller.set_movement_target(target)

func _on_wander_state_processing(_delta):
	if controller.global_position.distance_to(controller.movement_target) < 2.0:
		_pick_wander_target()

# CRAWL (Walking/Crawling on ground or walls)
func _on_crawl_state_entered() -> void:
	print("WaspBehavior: Entering Crawl State")
	_is_crawling = true
	if "fly_speed" in controller:
		controller.fly_speed = crawl_speed
	_pick_crawl_target()

func _on_crawl_state_processing(delta: float) -> void:
	if controller.global_position.distance_to(controller.movement_target) < 1.5:
		_pick_crawl_target()
		
	# Align to surface
	var normal = _get_surface_normal()
	if "custom_up_vector" in controller:
		controller.custom_up_vector = controller.custom_up_vector.lerp(normal, delta * 5.0)

func _on_crawl_state_exited() -> void:
	print("WaspBehavior: Exiting Crawl State")
	_is_crawling = false
	if "fly_speed" in controller:
		controller.fly_speed = _original_fly_speed
	if "custom_up_vector" in controller:
		controller.custom_up_vector = Vector3.UP

func _pick_crawl_target():
	var random_offset_xz = Vector3(
		randf_range(-wander_radius * 0.5, wander_radius * 0.5),
		0,
		randf_range(-wander_radius * 0.5, wander_radius * 0.5)
	)
	var target = controller.global_position + random_offset_xz
	
	# Snapped target Y on the ground or wall
	var ground_y = _get_ground_height(target)
	target.y = ground_y + 0.1 # Keep slightly off the ground to prevent getting stuck
	
	if controller.has_method("set_movement_target"):
		controller.set_movement_target(target)

# CIRCLE
func _on_circle_state_entered() -> void:
	print("WaspBehavior: Entering Circle State")
	_is_crawling = false
	_current_swoop_timer = swoop_cooldown

func _on_circle_state_physics_process(delta: float) -> void:
	if not is_instance_valid(target_entity):
		state_chart.send_event("PlayerLost")
		return
		
	_current_swoop_timer -= delta
	if _current_swoop_timer <= 0:
		print("WaspBehavior: Swoop Timer Reached!")
		state_chart.send_event("SwoopStart")
		return

	var vector_to_player = controller.global_position.direction_to(target_entity.global_position)
	var distance_to_player = controller.global_position.distance_to(target_entity.global_position)
	
	if distance_to_player > circle_distance * 1.5:
		if controller.has_method("set_movement_target"):
			controller.set_movement_target(target_entity.global_position + Vector3(0, 4, 0))
	else:
		var orbit_tangent = vector_to_player.cross(Vector3.UP).normalized()
		var target_pos = target_entity.global_position + (vector_to_player * -1.0 * circle_distance) + (orbit_tangent * 5.0) + Vector3(0, 5, 0)
		if controller.has_method("set_movement_target"):
			controller.set_movement_target(target_pos)

# SWOOP
func _on_swoop_state_entered() -> void:
	print("WaspBehavior: Entering Swoop State")
	_is_crawling = false
	if not is_instance_valid(target_entity):
		state_chart.send_event("CheckConditions")
		return
		
	if "fly_speed" in controller:
		controller.fly_speed = _original_fly_speed * swoop_speed_multiplier
	if controller.has_method("set_movement_target"):
		controller.set_movement_target(target_entity.global_position)
	_has_attacked_this_swoop = false

func _on_swoop_state_physics_process(_delta: float) -> void:
	if is_instance_valid(target_entity):
		if controller.has_method("set_movement_target"):
			controller.set_movement_target(target_entity.global_position)
		
		if not _has_attacked_this_swoop:
			var distance = controller.global_position.distance_to(target_entity.global_position)
			if distance <= attack_distance:
				_trigger_attack()

func _trigger_attack() -> void:
	_has_attacked_this_swoop = true
	print("WaspBehavior: Triggering attack animation!")
	if "animation_tree" in controller and controller.animation_tree:
		controller.animation_tree.set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	
	# Deal damage to player if within range
	if is_instance_valid(target_entity):
		var distance = controller.global_position.distance_to(target_entity.global_position)
		if distance <= attack_distance + 1.2:
			var player_hittable = DamageResolver.resolve_hittable(target_entity)
			if player_hittable:
				var hit_dir = (target_entity.global_position - controller.global_position).normalized()
				DamageResolver.emit_hit(player_hittable, attack_damage, controller, target_entity.global_position, hit_dir)
				print("WaspBehavior: Hit player for ", attack_damage, " damage!")

func _on_swoop_state_exited() -> void:
	if "fly_speed" in controller:
		controller.fly_speed = _original_fly_speed

# RECOVER
func _on_recover_state_entered() -> void:
	print("WaspBehavior: Entering Recover State")
	_is_crawling = false
	var target = controller.global_position + Vector3(0, 10, 0)
	if controller.has_method("set_movement_target"):
		controller.set_movement_target(target)

# HELPER FUNCTIONS

func _get_ground_height(pos: Vector3) -> float:
	var space_state := controller.get_world_3d().direct_space_state
	var from := pos + Vector3.UP * 15.0
	var to := pos + Vector3.DOWN * 30.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [controller.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space_state.intersect_ray(query)
	if hit and not hit.is_empty():
		return hit.position.y
	return pos.y

func _get_surface_normal() -> Vector3:
	var space_state := controller.get_world_3d().direct_space_state
	var pos := controller.global_position
	
	# Directions to scan for surfaces (walls, ground)
	var check_distance := 1.8
	var directions = [
		Vector3.DOWN,
		-controller.global_transform.basis.y,
		-controller.global_transform.basis.z,
		-controller.global_transform.basis.x,
		controller.global_transform.basis.x
	]
	
	for dir in directions:
		var query := PhysicsRayQueryParameters3D.create(pos, pos + dir * check_distance)
		query.exclude = [controller.get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space_state.intersect_ray(query)
		if hit and not hit.is_empty():
			return hit.normal
			
	return Vector3.UP

func _update_fly_walk_blend(delta: float) -> void:
	if not controller or not "animation_tree" in controller or not controller.animation_tree:
		return
		
	if not controller.animation_tree.active:
		controller.animation_tree.active = true
		
	var target_blend: float = 0.0 # Default: fly (0.0)
	
	if _is_crawling:
		target_blend = 1.0 # Force walk (1.0) when crawling
	else:
		# Check height above ground to blend animations dynamically
		var space_state := controller.get_world_3d().direct_space_state
		var from := controller.global_position
		var to := from + Vector3.DOWN * 3.0
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [controller.get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space_state.intersect_ray(query)
		
		if target_entity == null and hit and not hit.is_empty():
			var height = from.y - hit.position.y
			if height < 0.8:
				target_blend = clampf((0.8 - height) / 0.6, 0.0, 1.0)
				
	var old_blend = _fly_walk_blend
	_fly_walk_blend = lerpf(_fly_walk_blend, target_blend, delta * 5.0)
	controller.animation_tree.set("parameters/fly_walk/blend_amount", _fly_walk_blend)
	
	if abs(old_blend - _fly_walk_blend) > 0.05:
		print("WaspBehavior: Blend amount updated to: ", _fly_walk_blend, " (target: ", target_blend, ")")
