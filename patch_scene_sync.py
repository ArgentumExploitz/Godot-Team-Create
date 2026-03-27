import re

with open("addons/team_create/scene_sync.gd", "r") as f:
    content = f.read()

# Fix 1: scene_sync.gd -> receive_scene and receive_scene_state bytes.size() > 0 checks

# receive_scene active reload block
old_recv_scene_active = """			var file = FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_buffer(bytes)
				file.close()
			_is_reloading_scene = true"""

new_recv_scene_active = """			if bytes.size() > 0:
				var file = FileAccess.open(path, FileAccess.WRITE)
				if file:
					file.store_buffer(bytes)
					file.close()
			_is_reloading_scene = true"""
content = content.replace(old_recv_scene_active, new_recv_scene_active)

# receive_scene normal block
old_recv_scene_normal = """	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		print("Received scene: ", path)"""

new_recv_scene_normal = """	if bytes.size() > 0:
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
			file.close()
			print("Received scene: ", path)"""
content = content.replace(old_recv_scene_normal, new_recv_scene_normal)

# receive_scene_state
old_recv_scene_state = """	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		print("Team Create: Received up-to-date scene state for ", path)"""

new_recv_scene_state = """	if bytes.size() > 0:
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
			file.close()
			print("Team Create: Received up-to-date scene state for ", path)"""
content = content.replace(old_recv_scene_state, new_recv_scene_state)


# Fix 2 & 3: Selection box clearing
old_update_selection = """@rpc("any_peer", "reliable")
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
	var tree = current_scene.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
			if is_instance_valid(node):
				node.queue_free()

	# Add new indicators
	for id in selected_ids:"""

new_update_selection = """@rpc("any_peer", "reliable")
func update_peer_selection(peer_id: int, selected_ids: Array, scene_path: String = ""):
	# Add custom selection drawing logic
	var color = network.get_user_color(peer_id)
	var editor = network.plugin.get_editor_interface()
	var current_scene = editor.get_edited_scene_root()
	if not current_scene:
		return

	# Clear previous indicators globally for this peer in the current scene
	var tree = current_scene.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
			if is_instance_valid(node):
				node.queue_free()

	# If the peer is selecting nodes in a different scene, we don't draw new indicators here.
	if scene_path != "" and current_scene.scene_file_path != scene_path:
		return

	# Add new indicators
	for id in selected_ids:"""
content = content.replace(old_update_selection, new_update_selection)


# Fix 4: Resource path inside nodes (in `_check_single_node_changes` and `_sync_all_node_properties` and `update_node_property`)

# In `_check_single_node_changes`:
old_subres_1 = """						# Serialize local sub-resources or resources without a file path
						var bytes = var_to_bytes_with_objects(val)
						current_props[p.name] = {"sub_resource_bytes": bytes}"""
new_subres_1 = """						# Serialize local sub-resources or resources without a file path
						var bytes = var_to_bytes_with_objects(val)
						current_props[p.name] = {"sub_resource_bytes": bytes, "resource_path": val.resource_path}"""
content = content.replace(old_subres_1, new_subres_1)

# In `_sync_all_node_properties`:
old_subres_2 = """							var bytes = var_to_bytes_with_objects(val)
							current_props[p.name] = {"sub_resource_bytes": bytes}"""
new_subres_2 = """							var bytes = var_to_bytes_with_objects(val)
							current_props[p.name] = {"sub_resource_bytes": bytes, "resource_path": val.resource_path}"""
content = content.replace(old_subres_2, new_subres_2)

# In `_send_update_node_property`, we must pass "resource_path" through `update_node_property_chunked`
# But `update_node_property_chunked` signature is:
# func update_node_property_chunked(id: String, prop_name: String, chunk: PackedByteArray, scene_path: String = "", is_sub_resource: bool = false, is_final: bool = true):
# Wait, `update_node_property_chunked` reconstructs `reassembled_value = {"sub_resource_bytes": full_bytes}`. We need to preserve `resource_path`.
# Let's change `_send_update_node_property` to serialize the entire dictionary if it's a sub-resource.
# Actually, if we look at `_send_update_node_property`:

old_send_update = """	var needs_chunking = false
	var bytes = PackedByteArray()
	var is_sub_resource = false

	if typeof(value) == TYPE_DICTIONARY and value.has("sub_resource_bytes"):
		needs_chunking = true
		bytes = value["sub_resource_bytes"] as PackedByteArray
		is_sub_resource = true
	else:
		# Serialize any other property to see if it's too big
		bytes = var_to_bytes_with_objects(value)
		if bytes.size() > 60000:
			needs_chunking = true"""

new_send_update = """	var needs_chunking = false
	var bytes = PackedByteArray()

	# Serialize the entire value (whether dict or scalar) to bytes
	bytes = var_to_bytes_with_objects(value)
	if bytes.size() > 60000:
		needs_chunking = true"""

# Wait, `update_node_property_chunked` logic currently relies on `is_sub_resource` to wrap the reassembled bytes back into `{"sub_resource_bytes": full_bytes}`.
# BUT if we just serialize the whole `value` (which is already `{"sub_resource_bytes": bytes, "resource_path": path}`), we can just deserialize it back directly!
# Let's fix `_send_update_node_property` completely so we don't need `is_sub_resource` hack.
"""
pass
"""

with open("addons/team_create/scene_sync.gd", "w") as f:
    f.write(content)
