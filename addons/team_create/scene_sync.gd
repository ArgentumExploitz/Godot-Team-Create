@tool
extends Node

var network: Node
var _last_scene_path: String = ""
var _last_tracked_properties = {}
var _last_selected_ids = []
var _time_since_sync = 0.0
const SYNC_INTERVAL = 0.1

var _ignore_next_structure_event = false
var _is_reloading_scene = false
var _pre_removal_paths = {}
var _node_names = {}
var _force_full_sync_next_frame = false
var _pending_resource_properties = []

# Action Queue system
var _pending_actions: Array = []
var _receiving_properties: Dictionary = {}
var _receiving_scenes: Dictionary = {}
var _receiving_scene_states: Dictionary = {}

const TeamCreateAction = preload("res://addons/team_create/action.gd")
const TeamCreateActionExecutor = preload("res://addons/team_create/action_executor.gd")

func _ready():
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.node_added.connect(_on_node_added)
		tree.node_removed.connect(_on_node_removed)
		tree.node_renamed.connect(_on_node_renamed)
		var root = tree.root
		if root:
			_connect_tree_exiting_recursive(root)
	call_deferred("_setup_undo_redo")

func _setup_undo_redo():
	if network and network.plugin:
		var undo_redo = network.plugin.get_undo_redo()
		if undo_redo:
			if not undo_redo.version_changed.is_connected(_on_undo_redo_version_changed):
				undo_redo.version_changed.connect(_on_undo_redo_version_changed)

func _on_undo_redo_version_changed():
	_force_full_sync_next_frame = true

func _connect_tree_exiting_recursive(node: Node):
	if not node.tree_exiting.is_connected(_on_node_tree_exiting.bind(node)):
		node.tree_exiting.connect(_on_node_tree_exiting.bind(node))
	_node_names[node.get_instance_id()] = node.name
	for child in node.get_children():
		_connect_tree_exiting_recursive(child)

func _on_node_tree_exiting(node: Node):
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		var current_scene = null
		if network and network.plugin:
			current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
		var scene_path = ""
		if node.owner and node.owner.scene_file_path != "":
			scene_path = node.owner.scene_file_path
		elif node.scene_file_path != "":
			scene_path = node.scene_file_path
		elif current_scene:
			scene_path = current_scene.scene_file_path
		var root_node = node.owner if node.owner else current_scene
		if node == current_scene:
			root_node = node
		_pre_removal_paths[node.get_instance_id()] = {"id": network.assign_unique_id(node), "scene_path": scene_path, "root_node": root_node}

func _process(delta):
	if not network or not network.plugin or not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_time_since_sync += delta
	if _time_since_sync >= SYNC_INTERVAL:
		_time_since_sync = 0.0
		_track_selection()
		_track_changes_throttled()
	_sync_cursor_throttled(delta)

	# Process pending resource properties
	for i in range(_pending_resource_properties.size() - 1, -1, -1):
		var pending = _pending_resource_properties[i]
		if network and network.file_sync and pending.value in network.file_sync.downloading_files:
			continue
		if ResourceLoader.exists(pending.value):
			var editor = network.plugin.get_editor_interface()
			var current_scene = editor.get_edited_scene_root()
			if current_scene and current_scene.scene_file_path == pending.scene_path:
				var node = network.get_node_by_unique_id(current_scene, pending.id)
				if is_instance_valid(node):
					var res = load(pending.value)
					if res:
						node.set(pending.prop_name, res)
			_pending_resource_properties.remove_at(i)
		else:
			pending.retries -= 1
			if pending.retries <= 0:
				_pending_resource_properties.remove_at(i)

func _track_changes_throttled():
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene: return
	if current_scene.scene_file_path != _last_scene_path:
		_last_scene_path = current_scene.scene_file_path
		_last_tracked_properties.clear()
		if _last_scene_path != "":
			rpc("request_scene_state", _last_scene_path)
	if _force_full_sync_next_frame:
		_force_full_sync_next_frame = false
		_check_all_nodes(current_scene, current_scene)
	else:
		var selected = editor.get_selection().get_selected_nodes()
		for node in selected:
			_check_single_node_changes(node)

func _check_all_nodes(node: Node, scene_root: Node):
	if node.owner == scene_root or node == scene_root:
		_check_single_node_changes(node)
	for child in node.get_children():
		_check_all_nodes(child, scene_root)

func _check_single_node_changes(node: Node):
	var id = network.assign_unique_id(node)
	var props = node.get_property_list()
	var current_props = {}
	for p in props:
		if p.usage & PROPERTY_USAGE_EDITOR or p.name == "transform" or p.name == "name":
			if p.name.begins_with("metadata/"): continue
			var val = node.get(p.name)
			if typeof(val) == TYPE_OBJECT:
				if val is Resource:
					if val.resource_path != "" and not "::" in val.resource_path:
						current_props[p.name] = val.resource_path
					else:
						var bytes = var_to_bytes_with_objects(val)
						current_props[p.name] = {"sub_resource_bytes": bytes, "resource_path": val.resource_path}
			else:
				current_props[p.name] = val

	if not _last_tracked_properties.has(id):
		_last_tracked_properties[id] = current_props
	else:
		var last_props = _last_tracked_properties[id]
		for prop_name in current_props:
			if not last_props.has(prop_name) or str(last_props[prop_name]) != str(current_props[prop_name]):
				_send_update_node_property(id, prop_name, current_props[prop_name], last_props.get(prop_name, current_props[prop_name]), _last_scene_path)
				last_props[prop_name] = current_props[prop_name]

# ACTION DISPATCHING
func _dispatch_action(action: RefCounted, scene_path: String):
	_pending_actions.append(action)
	var dict = action.to_dict()
	var bytes = var_to_bytes_with_objects(dict)

	if bytes.size() > 60000:
		var chunk_size = 60000
		var total_size = bytes.size()
		var offset = 0
		while offset < total_size:
			var end_idx = min(offset + chunk_size, total_size)
			var chunk = bytes.slice(offset, end_idx)
			var is_final = (end_idx == total_size)
			rpc("submit_action_chunked", chunk, scene_path, is_final, action.action_id)
			offset += chunk_size
	else:
		if multiplayer.is_server():
			submit_action(dict, scene_path)
		else:
			rpc_id(1, "submit_action", dict, scene_path)

@rpc("any_peer", "reliable")
func submit_action_chunked(chunk: PackedByteArray, scene_path: String, is_final: bool, action_id: String):
	var sender_id = multiplayer.get_remote_sender_id()
	# Only server processes submissions, unless we are server broadcasting to clients
	if not multiplayer.is_server() and sender_id != 1:
		return
	var key = str(sender_id) + "_" + action_id
	if not _receiving_properties.has(key):
		_receiving_properties[key] = PackedByteArray()
	_receiving_properties[key].append_array(chunk)

	if is_final:
		var full_bytes = _receiving_properties[key]
		_receiving_properties.erase(key)
		var dict = bytes_to_var_with_objects(full_bytes)

		# If client receives chunked action from server, it's an ACK
		if not multiplayer.is_server() and sender_id == 1:
			_handle_ack(dict, scene_path)
		else:
			submit_action(dict, scene_path)

@rpc("any_peer", "reliable")
func submit_action(action_dict: Dictionary, scene_path: String):
	# If client receives this, it's a broadcasted ACK
	if not multiplayer.is_server():
		if multiplayer.get_remote_sender_id() == 1:
			_handle_ack(action_dict, scene_path)
		return

	# SERVER AUTHORITY
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene or (scene_path != "" and current_scene.scene_file_path != scene_path):
		return

	var action = TeamCreateAction.from_dict(action_dict)

	# Validate and apply
	var is_valid = true
	# Block metadata updates for security
	if action.type == TeamCreateAction.TYPE_PROPERTY_CHANGE and action.payload.get("property", "").begins_with("metadata/"):
		is_valid = false
		printerr("Team Create: Blocked unsafe property sync: ", action.payload.get("property"))

	# Validate paths
	if action.type == TeamCreateAction.TYPE_PROPERTY_CHANGE:
		var val = action.payload.get("value")
		if typeof(val) == TYPE_STRING and (val as String).begins_with("res://") and ".." in (val as String):
			is_valid = false

	if is_valid:
		_ignore_next_structure_event = true
		TeamCreateActionExecutor.execute(action, current_scene, network, scene_path)
		_ignore_next_structure_event = false

		# Broadcast ACK to all clients
		var bytes = var_to_bytes_with_objects(action_dict)
		if bytes.size() > 60000:
			var chunk_size = 60000
			var total_size = bytes.size()
			var offset = 0
			while offset < total_size:
				var end_idx = min(offset + chunk_size, total_size)
				var chunk = bytes.slice(offset, end_idx)
				var is_final = (end_idx == total_size)
				rpc("submit_action_chunked", chunk, scene_path, is_final, action.action_id)
				offset += chunk_size
		else:
			rpc("submit_action", action_dict, scene_path)
	else:
		# Send NACK back to the sender
		var nack_data = {"inverse_payload": action.inverse_payload}
		rpc_id(action.client_id, "reject_action", action.action_id, nack_data, scene_path)

func _handle_ack(action_dict: Dictionary, scene_path: String):
	var action = TeamCreateAction.from_dict(action_dict)

	# If we authored it, remove from pending
	if action.client_id == multiplayer.get_unique_id():
		for i in range(_pending_actions.size() - 1, -1, -1):
			if _pending_actions[i].action_id == action.action_id:
				_pending_actions.remove_at(i)
				break
	else:
		# Apply from other client
		var editor = network.plugin.get_editor_interface()
		var current_scene = editor.get_edited_scene_root()
		if current_scene:
			_ignore_next_structure_event = true
			TeamCreateActionExecutor.execute(action, current_scene, network, scene_path)
			_ignore_next_structure_event = false

			# Update last tracked properties
			if action.type == TeamCreateAction.TYPE_PROPERTY_CHANGE:
				var id = action.target_path
				if not _last_tracked_properties.has(id):
					_last_tracked_properties[id] = {}
				_last_tracked_properties[id][action.payload.get("property", "")] = action.payload.get("value")

@rpc("any_peer", "reliable")
func reject_action(action_id: String, nack_data: Dictionary, scene_path: String):
	if multiplayer.get_remote_sender_id() != 1: return

	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene: return

	# Rollback pending actions
	_ignore_next_structure_event = true

	var idx = -1
	for i in range(_pending_actions.size()):
		if _pending_actions[i].action_id == action_id:
			idx = i
			break

	if idx != -1:
		# Undo all actions from newest down to the rejected one
		for i in range(_pending_actions.size() - 1, idx - 1, -1):
			TeamCreateActionExecutor.undo(_pending_actions[i], current_scene, network, scene_path)

		# Remove rejected
		var rejected = _pending_actions[idx]
		_pending_actions.remove_at(idx)

		# Apply server state correction
		var corr_action = TeamCreateAction.new(1, rejected.target_path, rejected.type, nack_data.get("inverse_payload", {}))
		TeamCreateActionExecutor.execute(corr_action, current_scene, network, scene_path)

		# Replay remaining
		for i in range(idx, _pending_actions.size()):
			TeamCreateActionExecutor.execute(_pending_actions[i], current_scene, network, scene_path)

	_ignore_next_structure_event = false

func _send_update_node_property(id: String, prop_name: String, value: Variant, old_value: Variant, scene_path: String = ""):
	var action = TeamCreateAction.new(
		multiplayer.get_unique_id(),
		id,
		TeamCreateAction.TYPE_PROPERTY_CHANGE,
		{"property": prop_name, "value": value},
		{"property": prop_name, "value": old_value}
	)
	_dispatch_action(action, scene_path)

func _on_node_added(node: Node):
	if not node.tree_exiting.is_connected(_on_node_tree_exiting.bind(node)):
		node.tree_exiting.connect(_on_node_tree_exiting.bind(node))
	_node_names[node.get_instance_id()] = node.name
	if _ignore_next_structure_event or _is_reloading_scene or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		return
	var owner_at_add = node.owner
	await get_tree().process_frame
	if not is_instance_valid(node) or not node.get_parent(): return
	if node.name.begins_with("@") or node.name.begins_with("TeamCreateSelectionOutline_") or node.name.begins_with("TeamCreateCursor"): return
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene: return
	if node == current_scene or node.owner != current_scene or owner_at_add != null: return

	var parent_id = network.assign_unique_id(node.get_parent())
	var type = node.get_class()
	var new_name = node.name
	var new_id = network.assign_unique_id(node)
	_node_names[node.get_instance_id()] = new_name

	var action = TeamCreateAction.new(
		multiplayer.get_unique_id(),
		parent_id,
		TeamCreateAction.TYPE_NODE_CREATE,
		{"type": type, "name": new_name, "id": new_id},
		{"type": type, "name": new_name}
	)
	_dispatch_action(action, current_scene.scene_file_path)
	_sync_all_node_properties(node, new_id)

func _sync_all_node_properties(node: Node, id: String):
	var type = node.get_class()
	if not ClassDB.can_instantiate(type): return
	var default_node = ClassDB.instantiate(type)
	if not default_node: return
	var props = node.get_property_list()
	var current_props = {}
	for p in props:
		if p.usage & PROPERTY_USAGE_EDITOR or p.name == "transform" or p.name == "name":
			if p.name.begins_with("metadata/"): continue
			var val = node.get(p.name)
			var default_val = default_node.get(p.name)
			var is_different = false
			if typeof(val) != typeof(default_val): is_different = true
			elif typeof(val) == TYPE_OBJECT:
				if val != default_val and val != null: is_different = true
			else:
				if val != default_val: is_different = true
			if is_different:
				if typeof(val) == TYPE_OBJECT:
					if val is Resource:
						if val.resource_path != "" and not "::" in val.resource_path:
							current_props[p.name] = val.resource_path
						else:
							var bytes = var_to_bytes_with_objects(val)
							current_props[p.name] = {"sub_resource_bytes": bytes, "resource_path": val.resource_path}
				else:
					current_props[p.name] = val
	default_node.free()

	if not _last_tracked_properties.has(id):
		_last_tracked_properties[id] = current_props
	else:
		var last_props = _last_tracked_properties[id]
		for prop_name in current_props:
			last_props[prop_name] = current_props[prop_name]

	for prop_name in current_props:
		_send_update_node_property(id, prop_name, current_props[prop_name], null, _last_scene_path)

func _on_node_removed(node: Node):
	var inst_id = node.get_instance_id()
	var pre_data = _pre_removal_paths.get(inst_id, {})
	var id = ""
	var scene_path = ""
	var root_node = null
	if typeof(pre_data) == TYPE_DICTIONARY:
		id = pre_data.get("id", "")
		scene_path = pre_data.get("scene_path", "")
		root_node = pre_data.get("root_node")
	elif typeof(pre_data) == TYPE_STRING:
		id = pre_data

	if _pre_removal_paths.has(inst_id): _pre_removal_paths.erase(inst_id)
	if _node_names.has(inst_id): _node_names.erase(inst_id)

	# Cache values before the node is freed or we await a frame
	var parent_path_str = str(node.get_parent().get_path()) if node.get_parent() else ""
	var cached_class = node.get_class()
	var cached_name = node.name
	var cached_props = _last_tracked_properties.get(id, {}).duplicate()

	if id != "" and _last_tracked_properties.has(id): _last_tracked_properties.erase(id)

	if _ignore_next_structure_event or _is_reloading_scene or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty() or id == "" or id == ".": return
	await get_tree().process_frame
	if root_node != null and (not is_instance_valid(root_node) or not root_node.is_inside_tree()): return

	if network and network.plugin:
		var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
		if current_scene:
			var active_scene_path = current_scene.scene_file_path
			if scene_path != "" and active_scene_path != scene_path: return
		else:
			return

	var action = TeamCreateAction.new(
		multiplayer.get_unique_id(),
		id,
		TeamCreateAction.TYPE_NODE_REMOVE,
		{},
		{"parent_path": parent_path_str, "type": cached_class, "name": cached_name, "properties": cached_props}
	)
	_dispatch_action(action, scene_path)

func _on_node_renamed(node: Node):
	if _ignore_next_structure_event or _is_reloading_scene or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty(): return
	var parent = node.get_parent()
	var inst_id = node.get_instance_id()
	if parent and _node_names.has(inst_id):
		var old_name = _node_names[inst_id]
		var new_name = node.name
		if old_name != new_name:
			_node_names[inst_id] = new_name
			var parent_id = network.assign_unique_id(parent)
			var scene_path = ""
			var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
			if current_scene:
				scene_path = current_scene.scene_file_path
			var action = TeamCreateAction.new(
				multiplayer.get_unique_id(),
				parent_id,
				TeamCreateAction.TYPE_NODE_RENAME,
				{"old_name": old_name, "new_name": new_name},
				{"old_name": new_name, "new_name": old_name}
			)
			_dispatch_action(action, scene_path)

# Keep other RPCs (cursor, selection, scene push) mostly untouched for backwards compatibility with the rest of the plugin
# Only adapting the ones we strictly modified for actions

func _track_selection():
	var editor = network.plugin.get_editor_interface()
	var selection = editor.get_selection().get_selected_nodes()
	var selected_ids = []
	for node in selection:
		var id = network.assign_unique_id(node)
		selected_ids.append(id)
	if selected_ids != _last_selected_ids:
		_last_selected_ids = selected_ids
		rpc("update_peer_selection", multiplayer.get_unique_id(), selected_ids, _last_scene_path)

@rpc("any_peer", "reliable")
func update_peer_selection(peer_id: int, selected_ids: Array, scene_path: String = ""):
	var color = network.get_user_color(peer_id)
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene: return
	var tree = current_scene.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
			if is_instance_valid(node): node.queue_free()
	if scene_path != "" and current_scene.scene_file_path != scene_path: return

	for id in selected_ids:
		var node = network.get_node_by_unique_id(current_scene, id)
		if node:
			if node is Node3D:
				var outline = MeshInstance3D.new()
				outline.name = "TeamCreateSelectionOutline_" + str(peer_id)
				outline.set_meta("team_create_outline_peer", peer_id)
				outline.add_to_group("TeamCreateSelectionOutlines_" + str(peer_id))
				outline.add_to_group("TeamCreateSelectionOutlines")
				var mat = StandardMaterial3D.new()
				mat.albedo_color = color
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.5
				var box_mesh = BoxMesh.new()
				if node is MeshInstance3D and node.mesh:
					var aabb = node.mesh.get_aabb()
					box_mesh.size = aabb.size * 1.05
					outline.position = aabb.position + aabb.size/2
				else:
					box_mesh.size = Vector3(1.1, 1.1, 1.1)
				outline.mesh = box_mesh
				outline.material_override = mat
				if is_instance_valid(node) and node.is_inside_tree():
					node.add_child(outline)
			elif node is Node2D or node is Control:
				var outline = ColorRect.new()
				outline.name = "TeamCreateSelectionOutline_" + str(peer_id)
				outline.set_meta("team_create_outline_peer", peer_id)
				outline.add_to_group("TeamCreateSelectionOutlines_" + str(peer_id))
				outline.add_to_group("TeamCreateSelectionOutlines")
				outline.color = color
				outline.color.a = 0.5
				if node is Node2D:
					outline.size = Vector2(50, 50)
					outline.position = Vector2(-25, -25)
				else:
					outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
					outline.size = node.size
				outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if is_instance_valid(node) and node.is_inside_tree():
					node.add_child(outline)

func clear_peer_selections(peer_id: int):
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene: return
	var tree = current_scene.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
			if is_instance_valid(node): node.queue_free()

func push_current_scene():
	if multiplayer.is_server():
		var editor = network.plugin.get_editor_interface()
		var current_scene = editor.get_edited_scene_root()
		if current_scene:
			var path = current_scene.scene_file_path
			if path != "":
				if FileAccess.file_exists(path):
					var bytes = FileAccess.get_file_as_bytes(path)
					var chunk_size = 60000
					var total_size = bytes.size()
					var offset = 0
					if total_size == 0:
						rpc("receive_scene", path, bytes, true)
						return
					while offset < total_size:
						var end_idx = min(offset + chunk_size, total_size)
						var chunk = bytes.slice(offset, end_idx)
						var is_final = (end_idx == total_size)
						rpc("receive_scene", path, chunk, is_final)
						offset += chunk_size

func push_current_scene_to_peer(id: int):
	if multiplayer.is_server():
		var editor = network.plugin.get_editor_interface()
		var current_scene = editor.get_edited_scene_root()
		if current_scene:
			var path = current_scene.scene_file_path
			if path != "":
				if FileAccess.file_exists(path):
					var bytes = FileAccess.get_file_as_bytes(path)
					var chunk_size = 60000
					var total_size = bytes.size()
					var offset = 0
					if total_size == 0:
						rpc_id(id, "receive_scene", path, bytes, true)
						return
					while offset < total_size:
						var end_idx = min(offset + chunk_size, total_size)
						var chunk = bytes.slice(offset, end_idx)
						var is_final = (end_idx == total_size)
						rpc_id(id, "receive_scene", path, chunk, is_final)
						offset += chunk_size

@rpc("any_peer", "reliable")
func receive_scene(path: String, bytes: PackedByteArray, is_final: bool = true):
	if path.begins_with("res://addons/team_create") or path.begins_with("res://.godot") or path.begins_with("res://webrtc"): return
	if not path.begins_with("res://") or ".." in path: return

	var sender_id = multiplayer.get_remote_sender_id()
	var scene_key = str(sender_id) + "_" + path
	if not _receiving_scenes.has(scene_key):
		_receiving_scenes[scene_key] = PackedByteArray()
	_receiving_scenes[scene_key].append_array(bytes)
	if not is_final: return

	var full_bytes = _receiving_scenes[scene_key]
	_receiving_scenes.erase(scene_key)
	bytes = full_bytes

	if network and network.plugin:
		var editor = network.plugin.get_editor_interface()
		var current_scene = editor.get_edited_scene_root()
		var open_scenes = editor.get_open_scenes()
		var is_active = false
		if current_scene and current_scene.scene_file_path == path: is_active = true

		if is_active:
			if bytes.size() > 0:
				var file = FileAccess.open(path, FileAccess.WRITE)
				if file:
					file.store_buffer(bytes)
					file.close()
			_is_reloading_scene = true
			_force_full_sync_next_frame = true
			editor.reload_scene_from_path(path)
			get_tree().create_timer(0.5).timeout.connect(func(): _is_reloading_scene = false)
			return
		elif path in open_scenes:
			var prev_path = current_scene.scene_file_path if current_scene else ""
			editor.open_scene_from_path(path)
			editor.close_scene()
			if prev_path != "": editor.open_scene_from_path(prev_path)

	if bytes.size() > 0:
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
			file.close()

@rpc("any_peer", "reliable")
func request_scene_state(scene_path: String):
	if scene_path == "": return
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()

	if current_scene and current_scene.scene_file_path == scene_path:
		var sender_id = multiplayer.get_remote_sender_id()
		var outlines = []
		var tree = current_scene.get_tree()
		if tree:
			for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines"):
				if is_instance_valid(node): outlines.append({"node": node, "parent": node.get_parent()})
			for node in tree.get_nodes_in_group("TeamCreateCursors"):
				if is_instance_valid(node): outlines.append({"node": node, "parent": node.get_parent()})
		for data in outlines: data["parent"].remove_child(data["node"])

		var packed = PackedScene.new()
		var err = packed.pack(current_scene)

		for data in outlines:
			if is_instance_valid(data["parent"]) and is_instance_valid(data["node"]):
				data["parent"].add_child(data["node"])

		if err == OK:
			var temp_path = "user://temp_scene_state_" + str(multiplayer.get_unique_id()) + ".tscn"
			if ResourceSaver.save(packed, temp_path) == OK:
				if FileAccess.file_exists(temp_path):
					var bytes = FileAccess.get_file_as_bytes(temp_path)
					var chunk_size = 60000
					var total_size = bytes.size()
					var offset = 0
					if total_size == 0:
						rpc_id(sender_id, "receive_scene_state", scene_path, bytes, true)
						DirAccess.remove_absolute(temp_path)
						return
					while offset < total_size:
						var end_idx = min(offset + chunk_size, total_size)
						var chunk = bytes.slice(offset, end_idx)
						var is_final = (end_idx == total_size)
						rpc_id(sender_id, "receive_scene_state", scene_path, chunk, is_final)
						offset += chunk_size
				DirAccess.remove_absolute(temp_path)

@rpc("any_peer", "reliable")
func receive_scene_state(path: String, bytes: PackedByteArray, is_final: bool = true):
	if path.begins_with("res://addons/team_create") or path.begins_with("res://.godot") or path.begins_with("res://webrtc"): return
	if not path.begins_with("res://") or ".." in path: return

	var sender_id = multiplayer.get_remote_sender_id()
	var state_key = str(sender_id) + "_" + path
	if not _receiving_scene_states.has(state_key):
		_receiving_scene_states[state_key] = PackedByteArray()
	_receiving_scene_states[state_key].append_array(bytes)
	if not is_final: return

	var full_bytes = _receiving_scene_states[state_key]
	_receiving_scene_states.erase(state_key)
	bytes = full_bytes

	if bytes.size() > 0:
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
			file.close()

		if network and network.plugin:
			var editor = network.plugin.get_editor_interface()
			var current_scene = editor.get_edited_scene_root()
			if current_scene and current_scene.scene_file_path == path:
				_is_reloading_scene = true
				editor.reload_scene_from_path(path)
				get_tree().create_timer(0.5).timeout.connect(func(): _is_reloading_scene = false)

var _last_cursor_sync = 0.0
const CURSOR_SYNC_INTERVAL = 0.05
var _local_3d_cursor_pos: Transform3D = Transform3D()
var _local_2d_cursor_pos: Vector2 = Vector2.ZERO
var _has_3d_cursor = false
var _has_2d_cursor = false

func _sync_cursor_throttled(delta):
	_last_cursor_sync += delta
	if _last_cursor_sync >= CURSOR_SYNC_INTERVAL:
		_last_cursor_sync = 0.0
		if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			var data = _get_local_cursor_data()
			if data.has_3d:
				if data.pos_3d != _local_3d_cursor_pos:
					_local_3d_cursor_pos = data.pos_3d
					rpc("update_peer_cursor_3d", multiplayer.get_unique_id(), _local_3d_cursor_pos, _last_scene_path)
			elif data.has_2d:
				if data.pos_2d != _local_2d_cursor_pos:
					_local_2d_cursor_pos = data.pos_2d
					rpc("update_peer_cursor_2d", multiplayer.get_unique_id(), _local_2d_cursor_pos, _last_scene_path)

@rpc("any_peer", "unreliable")
func update_peer_cursor_3d(peer_id: int, pos: Transform3D, scene_path: String = ""):
	var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
	if not current_scene or (scene_path != "" and current_scene.scene_file_path != scene_path):
		_clear_peer_cursor(peer_id)
		return
	var tree = current_scene.get_tree()
	if not tree: return
	_clear_peer_cursor_2d(peer_id, current_scene)
	var cursor = _get_or_create_peer_cursor_3d(peer_id, current_scene)
	if cursor: cursor.global_transform = pos

@rpc("any_peer", "unreliable")
func update_peer_cursor_2d(peer_id: int, pos: Vector2, scene_path: String = ""):
	var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
	if not current_scene or (scene_path != "" and current_scene.scene_file_path != scene_path):
		_clear_peer_cursor(peer_id)
		return
	var tree = current_scene.get_tree()
	if not tree: return
	_clear_peer_cursor_3d(peer_id, current_scene)
	var cursor = _get_or_create_peer_cursor_2d(peer_id, current_scene)
	if cursor: cursor.position = pos

func _get_or_create_peer_cursor_3d(peer_id: int, current_scene: Node) -> Node3D:
	var group_name = "TeamCreateCursor3D_" + str(peer_id)
	var nodes = current_scene.get_tree().get_nodes_in_group(group_name)
	if nodes.size() > 0 and is_instance_valid(nodes[0]): return nodes[0]

	var cursor = Node3D.new()
	cursor.name = "TeamCreateCursor3D_" + str(peer_id)
	cursor.add_to_group(group_name)
	cursor.add_to_group("TeamCreateCursors")
	cursor.set_meta("_edit_lock_", true)

	var sphere_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	var mat = StandardMaterial3D.new()
	var color = network.get_user_color(peer_id)
	mat.albedo_color = color
	mat.albedo_color.a = 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	sphere_mesh.mesh = sphere
	sphere_mesh.material_override = mat
	sphere_mesh.position.z = 0.45
	cursor.add_child(sphere_mesh)

	var stick_mesh = MeshInstance3D.new()
	var stick = CylinderMesh.new()
	stick.top_radius = 0.02
	stick.bottom_radius = 0.02
	stick.height = 0.2
	stick_mesh.mesh = stick
	stick_mesh.material_override = mat
	stick_mesh.position.z = 0.25
	stick_mesh.rotation.x = -PI / 2.0
	cursor.add_child(stick_mesh)

	var arrow_mesh = MeshInstance3D.new()
	var arrow = CylinderMesh.new()
	arrow.top_radius = 0.0
	arrow.bottom_radius = 0.08
	arrow.height = 0.15
	arrow_mesh.mesh = arrow
	arrow_mesh.material_override = mat
	arrow_mesh.position.z = 0.075
	arrow_mesh.rotation.x = -PI / 2.0
	cursor.add_child(arrow_mesh)

	var label = Label3D.new()
	label.text = network.peers[peer_id].username if network.peers.has(peer_id) else "Peer " + str(peer_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 0.25
	label.position.z = 0.45
	label.modulate = color
	cursor.add_child(label)

	current_scene.add_child(cursor)
	return cursor

func _get_or_create_peer_cursor_2d(peer_id: int, current_scene: Node) -> Node2D:
	var group_name = "TeamCreateCursor2D_" + str(peer_id)
	var nodes = current_scene.get_tree().get_nodes_in_group(group_name)
	if nodes.size() > 0 and is_instance_valid(nodes[0]): return nodes[0]

	var cursor = Node2D.new()
	cursor.name = "TeamCreateCursor2D_" + str(peer_id)
	cursor.add_to_group(group_name)
	cursor.add_to_group("TeamCreateCursors")
	cursor.set_meta("_edit_lock_", true)

	var poly = Polygon2D.new()
	var color = network.get_user_color(peer_id)
	poly.color = color
	poly.color.a = 1.0
	poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(12, 12), Vector2(5, 12), Vector2(0, 17)])

	var outline = Line2D.new()
	outline.points = poly.polygon
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color(0.3, 0.3, 0.3, 0.8)
	cursor.add_child(outline)
	cursor.add_child(poly)
	current_scene.add_child(cursor)
	return cursor

func _clear_peer_cursor(peer_id: int):
	var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
	if not current_scene: return
	_clear_peer_cursor_3d(peer_id, current_scene)
	_clear_peer_cursor_2d(peer_id, current_scene)

func _clear_peer_cursor_3d(peer_id: int, current_scene: Node):
	for node in current_scene.get_tree().get_nodes_in_group("TeamCreateCursor3D_" + str(peer_id)):
		if is_instance_valid(node): node.queue_free()

func _clear_peer_cursor_2d(peer_id: int, current_scene: Node):
	for node in current_scene.get_tree().get_nodes_in_group("TeamCreateCursor2D_" + str(peer_id)):
		if is_instance_valid(node): node.queue_free()

func clear_all_peer_indicators():
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene: return
	var tree = current_scene.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines"):
			if is_instance_valid(node): node.queue_free()
		for node in tree.get_nodes_in_group("TeamCreateCursors"):
			if is_instance_valid(node): node.queue_free()

func _update_cursor_username(peer_id: int, username: String):
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene: return
	var tree = current_scene.get_tree()
	if not tree: return
	var nodes = tree.get_nodes_in_group("TeamCreateCursor3D_" + str(peer_id))
	for node in nodes:
		if is_instance_valid(node):
			for child in node.get_children():
				if child is Label3D:
					child.text = username

func _find_editor_viewport(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name: return node
	for i in range(node.get_child_count()):
		var res = _find_editor_viewport(node.get_child(i), type_name)
		if res: return res
	return null

func _find_editor_camera_3d(node: Node) -> Camera3D:
	if node is Camera3D: return node
	for i in range(node.get_child_count()):
		var res = _find_editor_camera_3d(node.get_child(i))
		if res: return res
	return null

var _cached_3d_viewport: Node = null
var _cached_2d_viewport: Control = null
var _cached_3d_camera: Camera3D = null

func _get_local_cursor_data() -> Dictionary:
	var result = {"has_3d": false, "pos_3d": Transform3D(), "has_2d": false, "pos_2d": Vector2.ZERO}
	var main_screen = network.plugin.get_editor_interface().get_editor_main_screen()
	if not is_instance_valid(main_screen) or not main_screen.is_inside_tree(): return result

	if not is_instance_valid(_cached_3d_viewport): _cached_3d_viewport = _find_editor_viewport(main_screen, "Node3DEditorViewport")
	if not is_instance_valid(_cached_2d_viewport): _cached_2d_viewport = _find_editor_viewport(main_screen, "CanvasItemEditorViewport")

	if is_instance_valid(_cached_3d_viewport) and _cached_3d_viewport.is_visible_in_tree():
		if not is_instance_valid(_cached_3d_camera): _cached_3d_camera = _find_editor_camera_3d(_cached_3d_viewport)
		var cam = _cached_3d_camera
		if is_instance_valid(cam):
			var viewport = cam.get_viewport()
			if viewport:
				result.has_3d = true
				result.pos_3d = cam.global_transform

	if is_instance_valid(_cached_2d_viewport) and _cached_2d_viewport.is_visible_in_tree():
		var mouse_pos = _cached_2d_viewport.get_local_mouse_position()
		var rect = Rect2(Vector2.ZERO, _cached_2d_viewport.size)
		if rect.has_point(mouse_pos):
			result.has_2d = true
			var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
			if current_scene and current_scene is Node2D:
				result.pos_2d = current_scene.get_global_transform_with_canvas().affine_inverse() * mouse_pos
			elif current_scene and current_scene is Control:
				result.pos_2d = current_scene.get_global_transform_with_canvas().affine_inverse() * mouse_pos
			else:
				result.pos_2d = _cached_2d_viewport.get_global_mouse_position()

	return result
