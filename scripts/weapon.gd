extends Node3D
class_name Weapon

## Base class for all modular first-person weapons.
## Communicates with PoseBlendComponent to drive animations and springs.

signal attack_started(attack_name: StringName)
signal attack_completed
signal weapon_fired
signal charge_changed(amount: float)

@export var definition: WeaponDefinition

var item_resource: InventoryItem
var owner_character: CharacterBody3D
var pose_blender: PoseBlendComponent

func setup(owner_body: CharacterBody3D, blender: PoseBlendComponent) -> void:
	owner_character = owner_body
	pose_blender = blender
	if pose_blender and definition:
		pose_blender.set_weapon(definition)

## Called when primary attack (left click) is pressed
func primary_pressed() -> void:
	pass

## Called when primary attack (left click) is released
func primary_released() -> void:
	pass

## Called when weapon action is cancelled (e.g. Escape or right click)
func cancel() -> void:
	pass

## Called in the player's _physics_process to update active drawing/channeling timers
func update_weapon(_delta: float, _aim_camera: Camera3D) -> void:
	pass
