extends Node

## Autoload singleton managing multiplayer connections, scene transitions,
## and server-authoritative player spawning/despawning.

# --- Signals for UI feedback ---
signal connection_succeeded
signal connection_failed
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal web_session_created(session_id: String)
signal network_error_raised(message: String)

# --- Configuration ---
const DEFAULT_PORT := 9999
const MAX_PLAYERS := 16
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"
const GAME_SCENE_PATH := "res://scenes/test_level.tscn"
const MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const TUBE_CONTEXT_PATH := "res://resources/network/tube_context.tres"

var player_scene: PackedScene = preload("res://scenes/player.tscn")

# --- Runtime state ---
var players_container: Node = null
var spawner: MultiplayerSpawner = null
var tube_client: TubeClient = null


# =============================================================================
# Public API
# =============================================================================

## Host a game on the given port. Returns OK on success.
func host_game(port: int = DEFAULT_PORT) -> Error:
	if uses_tube_transport():
		return host_web_session()

	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_load_game_scene()

	# Spawn the host's own player (server is always peer 1)
	spawner.spawn(1)

	return OK


## Join a game at the given address and port. Returns OK if the connection
## attempt was started (does not mean connected yet — wait for signals).
func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	if uses_tube_transport():
		return join_web_session(address)

	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	return OK


## Web exports use Tube/WebRTC sessions instead of raw IP/port ENet.
func uses_tube_transport() -> bool:
	return OS.has_feature("web")


## Create a Tube session. The host's session id is emitted by web_session_created.
func host_web_session() -> Error:
	var err := _ensure_tube_client()
	if err != OK:
		return err

	_connect_tube_signals()
	tube_client.create_session()
	return OK


## Join an existing Tube session by its 5-character session id.
func join_web_session(session_id: String) -> Error:
	session_id = session_id.strip_edges()
	if session_id.is_empty():
		return ERR_INVALID_PARAMETER

	var err := _ensure_tube_client()
	if err != OK:
		return err

	_connect_tube_signals()
	tube_client.join_session(session_id)
	return OK


## Cleanly disconnect and return to the main menu.
func disconnect_game() -> void:
	_disconnect_signals()
	_destroy_tube_client()
	multiplayer.multiplayer_peer = null
	players_container = null
	spawner = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_change_scene(MENU_SCENE_PATH)


# =============================================================================
# Server callbacks
# =============================================================================

func _on_peer_connected(peer_id: int) -> void:
	player_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_remove_player(peer_id)
	player_disconnected.emit(peer_id)


# =============================================================================
# Client callbacks
# =============================================================================

func _on_connected_to_server() -> void:
	_load_game_scene()
	_notify_server_ready.rpc_id(1)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	server_disconnected.emit()
	disconnect_game()


# =============================================================================
# Tube/WebRTC callbacks
# =============================================================================

func _on_tube_session_created() -> void:
	var session_id := tube_client.session_id
	DisplayServer.clipboard_set(session_id)
	web_session_created.emit(session_id)

	_load_game_scene()

	# Spawn the host's own player (server is always peer 1)
	spawner.spawn(1)


func _on_tube_session_joined() -> void:
	_load_game_scene()
	_notify_server_ready.rpc_id(1)
	connection_succeeded.emit()


func _on_tube_session_left() -> void:
	server_disconnected.emit()
	disconnect_game()


func _on_tube_error_raised(_code: int, message: String) -> void:
	connection_failed.emit()
	network_error_raised.emit(message)


func _on_tube_peer_connected(peer_id: int) -> void:
	player_connected.emit(peer_id)


func _on_tube_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_remove_player(peer_id)
	player_disconnected.emit(peer_id)


# =============================================================================
# RPCs
# =============================================================================

## Called by a client to tell the server it has loaded the game scene
## and is ready to receive its player.
@rpc("any_peer", "reliable")
func _notify_server_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	spawner.spawn(peer_id)


# =============================================================================
# Internal helpers
# =============================================================================

## Spawn function used by MultiplayerSpawner on all peers.
## [param data] is the peer_id (int) of the owning player.
func _spawn_player(data: Variant) -> Node:
	var player = player_scene.instantiate()
	player.name = str(data)
	return player


func _load_game_scene() -> void:
	_change_scene(GAME_SCENE_PATH)

	var level = get_tree().current_scene
	players_container = level.get_node("Players")
	spawner = level.get_node("PlayerSpawner")
	spawner.spawn_function = _spawn_player


func _change_scene(scene_path: String) -> void:
	var current = get_tree().current_scene
	if current:
		get_tree().root.remove_child(current)
		current.queue_free()

	var new_scene = load(scene_path).instantiate()
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene


func _remove_player(peer_id: int) -> void:
	if not players_container:
		return
	var player = players_container.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


func _ensure_tube_client() -> Error:
	if is_instance_valid(tube_client):
		return OK

	var context := load(TUBE_CONTEXT_PATH) as TubeContext
	if context == null:
		network_error_raised.emit("Tube context not found at %s" % TUBE_CONTEXT_PATH)
		return ERR_FILE_NOT_FOUND

	tube_client = TubeClient.new()
	tube_client.name = "TubeClient"
	tube_client.context = context
	tube_client.peer_signaling_timeout = 4.0
	tube_client.peer_signaling_max_attempts = 5
	add_child(tube_client)
	return OK


func _connect_tube_signals() -> void:
	if not is_instance_valid(tube_client):
		return

	if not tube_client.session_created.is_connected(_on_tube_session_created):
		tube_client.session_created.connect(_on_tube_session_created)
	if not tube_client.session_joined.is_connected(_on_tube_session_joined):
		tube_client.session_joined.connect(_on_tube_session_joined)
	if not tube_client.session_left.is_connected(_on_tube_session_left):
		tube_client.session_left.connect(_on_tube_session_left)
	if not tube_client.error_raised.is_connected(_on_tube_error_raised):
		tube_client.error_raised.connect(_on_tube_error_raised)
	if not tube_client.peer_connected.is_connected(_on_tube_peer_connected):
		tube_client.peer_connected.connect(_on_tube_peer_connected)
	if not tube_client.peer_disconnected.is_connected(_on_tube_peer_disconnected):
		tube_client.peer_disconnected.connect(_on_tube_peer_disconnected)


func _disconnect_tube_signals() -> void:
	if not is_instance_valid(tube_client):
		return

	if tube_client.session_created.is_connected(_on_tube_session_created):
		tube_client.session_created.disconnect(_on_tube_session_created)
	if tube_client.session_joined.is_connected(_on_tube_session_joined):
		tube_client.session_joined.disconnect(_on_tube_session_joined)
	if tube_client.session_left.is_connected(_on_tube_session_left):
		tube_client.session_left.disconnect(_on_tube_session_left)
	if tube_client.error_raised.is_connected(_on_tube_error_raised):
		tube_client.error_raised.disconnect(_on_tube_error_raised)
	if tube_client.peer_connected.is_connected(_on_tube_peer_connected):
		tube_client.peer_connected.disconnect(_on_tube_peer_connected)
	if tube_client.peer_disconnected.is_connected(_on_tube_peer_disconnected):
		tube_client.peer_disconnected.disconnect(_on_tube_peer_disconnected)


func _destroy_tube_client() -> void:
	if not is_instance_valid(tube_client):
		return

	_disconnect_tube_signals()
	if tube_client.state != TubeClient.State.IDLE:
		tube_client.leave_session()
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface())
	tube_client.queue_free()
	tube_client = null


func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
