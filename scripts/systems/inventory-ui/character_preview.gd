# character_preview.gd
# BEHAVIOR: Displays a 3D preview of the player character inside a SubViewport,
# supporting smooth mouse follow and click-and-drag rotation.
extends PanelContainer
class_name UICharacterPreview

@export var sub_viewport: SubViewport
@export var model_container: Node3D
@export var camera: Camera3D

# Rotation parameters
@export var drag_sensitivity: float = 0.005
@export var follow_sensitivity: float = 0.001
@export var lerp_speed: float = 8.0

var character_model_instance: Node3D = null
var base_y_rotation: float = 0.0  # Face the camera by default
var target_rotation_y: float = 0.0
var target_rotation_x: float = 0.0

var is_dragging: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO
var current_player: Player = null

func _ready() -> void:
	# Ensure the container receives mouse input events
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Clear container initially
	for child in model_container.get_children():
		child.queue_free()

func initialize(player: Player) -> void:
	cleanup()
	
	if not player:
		printerr("CharacterPreview: No player provided!")
		return
		
	current_player = player
	if current_player.inventory:
		if not current_player.inventory.equipment_updated.is_connected(_on_equipment_updated):
			current_player.inventory.equipment_updated.connect(_on_equipment_updated)
		
	var character_model = player.get_node_or_null("ViewModel/character_model")
	if not character_model:
		printerr("CharacterPreview: player does not have 'ViewModel/character_model' node!")
		return
		
	# Duplicate player's model to replicate current appearance and equipment
	character_model_instance = character_model.duplicate()
	model_container.add_child(character_model_instance)
	
	# Position in center of viewport and rotate to face camera
	character_model_instance.position = Vector3.ZERO
	character_model_instance.rotation = Vector3(0, base_y_rotation, 0)
	
	# Make sure the duplicate is visible (the player's own model is hidden in first person)
	character_model_instance.visible = true
	
	_disable_animations(character_model_instance)
	_update_preview_visuals()
	
	# Reset target rotations
	target_rotation_y = base_y_rotation
	target_rotation_x = 0.0
	
	# Optional: If the duplicate has an AnimationPlayer, let it play an animation if one exists
	var anim_player = character_model_instance.get_node_or_null("Anim") as AnimationPlayer
	if anim_player:
		# Just in case, stop any player-attached animation sync
		anim_player.active = true
		# Play idle if available, or just keep it in default pose
		if anim_player.has_animation("idle"):
			anim_player.play("idle")

func cleanup() -> void:
	is_dragging = false
	if is_instance_valid(current_player) and current_player.inventory:
		if current_player.inventory.equipment_updated.is_connected(_on_equipment_updated):
			current_player.inventory.equipment_updated.disconnect(_on_equipment_updated)
	current_player = null
	if is_instance_valid(character_model_instance):
		character_model_instance.queue_free()
	character_model_instance = null

func _on_equipment_updated() -> void:
	_update_preview_visuals()

func _update_preview_visuals() -> void:
	if not is_instance_valid(character_model_instance) or not is_instance_valid(current_player) or not current_player.inventory:
		return
		
	var model = character_model_instance
	
	var slot_helmet = model.find_child("slot_helmet", true, false)
	var slot_chest = model.find_child("slot_chest", true, false)
	var slot_foot_l = model.find_child("slot_foot_l", true, false)
	var slot_foot_r = model.find_child("slot_foot_r", true, false)
	
	var inventory = current_player.inventory
	
	# Update helmet slot
	if slot_helmet:
		for child in slot_helmet.get_children():
			child.queue_free()
		var helmet_stack = inventory.equipment_container[0]
		if helmet_stack and not helmet_stack.is_empty() and helmet_stack.item.scene:
			var inst = helmet_stack.item.scene.instantiate()
			slot_helmet.add_child(inst)
			
	# Update chest slot
	if slot_chest:
		for child in slot_chest.get_children():
			child.queue_free()
		var chest_stack = inventory.equipment_container[1]
		if chest_stack and not chest_stack.is_empty() and chest_stack.item.scene:
			var inst = chest_stack.item.scene.instantiate()
			slot_chest.add_child(inst)
			
	# Update feet slots
	if slot_foot_l:
		for child in slot_foot_l.get_children():
			child.queue_free()
		var feet_stack = inventory.equipment_container[2]
		if feet_stack and not feet_stack.is_empty() and feet_stack.item.scene:
			var inst = feet_stack.item.scene.instantiate()
			slot_foot_l.add_child(inst)
			
	if slot_foot_r:
		for child in slot_foot_r.get_children():
			child.queue_free()
		var feet_stack = inventory.equipment_container[2]
		if feet_stack and not feet_stack.is_empty() and feet_stack.item.scene:
			var inst = feet_stack.item.scene.instantiate()
			slot_foot_r.add_child(inst)

func _process(delta: float) -> void:
	if not is_instance_valid(character_model_instance) or not visible:
		return
		
	# Sync bones from the live player model to the preview duplicate
	if is_instance_valid(current_player):
		var src_model = current_player.get_node_or_null("ViewModel/character_model")
		if src_model:
			_sync_skeletons(src_model, character_model_instance)
		
	if not is_dragging:
		# Calculate relative mouse position from the center of this panel
		var mouse_pos = get_local_mouse_position()
		var center = size / 2.0
		var offset = mouse_pos - center
		
		# Rotate body Y based on horizontal mouse position
		# Clamp rotation so character doesn't twist all the way around
		var follow_y = clamp(offset.x * follow_sensitivity, -deg_to_rad(45), deg_to_rad(45))
		target_rotation_y = base_y_rotation + follow_y
		
		# Rotate body X (pitch) based on vertical mouse position
		var follow_x = clamp(offset.y * follow_sensitivity, -deg_to_rad(15), deg_to_rad(15))
		target_rotation_x = follow_x
		
		# Smoothly lerp towards target follow rotation
		character_model_instance.rotation.y = lerp_angle(character_model_instance.rotation.y, target_rotation_y, lerp_speed * delta)
		character_model_instance.rotation.x = lerp_angle(character_model_instance.rotation.x, target_rotation_x, lerp_speed * delta)
	else:
		# When dragging, smoothly lerp to the drag rotation
		character_model_instance.rotation.y = lerp_angle(character_model_instance.rotation.y, target_rotation_y, lerp_speed * 2.0 * delta)
		character_model_instance.rotation.x = lerp_angle(character_model_instance.rotation.x, target_rotation_x, lerp_speed * 2.0 * delta)

func _sync_skeletons(src_node: Node, dest_node: Node) -> void:
	if src_node is Skeleton3D and dest_node is Skeleton3D:
		for i in range(src_node.get_bone_count()):
			dest_node.set_bone_pose_position(i, src_node.get_bone_pose_position(i))
			dest_node.set_bone_pose_rotation(i, src_node.get_bone_pose_rotation(i))
			dest_node.set_bone_pose_scale(i, src_node.get_bone_pose_scale(i))
	
	for i in range(src_node.get_child_count()):
		if i < dest_node.get_child_count():
			_sync_skeletons(src_node.get_child(i), dest_node.get_child(i))

func _disable_animations(node: Node) -> void:
	if node is AnimationPlayer:
		node.active = false
	elif node is AnimationTree:
		node.active = false
	for child in node.get_children():
		_disable_animations(child)

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(character_model_instance):
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			last_mouse_position = event.position
			
	elif event is InputEventMouseMotion and is_dragging:
		var diff = event.position - last_mouse_position
		last_mouse_position = event.position
		
		# Update target rotation based on drag diff
		target_rotation_y += diff.x * drag_sensitivity
		target_rotation_x = clamp(target_rotation_x + diff.y * drag_sensitivity, -deg_to_rad(30), deg_to_rad(30))
