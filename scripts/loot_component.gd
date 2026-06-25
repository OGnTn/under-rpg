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
	# Only the server spawns loot drops (RPC broadcasts to all peers)
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
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
		
		GameManager.spawn_world_item_synced.rpc(stack.item.resource_path, stack.count, spawn_pos, initial_velocity, drop_name)
