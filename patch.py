import re

with open('addons/team_create/scene_sync.gd', 'r') as f:
    content = f.read()

# Find the start of _on_node_removed
start_idx = content.find('func _on_node_removed(node: Node):')
end_idx = content.find('func _on_node_renamed(node: Node):', start_idx)

func_body = content[start_idx:end_idx]

# Replace the part before await to cache the properties and parent path
replacement = """func _on_node_removed(node: Node):
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

"""

new_content = content.replace(func_body, replacement)

with open('addons/team_create/scene_sync.gd', 'w') as f:
    f.write(new_content)
