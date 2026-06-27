class_name ObjectReactComponent extends Area3D

@export var target: Node3D

@export_group("Reaction Parameters")
@export var effect_duration: float = 0.3
@export var squash_scale: Vector3 = Vector3(1.3, 0.7, 1.3) # Wider and flatter
@export var stretch_scale: Vector3 = Vector3(0.8, 1.2, 0.8) # Skinnier and taller
@export var shake_intensity: float = 0.15

var _initial_scale: Vector3
var _initial_position: Vector3
var _active_tween: Tween

func _ready() -> void:
	# Fallback to the parent if a target isn't explicitly assigned
	if not target:
		target = get_parent() as Node3D 
		
	if target:
		# Store the original transform data so we know what to return to
		_initial_scale = target.scale
		_initial_position = target.position
		
	# The body_entered signal passes a Node3D argument, so we need a wrapper function
	body_entered.connect(_on_body_entered)

func _on_body_entered(_body: Node3D) -> void:
	on_entity_touch()

func on_entity_touch() -> void:
	if not target:
		return
		
	# Kill any currently running tween to prevent animations from fighting each other
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
		
	_active_tween = create_tween()
	
	# Generate a random offset for the shake
	var random_shake = Vector3(
		randf_range(-shake_intensity, shake_intensity),
		0, # Usually best to keep vertical shake at 0 so it doesn't clip into the floor
		randf_range(-shake_intensity, shake_intensity)
	)
	
	# Calculate timing for the three phases
	var impact_duration = effect_duration * 0.15
	var rebound_duration = effect_duration * 0.25
	var settle_duration = effect_duration * 0.60
	
	# PHASE 1: SQUASH & SHAKE (Fast impact)
	_active_tween.tween_property(target, "scale", _initial_scale * squash_scale, impact_duration).set_trans(Tween.TRANS_SINE)
	_active_tween.parallel().tween_property(target, "position", _initial_position + random_shake, impact_duration)
	
	# PHASE 2: STRETCH (Rebound)
	_active_tween.chain().tween_property(target, "scale", _initial_scale * stretch_scale, rebound_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.parallel().tween_property(target, "position", _initial_position - (random_shake * 0.5), rebound_duration)
	
	# PHASE 3: SETTLE (Return to normal with an elastic bounce)
	_active_tween.chain().tween_property(target, "scale", _initial_scale, settle_duration).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_active_tween.parallel().tween_property(target, "position", _initial_position, settle_duration).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
