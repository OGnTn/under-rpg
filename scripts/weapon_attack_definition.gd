extends Resource
class_name WeaponAttackDefinition

## Ordered pose blend for one attack on a weapon.
## Add as many pose_keys as the attack needs; PoseBlendComponent blends between
## neighboring keys after warping time through the attack curve.

const USE_COMPONENT_VALUE := -1.0

@export var attack_name: StringName = &"regular"
@export var pose_keys: Array[WeaponPoseKey] = []

@export_group("Timing Overrides")
@export_range(0.0, 1.0) var strike_start: float = 0.25
@export_range(0.0, 1.0) var strike_end: float = 0.75
@export_range(0.0, 1.0) var strike_event_time: float = 0.75
@export var duration: float = USE_COMPONENT_VALUE
@export var enthusiasm: float = USE_COMPONENT_VALUE
@export var curve: Curve

func get_duration(default_duration: float) -> float:
	return duration if duration > 0.0 else default_duration

func get_enthusiasm(default_enthusiasm: float) -> float:
	return enthusiasm if enthusiasm >= 0.0 else default_enthusiasm

func get_curve(default_curve: Curve) -> Curve:
	return curve if curve else default_curve
