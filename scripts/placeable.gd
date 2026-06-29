extends Weapon

@export var placeable_scene: PackedScene

var preview_instance: Node3D = null

func _exit_tree() -> void:
	if is_instance_valid(preview_instance):
		preview_instance.queue_free()

func _press_primary() -> void:
	if not is_multiplayer_authority():
		return
	
	if is_instance_valid(preview_instance) and preview_instance.visible:
		if multiplayer.has_multiplayer_peer():
			_server_place_item.rpc(preview_instance.global_transform)
		else:
			_server_place_item(preview_instance.global_transform)

@rpc("any_peer", "call_local", "reliable")
func _server_place_item(placement_transform: Transform3D) -> void:
	# 1. Only instantiate the scene on the server (or in offline mode) to allow spawner replication
	# Perform this first while the node is guaranteed to be inside the scene tree
	#var is_server_or_offline := true
	#if is_inside_tree() and get_multiplayer():
		#is_server_or_offline = not get_multiplayer().has_multiplayer_peer() or get_multiplayer().is_server()
		#
	#if is_server_or_offline:
	if placeable_scene:
		var instance: Node3D = placeable_scene.instantiate()
		var placeables_node = get_tree().current_scene.get_node_or_null("%Placeables")
		if placeables_node:
			placeables_node.add_child(instance)
			instance.global_transform = placement_transform
		else:
			var parent = get_tree().current_scene
			if not parent:
				parent = get_tree().root
			parent.add_child(instance)
			instance.global_transform = placement_transform

	# 2. Determine item to consume and remove it from inventory
	var item_to_consume = item_resource
	if not item_to_consume and owner_character and owner_character.inventory:
		var hotbar_stack = owner_character.inventory.get_hotbar_selection()
		if hotbar_stack and not hotbar_stack.is_empty():
			item_to_consume = hotbar_stack.item
			
	if item_to_consume and owner_character and owner_character.inventory:
		owner_character.inventory.consume_item(item_to_consume, 1)
		
		# If the selected hotbar stack is now empty, unequip the placeable
		var hotbar_stack = owner_character.inventory.get_hotbar_selection()
		if hotbar_stack == null or hotbar_stack.is_empty():
			var equip_ctrl = owner_character.get_node_or_null("EquipmentController")
			if equip_ctrl:
				equip_ctrl.clear_item()

func _tick(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
		
	# Instantiate preview locally on demand
	if not is_instance_valid(preview_instance) and placeable_scene:
		_spawn_preview()
		
	# Perform raycast to find target surface
	var hit := _get_placement_raycast()
	if not hit.is_empty():
		if is_instance_valid(preview_instance):
			preview_instance.visible = true
			preview_instance.global_position = hit.position
			
			# Align preview's local UP with the surface normal and face the player
			var normal: Vector3 = hit.normal
			normal = normal.normalized()
			var player_forward: Vector3 = -owner_character.global_transform.basis.z
			var forward: Vector3 = (player_forward - player_forward.project(normal)).normalized()
			if forward.length_squared() < 0.0001:
				var fallback_forward: Vector3 = -owner_character.global_transform.basis.y
				forward = (fallback_forward - fallback_forward.project(normal)).normalized()
			
			var right: Vector3 = normal.cross(forward).normalized()
			var new_basis: Basis = Basis(right, normal, -forward)
			preview_instance.global_basis = new_basis
	else:
		if is_instance_valid(preview_instance):
			preview_instance.visible = false

func _spawn_preview() -> void:
	preview_instance = placeable_scene.instantiate()
	var parent = get_tree().current_scene
	if not parent:
		parent = get_tree().root
	parent.add_child(preview_instance)
	_make_transparent(preview_instance)
	_disable_collision(preview_instance)

func _make_transparent(node: Node) -> void:
	if node is GeometryInstance3D:
		node.transparency = 0.5
	for child in node.get_children():
		_make_transparent(child)

func _disable_collision(node: Node) -> void:
	if node is CollisionObject3D:
		node.process_mode = PROCESS_MODE_DISABLED
		if node is Area3D:
			node.monitoring = false
			node.monitorable = false
	if node is CollisionShape3D:
		node.disabled = true
	for child in node.get_children():
		_disable_collision(child)

func _get_placement_raycast() -> Dictionary:
	var aim_source := get_aim_source()
	if not aim_source:
		return {}
		
	var space_state := get_world_3d().direct_space_state
	var from := aim_source.global_position
	var max_distance := 6.0
	var to := from - aim_source.global_transform.basis.z * max_distance
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	
	var excludes: Array[RID] = []
	if owner_character:
		excludes.append(owner_character.get_rid())
	if is_instance_valid(preview_instance):
		_add_to_excludes_recursive(preview_instance, excludes)
	query.exclude = excludes
	
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	return space_state.intersect_ray(query)

func _add_to_excludes_recursive(node: Node, excludes: Array[RID]) -> void:
	if node is CollisionObject3D:
		excludes.append(node.get_rid())
	for child in node.get_children():
		_add_to_excludes_recursive(child, excludes)
