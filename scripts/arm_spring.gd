extends Node3D
class_name ArmSpring

@export_group("Linear Spring")
@export var linear_stiffness: float = 250.0
@export var linear_damping: float = 25.0
@export var max_linear_displacement: float = 0.5

@export_group("Angular Spring")
@export var angular_stiffness: float = 200.0
@export var angular_damping: float = 20.0
@export var max_angular_displacement: float = 0.5

@export var teleport_reset_distance: float = 5.0

var current_pos: Vector3
var current_vel: Vector3
var current_rot: Quaternion
var angular_vel: Vector3

@onready var target: Node3D = get_parent()

func _ready() -> void:
	if not target:
		push_error("ArmSpring requires a parent Node3D.")
		set_physics_process(false)
		return
	reset()

func reset() -> void:
	current_pos = target.global_position
	current_rot = target.global_transform.basis.get_rotation_quaternion()
	current_vel = Vector3.ZERO
	angular_vel = Vector3.ZERO
	global_transform = Transform3D(Basis(current_rot), current_pos)

func _physics_process(delta: float) -> void:
	var target_pos: Vector3 = target.global_position
	var target_rot: Quaternion = target.global_transform.basis.get_rotation_quaternion()

	if current_pos.distance_to(target_pos) > teleport_reset_distance:
		reset()
		return

	_integrate_position(delta, target_pos)
	_integrate_rotation(delta, target_rot)
	global_transform = Transform3D(Basis(current_rot), current_pos)

func _integrate_position(delta: float, target_pos: Vector3) -> void:
	var displacement: Vector3 = current_pos - target_pos
	var acceleration: Vector3 = -displacement * linear_stiffness - current_vel * linear_damping

	current_vel += acceleration * delta
	current_pos += current_vel * delta

	var local_pos: Vector3 = target.global_transform.affine_inverse() * current_pos
	if local_pos.length() > max_linear_displacement:
		local_pos = local_pos.normalized() * max_linear_displacement
		current_pos = target.global_transform * local_pos
		current_vel = Vector3.ZERO

func _integrate_rotation(delta: float, target_rot: Quaternion) -> void:
	var q_diff: Quaternion = target_rot * current_rot.inverse()
	var angle: float = q_diff.get_angle()
	if angle > PI:
		angle -= TAU

	var torque: Vector3 = Vector3.ZERO
	if absf(angle) > 0.0001:
		torque = q_diff.get_axis() * angle * angular_stiffness

	angular_vel += (torque - angular_vel * angular_damping) * delta

	var angle_delta: float = angular_vel.length() * delta
	if angle_delta > 0.0001:
		current_rot = (Quaternion(angular_vel.normalized(), angle_delta) * current_rot).normalized()
	else:
		current_rot = current_rot.normalized()

	var error: float = absf((target_rot * current_rot.inverse()).get_angle())
	if error > PI:
		error = TAU - error
	if error > max_angular_displacement:
		var t: float = (error - max_angular_displacement) / error
		current_rot = current_rot.slerp(target_rot, t).normalized()
		angular_vel *= 0.5
