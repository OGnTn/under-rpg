extends CPUParticles3D

func _ready() -> void:
	emitting = true
	# Wait for lifetime plus a tiny buffer, then free the node
	get_tree().create_timer(lifetime + 0.1).timeout.connect(queue_free)
