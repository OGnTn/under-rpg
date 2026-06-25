extends Weapon
class_name InstantProjectileWeapon

## Concrete implementation/template for Instant Projectile Weapons (e.g., Crossbow, Wand).
## Fires a projectile on click (or delayed based on animation progress) and plays recoil.

@export_group("Firing Mode")
@export var fire_on_event: bool = false

@export_group("Projectile Settings")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 30.0
@export var damage: float = 15.0
@export var projectile_lifetime: float = 4.0

@export_group("Visuals & Muzzle")
@export var muzzle_path: NodePath

var _muzzle: Node3D

func _ready() -> void:
	if not muzzle_path.is_empty():
		_muzzle = get_node_or_null(muzzle_path) as Node3D

func setup(owner_body: CharacterBody3D, blender: PoseBlendComponent) -> void:
	super.setup(owner_body, blender)
	if pose_blender and fire_on_event:
		if not pose_blender.attack_event_triggered.is_connected(_on_attack_event_triggered):
			pose_blender.attack_event_triggered.connect(_on_attack_event_triggered)

func primary_pressed() -> void:
	if pose_blender:
		pose_blender.start_attack(&"shoot")
		
	if not fire_on_event:
		_trigger_fire()

func _on_attack_event_triggered() -> void:
	if not is_visible_in_tree():
		return
	if fire_on_event and pose_blender and pose_blender.current_attack_type == &"shoot":
		_trigger_fire()

func _trigger_fire() -> void:
	# Resolve the camera
	var aim_source: Node3D = null
	if owner_character:
		if owner_character.has_node("ViewModel/Camera3D"):
			aim_source = owner_character.get_node("ViewModel/Camera3D")
		else:
			aim_source = owner_character.get_viewport().get_camera_3d()
			
	if not aim_source:
		return
		
	_fire_projectile(aim_source)
	weapon_fired.emit()

func _fire_projectile(aim_source: Node3D) -> void:
	if not projectile_scene:
		return
		
	var proj := projectile_scene.instantiate()
	var parent := get_tree().current_scene
	if not parent:
		parent = get_tree().root
	parent.add_child(proj)
	
	var launch_transform := aim_source.global_transform
	if _muzzle:
		launch_transform.origin = _muzzle.global_position
	else:
		launch_transform.origin += -aim_source.global_transform.basis.z * 0.6
		
	proj.global_transform = launch_transform
	
	if proj.has_method("launch"):
		proj.launch(-aim_source.global_transform.basis.z, projectile_speed, damage, owner_character, projectile_lifetime)
