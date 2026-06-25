extends Sprite3D
class_name ResourceBar3D

@export var vertical_offset: float = 1.0
@export var bar_width: int = 120
@export var bar_height: int = 16

@export var always_show: bool = false
@export var max_screen_distance_pct: float = 0.25

var resource_component: Node = null
var progress_bar: ProgressBar = null

func _ready() -> void:
	# Enable billboarding so it always faces the camera
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	
	# Find sibling ResourceComponent
	resource_component = get_parent().find_child("ResourceComponent", true, false)
	if not resource_component:
		queue_free()
		return
		
	# Create SubViewport to host the 2D ProgressBar in 3D space
	var viewport = SubViewport.new()
	viewport.size = Vector2i(bar_width, bar_height)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	
	# Instance the ResourceBar 2D scene
	var bar_scene = preload("res://scenes/ui/components/resource_bar.tscn")
	progress_bar = bar_scene.instantiate()
	progress_bar.custom_minimum_size = Vector2(bar_width, bar_height)
	progress_bar.size = Vector2(bar_width, bar_height)
	viewport.add_child(progress_bar)
	
	# Wait one frame for viewport to initialize, then set texture
	await get_tree().process_frame
	texture = viewport.get_texture()
	
	# Position above the parent entity
	position = Vector3(0, vertical_offset, 0)
	
	# Connect to parent's health signals
	resource_component.health_changed.connect(_on_health_changed)
	_update_bar(resource_component.current_health, resource_component.max_health)

func _on_health_changed(old_value: int, new_value: int) -> void:
	_update_bar(new_value, resource_component.max_health)

func _update_bar(current: int, max_val: int) -> void:
	if progress_bar:
		progress_bar.max_value = max_val
		progress_bar.value = current

func _process(_delta: float) -> void:
	if not resource_component:
		visible = false
		return
		
	var current = resource_component.current_health
	var max_val = resource_component.max_health
	var is_damaged_and_alive = (current > 0 and current < max_val)
	var should_be_visible = always_show or is_damaged_and_alive
	
	if not should_be_visible:
		visible = false
		return
		
	var camera = get_viewport().get_camera_3d()
	if not camera:
		visible = false
		return
		
	if camera.is_position_behind(global_position):
		visible = false
		return
		
	var screen_pos = camera.unproject_position(global_position)
	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var dist = screen_pos.distance_to(center)
	
	var threshold = viewport_size.y * max_screen_distance_pct
	visible = dist <= threshold
