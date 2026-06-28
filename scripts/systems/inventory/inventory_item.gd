# inventory_item.gd
class_name InventoryItem extends Resource

# The enum is for using the flags in your code. Its definition remains the same.
enum Type {
	WEAPON = 1,
	CONSUMABLE = 2,
	TOOL = 4,
	ARMOR = 8,
	QUEST_ITEM = 16,
	PLACEABLE = 32
}

# The engine automatically maps the first string to 1 (2^0), the second to 2 (2^1), the third to 4 (2^2), and so on.
@export_flags("Weapon", "Consumable", "Tool", "Armor", "Quest Item", "Placeable") var item_types: int = 0

@export var name: String
@export var description: String
@export var icon: Texture2D
@export var scene: PackedScene
@export var mesh: Mesh
@export var max_stack: int = 1

# This helper function still works perfectly with the enum.
func is_type(type_to_check: Type) -> bool:
	return (item_types & type_to_check) > 0
