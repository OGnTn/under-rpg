class_name Hittable extends Area3D

signal hit(damage: int, damage_source: Node3D, hit_position: Vector3, hit_normal: Vector3)

# References
@export_group("References")
@export var mesh_instance: MeshInstance3D

# Visual Settings
@export_group("Visual Settings")
@export var flash_material: Material # Drag a "White Unshaded" material here
@export var flash_duration: float = 0.15

# Hit Feedback
@export_group("Hit Feedback")
@export var particles_scene: PackedScene = preload("res://scenes/fx/hit_particles.tscn")
@export var squash_scale: Vector3 = Vector3(1.3, 0.7, 1.3)
@export var squash_duration: float = 0.05
@export var stretch_duration: float = 0.15

var _tween: Tween
var _reaction_tween: Tween
var _orig_mesh_scale: Vector3 = Vector3.ONE
var _orig_mesh_scale_initialized: bool = false
var _scale_node: Node3D = null

func _ready():
	_initialize_visual_nodes()

func _initialize_visual_nodes():
	if not mesh_instance:
		mesh_instance = _find_first_mesh(get_parent())
		
	if mesh_instance:
		_orig_mesh_scale_initialized = true
		
		# Resolve the node to scale for squash & stretch
		if not mesh_instance.skeleton.is_empty():
			var skeleton_node = mesh_instance.get_node_or_null(mesh_instance.skeleton)
			if skeleton_node:
				var parent_node = skeleton_node.get_parent()
				if parent_node and parent_node != get_parent():
					_scale_node = parent_node
				else:
					_scale_node = skeleton_node
			else:
				_scale_node = mesh_instance
		else:
			_scale_node = mesh_instance
			
		if _scale_node:
			_orig_mesh_scale = _scale_node.scale

func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var m = _find_first_mesh(child)
		if m:
			if m.visible:
				return m
	return null

@rpc("any_peer", "reliable", "call_local")
func receive_hit_rpc(
	damage: int,
	damage_source_path: NodePath = NodePath(),
	hit_position: Vector3 = Vector3.ZERO,
	hit_normal: Vector3 = Vector3.ZERO
) -> void:
	var damage_source: Node3D = null
	if not String(damage_source_path).is_empty():
		damage_source = get_node_or_null(damage_source_path) as Node3D
	receive_hit(damage, damage_source, hit_position, hit_normal)

func receive_hit(damage: int, damage_source: Node3D = null, hit_position: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO) -> void:
	flash_effect()
	
	if not _orig_mesh_scale_initialized:
		_initialize_visual_nodes()
		
	# Trigger squash & stretch tween on the resolved scale node
	if _scale_node:
		if _reaction_tween and _reaction_tween.is_running():
			_reaction_tween.kill()
		_reaction_tween = create_tween()
		_reaction_tween.tween_property(_scale_node, "scale", _orig_mesh_scale * squash_scale, squash_duration)
		_reaction_tween.tween_property(_scale_node, "scale", _orig_mesh_scale, stretch_duration).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		
	# Trigger particles
	if particles_scene:
		var proj_particles = particles_scene.instantiate() as CPUParticles3D
		var parent = get_tree().current_scene
		if not parent:
			parent = get_tree().root
		parent.add_child(proj_particles)
		
		var spawn_pos = hit_position
		if spawn_pos == Vector3.ZERO:
			spawn_pos = _scale_node.global_position if _scale_node else global_position
		proj_particles.global_position = spawn_pos
		
		if hit_normal.length_squared() > 0.01:
			var target_dir = spawn_pos + hit_normal
			if abs(hit_normal.dot(Vector3.UP)) > 0.99:
				proj_particles.look_at(target_dir, Vector3.RIGHT)
			else:
				proj_particles.look_at(target_dir, Vector3.UP)
				
	hit.emit(damage, damage_source, hit_position, hit_normal)

func take_damage(damage: int, damage_source: Node3D = null, hit_position: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO) -> void:
	receive_hit(damage, damage_source, hit_position, hit_normal)

func flash_effect() -> void:
	if not mesh_instance or not flash_material: return

	# Kill previous tween if we get hit rapidly
	if _tween: _tween.kill()
	_tween = create_tween()

	# 1. Apply the overlay immediately
	mesh_instance.material_overlay = flash_material

	# 2. Wait for duration
	_tween.tween_interval(flash_duration)
	# 3. Clear the overlay
	_tween.tween_callback(func(): mesh_instance.material_overlay = null)
