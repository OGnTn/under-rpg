class_name FlyingEnemyController extends CharacterBody3D

@export var fly_speed: float = 6.0
@export var turn_speed: float = 4.0
@export var custom_up_vector: Vector3 = Vector3.UP

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

@export var animation_tree: AnimationTree

# --- Combat & Physics ---
@export_group("Combat")
@export var hittable: Hittable
@export var skeleton: Skeleton3D
@export var physical_bone_simulator: PhysicalBoneSimulator3D
@export var knockback_force: float = 8.0
@export var ragdoll_on_death: bool = true

enum State {IDLE, WALKING}
@export var current_state = State.IDLE

@export var next_position: Vector3

var is_dead: bool = false:
	set(val):
		if is_dead == val:
			return
		is_dead = val
		if is_dead:
			_on_died()

var stun_timer: float = 0.1

# --- Culling ---
var _culling_timer: float = 0.0
var _is_culled: bool = false
@export var culling_distance: float = 50.0

var movement_target: Vector3
var has_target: bool = false

func _ready() -> void:
	movement_target = global_position
	next_position = position
	
	# Auto-wire Hittable if found
	if not hittable:
		hittable = find_child("Hittable", false) as Hittable
		if not hittable:
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
		if not skeleton:
			skeleton = find_child("Skeleton3D", true)
		
	# Auto-wire PhysicalBoneSimulator3D
	if not physical_bone_simulator:
		physical_bone_simulator = find_child("PhysicalBoneSimulator3D", true)
	
	if physical_bone_simulator:
		physical_bone_simulator.active = false

func set_movement_target(target: Vector3):
	if is_dead: return
	movement_target = target
	has_target = true

func _physics_process(delta: float) -> void:
	if is_dead: return
	
	var is_server = not multiplayer.has_multiplayer_peer() or (multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.is_server())
	if not is_server:
		# Client Side position interpolation
		position = position.move_toward(next_position, fly_speed * delta * 1.1)
		return

	# Server Side
	# 0. Server-Side Distance Culling (Optimization)
	_culling_timer -= delta
	if _culling_timer <= 0.0:
		_culling_timer = 0.5 + randf_range(0.0, 0.2) # Check every ~0.5s
		_check_distance_culling()
		
	if _is_culled:
		return

	# 1. Handle Stun (Knockback)
	if stun_timer > 0.0:
		stun_timer -= delta
		velocity.x = move_toward(velocity.x, 0, delta * 5.0)
		velocity.y = move_toward(velocity.y, 0, delta * 5.0)
		velocity.z = move_toward(velocity.z, 0, delta * 5.0)
		move_and_slide()
		next_position = position
		return

	# 2. State Management
	if velocity.length_squared() < 0.01:
		current_state = State.IDLE
	else:
		current_state = State.WALKING

	# 3. Direct movement for flying
	if not has_target:
		velocity = velocity.move_toward(Vector3.ZERO, fly_speed * delta)
		move_and_slide()
		next_position = position
		return

	var direction = global_position.direction_to(movement_target)
	var distance = global_position.distance_to(movement_target)
	
	if distance < 1.0:
		velocity = velocity.move_toward(Vector3.ZERO, fly_speed * delta)
	else:
		var target_velocity = direction * fly_speed
		velocity = velocity.move_toward(target_velocity, fly_speed * delta * 2.0)
		
		# Rotate to face movement
		if velocity.length() > 0.1:
			var look_target = global_position + velocity
			var target_xform = global_transform.looking_at(look_target, custom_up_vector)
			global_transform.basis = global_transform.basis.slerp(target_xform.basis, turn_speed * delta)

	move_and_slide()
	next_position = position

# --- Damage & Reaction ---

func _on_hit(amount: int, source: Node3D, _pos: Vector3, _normal: Vector3) -> void:
	if is_dead: return
	
	# Apply Knockback
	if source:
		var dir = (global_position - source.global_position).normalized()
		dir.y = 0.2
		velocity = dir * (knockback_force * 0.6)
		stun_timer = 0.4 # Disable nav for 0.4s
		move_and_slide()

func _on_died() -> void:
	if not is_dead:
		is_dead = true
	
	velocity = Vector3.ZERO
	if animation_tree:
		animation_tree.active = false
	
	# Start Ragdoll
	if ragdoll_on_death:
		if physical_bone_simulator:
			physical_bone_simulator.active = true
		elif skeleton:
			skeleton.physical_bones_start_simulation()
	
	# Cleanup Timer
	get_tree().create_timer(1.0).timeout.connect(queue_free)

func _check_distance_culling():
	var nearest_dist = 999999.0
	var players = get_tree().get_nodes_in_group("players")
	
	if players.is_empty():
		_set_culled(true)
		return
		
	for p in players:
		if p is Node3D:
			var d = global_position.distance_squared_to(p.global_position)
			if d < nearest_dist:
				nearest_dist = d
	
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
		if navigation_agent:
			navigation_agent.process_mode = Node.PROCESS_MODE_DISABLED
		if animation_tree:
			animation_tree.active = false
	else:
		if navigation_agent:
			navigation_agent.process_mode = Node.PROCESS_MODE_INHERIT
		if animation_tree:
			animation_tree.active = true
