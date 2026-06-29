extends Node
class_name LootComponent

@export var loot_table: LootTable
@export var dropped_item: InventoryItem
@export var count: int = 1
@export var world_item: PackedScene = preload("res://scenes/world_objects/world_item.tscn")

var resource_component: Node

func _ready():
	# Find sibling ResourceComponent to connect to
	for child in get_parent().get_children():
		if child.has_signal("health_depleted"):
			resource_component = child
			resource_component.health_depleted.connect(_on_health_depleted)

func _on_health_depleted():
	if multiplayer.is_server():
		spawn_drops()

func spawn_drops() -> void:
	var drops: Array[ItemStack] = []
	if loot_table:
		drops = loot_table.get_drops()
	elif dropped_item:
		drops.append(ItemStack.new(dropped_item, count))
		
	for stack in drops:
		if not stack.item:
			continue
			
		var drop_name = "item_drop_" + str(multiplayer.get_unique_id()) + "_" + str(Time.get_ticks_usec()) + "_" + str(randi())
		
		var rng = RandomNumberGenerator.new()
		var random_angle = deg_to_rad(rng.randf_range(-30, 30))
		var parent = get_parent()
		var throw_dir = - parent.transform.basis.z.rotated(Vector3.UP, random_angle)
		var initial_velocity = (throw_dir * 3.0) + Vector3(0, 5.0, 0)
		
		var spawn_pos = parent.global_position
		
		var drop = world_item.instantiate()
		drop.name = drop_name
		
		var spawn_parent = null
		if parent.is_inside_tree():
			var level = parent.get_tree().current_scene
			if level:
				spawn_parent = level.get_node_or_null("%WorldItems")
				if not spawn_parent:
					spawn_parent = level.find_child("WorldItems", true, false)
				if not spawn_parent:
					spawn_parent = level
		
		if not spawn_parent:
			spawn_parent = parent.get_parent()
			
		spawn_parent.add_child(drop)
		drop.global_position = spawn_pos
		
		var drop_component = drop.get_node_or_null("WorldItemComponent")
		if drop_component:
			drop_component.setup(stack, initial_velocity)
