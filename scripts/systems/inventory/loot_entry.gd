class_name LootEntry extends Resource

@export var item: InventoryItem
@export var min_count: int = 1
@export var max_count: int = 1
@export_range(0.0, 1.0) var probability: float = 1.0
