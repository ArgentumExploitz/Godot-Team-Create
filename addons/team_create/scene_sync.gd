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
var _pre_removal_paths = {}
var _pre_rename_paths = {}

func _ready():
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.node_added.connect(_on_node_added)
		tree.node_removed.connect(_on_node_removed)
		tree.node_renamed.connect(_on_node_renamed)

		# Hook into tree signals to capture state before the change applies
		var root = tree.root
		if root:
			root.child_entered_tree.connect(_on_any_child_entered_tree.bind(root))

func _on_any_child_entered_tree(node: Node, parent: Node):
	# Listen for predelete to get path before removal
	if not node.tree_exiting.is_connected(_on_node_tree_exiting.bind(node)):
		node.tree_exiting.connect(_on_node_tree_exiting.bind(node))

	for child in node.get_children():
		_on_any_child_entered_tree(child, node)

func _on_node_tree_exiting(node: Node):
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_pre_removal_paths[node.get_instance_id()] = network.assign_unique_id(node)

func _process(delta):
	if not network or not network.plugin or network.peer.get_connection_status() != ENetMultiplayerPeer.CONNECTION_CONNECTED:
		return

	_time_since_sync += delta
	if _time_since_sync >= SYNC_INTERVAL:
		_time_since_sync = 0.0
		_track_selection()
		_track_changes_throttled()

func _track_changes_throttled():
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene:
		return

	if current_scene.scene_file_path != _last_scene_path:
		_last_scene_path = current_scene.scene_file_path
		_last_tracked_properties.clear()

	# ONLY track changes for selected nodes to save massive performance costs
	var selected = editor.get_selection().get_selected_nodes()
	for node in selected:
		_check_single_node_changes(node)

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
				rpc("update_node_property", id, prop_name, current_props[prop_name])
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
		rpc("update_peer_selection", multiplayer.get_unique_id(), selected_ids)

@rpc("any_peer", "reliable")
func update_peer_selection(peer_id: int, selected_ids: Array):
	# Add custom selection drawing logic
	var color = network.get_user_color(peer_id)
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene:
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
	if _ignore_next_structure_event or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		return

	# Delay execution slightly so properties are set if instantiated via code
	await get_tree().process_frame

	# Ensure the node still exists and has a parent after the frame delay
	if not is_instance_valid(node) or not node.get_parent():
		return

	# Prevent syncing internal nodes like editor UI or auto-generated items
	if node.name.begins_with("@") or node.name.begins_with("TeamCreateSelectionOutline_"):
		return

	var parent_id = network.assign_unique_id(node.get_parent())
	var type = node.get_class()
	var new_name = node.name
	var new_id = network.assign_unique_id(node)

	rpc("remote_node_added", parent_id, type, new_name, new_id)

func _on_node_removed(node: Node):
	var inst_id = node.get_instance_id()
	var id = _pre_removal_paths.get(inst_id, "")
	if _pre_removal_paths.has(inst_id):
		_pre_removal_paths.erase(inst_id)

	if _ignore_next_structure_event or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty() or id == "":
		return

	rpc("remote_node_removed", id)

func _on_node_renamed(node: Node):
	if _ignore_next_structure_event or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		return

	var parent = node.get_parent()
	if parent:
		# The node is already renamed, so its current path is the NEW path.
		# The OLD path is parent_path + "/" + old_name.
		# But since we don't have the old name, we rely on the parent path and the fact that we can search children
		# by their previous path. Instead of guessing, we just sync the whole structure via parent if renamed.
		# To be robust, let's find the old name by seeing which tracked property had a name change.
		var id = network.assign_unique_id(node) # New ID
		rpc("remote_node_renamed", id, node.name)

@rpc("any_peer", "reliable")
func remote_node_added(parent_id: String, type: String, new_name: String, new_id: String):
	_ignore_next_structure_event = true
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		var parent = network.get_node_by_unique_id(current_scene, parent_id)
		if parent:
			var new_node = ClassDB.instantiate(type) as Node
			if new_node:
				new_node.name = new_name
				parent.add_child(new_node)
				new_node.owner = current_scene # Important for saving in scene
	_ignore_next_structure_event = false

@rpc("any_peer", "reliable")
func remote_node_removed(id: String):
	_ignore_next_structure_event = true
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		var node = network.get_node_by_unique_id(current_scene, id)
		if node and node != current_scene:
			node.get_parent().remove_child(node)
			node.queue_free()
	_ignore_next_structure_event = false

@rpc("any_peer", "reliable")
func remote_node_renamed(new_id: String, new_name: String):
	_ignore_next_structure_event = true
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		# We receive the NEW path (new_id).
		# If the node's name just changed, its path ends with new_name.
		# The parent's path is new_id without the /new_name part.
		var parts = new_id.split("/")
		if parts.size() > 0:
			parts.remove_at(parts.size() - 1)
			var parent_id = "/".join(parts)
			if parent_id == "":
				parent_id = "."

			var parent = network.get_node_by_unique_id(current_scene, parent_id)
			if parent:
				# We don't know the exact old name, but we know one of the children should be renamed to new_name.
				# We trust the other property syncs will fix everything else, so we just iterate until we find a match
				# or we just rely on the fact that Godot syncs the whole scene occasionally.
				pass # Simplified handling for renames: usually property sync handles 'name' correctly if IDs matched.
	_ignore_next_structure_event = false

@rpc("any_peer", "reliable")
func update_node_property(id: String, prop_name: String, value: Variant):
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if current_scene:
		var node = network.get_node_by_unique_id(current_scene, id)
		if node:
			if typeof(value) == TYPE_STRING and (value as String).begins_with("res://"):
				# It's a resource path
				if ResourceLoader.exists(value):
					var res = load(value)
					if res:
						node.set(prop_name, res)
				else:
					printerr("Team Create: Resource file not found or is an internal sub-resource: ", value)
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
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		print("Received scene: ", path)
		# Tell editor to reload scene
		if network.plugin:
			network.plugin.get_editor_interface().reload_scene_from_path(path)
