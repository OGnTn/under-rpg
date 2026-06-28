@tool
extends EditorPlugin

const ITEM_SCAN_DIR := "res://resources/items"
const ICON_OUTPUT_DIR := "res://assets/textures/items/icons"
const ICON_PREFIX := "icon_"
const ITEM_PREFIX := "res_"
const ICON_TEXTURE_EXTENSION := "tres"

var _pending_count := 0
var _generated_count := 0
var _assigned_existing_count := 0
var _skipped_count := 0
var _failed_count := 0

func _enter_tree() -> void:
	add_tool_menu_item("Generate Missing Item Icons", _generate_missing_item_icons)

func _exit_tree() -> void:
	remove_tool_menu_item("Generate Missing Item Icons")

func _generate_missing_item_icons() -> void:
	_reset_counters()
	_ensure_icon_output_dir()

	var item_paths := _find_item_resource_paths(ITEM_SCAN_DIR)
	for item_path in item_paths:
		_queue_icon_generation_if_needed(item_path)

	if _pending_count == 0:
		_print_summary()

func _queue_icon_generation_if_needed(item_path: String) -> void:
	var item := load(item_path) as InventoryItem
	if item == null:
		_skipped_count += 1
		return

	if item.icon != null:
		_skipped_count += 1
		return

	if item.mesh == null:
		_skipped_count += 1
		return

	var icon_path := _get_icon_path_for_item(item_path)
	var icon_resource_path := _get_icon_resource_path_for_item(item_path)
	if ResourceLoader.exists(icon_resource_path):
		var existing_icon_resource := load(icon_resource_path) as Texture2D
		if existing_icon_resource != null:
			item.icon = existing_icon_resource
			var save_resource_error := ResourceSaver.save(item, item_path)
			if save_resource_error == OK:
				_assigned_existing_count += 1
			else:
				_failed_count += 1
				push_warning("Could not save item after assigning existing icon resource: %s" % item_path)
			return

	if FileAccess.file_exists(icon_path):
		EditorInterface.get_resource_filesystem().update_file(icon_path)
		EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([icon_path]))
		var existing_icon: Texture2D = null
		if ResourceLoader.exists(icon_path):
			existing_icon = load(icon_path) as Texture2D
		if existing_icon != null:
			item.icon = existing_icon
			var save_error := ResourceSaver.save(item, item_path)
			if save_error == OK:
				_assigned_existing_count += 1
			else:
				_failed_count += 1
				push_warning("Could not save item after assigning existing icon: %s" % item_path)
		else:
			push_warning("Existing icon path could not be loaded as Texture2D, regenerating it: %s" % icon_path)
		if item.icon != null:
			return

	if item.mesh.resource_path.is_empty():
		_skipped_count += 1
		push_warning("Cannot generate icon for mesh without resource path: %s" % item_path)
		return

	_pending_count += 1
	EditorInterface.get_resource_previewer().queue_resource_preview(
		item.mesh.resource_path,
		self,
		&"_on_mesh_preview_ready",
		{
			&"item_path": item_path,
			&"icon_path": icon_path,
			&"icon_resource_path": icon_resource_path,
		},
	)

func _on_mesh_preview_ready(_mesh_path: String, preview: Texture2D, thumbnail_preview: Texture2D, metadata: Dictionary) -> void:
	var preview_texture := preview if preview != null else thumbnail_preview
	if preview_texture == null:
		_failed_count += 1
		_finish_pending_preview()
		push_warning("Godot did not return a mesh preview for: %s" % metadata.get(&"item_path", ""))
		return

	var image := preview_texture.get_image()
	if image == null:
		_failed_count += 1
		_finish_pending_preview()
		push_warning("Could not read preview image for: %s" % metadata.get(&"item_path", ""))
		return

	var icon_path := String(metadata[&"icon_path"])
	var save_error := image.save_png(ProjectSettings.globalize_path(icon_path))
	if save_error != OK:
		_failed_count += 1
		_finish_pending_preview()
		push_warning("Could not save generated icon: %s" % icon_path)
		return

	var icon_texture := ImageTexture.create_from_image(image)
	var icon_resource_path := String(metadata[&"icon_resource_path"])
	var resource_save_error := ResourceSaver.save(icon_texture, icon_resource_path)
	if resource_save_error != OK:
		_failed_count += 1
		_finish_pending_preview()
		push_warning("Could not save generated icon texture resource: %s" % icon_resource_path)
		return

	EditorInterface.get_resource_filesystem().update_file(icon_path)
	EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([icon_path]))
	EditorInterface.get_resource_filesystem().update_file(icon_resource_path)
	_assign_generated_icon.call_deferred(String(metadata[&"item_path"]), icon_resource_path)

func _assign_generated_icon(item_path: String, icon_path: String, attempt: int = 0) -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(icon_path):
		icon = load(icon_path) as Texture2D
	var item := load(item_path) as InventoryItem

	if icon == null and attempt < 10:
		EditorInterface.get_resource_filesystem().update_file(icon_path)
		EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([icon_path]))
		await get_tree().create_timer(0.1).timeout
		_assign_generated_icon(item_path, icon_path, attempt + 1)
		return

	if icon == null or item == null:
		_failed_count += 1
		_finish_pending_preview()
		push_warning("Generated icon could not be assigned: %s" % icon_path)
		return

	item.icon = icon
	var save_error := ResourceSaver.save(item, item_path)
	if save_error == OK:
		_generated_count += 1
	else:
		_failed_count += 1
		push_warning("Could not save item after generated icon assignment: %s" % item_path)

	_finish_pending_preview()

func _finish_pending_preview() -> void:
	_pending_count -= 1
	if _pending_count == 0:
		EditorInterface.get_resource_filesystem().scan_sources()
		_print_summary()

func _find_item_resource_paths(scan_dir: String) -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(scan_dir)
	if dir == null:
		push_warning("Could not open item scan directory: %s" % scan_dir)
		return paths

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var path := scan_dir.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				paths.append_array(_find_item_resource_paths(path))
		elif file_name.get_extension() == "tres":
			paths.append(path)
		file_name = dir.get_next()
	dir.list_dir_end()

	return paths

func _ensure_icon_output_dir() -> void:
	var absolute_dir := ProjectSettings.globalize_path(ICON_OUTPUT_DIR)
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if error != OK:
		push_warning("Could not create icon output directory: %s" % ICON_OUTPUT_DIR)

func _get_icon_path_for_item(item_path: String) -> String:
	var item_id := item_path.get_file().get_basename()
	if item_id.begins_with(ITEM_PREFIX):
		item_id = item_id.substr(ITEM_PREFIX.length())
	return ICON_OUTPUT_DIR.path_join("%s%s.png" % [ICON_PREFIX, item_id])

func _get_icon_resource_path_for_item(item_path: String) -> String:
	var item_id := item_path.get_file().get_basename()
	if item_id.begins_with(ITEM_PREFIX):
		item_id = item_id.substr(ITEM_PREFIX.length())
	return ICON_OUTPUT_DIR.path_join("%s%s.%s" % [ICON_PREFIX, item_id, ICON_TEXTURE_EXTENSION])

func _reset_counters() -> void:
	_pending_count = 0
	_generated_count = 0
	_assigned_existing_count = 0
	_skipped_count = 0
	_failed_count = 0

func _print_summary() -> void:
	print(
		"Item icon generation finished. Generated: %d, assigned existing: %d, skipped: %d, failed: %d."
		% [_generated_count, _assigned_existing_count, _skipped_count, _failed_count]
	)
