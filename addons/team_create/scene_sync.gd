@tool
extends Node

var network: Node
var _last_scene_path: String = ""
var _last_tracked_properties = {}
var _last_selected_ids = []
var _time_since_sync = 0.0
const SYNC_INTERVAL = 0.1 # Sync 10 times a second max

# Tracking structure changes locally so we don't bounce events back and forth
var _ignore_next_structure_event = false
var _is_reloading_scene = false
var _pre_removal_paths = {}
var _node_names = {}
var _force_full_sync_next_frame = false
var _pending_resource_properties = []

func _ready():
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.node_added.connect(_on_node_added)
		tree.node_removed.connect(_on_node_removed)
		tree.node_renamed.connect(_on_node_renamed)

		# Hook into tree signals to capture state before the change applies
		var root = tree.root
		if root:
			# Also connect existing nodes
			_connect_tree_exiting_recursive(root)

	call_deferred("_setup_undo_redo")

func _setup_undo_redo():
	if network and network.plugin:
		var undo_redo = network.plugin.get_undo_redo()
		if undo_redo:
			if not undo_redo.version_changed.is_connected(_on_undo_redo_version_changed):
				undo_redo.version_changed.connect(_on_undo_redo_version_changed)

func _on_undo_redo_version_changed():
	# Trigger a full check of modified nodes on the next sync interval
	# Useful for drag-and-drop actions that aren't on actively selected nodes
	_force_full_sync_next_frame = true

func _connect_tree_exiting_recursive(node: Node):
	if not node.tree_exiting.is_connected(_on_node_tree_exiting.bind(node)):
		node.tree_exiting.connect(_on_node_tree_exiting.bind(node))

	_node_names[node.get_instance_id()] = node.name

	for child in node.get_children():
		_connect_tree_exiting_recursive(child)

func _on_node_tree_exiting(node: Node):
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		var scene_path = ""
		if node.owner and node.owner.scene_file_path != "":
			scene_path = node.owner.scene_file_path
		elif node.scene_file_path != "":
			scene_path = node.scene_file_path
		elif network and network.plugin:
			var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
			if current_scene:
				scene_path = current_scene.scene_file_path

		var root_node = null
		if network and network.plugin:
			var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
			if current_scene:
				root_node = current_scene

		_pre_removal_paths[node.get_instance_id()] = {"id": network.assign_unique_id(node), "scene_path": scene_path, "root_node": root_node}

func _process(delta):
	if not network or not network.plugin or network.peer.get_connection_status() != ENetMultiplayerPeer.CONNECTION_CONNECTED:
		return

	_time_since_sync += delta
	if _time_since_sync >= SYNC_INTERVAL:
		_time_since_sync = 0.0
		_track_selection()
		_track_changes_throttled()

	# Process pending resource properties (waiting for file sync)
	for i in range(_pending_resource_properties.size() - 1, -1, -1):
		var pending = _pending_resource_properties[i]
		if ResourceLoader.exists(pending.value):
			var editor = network.plugin.get_editor_interface()
			var current_scene = editor.get_edited_scene_root()
			if current_scene:
				var node = network.get_node_by_unique_id(current_scene, pending.id)
				if node:
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
	if not current_scene:
		return

	if current_scene.scene_file_path != _last_scene_path:
		_last_scene_path = current_scene.scene_file_path
		_last_tracked_properties.clear()

	if _force_full_sync_next_frame:
		_force_full_sync_next_frame = false
		_check_all_nodes(current_scene)
	else:
		# ONLY track changes for selected nodes to save massive performance costs
		var selected = editor.get_selection().get_selected_nodes()
		for node in selected:
			_check_single_node_changes(node)

func _check_all_nodes(node: Node):
	if node.owner == network.plugin.get_editor_interface().get_edited_scene_root() or node == network.plugin.get_editor_interface().get_edited_scene_root():
		_check_single_node_changes(node)
	for child in node.get_children():
		_check_all_nodes(child)

func _check_single_node_changes(node: Node):
	var id = network.assign_unique_id(node)

	var props = node.get_property_list()
	var current_props = {}
	for p in props:
		# Filter for export or essential properties
		if p.usage & PROPERTY_USAGE_EDITOR or p.name == "transform" or p.name == "name":
			if p.name == "script" or p.name.begins_with("metadata/"):
				continue
			var val = node.get(p.name)
			if typeof(val) == TYPE_OBJECT:
				# For resources like Mesh or Material, sync the resource path if possible
				if val is Resource:
					if val.resource_path != "" and not "::" in val.resource_path:
						current_props[p.name] = val.resource_path
					else:
						# Serialize local sub-resources or resources without a file path
						var bytes = var_to_bytes_with_objects(val)
						current_props[p.name] = {"sub_resource_bytes": bytes}
			else:
				current_props[p.name] = val

	if not _last_tracked_properties.has(id):
		_last_tracked_properties[id] = current_props
	else:
		var last_props = _last_tracked_properties[id]
		for prop_name in current_props:
			if not last_props.has(prop_name) or last_props[prop_name] != current_props[prop_name]:
				rpc("update_node_property", id, prop_name, current_props[prop_name], _last_scene_path)
				last_props[prop_name] = current_props[prop_name]

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
	# Add custom selection drawing logic
	var color = network.get_user_color(peer_id)
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene:
		return
	if scene_path != "" and current_scene.scene_file_path != scene_path:
		return

	# Clear previous indicators
	for node in current_scene.find_children("*", "Node", true, false):
		if node.has_meta("team_create_outline_peer"):
			if node.get_meta("team_create_outline_peer") == peer_id:
				node.queue_free()
		elif node.name.begins_with("TeamCreateSelectionOutline_" + str(peer_id)):
			# Also clean up any unmanaged older outlines by name just in case
			node.queue_free()

	# Add new indicators
	for id in selected_ids:
		var node = network.get_node_by_unique_id(current_scene, id)
		if node:
			if node is Node3D:
				var outline = MeshInstance3D.new()
				outline.name = "TeamCreateSelectionOutline_" + str(peer_id)
				outline.set_meta("team_create_outline_peer", peer_id)
				var mat = StandardMaterial3D.new()
				mat.albedo_color = color
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.5

				# Attempt to fit box to mesh if available
				var box_mesh = BoxMesh.new()
				if node is MeshInstance3D and node.mesh:
					var aabb = node.mesh.get_aabb()
					box_mesh.size = aabb.size * 1.05
					outline.position = aabb.position + aabb.size/2
				else:
					box_mesh.size = Vector3(1.1, 1.1, 1.1)

				outline.mesh = box_mesh
				outline.material_override = mat
				node.add_child(outline)

			elif node is Node2D or node is Control:
				var outline = ColorRect.new()
				outline.name = "TeamCreateSelectionOutline_" + str(peer_id)
				outline.set_meta("team_create_outline_peer", peer_id)
				outline.color = color
				outline.color.a = 0.5
				outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)

				if node is Node2D:
					outline.size = Vector2(50, 50)
					outline.position = Vector2(-25, -25)
				else: # Control
					outline.size = node.size

				# Ensure it doesn't block mouse
				outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
				node.add_child(outline)

func clear_peer_selections(peer_id: int):
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene:
		return

	for node in current_scene.find_children("*", "Node", true, false):
		if node.has_meta("team_create_outline_peer"):
			if node.get_meta("team_create_outline_peer") == peer_id:
				node.queue_free()
		elif node.name.begins_with("TeamCreateSelectionOutline_" + str(peer_id)):
			node.queue_free()

func push_current_scene():
	if multiplayer.is_server():
		var editor = network.plugin.get_editor_interface()
		var current_scene = editor.get_edited_scene_root()
		if current_scene:
			var path = current_scene.scene_file_path
			if path != "":
				var bytes = FileAccess.get_file_as_bytes(path)
				if bytes:
					rpc("receive_scene", path, bytes)

func push_current_scene_to_peer(id: int):
	if multiplayer.is_server():
		var editor = network.plugin.get_editor_interface()
		var current_scene = editor.get_edited_scene_root()
		if current_scene:
			var path = current_scene.scene_file_path
			if path != "":
				var bytes = FileAccess.get_file_as_bytes(path)
				if bytes:
					rpc_id(id, "receive_scene", path, bytes)

func _on_node_added(node: Node):
	# Connect for tracking before removal
	if not node.tree_exiting.is_connected(_on_node_tree_exiting.bind(node)):
		node.tree_exiting.connect(_on_node_tree_exiting.bind(node))

	_node_names[node.get_instance_id()] = node.name

	if _ignore_next_structure_event or _is_reloading_scene or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		return

	# Capture owner state before the frame delay.
	# Nodes instantiated from a PackedScene (like during a scene reload or sub-scene drag-and-drop)
	# will already have their owner set. Nodes added manually via the editor GUI will have owner = null.
	var owner_at_add = node.owner

	# Delay execution slightly so properties are set if instantiated via code
	await get_tree().process_frame

	# Ensure the node still exists and has a parent after the frame delay
	if not is_instance_valid(node) or not node.get_parent():
		return

	# Prevent syncing internal nodes like editor UI or auto-generated items
	if node.name.begins_with("@") or node.name.begins_with("TeamCreateSelectionOutline_"):
		return

	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene:
		return

	# Never sync the root scene node itself
	if node == current_scene:
		return

	# Only sync nodes that are part of the edited scene
	if node.owner != current_scene:
		return

	# PREVENT SCENE FLOODING AND EMPTY MESHES:
	# If the node already had an owner when it was added to the tree, it was loaded from a file
	# (e.g., scene reload, sub-scene instantiation). Do NOT broadcast these to other peers as new nodes,
	# because the other peers either already have them (from file sync) or they are internal children of a sub-scene.
	if owner_at_add != null:
		return

	var parent_id = network.assign_unique_id(node.get_parent())
	var type = node.get_class()
	var new_name = node.name
	var new_id = network.assign_unique_id(node)

	_node_names[node.get_instance_id()] = new_name

	var scene_path = current_scene.scene_file_path
	rpc("remote_node_added", parent_id, type, new_name, new_id, scene_path)

	# Immediately sync properties of the new node to catch duplicates
	_sync_all_node_properties(node, new_id)

func _sync_all_node_properties(node: Node, id: String):
	# Create a temporary default instance to compare against
	var type = node.get_class()
	if not ClassDB.can_instantiate(type):
		return

	var default_node = ClassDB.instantiate(type)
	if not default_node:
		return

	var props = node.get_property_list()
	var current_props = {}

	for p in props:
		if p.usage & PROPERTY_USAGE_EDITOR or p.name == "transform" or p.name == "name":
			if p.name == "script" or p.name.begins_with("metadata/"):
				continue

			var val = node.get(p.name)
			var default_val = default_node.get(p.name)

			# Check if the property differs from the default value
			var is_different = false
			if typeof(val) != typeof(default_val):
				is_different = true
			elif typeof(val) == TYPE_OBJECT:
				if val != default_val and val != null:
					is_different = true
			else:
				if val != default_val:
					is_different = true

			if is_different:
				if typeof(val) == TYPE_OBJECT:
					if val is Resource:
						if val.resource_path != "" and not "::" in val.resource_path:
							current_props[p.name] = val.resource_path
						else:
							var bytes = var_to_bytes_with_objects(val)
							current_props[p.name] = {"sub_resource_bytes": bytes}
				else:
					current_props[p.name] = val

	default_node.free()

	if not _last_tracked_properties.has(id):
		_last_tracked_properties[id] = current_props
	else:
		var last_props = _last_tracked_properties[id]
		for prop_name in current_props:
			last_props[prop_name] = current_props[prop_name]

	# Send all non-default properties
	for prop_name in current_props:
		rpc("update_node_property", id, prop_name, current_props[prop_name], _last_scene_path)

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

	if _pre_removal_paths.has(inst_id):
		_pre_removal_paths.erase(inst_id)

	if _node_names.has(inst_id):
		_node_names.erase(inst_id)

	if _ignore_next_structure_event or _is_reloading_scene or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty() or id == "":
		return

	# Delay execution slightly to check if the scene root is also being destroyed
	# (which happens during scene reload/close)
	await get_tree().process_frame

	# If the root node that owned this node is no longer valid, the entire scene was closed or reloaded.
	# We should NOT broadcast individual node removals for a destroyed scene.
	if root_node != null and not is_instance_valid(root_node):
		return

	# Prevent sending removal if the user is just closing/switching scenes.
	if network and network.plugin:
		var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
		if current_scene:
			var active_scene_path = current_scene.scene_file_path
			if scene_path != "" and active_scene_path != scene_path:
				return
		else:
			# If current_scene is null, they are closing the last scene tab.
			return

	rpc("remote_node_removed", id, scene_path)

func _on_node_renamed(node: Node):
	if _ignore_next_structure_event or _is_reloading_scene or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		return

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
			rpc("remote_node_renamed_exact", parent_id, old_name, new_name, scene_path)

@rpc("any_peer", "reliable")
func remote_node_added(parent_id: String, type: String, new_name: String, new_id: String, scene_path: String = ""):
	_ignore_next_structure_event = true
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		if scene_path != "" and current_scene.scene_file_path != scene_path:
			_ignore_next_structure_event = false
			return
		var parent = network.get_node_by_unique_id(current_scene, parent_id)
		if parent:
			# Prevent duplicates. If the exact node name already exists under the parent,
			# DO NOT instantiate a new one. This fundamentally prevents exponential rejoin floods.
			if not parent.has_node(new_name):
				var new_node = ClassDB.instantiate(type) as Node
				if new_node:
					new_node.name = new_name
					parent.add_child(new_node)
					new_node.owner = current_scene # Important for saving in scene
					_node_names[new_node.get_instance_id()] = new_name
	_ignore_next_structure_event = false

@rpc("any_peer", "reliable")
func remote_node_removed(id: String, scene_path: String = ""):
	_ignore_next_structure_event = true
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		if scene_path != "" and current_scene.scene_file_path != scene_path:
			_ignore_next_structure_event = false
			return
		var node = network.get_node_by_unique_id(current_scene, id)
		if node and node != current_scene:
			_node_names.erase(node.get_instance_id())
			node.get_parent().remove_child(node)
			node.queue_free()
	_ignore_next_structure_event = false

@rpc("any_peer", "reliable")
func remote_node_renamed(new_id: String, new_name: String):
	# Kept for compatibility but superseded by remote_node_renamed_exact
	pass

@rpc("any_peer", "reliable")
func remote_node_renamed_exact(parent_id: String, old_name: String, new_name: String, scene_path: String = ""):
	_ignore_next_structure_event = true
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		if scene_path != "" and current_scene.scene_file_path != scene_path:
			_ignore_next_structure_event = false
			return
		var parent = network.get_node_by_unique_id(current_scene, parent_id)
		if parent:
			var node = parent.get_node_or_null(old_name)
			if node:
				node.name = new_name
				_node_names[node.get_instance_id()] = new_name
	_ignore_next_structure_event = false

@rpc("any_peer", "reliable")
func update_node_property(id: String, prop_name: String, value: Variant, scene_path: String = ""):
	# Block scripts and metadata updates for security
	if prop_name == "script" or prop_name.begins_with("metadata/"):
		printerr("Team Create: Blocked unsafe property sync: ", prop_name)
		return
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		if scene_path != "" and current_scene.scene_file_path != scene_path:
			return
		var node = network.get_node_by_unique_id(current_scene, id)
		if node:
			if typeof(value) == TYPE_STRING and (value as String).begins_with("res://"):
				# Validate path to prevent directory traversal
				if ".." in (value as String):
					printerr("Team Create: Invalid resource path received: ", value)
					return

				# It's a resource path
				if ResourceLoader.exists(value):
					var res = load(value)
					if res:
						node.set(prop_name, res)
				else:
					# Push to pending queue waiting for file sync to complete
					_pending_resource_properties.append({"id": id, "prop_name": prop_name, "value": value, "scene_path": scene_path, "retries": 100}) # About 1-2 seconds at 60 FPS
			elif typeof(value) == TYPE_DICTIONARY and value.has("sub_resource_bytes"):
				var res = bytes_to_var_with_objects(value["sub_resource_bytes"])
				if res is Resource:
					node.set(prop_name, res)
			else:
				node.set(prop_name, value)

			if not _last_tracked_properties.has(id):
				_last_tracked_properties[id] = {}
			_last_tracked_properties[id][prop_name] = value

@rpc("any_peer", "reliable")
func receive_scene(path: String, bytes: PackedByteArray):
	# Validate path to prevent directory traversal
	if path.begins_with("res://addons/team_create") or path.begins_with("res://.godot"):
		printerr("Team Create: Unauthorized scene access: ", path)
		return
	if not path.begins_with("res://") or ".." in path:
		printerr("Invalid scene path received: ", path)
		return

	if network and network.plugin:
		var editor = network.plugin.get_editor_interface()
		var current_scene = editor.get_edited_scene_root()
		var open_scenes = editor.get_open_scenes()

		var is_active = false
		if current_scene and current_scene.scene_file_path == path:
			is_active = true

		if is_active:
			# 1. Skip writing to disk so Godot does not auto-reload
			print("Team Create: Ignored saving active scene to disk to prevent auto-reload flood.")
			_is_reloading_scene = true
			_force_full_sync_next_frame = true

			get_tree().create_timer(0.5).timeout.connect(func():
				_is_reloading_scene = false
			)
			return
		elif path in open_scenes:
			# 2. Scene is open in tabs but not active ("closed" in the context of currently viewing)
			# Switch to the tab, close it, and switch back
			var prev_path = current_scene.scene_file_path if current_scene else ""
			editor.open_scene_from_path(path)
			editor.close_scene()

			if prev_path != "":
				editor.open_scene_from_path(prev_path)

			print("Team Create: Closed updated background scene tab: ", path)

	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		print("Received scene: ", path)
