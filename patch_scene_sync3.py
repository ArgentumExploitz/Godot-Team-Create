import re

with open("addons/team_create/scene_sync.gd", "r") as f:
    content = f.read()

old = """@rpc("any_peer", "reliable")
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
				var is_downloading = network and network.file_sync and value in network.file_sync.downloading_files
				if not is_downloading and ResourceLoader.exists(value):
					var res = load(value)
					if res:
						node.set(prop_name, res)
				else:
					# Push to pending queue waiting for file sync to complete
					_pending_resource_properties.append({"id": id, "prop_name": prop_name, "value": value, "scene_path": scene_path, "retries": 100}) # About 1-2 seconds at 60 FPS
			elif typeof(value) == TYPE_DICTIONARY and value.has("sub_resource_bytes"):
				var res = bytes_to_var_with_objects(value["sub_resource_bytes"])
				if res is Resource:
					if value.has("resource_path") and value["resource_path"] != "":
						res.take_over_path(value["resource_path"])
					node.set(prop_name, res)
			else:
				node.set(prop_name, value)

			if not _last_tracked_properties.has(id):
				_last_tracked_properties[id] = {}
			_last_tracked_properties[id][prop_name] = value"""

new = """@rpc("any_peer", "reliable")
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
				var is_downloading = network and network.file_sync and value in network.file_sync.downloading_files
				if not is_downloading and ResourceLoader.exists(value):
					var res = load(value)
					if res:
						node.set(prop_name, res)
				else:
					# Push to pending queue waiting for file sync to complete
					_pending_resource_properties.append({"id": id, "prop_name": prop_name, "value": value, "scene_path": scene_path, "retries": 100}) # About 1-2 seconds at 60 FPS
			elif typeof(value) == TYPE_DICTIONARY and value.has("sub_resource_bytes"):
				var res = bytes_to_var_with_objects(value["sub_resource_bytes"])
				if res is Resource:
					if value.has("resource_path") and value["resource_path"] != "":
						res.take_over_path(value["resource_path"])
					node.set(prop_name, res)
			else:
				node.set(prop_name, value)

			if not _last_tracked_properties.has(id):
				_last_tracked_properties[id] = {}
			_last_tracked_properties[id][prop_name] = value"""

with open("addons/team_create/scene_sync.gd", "w") as f:
    f.write(content.replace(old, new))
