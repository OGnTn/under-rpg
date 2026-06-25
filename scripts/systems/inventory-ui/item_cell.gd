class_name UIItemCell extends PanelContainer

var idx: int = -1
var item_stack: ItemStack
var is_hotbar = false

signal started_hovering()
signal stopped_hovering(idx: int)
signal clicked()
signal right_clicked() # New signal for the right mouse button

func update_item_stack():
	#print("updating item cell: " + str(idx))
	if(item_stack.item != null):
		$ItemIcon.texture = item_stack.item.icon
		$ItemIcon/ItemCount.text = str(item_stack.count)
	else:
		$ItemIcon.texture = null
		$ItemIcon/ItemCount.text = ""

func _on_started_hovering():
	started_hovering.emit()

func _on_stopped_hovering():
	stopped_hovering.emit(idx)

func _on_gui_event(event: InputEvent):
	if event is InputEventMouseButton and event.is_pressed():
		# Check which button was pressed and emit the correct signal.
		if event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit()
