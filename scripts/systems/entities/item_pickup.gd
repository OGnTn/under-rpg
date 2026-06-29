class_name ItemPickup
extends Node3D

@export var item: InventoryItem
@export var count: int = 1

@onready var item_mesh: MeshInstance3D = %Item
@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	if item and item.mesh:
		item_mesh.mesh = item.mesh

	if not interactable.interacted.is_connected(_on_interacted):
		interactable.interacted.connect(_on_interacted)


func _on_interacted(picker_id: int) -> void:
	if not multiplayer.is_server():
		return

	_pick_up.rpc(picker_id)


@rpc("authority", "call_local", "reliable")
func _pick_up(picker_id: int) -> void:
	if item and picker_id == multiplayer.get_unique_id():
		var player := get_tree().root.find_child(str(picker_id), true, false)
		if player:
			var inventory: Inventory = player.get_node_or_null("Inventory")
			if inventory:
				inventory.obtain_item(ItemStack.new(item, count))

	queue_free()
