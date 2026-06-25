extends Node
## NetworkManager — Autoload singleton for ENet host/join, lobby, and peer management.
##
## Responsibilities:
##   - Host a game (create ENet server, bind port)
##   - Join a game (create ENet client, connect to host)
##   - Track connected players and their ready status
##   - Emit signals for UI binding
##   - Orchestrate game start (load level across all peers)

#class_name NetworkManager

# ------------------------------------------------------------------ signals
signal connection_succeeded()
signal connection_failed(reason: String)
signal player_list_changed()
signal game_started()
signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)

# -------------------------------------------------------------- constants
const DEFAULT_PORT: int = 9999
const MAX_PLAYERS: int = 8

# ------------------------------------------------------------ properties
var is_host: bool = false
var is_connected: bool = false
var player_name: String = "Player"

## Dictionary[int peer_id -> PlayerInfo]
var _players: Dictionary = {}

# ---------------------------------------------------------- PlayerInfo
class PlayerInfo:
	var peer_id: int
	var name: String
	var is_ready: bool = false
	var character_node: Node3D = null
	
	func _init(p_id: int, p_name: String) -> void:
		peer_id = p_id
		name = p_name

# --------------------------------------------------------------- lifecycle
func _ready() -> void:
	# Connect built-in multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ------------------------------------------------------------ public API

## Host a game on the given port.
func host_game(port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("Failed to create server: error %d" % err)
		return err
	
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_connected = true
	
	# Add the host to the player list
	var info := PlayerInfo.new(multiplayer.get_unique_id(), player_name)
	info.is_ready = true
	_players[multiplayer.get_unique_id()] = info
	
	connection_succeeded.emit()
	player_list_changed.emit()
	print("[NetworkManager] Hosting on port %d as peer %d" % [port, multiplayer.get_unique_id()])
	return OK


## Join a game at the given address and port.
func join_game(address: String, port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Failed to create client: error %d" % err)
		return err
	
	multiplayer.multiplayer_peer = peer
	is_host = false
	# connected_to_server signal will fire on success; connection_failed on failure
	print("[NetworkManager] Connecting to %s:%d ..." % [address, port])
	return OK


## Disconnect and return to main menu.
func disconnect_from_game() -> void:
	_cleanup()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false
	is_connected = false


## Mark the local player as ready in the lobby.
func set_ready(ready: bool) -> void:
	var my_id := multiplayer.get_unique_id()
	
	# Update our local copy immediately for responsive UI
	if _players.has(my_id):
		_players[my_id].is_ready = ready
		player_list_changed.emit()
	
	# If we're the host, broadcast to all peers
	if multiplayer.is_server():
		_sync_player_list.rpc(_serialize_player_list())
	else:
		# Client: send ready request to server
		_request_set_ready.rpc_id(1, ready)


## Client → Server: request to toggle ready state.
@rpc("any_peer", "reliable")
func _request_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if _players.has(sender_id):
		_players[sender_id].is_ready = ready
		player_list_changed.emit()
		# Broadcast updated list to all peers
		_sync_player_list.rpc(_serialize_player_list())


## Return the list of connected players.
func get_players() -> Array:
	var list: Array = []
	for info in _players.values():
		list.append({"peer_id": info.peer_id, "name": info.name, "is_ready": info.is_ready})
	return list


## Check if all players are ready.
func all_players_ready() -> bool:
	if _players.is_empty():
		return false
	for info in _players.values():
		if not info.is_ready:
			return false
	return true


## The host calls this to tell everyone to load the game scene.
func start_game() -> void:
	if not is_host or not multiplayer.is_server():
		push_warning("[NetworkManager] Only the host can start the game.")
		return
	
	# load_game_level has call_local, so .rpc() runs on server AND all clients
	GameManager.load_game_level.rpc()


## Return the peer ID of the host (always 1 for ENet server).
func get_host_id() -> int:
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return 1  # ENet server is always peer ID 1
	return -1

# --------------------------------------------------- multiplayer callbacks

func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] Peer connected: %d" % peer_id)
	
	if multiplayer.is_server():
		# Add placeholder — name will arrive via RPC from client
		# But we also send the existing player list to the new peer
		_send_player_list_to_peer.rpc_id(peer_id, _serialize_player_list())
		
		# Ask the new peer for their name
		_request_player_name.rpc_id(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer disconnected: %d" % peer_id)
	if _players.has(peer_id):
		_players.erase(peer_id)
		player_list_changed.emit()
		player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	print("[NetworkManager] Connected to server. My ID: %d" % multiplayer.get_unique_id())
	is_connected = true
	connection_succeeded.emit()
	
	# Tell the server our name
	_register_with_server.rpc_id(1, player_name)


func _on_connection_failed() -> void:
	print("[NetworkManager] Connection failed.")
	connection_failed.emit("Connection failed.")
	_cleanup()


func _on_server_disconnected() -> void:
	print("[NetworkManager] Disconnected from server.")
	is_connected = false
	player_list_changed.emit()
	
	# Return to main menu
	if get_tree():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# --------------------------------------------------------- RPCs (server)

## Server receives a new client's name registration.
@rpc("any_peer", "reliable")
func _register_with_server(player_name_str: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server():
		return
	
	print("[NetworkManager] Registering player %d: %s" % [sender_id, player_name_str])
	var info := PlayerInfo.new(sender_id, player_name_str)
	_players[sender_id] = info
	player_joined.emit(sender_id, player_name_str)
	
	# Emit locally so the host's lobby updates immediately
	player_list_changed.emit()
	
	# Broadcast updated player list to all peers
	_sync_player_list.rpc(_serialize_player_list())


## Broadcast the serialized player list to all clients.
@rpc("authority", "reliable", "call_remote")
func _sync_player_list(serialized: Dictionary) -> void:
	_deserialize_player_list(serialized)
	player_list_changed.emit()


## Send the current player list to a specific newly-connected peer.
@rpc("authority", "reliable")
func _send_player_list_to_peer(serialized: Dictionary) -> void:
	_deserialize_player_list(serialized)
	player_list_changed.emit()


## Server asks a peer for their name.
@rpc("authority", "reliable")
func _request_player_name() -> void:
	if not multiplayer.is_server():
		_register_with_server.rpc_id(1, player_name)

# ------------------------------------------------- helpers

func _serialize_player_list() -> Dictionary:
	var data := {}
	for pid in _players:
		data[str(pid)] = {"n": _players[pid].name, "r": _players[pid].is_ready}
	return data


func _deserialize_player_list(data: Dictionary) -> void:
	_players.clear()
	for pid_str in data:
		var pid := int(pid_str)
		var entry: Dictionary = data[pid_str]
		var info := PlayerInfo.new(pid, entry.get("n", "Unknown"))
		info.is_ready = entry.get("r", false)
		_players[pid] = info


func _cleanup() -> void:
	_players.clear()
	is_host = false
	is_connected = false
