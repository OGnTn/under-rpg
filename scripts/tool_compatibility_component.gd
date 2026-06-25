extends Node
class_name ToolCompatibilityComponent

@export var requires_tool: bool = false
@export var resource_type: ToolItem.ResourceType = ToolItem.ResourceType.OAK_TREE
@export var min_tool_tier: int = 0

func is_compatible(damage_tool: Node3D) -> bool:
	if not requires_tool:
		return true
	if not damage_tool:
		return false
		
	var tool_resource = damage_tool.get("item_resource")
	if not (tool_resource and tool_resource is ToolItem):
		return false
		
	if resource_type not in tool_resource.gatherable_types:
		return false
		
	if tool_resource.tool_tier < min_tool_tier:
		return false
		
	return true
