extends Node3D
class_name Weapon

## Base class for player weapons.

signal attack_started(attack_name: StringName)
signal attack_completed
signal weapon_fired
signal charge_changed(amount: float)

@export var definition: WeaponDefinition

var item_resource: InventoryItem
var owner_character: CharacterBody3D
var pose_blender: PoseBlendComponent
var camera: Camera3D

func setup(owner_body: CharacterBody3D, blender: PoseBlendComponent) -> void:
	owner_character = owner_body
	pose_blender = blender
	camera = owner_body.camera if owner_body and "camera" in owner_body else null
	_setup_weapon()
	_configure_pose_player()

@rpc("any_peer", "call_local", "reliable")
func press_primary() -> void:
	_press_primary()

@rpc("any_peer", "call_local", "reliable")
func release_primary() -> void:
	_release_primary()

@rpc("any_peer", "call_local", "reliable")
func cancel() -> void:
	_cancel()

func tick(delta: float) -> void:
	_tick(delta)

func get_aim_source() -> Node3D:
	if camera:
		return camera
	if owner_character:
		return owner_character.get_viewport().get_camera_3d()
	return get_viewport().get_camera_3d()

func get_attack(attack_name: StringName) -> WeaponAttackDefinition:
	if not definition:
		return null
	var attack := definition.get_attack(attack_name)
	if attack:
		return attack
	return definition.get_default_attack()

func _configure_pose_player() -> void:
	if not pose_blender or not definition:
		return
	pose_blender.set_rest_pose(definition.rest_animation, definition.rest_position, definition.rest_rotation)
	pose_blender.set_draw_pose(definition.draw_animation)
	pose_blender.set_animation_clips(definition.attacks)

func _setup_weapon() -> void:
	pass

func _press_primary() -> void:
	pass

func _release_primary() -> void:
	pass

func _cancel() -> void:
	pass

func _tick(_delta: float) -> void:
	pass
