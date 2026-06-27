extends Node

class_name PlayerInput

var movement: Vector2 = Vector2.ZERO

func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)

func _gather():
	if not is_multiplayer_authority():
		return
	movement = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
