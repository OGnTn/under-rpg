class_name EnemyController extends CharacterBody3D

@export var movement_speed: float = 4.0
@onready var navigation_agent: NavigationAgent3D = get_node("NavigationAgent3D")

#@export var state_machine: StateMachine

@export var animation_tree: AnimationTree

# --- Combat & Physics ---
@export_group("Combat")
@export var hittable: Hittable
@export var skeleton: Skeleton3D
@export var physical_bone_simulator: PhysicalBoneSimulator3D
@export var knockback_force: float = 8.0
@export var ragdoll_on_death: bool = true

enum State {IDLE, WALKING}
@export
var current_state = State.IDLE
var run_walk_blend: float = 0.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
#var gravity: float = 0.0
signal target_reached()

@export var next_position: Vector3

var is_dead: bool = false:
	set(val):
		if is_dead == val:
			return
		is_dead = val
		if is_dead:
			_on_died()
var stun_timer: float = 0.1

func _ready() -> void:
	next_position = position
	navigation_agent.velocity_computed.connect(Callable(_on_velocity_computed))
	navigation_agent.target_reached.connect(_on_target_reached)
	
	# Auto-wire Hittable if found
	if not hittable:
		hittable = find_child("Hittable", false) as Hittable
		if not hittable:
			# Try finding generic Hitbox
			var hitbox = find_child("Hitbox", false)
			if hitbox and hitbox is Hittable:
				hittable = hitbox
	
	if hittable:
		hittable.hit.connect(_on_hit)
	
	# Auto-wire ResourceComponent if found
	var resource_comp = find_child("ResourceComponent", false)
	if resource_comp:
		resource_comp.health_depleted.connect(_on_died)
	
	# Auto-wire Skeleton if found
	if not skeleton:
		skeleton = find_child("GeneralSkeleton", true)
		
	# Auto-wire PhysicalBoneSimulator3D
	if not physical_bone_simulator:
		physical_bone_simulator = find_child("PhysicalBoneSimulator3D", true)
	
	if physical_bone_simulator:
		physical_bone_simulator.active = false

	if NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()) == 0:
		return

func _on_target_reached():
	emit_signal("target_reached")

func set_movement_target(movement_target: Vector3):
	if is_dead: return
	
	#navigation_agent.set_target_position(movement_target)
	# Get the RID of the navigation map this node belongs to
	var map_rid = get_world_3d().get_navigation_map()
	# Snap the target position to the closest point on the NavMesh
	var closest_point = NavigationServer3D.map_get_closest_point(map_rid, movement_target)
	# Set the agent's target to this valid point
	navigation_agent.set_target_position(closest_point)

func _physics_process(delta):
	# Dead things don't move (unless ragdolling via physics engine)
	if is_dead: return
	
	if not multiplayer.has_multiplayer_peer() or (multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.is_server()):
		# 0. Server-Side Distance Culling (Optimization)
		_culling_timer -= delta
		if _culling_timer <= 0.0:
			_culling_timer = 0.5 + randf_range(0.0, 0.2) # Check every ~0.5s
			_check_distance_culling()
			
		if _is_culled:
			# If culled, we just apply simple gravity if not on floor, or sleep
			if not is_on_floor():
				velocity.y -= gravity * delta
				move_and_slide()
			return

		# 1. Handle Stun (Knockback)
		if stun_timer > 0.0:
			stun_timer -= delta
			# Apply gravity and friction while stunned
			if not is_on_floor():
				velocity.y -= gravity * delta
			velocity.x = move_toward(velocity.x, 0, delta * 5.0) # Sliding friction
			velocity.z = move_toward(velocity.z, 0, delta * 5.0)
			move_and_slide()
			return # Skip navigation logic
			
		# 1. State Management
		if velocity.length_squared() < 0.01:
			current_state = State.IDLE
		else:
			current_state = State.WALKING
		
		# 2. Optimized Animation Blending
		var target_blend = 1.0 if current_state == State.WALKING else 0.0
		if abs(run_walk_blend - target_blend) > 0.01:
			run_walk_blend = lerp(run_walk_blend, target_blend, delta * 10)
			animation_tree.set("parameters/idle_walk/blend_amount", run_walk_blend)
		
		# 3. Navigation Checks (Simplified)
		if navigation_agent.is_navigation_finished():
			velocity = velocity.move_toward(Vector3.ZERO, delta * 20.0) # Friction
			move_and_slide() # Ensure friction applies
			return

		var next_path_position: Vector3 = navigation_agent.get_next_path_position()
		var new_velocity: Vector3 = global_position.direction_to(next_path_position) * movement_speed
		
		# 4. Safer Rotation (Y-axis only)
		if global_position.distance_squared_to(next_path_position) > 0.1:
			var look_target = next_path_position
			look_target.y = global_position.y # Keep looking level
			var target_rot = Transform3D(global_transform.basis, global_position).looking_at(look_target, Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(target_rot.basis, delta * 10)

		# 5. Apply Gravity BEFORE Avoidance
		if not is_on_floor():
			new_velocity.y -= gravity * delta

		if navigation_agent.avoidance_enabled:
			navigation_agent.set_velocity(new_velocity)
		else:
			_on_velocity_computed(new_velocity)

	else:
		# Client Side
		# Use move_toward for constant speed, preventing the "Zeno's paradox" slowdown
		position = position.move_toward(next_position, movement_speed * delta * 1.1)
		# Multiplied by 1.1 to slightly overspeed and catch up to server if lagging

func _on_velocity_computed(safe_velocity: Vector3):
	if is_dead: return
	velocity = safe_velocity
	
	move_and_slide()
	next_position = position

# --- Damage & Reaction ---

func _on_hit(amount: int, source: Node3D, _pos: Vector3, _normal: Vector3) -> void:
	if is_dead: return
	
	# Apply Knockback
	if source:
		var dir = (global_position - source.global_position).normalized()
		dir.y = 0.2 # Reduced popup to prevent air-state confusion
		velocity = dir * (knockback_force * 0.6) # Reduced force (was 8.0, now effectively ~5.0)
		stun_timer = 0.4 # Disable nav for 0.4s
		move_and_slide()
	
	# Removed Animation React as requested
	# if animation_tree and "parameters/hit_react/request" in animation_tree:
	# 	animation_tree.set("parameters/hit_react/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_died() -> void:
	if not is_dead:
		is_dead = true
	
	# Stop logic
	velocity = Vector3.ZERO
	if animation_tree:
		animation_tree.active = false # Stop animation to allow physics control
	
	# Start Ragdoll
	if ragdoll_on_death:
		if physical_bone_simulator:
			physical_bone_simulator.active = true
		elif skeleton:
			skeleton.physical_bones_start_simulation()
		
		# Optional: Apply killing blow impulse to torso/all bones
		# If we knew the source, we could push it. 
		# For now, we assume velocity carries over or we default to a slump.
	
	# Cleanup Timer
	get_tree().create_timer(1.0).timeout.connect(queue_free)

var _culling_timer: float = 0.0
var _is_culled: bool = false
@export var culling_distance: float = 50.0

func _check_distance_culling():
	var nearest_dist = 999999.0
	# We rely on the group system to find players
	var players = get_tree().get_nodes_in_group("players")
	
	if players.is_empty():
		_set_culled(true)
		return
		
	for p in players:
		if p is Node3D:
			var d = global_position.distance_squared_to(p.global_position)
			if d < nearest_dist:
				nearest_dist = d
	
	# Use squared distance for comparison
	var cull_dist_sq = culling_distance * culling_distance
	if nearest_dist > cull_dist_sq:
		if not _is_culled:
			_set_culled(true)
	else:
		if _is_culled:
			_set_culled(false)

func _set_culled(is_culled: bool):
	_is_culled = is_culled
	if is_culled:
		# Disable Expensive Logic
		if navigation_agent:
			navigation_agent.process_mode = Node.PROCESS_MODE_DISABLED
			navigation_agent.avoidance_enabled = false
		if animation_tree:
			animation_tree.active = false
		# We don't disable physics_process entirely so gravity can still apply slightly, 
		# but we could if we wanted total freeze.
	else:
		# Re-enable
		if navigation_agent:
			navigation_agent.process_mode = Node.PROCESS_MODE_INHERIT
			navigation_agent.avoidance_enabled = true
		if animation_tree:
			animation_tree.active = true

# --- Persistence ---
var spawn_id: String = ""

func setup_persistence(id: String, initial_state: Dictionary):
	spawn_id = id
	# If we track health or other state, apply it here
	# e.g. if initial_state.has("health"): health = initial_state["health"]
