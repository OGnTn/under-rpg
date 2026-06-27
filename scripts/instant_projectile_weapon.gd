extends Weapon
class_name InstantProjectileWeapon

## Weapon that fires once per primary press.

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

func _setup_weapon() -> void:
	if pose_blender and fire_on_event:
		if not pose_blender.marker_reached.is_connected(_on_pose_marker_reached):
			pose_blender.marker_reached.connect(_on_pose_marker_reached)

func _press_primary() -> void:
	if pose_blender:
		pose_blender.play_pose(&"shoot")
		
	if not fire_on_event:
		_trigger_fire()

func _on_pose_marker_reached(marker_name: StringName, animation_name: StringName) -> void:
	if not is_visible_in_tree():
		return
	if fire_on_event and marker_name == &"event" and animation_name == &"shoot":
		_trigger_fire()

func _trigger_fire() -> void:
	if not is_multiplayer_authority():
		return

	var aim_source := get_aim_source()
	if not aim_source:
		return

	var launch_transform := _get_launch_transform(aim_source)
	var direction := -aim_source.global_transform.basis.z
	if multiplayer.has_multiplayer_peer():
		_fire_projectile_rpc.rpc(launch_transform, direction)
	else:
		_fire_projectile_rpc(launch_transform, direction)

@rpc("any_peer", "call_local", "reliable")
func _fire_projectile_rpc(launch_transform: Transform3D, direction: Vector3) -> void:
	if not projectile_scene:
		return
		
	var proj := projectile_scene.instantiate()
	var parent := get_tree().current_scene
	if not parent:
		parent = get_tree().root
	parent.add_child(proj)
	
	proj.global_transform = launch_transform
	
	if proj.has_method("launch"):
		proj.launch(direction, projectile_speed, damage, owner_character, projectile_lifetime, self)

	weapon_fired.emit()

func _get_launch_transform(aim_source: Node3D) -> Transform3D:
	var launch_transform := aim_source.global_transform
	if _muzzle:
		launch_transform.origin = _muzzle.global_position
	else:
		launch_transform.origin += -aim_source.global_transform.basis.z * 0.6
	return launch_transform
