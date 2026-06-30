extends AnimationTree

@export
var blend_pos := Vector2.ZERO
@onready var parent = $"../"

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		var local_vel: Vector3 = parent.transform.basis.inverse() * parent.velocity
		blend_pos = Vector2(
				clamp(local_vel.x / parent.speed, -1.0, 1.0),
				clamp(-local_vel.z / parent.speed, -1.0, 1.0)
			)
			
		set("parameters/idle-run/blend_position", blend_pos)
		if(get("parameters/OneShot/active") and get_parent().is_on_floor()):
			set("parameters/JumpStateMachine/conditions/landed", true)
		if(get("parameters/JumpStateMachine/conditions/landed") and not get("parameters/OneShot/active")):
			set("parameters/JumpStateMachine/conditions/landed", false)
func _on_land():
	set("parameters/JumpStateMachine/conditions/landed", true)
	


func _on_jump() -> void:
	set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
