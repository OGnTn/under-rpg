# equipment_item.gd
class_name EquipmentItem extends InventoryItem

enum EquipmentSlot { HELMET, CHEST, FEET }

@export var slot_type: EquipmentSlot
@export var stat_modifiers: Array[Resource] = []
