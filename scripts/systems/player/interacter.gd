extends RayCast3D
class_name PlayerInteractor

@export var interact_distance: float = 5.0

@onready var interact_prompt: Control = %InteractPrompt
@onready var crosshair: Control = %Crosshair
@onready var prompt_label: Label = interact_prompt.get_node_or_null("HBoxContainer/Label") as Label

var player: Player
var target: Interactable

func _ready() -> void:
	player = _find_player()
	if player:
		add_exception(player)
	_update_prompt(null)

func get_target() -> Interactable:
	return target if is_instance_valid(target) else null

func clear_target() -> void:
	target = null
	_update_prompt(null)

func interact() -> void:
	if not is_instance_valid(target):
		return
	target.interact.rpc(multiplayer.get_unique_id())

func _input(event: InputEvent) -> void:
	if is_multiplayer_authority() and event.is_action_pressed("interact"):
		interact()

func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	_update_distance()
	var next_target := _get_hovered_interactable()
	if not is_instance_valid(target) or target != next_target:
		target = next_target
		_update_prompt(target)

func _find_player() -> Player:
	var node := get_parent()
	while node and not node is Player:
		node = node.get_parent()
	return node as Player

func _update_distance() -> void:
	var distance := interact_distance
	if player and player.is_third_person:
		distance += player.third_person_distance
	target_position = Vector3(0.0, 0.0, -distance)

func _get_hovered_interactable() -> Interactable:
	if not is_colliding():
		return null
	var collider := get_collider()
	if collider is Interactable and collider.is_enabled:
		return collider
	return null

func _update_prompt(interactable: Interactable) -> void:
	var has_target := interactable != null
	interact_prompt.visible = has_target
	crosshair.visible = not has_target
	if has_target and prompt_label:
		prompt_label.text = interactable.prompt_message
