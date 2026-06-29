extends Control

## Main menu script handling Host / Join UI and connection feedback.

@onready var ip_container: Control = $IPContainer
@onready var webrtc_container: Control = $WebRTCContainer
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: LineEdit = %PortInput
@onready var status_label: Label = %StatusLabel
@onready var webrtc_host_button: Button = %WebRTCHostButton
@onready var session_code_input: LineEdit = $WebRTCContainer/PanelContainer/MarginContainer/VBoxContainer/SessionCodeInput
@onready var webrtc_join_button: Button = %WebRTCJoinButton
@onready var webrtc_status_label: Label = $WebRTCContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	webrtc_host_button.pressed.connect(_on_webrtc_host_pressed)
	webrtc_join_button.pressed.connect(_on_webrtc_join_pressed)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.web_session_created.connect(_on_web_session_created)
	NetworkManager.network_error_raised.connect(_on_network_error_raised)
	_configure_transport_ui()


func _exit_tree() -> void:
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.web_session_created.is_connected(_on_web_session_created):
		NetworkManager.web_session_created.disconnect(_on_web_session_created)
	if NetworkManager.network_error_raised.is_connected(_on_network_error_raised):
		NetworkManager.network_error_raised.disconnect(_on_network_error_raised)


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


func _on_webrtc_host_pressed() -> void:
	webrtc_status_label.text = "Creating session..."
	_set_webrtc_buttons_disabled(true)

	var err := NetworkManager.host_web_session()
	if err != OK:
		webrtc_status_label.text = "Failed to create session: " + error_string(err)
		_set_webrtc_buttons_disabled(false)


func _on_webrtc_join_pressed() -> void:
	var session_id := session_code_input.text.strip_edges()
	if session_id.is_empty():
		webrtc_status_label.text = "Enter a session code."
		return

	webrtc_status_label.text = "Joining session %s..." % session_id
	_set_webrtc_buttons_disabled(true)

	var err := NetworkManager.join_web_session(session_id)
	if err != OK:
		webrtc_status_label.text = "Failed to join session: " + error_string(err)
		_set_webrtc_buttons_disabled(false)


func _on_connection_failed() -> void:
	if NetworkManager.uses_tube_transport():
		webrtc_status_label.text = "Connection failed. Check the session code and try again."
		_set_webrtc_buttons_disabled(false)
	else:
		status_label.text = "Connection failed. Check the address and try again."
		host_button.disabled = false
		join_button.disabled = false


func _on_web_session_created(session_id: String) -> void:
	webrtc_status_label.text = "Session %s copied to clipboard. Starting..." % session_id


func _on_network_error_raised(message: String) -> void:
	if NetworkManager.uses_tube_transport():
		webrtc_status_label.text = message
		_set_webrtc_buttons_disabled(false)


func _configure_transport_ui() -> void:
	var use_webrtc := NetworkManager.uses_tube_transport()
	ip_container.visible = not use_webrtc
	webrtc_container.visible = use_webrtc


func _set_webrtc_buttons_disabled(disabled: bool) -> void:
	webrtc_host_button.disabled = disabled
	webrtc_join_button.disabled = disabled
