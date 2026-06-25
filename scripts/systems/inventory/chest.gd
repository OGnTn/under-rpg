extends Node3D

@onready
var inventory: Inventory = $Inventory
var inventory_ui


func _on_interactable_interacted(picker_id: int) -> void:
	# Server authority handles the interaction signal
	# picker_id is passed directly now
	sync_interact.rpc(picker_id)

@rpc("call_local", "reliable")
func sync_interact(picker_id: int):
	$AnimationPlayer.play("open_close")
	
	# Only the player who picked it needs to see the UI
	if picker_id == multiplayer.get_unique_id():
		# Find the player node. Assuming standard spawning structure under /root/.../Players or similar
		# or we can find it by name since we know the ID
		var player = get_tree().root.find_child(str(picker_id), true, false)
		if player and player.has_node("InventoryCanvas/InventoryControl"):
			inventory_ui = player.get_node("InventoryCanvas/InventoryControl")
			open_chest_ui()

func open_chest_ui():
	if (inventory_ui):
		inventory_ui.connect("ui_hidden", close_chest)
		inventory_ui.open_external_inventory(inventory)
		inventory_ui.show_inventory()

func close_chest():
	if (inventory_ui):
		inventory_ui.disconnect("ui_hidden", close_chest)
		inventory_ui.close_external_inventory()
		inventory_ui.hide_inventory()
		# Animation should be synced separately or we just play it locally?
		# For now, let's RPC the close animation too if we want it to look correct for others.
		sync_close.rpc()
		inventory_ui = null

@rpc("call_local", "reliable")
func sync_close():
	$AnimationPlayer.play("open_close", -1, -1.0, true)
