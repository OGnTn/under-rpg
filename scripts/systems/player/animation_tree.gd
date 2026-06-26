extends AnimationTree

var blend_pos := Vector2.ZERO
@onready var parent = $"../"

func _process(delta: float) -> void:
	var local_vel: Vector3 = parent.transform.basis.inverse() * parent.velocity
	blend_pos = Vector2(
			clamp(local_vel.x / parent.speed, -1.0, 1.0),
			clamp(-local_vel.z / parent.speed, -1.0, 1.0)
		)
	set("parameters/idle-run/blend_position", blend_pos)
