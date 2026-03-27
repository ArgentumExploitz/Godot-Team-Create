import re

with open('addons/team_create/scene_sync.gd', 'r') as f:
    content = f.read()

send_prop_old = """func _send_update_node_property(id: String, prop_name: String, value: Variant, scene_path: String = ""):
	if typeof(value) == TYPE_DICTIONARY and value.has("sub_resource_bytes"):
		var bytes = value["sub_resource_bytes"] as PackedByteArray
		var chunk_size = 60000
		var total_size = bytes.size()
		var offset = 0

		if total_size == 0:
			rpc("update_node_property_chunked", id, prop_name, bytes, scene_path, true)
			return

		while offset < total_size:
			var end_idx = min(offset + chunk_size, total_size)
			var chunk = bytes.slice(offset, end_idx)
			var is_final = (end_idx == total_size)
			rpc("update_node_property_chunked", id, prop_name, chunk, scene_path, is_final)
			offset += chunk_size
	else:
		rpc("update_node_property", id, prop_name, value, scene_path)

@rpc("any_peer", "reliable")
func update_node_property_chunked(id: String, prop_name: String, chunk: PackedByteArray, scene_path: String = "", is_final: bool = true):
	var sender_id = multiplayer.get_remote_sender_id()
	var prop_key = str(sender_id) + "_" + id + "_" + prop_name

	if not _receiving_properties.has(prop_key):
		_receiving_properties[prop_key] = PackedByteArray()

	_receiving_properties[prop_key].append_array(chunk)

	if is_final:
		var full_bytes = _receiving_properties[prop_key]
		_receiving_properties.erase(prop_key)
		# Forward the reassembled value to the main property handler
		update_node_property(id, prop_name, {"sub_resource_bytes": full_bytes}, scene_path)"""


send_prop_new = """func _send_update_node_property(id: String, prop_name: String, value: Variant, scene_path: String = ""):
	var needs_chunking = false
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
			needs_chunking = true

	if needs_chunking:
		var chunk_size = 60000
		var total_size = bytes.size()
		var offset = 0

		if total_size == 0:
			rpc("update_node_property_chunked", id, prop_name, bytes, scene_path, is_sub_resource, true)
			return

		while offset < total_size:
			var end_idx = min(offset + chunk_size, total_size)
			var chunk = bytes.slice(offset, end_idx)
			var is_final = (end_idx == total_size)
			rpc("update_node_property_chunked", id, prop_name, chunk, scene_path, is_sub_resource, is_final)
			offset += chunk_size
	else:
		rpc("update_node_property", id, prop_name, value, scene_path)

@rpc("any_peer", "reliable")
func update_node_property_chunked(id: String, prop_name: String, chunk: PackedByteArray, scene_path: String = "", is_sub_resource: bool = false, is_final: bool = true):
	var sender_id = multiplayer.get_remote_sender_id()
	var prop_key = str(sender_id) + "_" + id + "_" + prop_name

	if not _receiving_properties.has(prop_key):
		_receiving_properties[prop_key] = PackedByteArray()

	_receiving_properties[prop_key].append_array(chunk)

	if is_final:
		var full_bytes = _receiving_properties[prop_key]
		_receiving_properties.erase(prop_key)

		var reassembled_value
		if is_sub_resource:
			reassembled_value = {"sub_resource_bytes": full_bytes}
		else:
			reassembled_value = bytes_to_var_with_objects(full_bytes)

		# Forward the reassembled value to the main property handler
		update_node_property(id, prop_name, reassembled_value, scene_path)"""

content = content.replace(send_prop_old, send_prop_new)

with open('addons/team_create/scene_sync.gd', 'w') as f:
    f.write(content)
