# ItemStack.gd
class_name ItemStack extends RefCounted

var item: InventoryItem
var count: int

func _init(_item: InventoryItem = null, _count: int = 0):
	self.item = _item
	self.count = _count

func is_empty() -> bool:
	return item == null or count <= 0

func is_full() -> bool:
	if is_empty():
		return false
	return count >= item.max_stack

func get_space_left() -> int:
	if is_empty():
		# Logic assumes checking against a specific item type usually, 
		# but if empty, technically max_stack of the incoming item. 
		# Returning 0 or handling this in inventory logic is standard.
		return 0 
	return item.max_stack - count

func empty_slot():
	item = null
	count = 0

# --- NETWORKING HELPERS ---

# Converts this object into a Dictionary for the RPC
func serialize() -> Dictionary:
	if is_empty():
		return {}
		
	return {
		"item_path": item.resource_path, # We send the path, not the object
		"count": count
	}

# Creates a new ItemStack from a Dictionary received via RPC
static func deserialize(data: Dictionary) -> ItemStack:
	if data.is_empty():
		return null
		
	var new_stack = ItemStack.new()
	if data.has("item_path"):
		new_stack.item = load(data["item_path"])
	new_stack.count = data.get("count", 1)
	return new_stack
