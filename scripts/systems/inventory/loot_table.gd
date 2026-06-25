class_name LootTable extends Resource

@export var drops: Array[LootEntry]

func get_drops() -> Array[ItemStack]:
	var items: Array[ItemStack] = []
	for entry in drops:
		if randf() <= entry.probability:
			var count = randi_range(entry.min_count, entry.max_count)
			if count > 0:
				items.append(ItemStack.new(entry.item, count))
	return items
