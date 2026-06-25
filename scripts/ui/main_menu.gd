extends Control
## MainMenu — Host/Join UI for The Underlands multiplayer.
##
## Provides:
##   - Host Game button (with optional port)
##   - Join Game with IP address and port input
##   - Connection status display
##   - Player list (host sees all connected players)
##   - Ready toggle (clients)
##   - Start Game button (host only, enabled when all ready)

# -------------------------------------------------------------- onready
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _ip_input: LineEdit = %IPInput
@onready var _port_input: LineEdit = %PortInput
@onready var _player_name_input: LineEdit = %PlayerNameInput
@onready var _status_label: Label = %StatusLabel
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _start_button: Button = %StartButton
@onready var _ready_check: CheckBox = %ReadyCheck
@onready var _disconnect_button: Button = %DisconnectButton
@onready var _main_panel: PanelContainer = %MainPanel
@onready var _lobby_panel: PanelContainer = %LobbyPanel


# --------------------------------------------------------------- lifecycle
func _ready() -> void:
	# Wire up button signals
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)
	_ready_check.toggled.connect(_on_ready_toggled)
	
	# Wire up NetworkManager signals
	if NetworkManager:
		NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
		NetworkManager.connection_failed.connect(_on_connection_failed)
		NetworkManager.player_list_changed.connect(_on_player_list_changed)
		NetworkManager.game_started.connect(_on_game_started)
	
	# Default values
	_port_input.text = str(NetworkManager.DEFAULT_PORT)
	_player_name_input.text = "Player" + str(randi() % 1000)
	
	# Initial UI state
	_show_main_menu()


# ------------------------------------------------------------ UI handlers

func _on_host_pressed() -> void:
	NetworkManager.player_name = _player_name_input.text.strip_edges()
	if NetworkManager.player_name == "":
		NetworkManager.player_name = "Host"
	
	var port := int(_port_input.text)
	if port <= 0 or port > 65535:
		port = NetworkManager.DEFAULT_PORT
	
	_status_label.text = "Starting server on port %d..." % port
	_set_buttons_enabled(false)
	NetworkManager.host_game(port)


func _on_join_pressed() -> void:
	NetworkManager.player_name = _player_name_input.text.strip_edges()
	if NetworkManager.player_name == "":
		NetworkManager.player_name = "Player"
	
	var ip := _ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	
	var port := int(_port_input.text)
	if port <= 0 or port > 65535:
		port = NetworkManager.DEFAULT_PORT
	
	_status_label.text = "Connecting to %s:%d..." % [ip, port]
	_set_buttons_enabled(false)
	NetworkManager.join_game(ip, port)


func _on_start_pressed() -> void:
	if NetworkManager.is_host:
		_status_label.text = "Starting game..."
		_set_buttons_enabled(false)
		NetworkManager.start_game()


func _on_disconnect_pressed() -> void:
	_status_label.text = "Disconnecting..."
	NetworkManager.disconnect_from_game()
	_show_main_menu()


func _on_ready_toggled(toggled: bool) -> void:
	NetworkManager.set_ready(toggled)
	_start_button.disabled = not NetworkManager.all_players_ready()


# ------------------------------------------------ NetworkManager callbacks

func _on_connection_succeeded() -> void:
	if NetworkManager.is_host:
		_status_label.text = "Hosting on port %s. Waiting for players..." % _port_input.text
	else:
		_status_label.text = "Connected! Waiting for host to start..."
	
	_show_lobby()
	_refresh_player_list()


func _on_connection_failed(reason: String) -> void:
	_status_label.text = "Error: " + reason
	_set_buttons_enabled(true)
	_show_main_menu()


func _on_player_list_changed() -> void:
	_refresh_player_list()
	
	# Update start button state
	if NetworkManager.is_host:
		_start_button.disabled = not NetworkManager.all_players_ready()


func _on_game_started() -> void:
	_status_label.text = "Game started!"
	# The level change happens via GameManager, so this panel will be unloaded


# ---------------------------------------------------------------- helpers
func _show_main_menu() -> void:
	if _main_panel:
		_main_panel.visible = true
	if _lobby_panel:
		_lobby_panel.visible = false
	_set_buttons_enabled(true)


func _show_lobby() -> void:
	if _main_panel:
		_main_panel.visible = false
	if _lobby_panel:
		_lobby_panel.visible = true
	
	# Host sees Start + Ready is always true; clients see Ready toggle
	_start_button.visible = NetworkManager.is_host
	_ready_check.visible = not NetworkManager.is_host
	_ready_check.button_pressed = false
	
	if NetworkManager.is_host:
		_start_button.disabled = true


func _set_buttons_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled


func _refresh_player_list() -> void:
	if not _player_list:
		return
	
	# Clear existing entries
	for child in _player_list.get_children():
		if child is Label:
			child.queue_free()
	
	var players := NetworkManager.get_players()
	if players.is_empty():
		var label := Label.new()
		label.text = "No players connected."
		_player_list.add_child(label)
		return
	
	for p in players:
		var label := Label.new()
		var ready_text := "✓" if p["is_ready"] else "…"
		var host_text := " [HOST]" if p["peer_id"] == 1 else ""
		label.text = "%s %s (ID: %d)%s" % [ready_text, p["name"], p["peer_id"], host_text]
		_player_list.add_child(label)
