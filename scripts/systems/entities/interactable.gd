class_name Interactable extends Area3D

signal interacted(interacter_id: int)

@export var prompt_message: String = "Interact"
@export var is_enabled: bool = true

@rpc("any_peer", "call_local", "reliable")
func interact(peer_id: int):
	if (multiplayer.is_server()):
		if not is_enabled:
			return
		print(str(peer_id) + " interacted with: " + get_parent().name)
		interacted.emit(peer_id)
