extends AnimationTree


@rpc("authority", "call_local", "reliable")
func one_shot(animation: String):
	set("parameters/" + animation + "/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
