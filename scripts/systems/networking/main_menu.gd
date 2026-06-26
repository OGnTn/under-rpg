extends Control

## Main menu script handling Host / Join UI and connection feedback.

@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: LineEdit = %PortInput
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.connection_failed.connect(_on_connection_failed)


func _exit_tree() -> void:
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)


func _on_host_pressed() -> void:
	var port := port_input.text.to_int()
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT

	var err := NetworkManager.host_game(port)
	if err != OK:
		status_label.text = "Failed to host: " + error_string(err)
	# On success the scene has already changed — this node is freed.


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "localhost"

	var port := port_input.text.to_int()
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT

	status_label.text = "Connecting to %s:%d..." % [address, port]
	host_button.disabled = true
	join_button.disabled = true

	var err := NetworkManager.join_game(address, port)
	if err != OK:
		status_label.text = "Failed to connect: " + error_string(err)
		host_button.disabled = false
		join_button.disabled = false
	# On success, NetworkManager loads the game scene and this node is freed.


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the address and try again."
	host_button.disabled = false
	join_button.disabled = false
