extends InventoryItem
class_name ToolItem

# Define the types of resources existing in your world.
# In a larger project, you might move this Enum to a global 'GameConstants.gd' file.
enum ResourceType {
	OAK_TREE,
	IRON_ORE,
	STONE,
	COAL,
	COPPER
}

@export_group("Tool Stats")
@export var efficiency: float = 1.0
@export var durability: int = 100
@export var tool_tier: int = 0

# This Array allows you to select multiple types in the Inspector.
# For example, a "Basic Axe" would only have OAK_TREE and BIRCH_TREE checked.
@export var gatherable_types: Array[ResourceType] = []

# --- Helper Functions ---

# Call this when the player hits an object to see if this tool works
func can_gather(target_type: ResourceType) -> bool:
	return target_type in gatherable_types

# Optional: Logic to reduce durability
func use_tool(amount: int = 1) -> void:
	durability -= amount
	if durability < 0:
		durability = 0
		# Add logic here for breaking the tool (e.g., signal emission)
