extends Resource
class_name WeaponPoseKey

## A single pose in an attack blend.
## If animation_name is set, PoseBlendComponent loads the first position/rotation
## key for the target node from that AnimationPlayer clip.

@export_range(0.0, 1.0) var progress: float = 0.0
@export var animation_name: StringName = &""
@export var load_from_animation: bool = true
@export var position: Vector3 = Vector3(0.6, 1.3, -0.8)
@export var rotation: Vector3 = Vector3.ZERO

func duplicate_key() -> WeaponPoseKey:
	var key := WeaponPoseKey.new()
	key.progress = progress
	key.animation_name = animation_name
	key.load_from_animation = load_from_animation
	key.position = position
	key.rotation = rotation
	return key
