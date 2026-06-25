extends Node
## GameManager — Autoload singleton for game state, player spawning, and item sync.
##
## Responsibilities:
##   - Load the game level for all peers
##   - Spawn player characters with correct authority
##   - Provide `spawn_world_item_synced` RPC (referenced by loot_component.gd)
##   - Manage spawn points
##   - Handle game-level state transitions

#class_name GameManager

const GAME_LEVEL_PATH: String = "res://scenes/test_level.tscn"
const PLAYER_SCENE_PATH: String = "res://scenes/player.tscn"

# ------------------------------------------------------------ properties
var is_game_active: bool = false
var spawn_points: Array[Marker3D] = []
var _spawn_index: int = 0


# --------------------------------------------------------------- lifecycle
func _ready() -> void:
	pass


# ------------------------------------------------------------ public API

## Load the game level. Called on all peers when the host starts the game.
@rpc("authority", "reliable", "call_local")
func load_game_level() -> void:
	print("[GameManager] Loading game level: %s" % GAME_LEVEL_PATH)
	
	# Disconnect any existing gameplay signals to avoid stale references
	_cleanup_level_state()
	
	# Change to the game scene
	var err := get_tree().change_scene_to_file(GAME_LEVEL_PATH)
	if err != OK:
		push_error("[GameManager] Failed to load level: error %d" % err)
		return
	
	# Wait for the scene to be ready, then spawn players
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame for scene tree stability
	
	is_game_active = true
	
	# Server spawns all players
	if multiplayer.is_server():
		spawn_all_players()


## Spawn a player for the given peer. Runs on ALL peers via RPC so the player
## node exists everywhere. Server is set as multiplayer authority.
@rpc("authority", "reliable", "call_local")
func _spawn_player_synced(peer_id: int, spawn_pos: Vector3) -> void:
	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	if not player_scene:
		push_error("[GameManager] Could not load player scene: %s" % PLAYER_SCENE_PATH)
		return
	
	var player_node := player_scene.instantiate() as CharacterBody3D
	if not player_node:
		push_error("[GameManager] Player scene root is not CharacterBody3D.")
		return
	
	# Name the node by peer ID so it can be found via get_node()
	player_node.name = str(peer_id)
	player_node.global_position = spawn_pos
	
	# SERVER AUTHORITY: Server (peer 1) owns all player nodes.
	player_node.set_multiplayer_authority(1)
	player_node.owning_peer_id = peer_id
	
	# Add to the current scene on every peer
	var level_root := get_tree().current_scene
	if level_root:
		level_root.add_child(player_node, true)
	else:
		get_tree().root.add_child(player_node, true)
	
	print("[GameManager] Spawned player for peer %d at %s (local peer: %d)" % [peer_id, spawn_pos, multiplayer.get_unique_id()])
	
	# Track in NetworkManager (only meaningful on server, but harmless elsewhere)
	if NetworkManager._players.has(peer_id):
		NetworkManager._players[peer_id].character_node = player_node


@rpc("authority", "reliable", "call_local")
func spawn_all_players() -> void:
	if not multiplayer.is_server():
		return
	
	# Remove the pre-placed Player from the level (it's a singleplayer leftover)
	_remove_preplaced_player()
	
	# Collect spawn points from the level
	_gather_spawn_points()
	
	for pid in NetworkManager._players.keys():
		# Skip if already spawned
		if is_instance_valid(NetworkManager._players[pid].character_node):
			continue
		
		var pos := _next_spawn_position()
		# Use RPC so the player node is created on ALL peers
		_spawn_player_synced.rpc(pid, pos)


## Spawn a world item (dropped loot) synced across all peers.
## Called by LootComponent when an entity dies.
@rpc("authority", "reliable", "call_local")
func spawn_world_item_synced(item_resource_path: String, count: int, spawn_pos: Vector3, initial_velocity: Vector3, drop_name: String) -> void:
	
	var item_resource := load(item_resource_path) as InventoryItem
	if not item_resource:
		push_warning("[GameManager] Could not load item resource: %s" % item_resource_path)
		return
	
	var world_item_scene := load("res://scenes/world_objects/world_item.tscn") as PackedScene
	if not world_item_scene:
		push_error("[GameManager] Could not load world_item.tscn")
		return
	
	var world_item := world_item_scene.instantiate() as WorldItem
	if not world_item:
		return
	
	world_item.name = drop_name
	var stack := ItemStack.new(item_resource, count)
	world_item.setup(stack, initial_velocity)
	world_item.global_position = spawn_pos
	
	var level_root := get_tree().current_scene
	if level_root:
		level_root.add_child(world_item, true)
	else:
		get_tree().root.add_child(world_item, true)
	
	print("[GameManager] Spawned world item: %s x%d at %s" % [item_resource_path, count, spawn_pos])


## Remove a player's character from the world (e.g., on disconnect).
func despawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var info = NetworkManager._players.get(peer_id)
	if info and is_instance_valid(info.character_node):
		info.character_node.queue_free()
		info.character_node = null
		print("[GameManager] Despawned player %d" % peer_id)

# ---------------------------------------------------------------- helpers

func _gather_spawn_points() -> void:
	spawn_points.clear()
	var level := get_tree().current_scene
	if not level:
		return
	
	# Look for nodes with "SpawnPoint" in their name
	for child in level.get_children():
		if child is Marker3D and "SpawnPoint" in child.name:
			spawn_points.append(child as Marker3D)
	
	# If no spawn points found, create default ones around origin
	if spawn_points.is_empty():
		_create_default_spawn_points(level)


func _create_default_spawn_points(level: Node) -> void:
	# Create 8 default spawn positions in a circle
	for i in range(8):
		var angle := TAU * i / 8.0
		var marker := Marker3D.new()
		marker.name = "SpawnPoint%d" % i
		marker.position = Vector3(cos(angle) * 4.0, 1.0, sin(angle) * 4.0)
		level.add_child(marker)
		spawn_points.append(marker)


func _remove_preplaced_player() -> void:
	var level := get_tree().current_scene
	if not level:
		return
	
	# Find and remove any pre-placed Player nodes (from the tscn file)
	for child in level.get_children():
		if child is Player and child.owning_peer_id == 0:
			print("[GameManager] Removing pre-placed Player from level")
			child.queue_free()


func _next_spawn_position() -> Vector3:
	if spawn_points.is_empty():
		# Fallback: random offset from origin
		_spawn_index += 1
		return Vector3(_spawn_index * 2.0 - 4.0, 1.0, 0.0)
	
	var idx := _spawn_index % spawn_points.size()
	_spawn_index += 1
	return spawn_points[idx].global_position


func _cleanup_level_state() -> void:
	spawn_points.clear()
	_spawn_index = 0
	is_game_active = false
