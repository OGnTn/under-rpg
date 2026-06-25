# interacter.gd
extends RayCast3D

var highlighted_obj: Interactable = null
#@onready var world_node: World = null

@export
var manipulating = false

func _ready() -> void:
	# Attempt to find the world node dynamically
	# Adjust this path if your scene structure is different
	#world_node = get_tree().current_scene.find_child("World", true, false)
	
	# Exclude the player from the raycast so we don't hit our own back in 3rd person
	var p = get_parent()
	while p and not p is CharacterBody3D:
		p = p.get_parent()
	if p:
		player = p
		add_exception(player)

@onready var interact_prompt: Control = %InteractPrompt
@onready var crosshair: Control = %Crosshair
var player: CharacterBody3D = null


func _physics_process(_delta: float) -> void:
	# Only process for the local player
	if not _is_local():
		return

	if player and "is_third_person" in player:
		var base_dist = 5.0
		if player.is_third_person:
			target_position.z = -(base_dist + player.third_person_distance)
		else:
			target_position.z = -base_dist

	if is_colliding():
		var obj = get_collider()
		if obj is Interactable and obj.is_enabled:
			highlighted_obj = obj
			interact_prompt.visible = true
			crosshair.visible = false
			var label = interact_prompt.get_node_or_null("HBoxContainer/Label")
			if label:
				label.text = obj.prompt_message
		else:
			# If looking at terrain, clear interact prompt but keep crosshair
			highlighted_obj = null
			interact_prompt.visible = false
			crosshair.visible = true
	else:
		highlighted_obj = null
		interact_prompt.visible = false
		crosshair.visible = true
	

func _is_local() -> bool:
	if player and "owning_peer_id" in player:
		return player.owning_peer_id == multiplayer.get_unique_id()
	return is_multiplayer_authority()


func _input(event: InputEvent) -> void:
	# Only process input for the local player
	if not _is_local():
		return

	if event.is_action_pressed("interact"):
		interact()
		return

func interact():
	if (highlighted_obj != null):
		highlighted_obj.interact.rpc(multiplayer.get_unique_id())
