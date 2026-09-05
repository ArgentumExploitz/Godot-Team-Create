@tool
extends Node

var _file_write_mutex = Mutex.new()

const SUPPORTED_EXTENSIONS = {
	"gd": true, "cs": true, "tscn": true, "scn": true,
	"png": true, "jpg": true, "jpeg": true, "webp": true, "svg": true, "bmp": true,
	"wav": true, "ogg": true, "mp3": true,
	"tres": true, "res": true, "material": true, "import": true,
	"json": true, "txt": true, "blend": true, "glb": true, "gltf": true
}

var network: Node
var _is_syncing_files = false
var _scan_timer = null

var _http_server: TCPServer
var _http_clients: Array = []
var _http_buffers: Dictionary = {}
var _http_responses: Dictionary = {}

func _get_editor_interface():
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface")
	if network and network.plugin and network.plugin.has_method("get_editor_interface"):
		return network.plugin.get_editor_interface()
	return null

func _process(delta):
	if _http_server and _http_server.is_listening():
		if _http_server.is_connection_available():
			var peer = _http_server.take_connection()
			_http_clients.append(peer)
			_http_buffers[peer] = PackedByteArray()
			_http_responses[peer] = { "data": PackedByteArray(), "sent": 0, "active": false, "timer": 0.0 }

		for i in range(_http_clients.size() - 1, -1, -1):
			var peer: StreamPeerTCP = _http_clients[i]
			peer.poll()
			var status = peer.get_status()

			if status == StreamPeerTCP.STATUS_CONNECTED:
				var resp = _http_responses[peer]
				resp["timer"] += delta

				# Timeout idle connections (10 seconds)
				if resp["timer"] > 10.0:
					peer.disconnect_from_host()
					_http_clients.remove_at(i)
					_http_buffers.erase(peer)
					_http_responses.erase(peer)
					continue

				if not resp["active"]:
					if peer.get_available_bytes() > 0:
						var bytes = peer.get_data(peer.get_available_bytes())
						if bytes[0] == OK:
							_http_buffers[peer].append_array(bytes[1])
							var buffer_bytes = _http_buffers[peer]
							var header_end_idx = -1
							var header_len = 4

							# Find sequence manually
							for k in range(buffer_bytes.size() - 3):
								if buffer_bytes[k] == 13 and buffer_bytes[k+1] == 10 and buffer_bytes[k+2] == 13 and buffer_bytes[k+3] == 10:
									header_end_idx = k
									break

							if header_end_idx == -1:
								for k in range(buffer_bytes.size() - 1):
									if buffer_bytes[k] == 10 and buffer_bytes[k+1] == 10:
										header_end_idx = k
										header_len = 2
										break

							var req_str = ""
							if header_end_idx != -1:
								req_str = buffer_bytes.slice(0, header_end_idx).get_string_from_utf8()

								if req_str.begins_with("GET "):
									var lines_arr = req_str.split("\n")
									if lines_arr.size() > 0:
										var parts = lines_arr[0].split(" ")
										if parts.size() > 1:
											var path = parts[1]
											path = path.uri_decode()
											if path.begins_with("/res/"):
												path = "res://" + path.substr(5)

											if _is_safe_path(path) and FileAccess.file_exists(path):
												var file_bytes = FileAccess.get_file_as_bytes(path)
												var response_headers = "HTTP/1.1 200 OK\r\nContent-Length: " + str(file_bytes.size()) + "\r\nConnection: close\r\n\r\n"
												resp["data"].append_array(response_headers.to_utf8_buffer())
												resp["data"].append_array(file_bytes)
												resp["active"] = true
											else:
												var response_headers = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
												resp["data"].append_array(response_headers.to_utf8_buffer())
												resp["active"] = true
								elif req_str.begins_with("POST "):
									var lines_arr = req_str.split("\n")
									if lines_arr.size() > 0:
										var parts = lines_arr[0].split(" ")
										if parts.size() > 1:
											var path = parts[1]
											path = path.uri_decode()
											if path.begins_with("/res/"):
												path = "res://" + path.substr(5)

											if _is_safe_path(path):
												var content_length = 0
												for req_line in lines_arr:
													var lower_line = req_line.to_lower()
													if lower_line.begins_with("content-length:"):
														content_length = lower_line.split(":")[1].strip_edges().to_int()
														break

												if buffer_bytes.size() >= header_end_idx + header_len + content_length:
													var body_bytes = buffer_bytes.slice(header_end_idx + header_len, header_end_idx + header_len + content_length)

													# receive_file will handle dir creation and writing
													receive_file(path, randi(), body_bytes, true)

													var response_headers = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
													resp["data"].append_array(response_headers.to_utf8_buffer())
													resp["active"] = true

							if not resp["active"]:
								if header_end_idx == -1:
									var check_len = min(buffer_bytes.size(), 2048)
									req_str = buffer_bytes.slice(0, check_len).get_string_from_ascii()

								# Check if it's a POST waiting for more body data
								if req_str.begins_with("POST "):
									continue
								peer.disconnect_from_host()
								_http_clients.remove_at(i)
								_http_buffers.erase(peer)
								_http_responses.erase(peer)
				else:
					# Active response, send in chunks asynchronously
					var to_send = resp["data"].size() - resp["sent"]
					if to_send > 0:
						var chunk = resp["data"].slice(resp["sent"], resp["sent"] + min(to_send, 65536))
						var sent_arr = peer.put_partial_data(chunk)
						if sent_arr[0] == OK:
							resp["sent"] += sent_arr[1]
							resp["timer"] = 0.0 # Reset timeout on activity
						elif sent_arr[0] != ERR_BUSY:
							# Error
							peer.disconnect_from_host()
							_http_clients.remove_at(i)
							_http_buffers.erase(peer)
							_http_responses.erase(peer)
					else:
						# Done
						peer.disconnect_from_host()
						_http_clients.remove_at(i)
						_http_buffers.erase(peer)
						_http_responses.erase(peer)

			elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
				_http_clients.remove_at(i)
				_http_buffers.erase(peer)
				_http_responses.erase(peer)

func _setup_http_server():
	if network and network.get("is_standalone_server"):
		_http_server = TCPServer.new()
		var base_port = network.PORT if (network and "PORT" in network) else (network.get("PORT") if network and network.get("PORT") != null else 12345)
		var port = base_port + 1
		var err = _http_server.listen(port)
		if err == OK:
			network.tc_print("HTTP File Server listening on port " + str(port))
		else:
			network.tc_print("Failed to start HTTP File Server on port " + str(port))



func _get_cached_md5(path: String) -> String:
	var mod_time = FileAccess.get_modified_time(path)
	if _file_hash_cache.has(path):
		var cached = _file_hash_cache[path]
		if cached["time"] == mod_time:
			return cached["md5"]

	var md5 = FileAccess.get_md5(path)
	_file_hash_cache[path] = {"time": mod_time, "md5": md5}
	return md5

func _is_safe_path(p: String) -> bool:
	var decoded = p.replace("%2e", ".").replace("%2E", ".")
	decoded = decoded.replace("%2f", "/").replace("%2F", "/")
	decoded = decoded.replace("%5c", "\\").replace("%5C", "\\")
	decoded = decoded.uri_decode()
	decoded = decoded.replace("\\", "/")

	if not decoded.begins_with("res://"):
		return false

	var base_res = ProjectSettings.globalize_path("res://").simplify_path()
	if not base_res.ends_with("/"):
		base_res += "/"

	var target = ProjectSettings.globalize_path(decoded).simplify_path()

	if not target.begins_with(base_res):
		return false

	var rel_path = "res://" + target.trim_prefix(base_res)

	var blocked_dirs = ["addons/team_create", ".team_create", ".godot"]
	for d in blocked_dirs:
		if rel_path == "res://" + d or rel_path.begins_with("res://" + d + "/"):
			return false

	if rel_path == "res://project.godot":
		return false

	return true

var _pending_files_to_receive = 0
var downloading_files: Array = []
var _sync_blocker: ColorRect
var _receiving_files: Dictionary = {}
var _known_files: Array = []
var _file_hash_cache: Dictionary = {}
signal sync_completed
var auto_backups_enabled = false
signal asset_imported(path: String)

func backup_scene(path: String, is_manual: bool = false) -> String:
	if not is_manual and not auto_backups_enabled:
		return ""
	if not FileAccess.file_exists(path):
		return ""
	var base_backup_dir = "res://.team_create/backups"
	if not DirAccess.dir_exists_absolute(base_backup_dir):
		DirAccess.make_dir_recursive_absolute(base_backup_dir)
	var time_str = Time.get_datetime_string_from_system().replace(":", "-")
	var scene_name = path.get_file().get_basename()
	var ext = path.get_extension()
	var backup_path = base_backup_dir + "/" + scene_name + "_" + time_str + "." + ext
	var bytes = FileAccess.get_file_as_bytes(path)
	var f = FileAccess.open(backup_path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()
		if network:
			network.tc_print("Team Create: Backup created: ", backup_path)
		return backup_path
	return ""

func request_asset_immediately(path: String, sender_id: int = 1):
	if not _is_safe_path(path):
		return
	if FileAccess.file_exists(path) and (not FileAccess.file_exists(path + ".import") or ResourceLoader.exists(path)):
		asset_imported.emit(path)
		return

	if is_inside_tree() and multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var target_id = sender_id
		if target_id == 0 or target_id == multiplayer.get_unique_id():
			target_id = 1
		rpc_id(target_id, "request_asset_package", path)

@rpc("any_peer", "reliable")
func request_asset_package(path: String):
	if not _is_safe_path(path):
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var asset_bytes = PackedByteArray()
	var import_bytes = PackedByteArray()
	if FileAccess.file_exists(path):
		asset_bytes = FileAccess.get_file_as_bytes(path)
	if FileAccess.file_exists(path + ".import"):
		import_bytes = FileAccess.get_file_as_bytes(path + ".import")

	if asset_bytes.size() > 0:
		rpc_id(sender_id, "deliver_asset_package", path, asset_bytes, import_bytes)

@rpc("any_peer", "reliable")
func deliver_asset_package(path: String, asset_bytes: PackedByteArray, import_bytes: PackedByteArray):
	if not _is_safe_path(path):
		return
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	if asset_bytes.size() > 0:
		_file_write_mutex.lock()
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(asset_bytes)
			f.close()
		if import_bytes.size() > 0:
			var fi = FileAccess.open(path + ".import", FileAccess.WRITE)
			if fi:
				fi.store_buffer(import_bytes)
				fi.close()
		_file_write_mutex.unlock()

		if _file_hash_cache.has(path):
			_file_hash_cache.erase(path)

		var ei = _get_editor_interface()
		if ei and ei.get_resource_filesystem():
			ei.get_resource_filesystem().reimport_files(PackedStringArray([path]))

		asset_imported.emit(path)
		if network:
			network.tc_print("Team Create: Immediately received and reimported requested asset: ", path)



func _show_sync_blocker():
	if not _sync_blocker:
		var editor = _get_editor_interface()
		if not editor: return
		var base = editor.get_base_control()
		_sync_blocker = ColorRect.new()
		_sync_blocker.color = Color(0, 0, 0, 0.5)
		_sync_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var label = Label.new()
		label.name = "SyncLabel"
		label.text = "Syncing Files... (0 remaining)"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sync_blocker.add_child(label)

		base.add_child(_sync_blocker)

func _update_sync_blocker():
	if _sync_blocker:
		var label = _sync_blocker.get_node_or_null("SyncLabel")
		if label:
			var txt = "Syncing Files... (" + str(_pending_files_to_receive) + " remaining)"
			if downloading_files.size() > 0:
				txt += "\nWaiting for: " + downloading_files[0]
			label.text = txt

func _hide_sync_blocker():
	if _sync_blocker:
		_sync_blocker.queue_free()
		_sync_blocker = null

func _ready():
	call_deferred("_setup_fs_signals")

func _setup_fs_signals():
	var ei = _get_editor_interface()
	if ei:
		var efs = ei.get_resource_filesystem()
		if efs:
			if not efs.filesystem_changed.is_connected(_on_filesystem_changed):
				efs.filesystem_changed.connect(_on_filesystem_changed)

func _on_filesystem_changed():
	if _is_syncing_files or not is_inside_tree() or not multiplayer or not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer == null or multiplayer.get_peers().is_empty():
		return

	var current_files = get_all_files("res://")
	var current_files_dict = {}
	for path in current_files:
		current_files_dict[path] = true

	var known_files_dict = {}
	for path in _known_files:
		known_files_dict[path] = true

	# Clear cache entries for files that were removed
	var keys_to_remove = []
	for path in _file_hash_cache.keys():
		if not current_files_dict.has(path):
			keys_to_remove.append(path)
	for path in keys_to_remove:
		_file_hash_cache.erase(path)

	# Check for local files that exceed max_file_size
	if network and network.max_file_size > 0:
		var removed_any = false
		var i = current_files.size() - 1
		while i >= 0:
			var path = current_files[i]
			if not known_files_dict.has(path):
				var f = FileAccess.open(path, FileAccess.READ)
				if f:
					var size = f.get_length()
					f.close()
					if size > network.max_file_size:
						DirAccess.remove_absolute(path)
						network.tc_print_rich("[color=red]Warning: File " + path + " is too large (max " + str(network.max_file_size / (1024 * 1024.0)) + " MB). It was deleted and not synced.[/color]")
						if _file_hash_cache.has(path):
							_file_hash_cache.erase(path)
						removed_any = true
						current_files.remove_at(i)
						current_files_dict.erase(path)
			i -= 1

		if removed_any:
			# Scan again so editor notices deleted files
			var ei = _get_editor_interface()
			if ei and ei.get_resource_filesystem():
				ei.get_resource_filesystem().scan()

	# Automatically sync files whenever Godot detects a local file system change.
	sync_all_files(current_files)

	# Check for local deletions and broadcast them
	for known_path in _known_files:
		if not current_files_dict.has(known_path):
			rpc("remote_delete_file", known_path)

	_known_files = current_files.duplicate()

func sync_project_settings():
	if multiplayer.is_server():
		var bytes = FileAccess.get_file_as_bytes("res://project.godot")
		if network and network.get("is_standalone_server"):
			var text = bytes.get_string_from_utf8()
			text = text.replace("run/main_scene=\"res://addons/team_create/server.tscn\"", "")
			text = text.replace("run/main_scene.teamcreateserver=\"res://addons/team_create/server.tscn\"", "")
			bytes = text.to_utf8_buffer()
		if bytes:
			rpc("receive_project_settings", bytes)

func sync_all_files(all_files: Array = []):
	_is_syncing_files = true
	if all_files.is_empty():
		all_files = get_all_files("res://")
	var file_hashes = {}
	for path in all_files:
		if path.begins_with("res://addons/team_create"):
			continue
		file_hashes[path] = _get_cached_md5(path)
	rpc("compare_and_sync_files", file_hashes)
	_is_syncing_files = false

func sync_all_files_to_peer(id: int, all_files: Array = []):
	if multiplayer.is_server():
		if all_files.is_empty():
			all_files = get_all_files("res://")
		var file_hashes = {}
		for path in all_files:
			if path.begins_with("res://addons/team_create"):
				continue
			file_hashes[path] = _get_cached_md5(path)
		rpc_id(id, "compare_and_sync_files", file_hashes)

func get_all_files(dir_path: String, exclude_dirs: Array = []) -> Array:
	var files = []
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				var sub_dir = dir_path.path_join(file_name)
				if not file_name.begins_with("."):
					if not exclude_dirs.has(sub_dir):
						files.append_array(get_all_files(sub_dir, exclude_dirs))
			elif not dir.current_is_dir() and not file_name.begins_with("."):
				var full_path = dir_path.path_join(file_name)

				# Convert local .tmp files to real assets instantly, as requested.
				if file_name.ends_with(".tmp"):
					# Strip the .tmp extension to get the original desired filename
					# (e.g. script.gd.tmp -> script.gd, not script.gd.res)
					var real_path = full_path.trim_suffix(".tmp")

					# Only override if it looks like Godot was trying to create an entirely new temporary resource
					# rather than overwriting an existing script or asset
					if not SUPPORTED_EXTENSIONS.has(real_path.get_extension()):
						if not real_path.ends_with(".res") and not real_path.ends_with(".tres"):
							real_path += ".res"

					DirAccess.rename_absolute(full_path, real_path)
					files.append(real_path)
					network.tc_print("Converted temporary file to real asset: ", real_path)
					# Trigger editor refresh
					var ei = _get_editor_interface()
					if ei and ei.get_resource_filesystem():
						ei.get_resource_filesystem().scan()
				else:
					if full_path != "res://project.godot":
						files.append(full_path)
			file_name = dir.get_next()
	return files

@rpc("any_peer", "reliable")
func receive_project_settings(bytes: PackedByteArray):
	if multiplayer.get_remote_sender_id() != 1:
		printerr("Unauthorized settings sync attempt")
		return

	# Only overwrite if contents actually changed to prevent editor reload loops
	if FileAccess.file_exists("res://project.godot"):
		var existing_bytes = FileAccess.get_file_as_bytes("res://project.godot")
		if existing_bytes == bytes:
			return

	var file = FileAccess.open("res://project.godot", FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		network.tc_print("Project settings updated.")

@rpc("any_peer", "reliable")
func compare_and_sync_files(peer_hashes: Dictionary):
	_is_syncing_files = true
	var sender_id = multiplayer.get_remote_sender_id()
	var local_files = get_all_files("res://")
	var local_hashes = {}

	for path in local_files:
		if path.begins_with("res://addons/team_create"):
			continue
		local_hashes[path] = _get_cached_md5(path)

	var open_scenes = []
	var ei = _get_editor_interface()
	if ei:
		open_scenes = ei.get_open_scenes()

	# Find files to delete (only allow the server to delete files to prevent clients wiping the server)
	if sender_id == 1:
		for path in local_hashes:
			if path.begins_with("res://.godot/"):
				continue
			if not peer_hashes.has(path):
				if path in open_scenes:
					network.tc_print("Skipping deletion of open scene: ", path)
					continue
				if path.ends_with(".tscn") or path.ends_with(".scn") or path.ends_with(".gd"):
					var trash_dir = "res://.team_create/trash"
					if not DirAccess.dir_exists_absolute(trash_dir):
						DirAccess.make_dir_recursive_absolute(trash_dir)
					var trash_dest = trash_dir + "/" + path.get_file()
					DirAccess.rename_absolute(path, trash_dest)
					network.tc_print("Team Create: Moved unreferenced file to trash backup: ", path, " -> ", trash_dest)
				else:
					var err = DirAccess.remove_absolute(path)
					if err != OK:
						continue
					network.tc_print("Deleted unused file: ", path)
				if _file_hash_cache.has(path):
					_file_hash_cache.erase(path)

	# Request differing files
	var files_to_request = []
	for path in peer_hashes:
		if path == "res://project.godot" or path.begins_with("res://.godot/"):
			continue

		# Server is authoritative: The server never downloads existing files over its own copy
		if multiplayer.is_server() and local_hashes.has(path):
			continue

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


	var use_http = false
	if network and sender_id == 1 and network.peers.has(1) and network.peers[1].has("is_standalone") and network.peers[1]["is_standalone"]:
		use_http = true

	_pending_files_to_receive = files_to_request.size()
	downloading_files.clear()
	downloading_files.append_array(files_to_request)

	_known_files = local_files.duplicate()

	if _pending_files_to_receive > 0:
		call_deferred("_show_sync_blocker")
		call_deferred("_update_sync_blocker")

	for path in files_to_request:

		if use_http:
			_download_file_http(path)
		else:
			rpc_id(sender_id, "request_file", path)


	if _pending_files_to_receive == 0:
		sync_completed.emit()

	_is_syncing_files = false


func _download_file_http(path: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(self._http_download_completed.bind(http_request, path))

	var ip = network.server_ip
	if ip == "":
		ip = "127.0.0.1"
	var base_port = network.PORT if (network and "PORT" in network) else (network.get("PORT") if network and network.get("PORT") != null else 12345)
	var port = base_port + 1

	var raw_path = path.replace("res://", "/res/")
	var path_parts = raw_path.split("/")
	for i in range(path_parts.size()):
		path_parts[i] = path_parts[i].uri_encode()
	var encoded_path = "/".join(path_parts)
	var url = "http://" + ip + ":" + str(port) + encoded_path

	var error = http_request.request(url)
	if error != OK:
		printerr("HTTP Request failed for ", path)
		http_request.queue_free()
		_finish_http_download(path)

func _http_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, path: String):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		receive_file(path, randi(), body, true)
	else:
		printerr("Failed to download file via HTTP: ", path, " Response: ", response_code)
		_finish_http_download(path)

	http_request.queue_free()


func _upload_file_http(path: String, bytes: PackedByteArray):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(self._http_upload_completed.bind(http_request, path))

	var ip = network.server_ip
	if ip == "":
		ip = "127.0.0.1"
	var base_port = network.PORT if (network and "PORT" in network) else (network.get("PORT") if network and network.get("PORT") != null else 12345)
	var port = base_port + 1

	var raw_path = path.replace("res://", "/res/")
	var path_parts = raw_path.split("/")
	for i in range(path_parts.size()):
		path_parts[i] = path_parts[i].uri_encode()
	var encoded_path = "/".join(path_parts)
	var url = "http://" + ip + ":" + str(port) + encoded_path

	var headers = ["Content-Type: application/octet-stream"]
	var error = http_request.request_raw(url, headers, HTTPClient.METHOD_POST, bytes)
	if error != OK:
		printerr("HTTP POST Request failed for ", path)
		http_request.queue_free()

func _http_upload_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, path: String):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		printerr("Failed to upload file via HTTP: ", path, " Response: ", response_code)
	http_request.queue_free()

@rpc("any_peer", "reliable")
func request_file(path: String):
	var sender_id = multiplayer.get_remote_sender_id()

	if not _is_safe_path(path):
		printerr("Team Create: Unauthorized or invalid file access requested: ", path)
		rpc_id(sender_id, "receive_file", path, randi(), PackedByteArray(), true)
		return

	# Send file back
	if FileAccess.file_exists(path):
		var bytes = FileAccess.get_file_as_bytes(path)
		var total_size = bytes.size()

		if total_size == 0:
			rpc_id(sender_id, "receive_file", path, randi(), bytes, true)
			return

		var use_http = false
		if network and sender_id == 1 and network.peers.has(1) and network.peers[1].has("is_standalone") and network.peers[1]["is_standalone"]:
			use_http = true

		if use_http:
			_upload_file_http(path, bytes)
		else:
			rpc_id(sender_id, "receive_file", path, randi(), bytes, true)
	else:
		rpc_id(sender_id, "receive_file", path, randi(), PackedByteArray(), true)

@rpc("any_peer", "reliable")
func receive_file(path: String, transfer_id: int, bytes: PackedByteArray, is_final: bool = true):
	if not _is_safe_path(path):
		printerr("Team Create: Unauthorized or invalid file path received: ", path)
		return

	var sender_id = multiplayer.get_remote_sender_id()
	var file_key = str(sender_id) + "_" + str(transfer_id) + "_" + path
	if not _receiving_files.has(file_key):
		_receiving_files[file_key] = PackedByteArray()

	_receiving_files[file_key].append_array(bytes)

	if not is_final:
		return

	var full_bytes = _receiving_files[file_key]
	_receiving_files.erase(file_key)
	bytes = full_bytes

	# Convert temporary files based on origin
	if path.ends_with(".tmp"):
		var real_path = path.trim_suffix(".tmp")
		if not SUPPORTED_EXTENSIONS.has(real_path.get_extension()):
			if not real_path.ends_with(".res") and not real_path.ends_with(".tres"):
				real_path += ".res"
		path = real_path

	# If this is a scene file, and the user has it open, we intercept writing it to disk.
	if network and network.scene_sync and (path.ends_with(".tscn") or path.ends_with(".scn")):
		var ei = _get_editor_interface()
		var current_scene: Node = null
		var open_scenes = []
		if ei:
			current_scene = ei.get_edited_scene_root()
			open_scenes = ei.get_open_scenes()

		if path in open_scenes:
			var merge_data = {}
			if network and network.scene_sync and not (multiplayer and multiplayer.is_server()):
				merge_data = network.scene_sync.prepare_offline_scene_merge(path, bytes)

			var is_active = current_scene and current_scene.scene_file_path == path
			if is_active:
				network.tc_print("Team Create: Applying received file to active scene view.")
			else:
				network.tc_print("Team Create: Applying received file to open background scene.")

			if bytes.size() > 0:
				backup_scene(path)
				_file_write_mutex.lock()
				var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
				if file:
					file.store_buffer(bytes)
					file.close()
					if DirAccess.remove_absolute(path) == OK or not FileAccess.file_exists(path):
						DirAccess.rename_absolute(path + ".tmp", path)
				_file_write_mutex.unlock()

			if is_active:
				network.scene_sync._is_reloading_scene = true
				network.scene_sync._force_full_sync_next_frame = true

			var prev_path = current_scene.scene_file_path if current_scene else ""
			ei.reload_scene_from_path(path)

			if not is_active and prev_path != "":
				# reload_scene_from_path might change the active tab, so we switch back just in case
				ei.open_scene_from_path(prev_path)

			if is_active:
				get_tree().create_timer(0.5).timeout.connect(func():
					if is_instance_valid(network) and network.scene_sync:
						network.scene_sync._is_reloading_scene = false
						if merge_data.size() > 0 and merge_data.get("added_nodes", []).size() > 0:
							network.scene_sync.apply_offline_merge_deferred(path, merge_data)
				)

			downloading_files.erase(path)
			if _pending_files_to_receive > 0:
				_pending_files_to_receive -= 1
				call_deferred("_update_sync_blocker")
				if _pending_files_to_receive <= 0:
					call_deferred("_hide_sync_blocker")
					_known_files = get_all_files("res://")
					sync_completed.emit()

			return

	# Ensure directory exists before writing
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	if bytes.size() > 0:
		var should_write = true
		if FileAccess.file_exists(path):
			var existing_bytes = FileAccess.get_file_as_bytes(path)
			if existing_bytes == bytes:
				should_write = false

		if should_write:
			if path.ends_with(".tscn") or path.ends_with(".scn"):
				backup_scene(path)
				if network and network.scene_sync and not (multiplayer and multiplayer.is_server()):
					network.scene_sync.prepare_offline_scene_merge(path, bytes)
			_file_write_mutex.lock()
			var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
			if file:
				file.store_buffer(bytes)
				file.close()
				if DirAccess.remove_absolute(path) == OK or not FileAccess.file_exists(path):
					DirAccess.rename_absolute(path + ".tmp", path)
				network.tc_print("Received and updated file: ", path)
			_file_write_mutex.unlock()
			if _file_hash_cache.has(path):
				_file_hash_cache.erase(path)
		else:
			network.tc_print("File unchanged, skipped writing: ", path)

		asset_imported.emit(path)

		# Trigger Editor resource scan if it's an asset, debounced to prevent premature imports generating new UIDs
		var ei = _get_editor_interface()
		if ei and ei.get_resource_filesystem():
			if _scan_timer == null:
				_scan_timer = get_tree().create_timer(0.5)
				_scan_timer.timeout.connect(func():
					_scan_timer = null
					var e = _get_editor_interface()
					if e and e.get_resource_filesystem():
						e.get_resource_filesystem().scan()
				)

	downloading_files.erase(path)
	if _pending_files_to_receive > 0:
		_pending_files_to_receive -= 1
		call_deferred("_update_sync_blocker")
		if _pending_files_to_receive <= 0:
			call_deferred("_hide_sync_blocker")
			_known_files = get_all_files("res://")
			sync_completed.emit()


# TODO: Handle cases where a local file is deleted while offline/disconnected before broadcasting
@rpc("any_peer", "reliable")
func remote_delete_file(path: String):
	if multiplayer.get_remote_sender_id() != 1:
		return # Only server can dictate deletions for security

	if not _is_safe_path(path):
		return

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		if _file_hash_cache.has(path):
			_file_hash_cache.erase(path)
		network.tc_print("Team Create: Replicated file deletion: ", path)

		# Remove from known files
		if _known_files.has(path):
			_known_files.erase(path)

func _finish_http_download(path: String):
	downloading_files.erase(path)
	if _pending_files_to_receive > 0:
		_pending_files_to_receive -= 1
		call_deferred("_update_sync_blocker")
		if _pending_files_to_receive <= 0:
			call_deferred("_hide_sync_blocker")
			_known_files = get_all_files("res://")
			sync_completed.emit()
