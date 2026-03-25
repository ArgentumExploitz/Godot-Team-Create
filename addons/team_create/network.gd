@tool
extends Node

const PORT = 12345
const MAX_CLIENTS = 10

var ui: Control
var plugin: EditorPlugin
var peer = ENetMultiplayerPeer.new()
var is_server = false
var peers = {} # Dictionary mapping peer_id to user info (username, color)
var file_sync
var scene_sync

func _ready():
	name = "TeamCreateNetwork"
	# Load sync modules
	var file_sync_script = preload("res://addons/team_create/file_sync.gd")
	file_sync = file_sync_script.new()
	file_sync.network = self
	add_child(file_sync)

	var scene_sync_script = preload("res://addons/team_create/scene_sync.gd")
	scene_sync = scene_sync_script.new()
	scene_sync.network = self
	add_child(scene_sync)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_server():
	peer.create_server(PORT, MAX_CLIENTS)
	multiplayer.multiplayer_peer = peer
	is_server = true
	_add_peer(1)
	_update_ui_state()

func join_server(ip: String):
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer
	is_server = false
	_add_peer(multiplayer.get_unique_id())

func disconnect_peer():
	peer.close()
	multiplayer.multiplayer_peer = null
	peers.clear()
	if ui:
		ui.set_disconnected()
	print("Disconnected")

func _add_peer(id: int):
	if not peers.has(id):
		var rng = RandomNumberGenerator.new()
		rng.seed = id
		var color = Color.from_hsv(rng.randf(), 0.8, 0.9)
		var adjectives = ["Fast", "Cool", "Smart", "Brave", "Wild", "Quick", "Sly", "Bold"]
		var nouns = ["Cat", "Dog", "Fox", "Bear", "Wolf", "Hawk", "Owl", "Lion"]
		var username = adjectives[rng.randi() % adjectives.size()] + nouns[rng.randi() % nouns.size()] + str(rng.randi() % 100)
		peers[id] = {"username": username, "color": color}

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
	_add_peer(id)
	if ui:
		ui.update_users_count(peers.size())

	if is_server:
		# Auto sync all files when a peer joins
		call_deferred("sync_all_files_to_peer", id)
		call_deferred("push_current_scene_to_peer", id)
		# Send current peer list to the new peer
		for existing_id in peers.keys():
			rpc_id(id, "sync_peer_info", existing_id, peers[existing_id])

	# Everyone tells the new peer about themselves
	rpc_id(id, "sync_peer_info", multiplayer.get_unique_id(), peers[multiplayer.get_unique_id()])

func _on_peer_disconnected(id: int):
	print("Peer disconnected: ", id)
	if peers.has(id):
		peers.erase(id)
	if ui:
		ui.update_users_count(peers.size())

	# Clear selection outlines for disconnected peer
	if scene_sync:
		scene_sync.clear_peer_selections(id)

func _on_connected_to_server():
	print("Connected to server successfully!")
	_add_peer(1) # Add server to peers list
	_update_ui_state()

@rpc("any_peer", "reliable")
func sync_peer_info(id: int, info: Dictionary):
	peers[id] = info
	if ui:
		ui.update_users_count(peers.size())

func _on_connection_failed():
	print("Connection to server failed.")
	disconnect_peer()

func _on_server_disconnected():
	print("Server disconnected.")
	disconnect_peer()

func _update_ui_state():
	if ui:
		ui.set_connected(is_server)
		var username = get_username(multiplayer.get_unique_id())
		ui.status_label.text = "Status: " + username + " Connected"
		ui.update_users_count(peers.size())

func push_current_scene():
	if scene_sync:
		scene_sync.push_current_scene()

func push_current_scene_to_peer(id: int):
	if scene_sync:
		scene_sync.push_current_scene_to_peer(id)

func sync_project_settings():
	if file_sync:
		file_sync.sync_project_settings()

func sync_all_files():
	if file_sync:
		file_sync.sync_all_files()

func sync_all_files_to_peer(id: int):
	if file_sync:
		file_sync.sync_all_files_to_peer(id)

# Unique ID management for nodes (Using node paths for consistency across network without modifying .tscn files on every connection)
static func assign_unique_id(node: Node) -> String:
	# Using the absolute path from the scene root is deterministic and avoids .tscn serialization issues
	var tree = node.get_tree()
	if tree and tree.edited_scene_root:
		var root = tree.edited_scene_root
		if node == root:
			return "."
		return root.get_path_to(node)
	return node.get_path()

static func get_node_by_unique_id(root: Node, id: String) -> Node:
	if id == ".":
		return root
	if root.has_node(id):
		return root.get_node(id)
	return null

# User Info management
func get_user_color(id: int) -> Color:
	if peers.has(id):
		return peers[id]["color"]
	# Fallback
	var rng = RandomNumberGenerator.new()
	rng.seed = id
	return Color.from_hsv(rng.randf(), 0.8, 0.9)

func get_username(id: int) -> String:
	if peers.has(id):
		return peers[id]["username"]
	return "User" + str(id)
