extends Node3D
class_name CraftingStation

@export var station_type: String = "workbench"
@export var prompt_message: String = "Interact with Workbench"

@onready var interactable: Interactable = $Interactable

var current_ui = null

func _ready() -> void:
	if not interactable:
		interactable = get_node_or_null("Interactable")
	
	if interactable:
		interactable.prompt_message = prompt_message
		if not interactable.interacted.is_connected(_on_interacted):
			interactable.interacted.connect(_on_interacted)
	else:
		printerr("CraftingStation: No Interactable node found on ", name)

func _on_interacted(picker_id: int) -> void:
	sync_interact.rpc(picker_id)

@rpc("call_local", "reliable")
func sync_interact(picker_id: int) -> void:
	# Only the player who interacted needs to see the UI
	if picker_id == multiplayer.get_unique_id():
		var player = get_tree().root.find_child(str(picker_id), true, false)
		if player:
			var inventory_ui = player.find_child("InventoryControl", true, false)
			if inventory_ui:
				current_ui = inventory_ui
				# Connect to ui_hidden to reset the station filter when closed
				if not inventory_ui.ui_hidden.is_connected(_on_ui_hidden):
					inventory_ui.ui_hidden.connect(_on_ui_hidden)
				
				# Open the station UI
				if inventory_ui.has_method("open_station"):
					inventory_ui.open_station(station_type)
				else:
					# Fallback if inventory_ui doesn't have the method yet
					var crafting_ui = inventory_ui.get_node_or_null("%CraftingUI")
					if crafting_ui and crafting_ui.has_method("set_station_filter"):
						crafting_ui.set_station_filter(station_type)
					inventory_ui.show_inventory()

func _on_ui_hidden() -> void:
	if current_ui:
		if current_ui.ui_hidden.is_connected(_on_ui_hidden):
			current_ui.ui_hidden.disconnect(_on_ui_hidden)
		
		# Reset station filter back to manual when closing
		if current_ui.has_method("open_station"):
			current_ui.open_station("manual")
		else:
			var crafting_ui = current_ui.get_node_or_null("%CraftingUI")
			if crafting_ui and crafting_ui.has_method("set_station_filter"):
				current_ui.set_station_filter("manual")
		
		current_ui = null
