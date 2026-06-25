extends Node3D

## Arm Spring Physics
## Simulates a 3D linear and angular spring on this node, attracting it to its parent's transform
## in world space. This provides realistic inertia, sway, bobbing, and overshoot.

@export_group("Linear Spring Settings")
@export var linear_stiffness: float = 250.0
@export var linear_damping: float = 25.0
@export var max_linear_displacement: float = 0.5

@export_group("Angular Spring Settings")
@export var angular_stiffness: float = 200.0
@export var angular_damping: float = 20.0
@export var max_angular_displacement: float = 0.5 # In radians (~28 degrees)

# State variables
var current_pos: Vector3
var current_vel: Vector3
var current_rot: Quaternion
var angular_vel: Vector3

# Parent target reference
@onready var parent: Node3D = get_parent()

func _ready() -> void:
	if not parent:
		push_error("ArmSpring script requires a parent Node3D!")
		set_physics_process(false)
		return
		
	# Initialize spring state to match the parent's global transform exactly
	current_pos = parent.global_transform.origin
	current_rot = parent.global_transform.basis.get_rotation_quaternion()
	current_vel = Vector3.ZERO
	angular_vel = Vector3.ZERO

func _physics_process(delta: float) -> void:
	var target_pos = parent.global_transform.origin
	var target_rot = parent.global_transform.basis.get_rotation_quaternion()
	
	# --- Teleport & Initial Load Protection ---
	var displacement = current_pos - target_pos
	
	var _pose_blend = get_node_or_null("../../../../PoseBlendComponent")
	#if pose_blend and pose_blend.is_attacking:
	#	print("Spring physics - parent target: ", target_pos, " | current: ", current_pos, " | displacement: ", displacement.length(), " | parent local pos: ", parent.position)
		
	if displacement.length() > 5.0:
		current_pos = target_pos
		current_vel = Vector3.ZERO
		current_rot = target_rot
		angular_vel = Vector3.ZERO
		global_transform = Transform3D(Basis(current_rot), current_pos)
		return

	# --- Linear Spring Physics ---
	var spring_force = -displacement * linear_stiffness
	var damping_force = -current_vel * linear_damping
	var accel = spring_force + damping_force
	
	current_vel += accel * delta
	current_pos += current_vel * delta
	
	# Clamp linear displacement relative to parent to keep the weapon near the camera
	var local_pos = parent.global_transform.affine_inverse() * current_pos
	if local_pos.length() > max_linear_displacement:
		local_pos = local_pos.normalized() * max_linear_displacement
		current_pos = parent.global_transform * local_pos
		current_vel = Vector3.ZERO # Cancel velocity when hitting limits
		
	# --- Angular Spring Physics ---
	# Calculate difference: q_diff * current_rot = target_rot => q_diff = target_rot * current_rot.inverse()
	var q_diff = target_rot * current_rot.inverse()
	
	var axis = q_diff.get_axis()
	var angle = q_diff.get_angle()
	
	# Wrap angle to [-PI, PI] for the shortest rotation path
	if angle > PI:
		angle -= 2.0 * PI
		
	# Torque calculation
	var spring_torque = Vector3.ZERO
	if abs(angle) > 0.0001:
		spring_torque = axis * angle * angular_stiffness
		
	var damping_torque = -angular_vel * angular_damping
	var rot_accel = spring_torque + damping_torque
	
	angular_vel += rot_accel * delta
	
	var angle_delta = angular_vel.length() * delta
	if angle_delta > 0.0001:
		var rot_delta = Quaternion(angular_vel.normalized(), angle_delta)
		current_rot = (rot_delta * current_rot).normalized()
	else:
		current_rot = current_rot.normalized()
		
	# Clamp angular displacement relative to parent to prevent excessive twisting
	var rot_error = abs((target_rot * current_rot.inverse()).get_angle())
	if rot_error > PI:
		rot_error = 2.0 * PI - rot_error
		
	if rot_error > max_angular_displacement:
		# Slerp back within bounds
		var t = (rot_error - max_angular_displacement) / rot_error
		current_rot = current_rot.slerp(target_rot, t).normalized()
		angular_vel = angular_vel * 0.5 # Soften angular speed on impact
		
	# --- Apply global state to node transform ---
	global_transform = Transform3D(Basis(current_rot), current_pos)
