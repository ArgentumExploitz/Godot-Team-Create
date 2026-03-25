@tool
extends Node

var network: Node
var _is_syncing_files = false

func _ready():
	call_deferred("_setup_fs_signals")

func _setup_fs_signals():
	if network and network.plugin:
		var efs = network.plugin.get_editor_interface().get_resource_filesystem()
		if efs:
			if not efs.filesystem_changed.is_connected(_on_filesystem_changed):
				efs.filesystem_changed.connect(_on_filesystem_changed)

func _on_filesystem_changed():
	if _is_syncing_files or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		return

	# Automatically sync files whenever Godot detects a local file system change.
	sync_all_files()

func sync_project_settings():
	if multiplayer.is_server():
		var bytes = FileAccess.get_file_as_bytes("res://project.godot")
		if bytes:
			rpc("receive_project_settings", bytes)

func sync_all_files():
	if multiplayer.is_server():
		_is_syncing_files = true
		var all_files = get_all_files("res://")
		var file_hashes = {}
		for path in all_files:
			if path.begins_with("res://addons/team_create"):
				continue
			if FileAccess.file_exists(path):
				file_hashes[path] = FileAccess.get_md5(path)
		rpc("compare_and_sync_files", file_hashes)
		_is_syncing_files = false

func sync_all_files_to_peer(id: int):
	if multiplayer.is_server():
		var all_files = get_all_files("res://")
		var file_hashes = {}
		for path in all_files:
			if path.begins_with("res://addons/team_create"):
				continue
			if FileAccess.file_exists(path):
				file_hashes[path] = FileAccess.get_md5(path)
		rpc_id(id, "compare_and_sync_files", file_hashes)

func get_all_files(dir_path: String, exclude_dirs: Array = ["res://.godot"]) -> Array:
	var files = []
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and not file_name.begins_with("."):
				var sub_dir = dir_path.path_join(file_name)
				if not exclude_dirs.has(sub_dir):
					files.append_array(get_all_files(sub_dir, exclude_dirs))
			elif not dir.current_is_dir() and not file_name.begins_with("."):
				# Convert local .tmp files to real assets instantly, as requested.
				var full_path = dir_path.path_join(file_name)
				if file_name.ends_with(".tmp"):
					# Strip the .tmp extension to get the original desired filename
					# (e.g. script.gd.tmp -> script.gd, not script.gd.res)
					var real_path = full_path.trim_suffix(".tmp")

					# Only override if it looks like Godot was trying to create an entirely new temporary resource
					# rather than overwriting an existing script or asset
					if not real_path.get_extension() in ["gd", "cs", "tscn", "scn", "png", "jpg", "wav", "ogg"]:
						if not real_path.ends_with(".res") and not real_path.ends_with(".tres"):
							real_path += ".res"

					DirAccess.rename_absolute(full_path, real_path)
					files.append(real_path)
					print("Converted temporary file to real asset: ", real_path)
					# Trigger editor refresh
					if network and network.plugin:
						network.plugin.get_editor_interface().get_resource_filesystem().scan()
				else:
					files.append(full_path)
			file_name = dir.get_next()
	return files

@rpc("any_peer", "reliable")
func receive_project_settings(bytes: PackedByteArray):
	var file = FileAccess.open("res://project.godot", FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		print("Project settings updated.")

@rpc("any_peer", "reliable")
func compare_and_sync_files(server_hashes: Dictionary):
	_is_syncing_files = true
	# Only clients should execute this from server
	var local_files = get_all_files("res://")
	var local_hashes = {}

	for path in local_files:
		if path.begins_with("res://addons/team_create"):
			continue
		if FileAccess.file_exists(path):
			local_hashes[path] = FileAccess.get_md5(path)

	# Find files to delete
	for path in local_hashes:
		if not server_hashes.has(path):
			DirAccess.remove_absolute(path)
			print("Deleted unused file: ", path)

	# Request differing files
	for path in server_hashes:
		if not local_hashes.has(path) or local_hashes[path] != server_hashes[path]:
			rpc_id(1, "request_file", path)
	_is_syncing_files = false

@rpc("any_peer", "reliable")
func request_file(path: String):
	# Validate path to prevent directory traversal / arbitrary file read
	if not path.begins_with("res://") or ".." in path:
		printerr("Invalid file path requested: ", path)
		return

	# Send file back
	var bytes = FileAccess.get_file_as_bytes(path)
	if bytes:
		rpc_id(multiplayer.get_remote_sender_id(), "receive_file", path, bytes)

@rpc("any_peer", "reliable")
func receive_file(path: String, bytes: PackedByteArray):
	# Validate path to prevent directory traversal
	if not path.begins_with("res://") or ".." in path:
		printerr("Invalid file path received: ", path)
		return

	# Convert temporary files based on origin
	if path.ends_with(".tmp"):
		var real_path = path.trim_suffix(".tmp")
		if not real_path.get_extension() in ["gd", "cs", "tscn", "scn", "png", "jpg", "wav", "ogg"]:
			if not real_path.ends_with(".res") and not real_path.ends_with(".tres"):
				real_path += ".res"
		path = real_path

	# Ensure directory exists before writing
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		print("Received file: ", path)

		# If the file being received is the currently edited scene, the editor will auto-reload it.
		# Pause structure syncing to prevent massive node-removal/addition floods across the network.
		if network and network.scene_sync and network.plugin:
			var current_scene = network.plugin.get_editor_interface().get_edited_scene_root()
			if current_scene and current_scene.scene_file_path == path:
				network.scene_sync._is_reloading_scene = true

				# Wait for Godot to complete the asynchronous scene reload
				get_tree().create_timer(1.5).timeout.connect(func():
					if is_instance_valid(network) and network.scene_sync:
						network.scene_sync._is_reloading_scene = false
						network.scene_sync._last_tracked_properties.clear()
				)

		# Trigger Editor resource scan if it's an asset
		if network.plugin and network.plugin.get_editor_interface().get_resource_filesystem():
			network.plugin.get_editor_interface().get_resource_filesystem().scan()
