@tool
extends Node

var network: Node
var _is_syncing_files = false
var _scan_timer: SceneTreeTimer
var _pending_files_to_receive = 0
signal sync_completed

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
func compare_and_sync_files(peer_hashes: Dictionary):
	_is_syncing_files = true
	var sender_id = multiplayer.get_remote_sender_id()
	var local_files = get_all_files("res://")
	var local_hashes = {}

	for path in local_files:
		if path.begins_with("res://addons/team_create"):
			continue
		if FileAccess.file_exists(path):
			local_hashes[path] = FileAccess.get_md5(path)

	# Find files to delete (only allow the server to delete files to prevent clients wiping the server)
	if sender_id == 1:
		for path in local_hashes:
			if not peer_hashes.has(path):
				DirAccess.remove_absolute(path)
				print("Deleted unused file: ", path)

	# Request differing files
	var files_to_request = []
	for path in peer_hashes:
		if not local_hashes.has(path) or local_hashes[path] != peer_hashes[path]:
			files_to_request.append(path)

	# Sort requests so scenes are requested LAST to ensure assets are downloaded first
	files_to_request.sort_custom(func(a, b):
		var a_is_scene = a.ends_with(".tscn") or a.ends_with(".scn")
		var b_is_scene = b.ends_with(".tscn") or b.ends_with(".scn")
		if a_is_scene and not b_is_scene:
			return false
		if b_is_scene and not a_is_scene:
			return true
		return a < b
	)

	_pending_files_to_receive = files_to_request.size()

	for path in files_to_request:
		rpc_id(sender_id, "request_file", path)

	if _pending_files_to_receive == 0:
		sync_completed.emit()

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

		# Trigger Editor resource scan if it's an asset, debounced to prevent premature imports generating new UIDs
		if network.plugin and network.plugin.get_editor_interface().get_resource_filesystem():
			if _scan_timer == null:
				_scan_timer = get_tree().create_timer(0.5)
				_scan_timer.timeout.connect(func():
					_scan_timer = null
					if network and network.plugin and network.plugin.get_editor_interface().get_resource_filesystem():
						network.plugin.get_editor_interface().get_resource_filesystem().scan()
				)

		if _pending_files_to_receive > 0:
			_pending_files_to_receive -= 1
			if _pending_files_to_receive <= 0:
				sync_completed.emit()
