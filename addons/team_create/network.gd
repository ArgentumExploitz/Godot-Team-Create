@tool
extends Node

const ADJECTIVES = ["Fast", "Cool", "Smart", "Brave", "Wild", "Quick", "Sly", "Bold"]
const NOUNS = ["Cat", "Dog", "Fox", "Bear", "Wolf", "Hawk", "Owl", "Lion"]

const PORT = 12345
const MAX_CLIENTS = 10

var ui: Control
var plugin: Node
var peer = ENetMultiplayerPeer.new()
var is_server = false
var is_standalone_server = false
var server_ip: String = ""
var peers = {} # Dictionary mapping peer_id to user info (username, color)
var _color_assignment_counter = 0
var _assigned_colors = []
var file_sync
var scene_sync
var test_runner
var node_locks: Dictionary = {}

var _local_username = ""
# Console thread
var chat_window: Control
var _console_thread: Thread
var _console_should_exit: bool = false

# Server commands config
var auto_save_prints_enabled: bool = false
var timeprint_enabled: bool = true
var joins_enabled: bool = true
var allow_client_file_deletions: bool = true
var chat_locked: bool = false
var chat_images_enabled: bool = true
var muted_users = []
var admins = []

var max_file_size: int = 0

var chat_history = []
var chat_id_counter = 0
const CHAT_HISTORY_FILE = "user://team_chat_history.json"

func _get_editor_interface():
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface")
	if plugin and plugin.has_method("get_editor_interface"):
		return plugin.get_editor_interface()
	return null


func tc_print(msg: String, arg1="", arg2="", arg3=""):
	var full_msg = msg + str(arg1) + str(arg2) + str(arg3)
	if timeprint_enabled:
		var time = Time.get_time_string_from_system()
		print("<" + time + "> " + full_msg)
	else:
		print(full_msg)

func tc_print_rich(msg: String, arg1="", arg2="", arg3=""):
	var full_msg = msg + str(arg1) + str(arg2) + str(arg3)
	if timeprint_enabled:
		var time = Time.get_time_string_from_system()
		print_rich("[color=gray]<" + time + ">[/color] " + full_msg)
	else:
		print_rich(full_msg)

func _ready():
	if is_standalone_server:
		_console_thread = Thread.new()
		_console_thread.start(Callable(self, "_server_console_thread_func"))

	_load_chat_history()

	name = "TeamCreateNetwork"
	# Load sync modules
	var file_sync_script = load("res://addons/team_create/file_sync.gd")
	if file_sync_script:
		file_sync = file_sync_script.new()
		file_sync.name = "TeamCreateFileSync"
		file_sync.network = self
		add_child(file_sync)

	var scene_sync_script = load("res://addons/team_create/scene_sync.gd")
	if scene_sync_script:
		scene_sync = scene_sync_script.new()
		scene_sync.name = "TeamCreateSceneSync"
		scene_sync.network = self
		add_child(scene_sync)

	var test_runner_script = load("res://addons/team_create/test_runner.gd")
	if test_runner_script:
		test_runner = test_runner_script.new()
		test_runner.name = "TeamCreateTestRunner"
		test_runner.network = self
		add_child(test_runner)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if scene_sync and scene_sync.has_method("flush_all_scenes_to_disk"):
			scene_sync.flush_all_scenes_to_disk()
		_save_chat_history()

func _exit_tree():
	if scene_sync and scene_sync.has_method("flush_all_scenes_to_disk"):
		scene_sync.flush_all_scenes_to_disk()
	_save_chat_history()
	if _console_thread and _console_thread.is_started():
		_console_should_exit = true
		# We do not wait_to_finish() here because read_string_from_stdin() blocks infinitely
		# and attempting to wait will cause the server to hang on shutdown.
		# Godot will forcefully clean up the thread when the process exits.


func _server_console_thread_func():
	tc_print_rich("[color=green]Server console ready. Type /help for a list of commands.[/color]")
	while not _console_should_exit:
		# OS.read_string_from_stdin is blocking. It will wake up when the user hits Enter.
		var input = OS.read_string_from_stdin().strip_edges()
		if input == "":
			OS.delay_msec(50)
			continue
		call_deferred("_process_console_command", input)

func _process_console_command(input: String):
	var args = input.split(" ")
	var cmd = args[0].to_lower()

	if cmd == "/help":
		if args.size() > 1 and args[1] == "2":
			tc_print_rich("[color=cyan]--- Available Commands (Page 2) ---[/color]")
			tc_print_rich("[color=white]/lockchat <true/false>[/color] - Prevents users from chatting")
			tc_print_rich("[color=white]/chatmsg <message>[/color]    - Creates chat message from a server")
			tc_print_rich("[color=white]/mute <user or id>[/color]      - Mutes user from chatting")
			tc_print_rich("[color=white]/unmute <user or id>[/color]    - Unmutes user from chatting")
			tc_print_rich("[color=white]/admin <user or id>[/color]     - Gives admin privileges to a user")
			tc_print_rich("[color=white]/unadmin <user or id>[/color]   - Removes admin privileges from a user")
			tc_print_rich("[color=white]/chatimgs <true/false>[/color] - Lets users send images in the chat")
			tc_print_rich("[color=white]/filesize <num or none>[/color] - Sets maximum file size limit")
			tc_print_rich("[color=white]/backup [scene][/color]       - Creates a snapshot backup of scenes")
			tc_print_rich("[color=white]/autobackup <true/false>[/color] - Toggles automatic backups (default: false)")
			tc_print_rich("[color=white]/allowdeletions <true/false>[/color] - Toggles client-side file deletion replication (default: true)")
			tc_print_rich("[color=white]/test <user> [1-6][/color]     - Runs automated live sync tests on target scene")
			tc_print_rich("[color=cyan]--------------------------[/color]")
		else:
			tc_print_rich("[color=cyan]--- Available Commands (Page 1) ---[/color]")
			tc_print_rich("[color=white]/kick <user>[/color]   - Kicks a user from the server")
			tc_print_rich("[color=white]/list[/color]          - Lists all connected users")
			tc_print_rich("[color=white]/info[/color]          - Shows server statistics (memory, CPU, players, etc.)")
			tc_print_rich("[color=white]/update[/color]        - Downloads latest update and restarts the server")
			tc_print_rich("[color=white]/restart[/color]       - Restarts the server")
			tc_print_rich("[color=white]/stop[/color]          - Stops and exits the server")
			tc_print_rich("[color=white]/saveprints <true/false>[/color] - Toggles auto-save prints")
			tc_print_rich("[color=white]/timeprint <true/false>[/color] - Toggles time prefix in prints")
			tc_print_rich("[color=white]/togglejoins <true/false>[/color] - Toggles people joining the server")
			tc_print_rich("[color=white]/msg <message>[/color]    - Shows a message to everyone")
			tc_print_rich("[color=white]/popup <message>[/color]  - Creates a pop up for everyone")
			tc_print_rich("[color=white]/clearchat[/color]       - Clears all chat messages")
			tc_print_rich("[color=cyan]Type /help 2 for more commands[/color]")
			tc_print_rich("[color=cyan]--------------------------[/color]")

	elif cmd == "/clearchat":
		clear_chat()

	elif cmd == "/lockchat":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /lockchat <true/false>[/color]")
		else:
			var val = args[1].to_lower()
			if val == "true":
				chat_locked = true
				tc_print_rich("[color=green]Chat is now locked.[/color]")
			elif val == "false":
				chat_locked = false
				tc_print_rich("[color=green]Chat is now unlocked.[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use true or false.[/color]")

	elif cmd == "/chatmsg":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /chatmsg <message>[/color]")
		else:
			var msg_text = input.substr(args[0].length()).strip_edges()
			var msg = {
				"id": chat_id_counter,
				"type": "text",
				"sender_id": 1,
				"sender_name": "Server",
				"sender_color": "FFA500",
				"pinned": false,
				"text": msg_text
			}
			chat_id_counter += 1
			chat_history.append(msg)
			_save_chat_history()
			rpc("receive_chat_message", msg)
			_add_message_to_local_ui(msg)
			tc_print("[Chat] Server: " + msg_text)

	elif cmd == "/mute" or cmd == "/unmute":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: " + cmd + " <user or peer id>[/color]")
		else:
			var target_str = args[1]
			var target_id = -1
			if target_str.is_valid_int():
				target_id = target_str.to_int()
				if not peers.has(target_id):
					target_id = -1
			if target_id == -1:
				for id in peers.keys():
					if peers[id]["username"] == target_str:
						target_id = id
						break

			if target_id != -1:
				if cmd == "/mute":
					if not muted_users.has(target_id):
						muted_users.append(target_id)
						tc_print_rich("[color=yellow]User muted: " + peers[target_id]["username"] + "[/color]")
					else:
						tc_print_rich("[color=yellow]User is already muted.[/color]")
				else:
					if muted_users.has(target_id):
						muted_users.erase(target_id)
						tc_print_rich("[color=green]User unmuted: " + peers[target_id]["username"] + "[/color]")
					else:
						tc_print_rich("[color=yellow]User is not muted.[/color]")
			else:
				tc_print_rich("[color=red]User not found: " + target_str + "[/color]")

	elif cmd == "/admin" or cmd == "/unadmin":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: " + cmd + " <user or peer id>[/color]")
		else:
			var target_str = args[1]
			var target_id = -1
			if target_str.is_valid_int():
				target_id = target_str.to_int()
				if not peers.has(target_id):
					target_id = -1
			if target_id == -1:
				for id in peers.keys():
					if peers[id]["username"] == target_str:
						target_id = id
						break

			if target_id != -1:
				if cmd == "/admin":
					if not admins.has(target_id):
						admins.append(target_id)
						tc_print_rich("[color=green]User granted admin: " + peers[target_id]["username"] + "[/color]")
					else:
						tc_print_rich("[color=yellow]User is already an admin.[/color]")
				else:
					if admins.has(target_id):
						admins.erase(target_id)
						tc_print_rich("[color=green]User removed from admin: " + peers[target_id]["username"] + "[/color]")
					else:
						tc_print_rich("[color=yellow]User is not an admin.[/color]")
			else:
				tc_print_rich("[color=red]User not found: " + target_str + "[/color]")

	elif cmd == "/filesize":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /filesize <number (in Mb) or none>[/color]")
		else:
			var val = args[1].to_lower()
			if val == "none":
				max_file_size = 0
				rpc("update_max_file_size", max_file_size)
				tc_print_rich("[color=green]Max file size limit disabled (unlimited).[/color]")
			elif val.is_valid_int() or val.is_valid_float():
				var mb = val.to_float()
				if mb <= 0:
					tc_print_rich("[color=red]Invalid file size. Must be greater than 0 or none.[/color]")
				else:
					# Convert Mb to bytes
					max_file_size = int(mb * 1024 * 1024)
					rpc("update_max_file_size", max_file_size)
					tc_print_rich("[color=green]Max file size set to " + val + " MB.[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use a number or none.[/color]")

	elif cmd == "/chatimgs":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /chatimgs <true/false>[/color]")
		else:
			var val = args[1].to_lower()
			if val == "true":
				chat_images_enabled = true
				tc_print_rich("[color=green]Chat images enabled.[/color]")
			elif val == "false":
				chat_images_enabled = false
				tc_print_rich("[color=green]Chat images disabled.[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use true or false.[/color]")

	elif cmd == "/saveprints":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /saveprints <true/false>[/color]")
		else:
			var val = args[1].to_lower()
			if val == "true":
				auto_save_prints_enabled = true
				tc_print_rich("[color=green]Auto-save prints enabled.[/color]")
			elif val == "false":
				auto_save_prints_enabled = false
				tc_print_rich("[color=green]Auto-save prints disabled.[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use true or false.[/color]")

	elif cmd == "/timeprint":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /timeprint <true/false>[/color]")
		else:
			var val = args[1].to_lower()
			if val == "true":
				timeprint_enabled = true
				tc_print_rich("[color=green]Time prints enabled.[/color]")
			elif val == "false":
				timeprint_enabled = false
				tc_print_rich("[color=green]Time prints disabled.[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use true or false.[/color]")

	elif cmd == "/togglejoins":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /togglejoins <true/false>[/color]")
		else:
			var val = args[1].to_lower()
			if val == "true":
				joins_enabled = true
				if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
					multiplayer.multiplayer_peer.refuse_new_connections = false
				tc_print_rich("[color=green]Joining is now enabled.[/color]")
			elif val == "false":
				joins_enabled = false
				if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
					multiplayer.multiplayer_peer.refuse_new_connections = true
				tc_print_rich("[color=green]Joining is now disabled.[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use true or false.[/color]")

	elif cmd == "/allowdeletions":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /allowdeletions <true/false>[/color]")
		else:
			var val = args[1].to_lower()
			if val == "true":
				allow_client_file_deletions = true
				if file_sync:
					file_sync.allow_client_file_deletions = true
				tc_print_rich("[color=green]Client file deletions enabled.[/color]")
			elif val == "false":
				allow_client_file_deletions = false
				if file_sync:
					file_sync.allow_client_file_deletions = false
				tc_print_rich("[color=yellow]Client file deletions disabled (server-only deletions).[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use true or false.[/color]")

	elif cmd == "/msg":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /msg <message>[/color]")
		else:
			var msg = input.substr(args[0].length()).strip_edges()
			rpc("show_message", msg)
			show_message(msg)
			tc_print_rich("[color=green]Message sent: " + msg + "[/color]")

	elif cmd == "/popup":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /popup <message>[/color]")
		else:
			var msg = input.substr(args[0].length()).strip_edges()
			rpc("show_popup", msg)
			show_popup(msg)
			tc_print_rich("[color=green]Popup sent: " + msg + "[/color]")

	elif cmd == "/kick":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /kick <username>[/color]")
		else:
			var target_username = args[1]
			var target_id = -1
			for id in peers.keys():
				if peers[id]["username"] == target_username:
					target_id = id
					break
			if target_id != -1:
				if target_id == 1:
					tc_print_rich("[color=red]Cannot kick the server.[/color]")
				else:
					tc_print_rich("[color=yellow]Kicking user: " + target_username + "[/color]")
					call_deferred("kick_peer", target_id)
			else:
				tc_print_rich("[color=red]User not found: " + target_username + "[/color]")

	elif cmd == "/update" or cmd == "update":
		tc_print_rich("[color=cyan]Updating server from GitHub...[/color]")
		download_update()

	elif cmd == "/list":
		tc_print_rich("[color=cyan]Connected users:[/color]")
		var count = 0
		for id in peers.keys():
			if id == 1:
				continue # Skip the server
			var info = peers[id]
			var ip_str = "N/A"
			if is_inside_tree() and multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				ip_str = multiplayer.multiplayer_peer.get_peer(id).get_remote_address()
			tc_print_rich("[color=white]- " + info["username"] + " (ID: " + str(id) + ", IP: " + ip_str + ")[/color]")
			count += 1
		tc_print_rich("[color=green]Total users: " + str(count) + "[/color]")

	elif cmd == "/restart" or cmd == "restart":
		tc_print_rich("[color=orange]Restarting server...[/color]")
		call_deferred("_deferred_restart")

	elif cmd == "/stop" or cmd == "stop":
		tc_print_rich("[color=red]Stopping server...[/color]")
		call_deferred("_deferred_stop")

	elif cmd == "/info":
		tc_print_rich("[color=cyan]--- Server Info ---[/color]")
		tc_print_rich("[color=white]Memory Usage:[/color] " + String.humanize_size(OS.get_static_memory_usage()))
		tc_print_rich("[color=white]Peak Memory Usage:[/color] " + String.humanize_size(OS.get_static_memory_peak_usage()))
		var cpu_usage = Performance.get_monitor(Performance.TIME_PROCESS) * Engine.get_frames_per_second() * 100.0
		tc_print_rich("[color=white]CPU Usage:[/color] " + ("%.2f" % cpu_usage) + "%")
		var port = str(PORT)
		var local_ip = "127.0.0.1"
		for address in IP.get_local_addresses():
			if address.split(".").size() == 4 and not address.begins_with("127.") and not address.begins_with("169.254."):
				local_ip = address
				break
		tc_print_rich("[color=white]Network:[/color] " + local_ip + ":" + str(port))
		var user_count = peers.size() - 1 if peers.has(1) else peers.size()
		tc_print_rich("[color=white]Total users connected:[/color] " + str(user_count))
		tc_print_rich("[color=cyan]-------------------[/color]")

	elif cmd == "/backup" or cmd == "backup":
		var target_path = args[1] if args.size() > 1 else ""
		create_server_backup(target_path)

	elif cmd == "/autobackup" or cmd == "autobackup":
		if args.size() < 2:
			tc_print_rich("[color=orange]Usage: /autobackup <true/false> (Current: " + str(file_sync.auto_backups_enabled if file_sync else false) + ")[/color]")
		else:
			var val = args[1].to_lower()
			if val == "true":
				if file_sync: file_sync.auto_backups_enabled = true
				tc_print_rich("[color=green]Automatic backups enabled.[/color]")
			elif val == "false":
				if file_sync: file_sync.auto_backups_enabled = false
				tc_print_rich("[color=green]Automatic backups disabled.[/color]")
			else:
				tc_print_rich("[color=red]Invalid argument. Use true or false.[/color]")
	elif cmd == "/test" or cmd == "test":
		if test_runner:
			test_runner.handle_test_command(args)
		else:
			tc_print_rich("[color=red]Test runner module not loaded.[/color]")
	else:
		tc_print_rich("[color=red]Unknown command: " + cmd + "[/color]")

var downloading = false

func download_update() -> void:
	if downloading:
		tc_print_rich("[color=orange]An update download is already in progress.[/color]")
		return
	downloading = true

	if is_server:
		rpc("show_popup", "Server is updating to the latest version. Please reconnect in a moment.")
		if scene_sync and scene_sync.has_method("flush_all_scenes_to_disk"):
			scene_sync.flush_all_scenes_to_disk()

	if plugin and "dock" in plugin and plugin.dock and "update_btn" in plugin.dock and plugin.dock.update_btn:
		plugin.dock.update_btn.text = "Downloading..."

	tc_print_rich("[color=yellow]Downloading update from GitHub...[/color]")
	var http_request = HTTPRequest.new()
	http_request.name = "TC_Update_HTTPRequest"
	add_child(http_request)
	http_request.request_completed.connect(self._on_update_download_completed.bind(http_request))
	http_request.download_file = "user://team_create_update.zip"
	var headers = ["User-Agent: Godot-Team-Create-Plugin"]
	var error = http_request.request("https://github.com/N3rmis/Godot-Team-Create/archive/refs/heads/main.zip", headers)
	if error != OK:
		tc_print_rich("[color=red]Failed to start HTTP download: " + error_string(error) + "[/color]")
		downloading = false
		if plugin:
			if plugin.has_method("_reset_update_button"):
				plugin._reset_update_button()
			plugin.downloading = false
		http_request.queue_free()

func _on_update_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	http_request.queue_free()

	if result == HTTPRequest.RESULT_SUCCESS and (response_code >= 200 and response_code < 400):
		tc_print_rich("[color=green]Download completed successfully. Applying update...[/color]")
		_apply_update_zip("user://team_create_update.zip")
	else:
		tc_print_rich("[color=red]Failed to download update. Result: " + str(result) + ", HTTP Response Code: " + str(response_code) + "[/color]")
		downloading = false
		if FileAccess.file_exists("user://team_create_update.zip"):
			DirAccess.remove_absolute("user://team_create_update.zip")
		if plugin:
			if plugin.has_method("_reset_update_button"):
				plugin._reset_update_button()
			plugin.downloading = false

func _apply_update_zip(zip_path: String) -> void:
	var zip_reader = ZIPReader.new()
	var err = zip_reader.open(zip_path)
	if err != OK:
		tc_print_rich("[color=red]Failed to open update zip file (Error: " + error_string(err) + ").[/color]")
		DirAccess.remove_absolute(zip_path)
		downloading = false
		if plugin:
			if plugin.has_method("_reset_update_button"):
				plugin._reset_update_button()
			plugin.downloading = false
		return

	tc_print_rich("[color=yellow]Extracting updated plugin files...[/color]")
	var files = zip_reader.get_files()
	var updated_count = 0

	for f in files:
		if f.ends_with("/"):
			continue

		var f_norm = f.replace("\\", "/")
		var parts = f_norm.split("/")
		var addons_idx = -1
		for i in range(parts.size() - 1):
			if parts[i] == "addons" and parts[i + 1] == "team_create":
				addons_idx = i
				break

		if addons_idx != -1:
			var rel_parts = parts.slice(addons_idx, parts.size())
			var dest_path = ("res://" + "/".join(rel_parts)).simplify_path()

			if not dest_path.begins_with("res://addons/team_create/"):
				printerr("Security Warning: Traversal attempt detected in update zip: ", f)
				continue

			var global_dest = ProjectSettings.globalize_path(dest_path)
			var dest_dir = global_dest.get_base_dir()
			if not DirAccess.dir_exists_absolute(dest_dir):
				DirAccess.make_dir_recursive_absolute(dest_dir)

			var content = zip_reader.read_file(f)
			if DirAccess.remove_absolute(global_dest) != OK and FileAccess.file_exists(global_dest):
				pass

			var out_file = FileAccess.open(global_dest, FileAccess.WRITE)
			if out_file:
				out_file.store_buffer(content)
				out_file.close()
				updated_count += 1
			else:
				tc_print_rich("[color=red]Failed to write updated file: " + dest_path + "[/color]")

	zip_reader.close()
	DirAccess.remove_absolute(zip_path)
	downloading = false
	if plugin:
		plugin.downloading = false

	# If server.gd exists, synchronize it from updated server_exporter.gd
	if FileAccess.file_exists("res://addons/team_create/server.gd"):
		_update_server_bootstrap_script()

	tc_print_rich("[color=green]Update applied successfully (" + str(updated_count) + " files updated). Restarting server...[/color]")

	if plugin and "dock" in plugin and plugin.dock and "update_btn" in plugin.dock and plugin.dock.update_btn:
		plugin.dock.update_btn.text = "Restarting..."

	call_deferred("_deferred_restart")

func _update_server_bootstrap_script() -> void:
	var exporter = load("res://addons/team_create/server_exporter.gd")
	if exporter:
		var server_path = ProjectSettings.globalize_path("res://addons/team_create/server.gd")
		var f = FileAccess.open(server_path, FileAccess.WRITE)
		if f:
			f.store_string(exporter.SERVER_SCRIPT_TEMPLATE)
			f.close()
			tc_print_rich("[color=cyan]Updated standalone server bootstrap (server.gd).[/color]")

func _deferred_update_and_close():
	download_update()

func _deferred_restart():
	tc_print_rich("[color=orange]Restarting server...[/color]")
	if scene_sync and scene_sync.has_method("flush_all_scenes_to_disk"):
		scene_sync.flush_all_scenes_to_disk()

	if file_sync and file_sync.has_method("stop_http_server"):
		file_sync.stop_http_server()

	disconnect_peer()
	_save_chat_history()

	var is_headless = DisplayServer.get_name() == "headless"
	var exec_path = OS.get_executable_path()
	var args: PackedStringArray = []

	for arg in OS.get_cmdline_args():
		args.append(arg)

	if is_headless and not "--headless" in args:
		args.insert(0, "--headless")

	if _console_thread and _console_thread.is_started():
		_console_should_exit = true

	if is_headless:
		# On Windows, locate the console wrapper if currently running via the main binary
		if OS.get_name() == "Windows":
			var base_dir = exec_path.get_base_dir()
			var base_name = exec_path.get_file().get_basename()
			if not base_name.to_lower().contains("console"):
				var candidates = [
					base_dir + "/" + base_name + "_console.exe",
					base_dir + "/" + base_name + ".console.exe",
					base_dir + "/godot.console.exe"
				]
				for cand in candidates:
					if FileAccess.file_exists(cand):
						exec_path = cand
						break

		# Important: on Windows, p_open_console MUST be true when restarting headless,
		# otherwise OS_Windows::create_process spawns with CREATE_NO_WINDOW which hides the console completely!
		var pid = OS.create_process(exec_path, args, true)
		if pid <= 0:
			tc_print_rich("[color=red]Failed to launch new server process.[/color]")
		else:
			tc_print_rich("[color=green]Server restarted in new console (PID: " + str(pid) + "). Exiting current instance...[/color]")
		get_tree().quit(0)
	else:
		var editor_iface = _get_editor_interface()
		if editor_iface and editor_iface.has_method("restart_editor"):
			editor_iface.restart_editor()
		elif OS.has_method("set_restart_on_exit"):
			OS.set_restart_on_exit(true, args)
			get_tree().quit(0)
		else:
			OS.create_process(exec_path, args)
			get_tree().quit(0)

func _deferred_stop():
	if scene_sync and scene_sync.has_method("flush_all_scenes_to_disk"):
		scene_sync.flush_all_scenes_to_disk()
	if file_sync and file_sync.has_method("stop_http_server"):
		file_sync.stop_http_server()
	disconnect_peer()
	_save_chat_history()

	if _console_thread and _console_thread.is_started():
		_console_should_exit = true

	get_tree().quit(0)

func kick_peer(id: int):
	if is_server and id != 1:
		if is_inside_tree() and multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		tc_print("Kicked peer ", id)

func is_connected_to_session() -> bool:
	return is_inside_tree() and multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func update_local_username(new_name: String):
	_local_username = new_name
	if not is_connected_to_session():
		return
	var my_id = multiplayer.get_unique_id()
	if is_server:
		request_username_change(my_id, _local_username)
	elif my_id != 1:
		rpc_id(1, "request_username_change", my_id, _local_username)

func host_server():
	disconnect_peer()
	var err = peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		tc_print("Failed to host server: Error code ", err)
		disconnect_peer()
		return

	multiplayer.multiplayer_peer = peer
	is_server = true
	if file_sync:
		file_sync._initial_sync_done = true
	if is_standalone_server and file_sync:
		file_sync._setup_http_server()

	_add_peer(1)
	call_deferred("_update_local_chat_ui")
	_update_ui_state()

func join_server(ip: String):
	server_ip = ip
	if scene_sync:
		var cur_scn = scene_sync._get_edited_scene_root()
		if cur_scn and cur_scn.scene_file_path != "":
			scene_sync.save_current_camera_for_scene(cur_scn.scene_file_path, true)
			scene_sync._save_camera_cache()
	disconnect_peer()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		tc_print("Failed to join server: Error code ", err)
		disconnect_peer()
		return
	multiplayer.multiplayer_peer = peer
	is_server = false
	if is_connected_to_session():
		_add_peer(multiplayer.get_unique_id())
	if plugin:
		plugin._force_close_all_scenes()

func disconnect_peer():
	var was_connected = false
	if is_inside_tree() and multiplayer:
		was_connected = multiplayer.has_multiplayer_peer()
		multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
	is_server = false
	if scene_sync:
		var cur_scn = scene_sync._get_edited_scene_root()
		if cur_scn and cur_scn.scene_file_path != "":
			scene_sync.save_current_camera_for_scene(cur_scn.scene_file_path, true)
			scene_sync._last_scene_path = cur_scn.scene_file_path
		elif scene_sync._last_scene_path != "":
			scene_sync.save_current_camera_for_scene(scene_sync._last_scene_path, true)
		scene_sync._save_camera_cache()
		scene_sync.clear_all_peer_indicators()
		scene_sync._last_tracked_properties.clear()
		scene_sync._node_names.clear()
		scene_sync._pre_removal_paths.clear()
		scene_sync._last_selected_ids.clear()
		scene_sync._dirty_scenes.clear()
		scene_sync._pending_resource_properties.clear()
		scene_sync._active_node_locks.clear()
		scene_sync._pending_selection_nodes.clear()
		scene_sync._pending_selection_index = 0
		scene_sync._is_applying_remote_update = false
		scene_sync._is_reloading_scene = false
		scene_sync._ignore_next_structure_event = false
	peers.clear()
	_color_assignment_counter = 0
	_assigned_colors.clear()
	if ui:
		ui.set_disconnected()
	if file_sync:
		file_sync._hide_sync_blocker()
		file_sync._initial_sync_done = false
		file_sync.downloading_files.clear()
		if file_sync.has_method("stop_http_server"):
			file_sync.stop_http_server()
	if was_connected:
		tc_print("Disconnected")

func _add_peer(id: int):
	if not peers.has(id):
		if is_server:
			peers[id] = _generate_peer_info(id)
			if id != 1:
				rpc("sync_peer_info", id, peers[id])
		else:
			peers[id] = _get_default_peer_info(id) # temporary fallback until server syncs

func _on_peer_connected(id: int):
	if is_server and not joins_enabled:
		tc_print("Rejected peer connection because joins are disabled: ", id)
		call_deferred("kick_peer", id)
		return

	tc_print("Peer connected: ", id)
	_add_peer(id)
	if ui:
		ui.update_users_count(peers.size())

	_update_ui_state()

	if is_server:
		# Auto sync all files when a peer joins
		call_deferred("sync_all_files_to_peer", id)
		# NOTE: We DO NOT push the scene here anymore! The client will request it when file sync finishes.
		# Sync max file size to the new peer
		rpc_id(id, "update_max_file_size", max_file_size)

		# Send current peer list to the new peer
		for existing_id in peers.keys():
			rpc_id(id, "sync_peer_info", existing_id, peers[existing_id])

		# Inform all other peers about the new peer with its server-assigned info
		for peer_id in peers.keys():
			if peer_id != 1 and peer_id != id:
				rpc_id(peer_id, "sync_peer_info", id, peers[id])

		# Send chat history to the new user
		rpc_id(id, "sync_chat_history", chat_history)



func _on_peer_disconnected(id: int):
	tc_print("Peer disconnected: ", id)
	if is_server and scene_sync and scene_sync._dirty_scenes.size() > 0:
		scene_sync.save_dirty_scenes()
	if peers.has(id):
		peers.erase(id)
	if ui:
		ui.update_users_count(peers.size())

	# Clear selection outlines and locks for disconnected peer
	if scene_sync:
		scene_sync.clear_peer_selections(id)
		scene_sync._clear_peer_cursor(id)
		if scene_sync.has_method("release_all_locks_for_peer"):
			scene_sync.release_all_locks_for_peer(id)

	if is_server and is_connected_to_session():
		var to_release = []
		for nid in node_locks.keys():
			if node_locks[nid] == id:
				to_release.append(nid)
		for nid in to_release:
			node_locks.erase(nid)
			rpc("sync_node_unlock", nid, "")
			sync_node_unlock(nid, "")

func _on_connected_to_server():
	tc_print("Connected to server successfully!")
	_add_peer(1) # Add server to peers list
	_update_ui_state()

	# Wait for the initial file sync to complete before asking for the scene
	if file_sync:
		if not file_sync.sync_completed.is_connected(_request_scene_from_server):
			file_sync.sync_completed.connect(_request_scene_from_server, CONNECT_ONE_SHOT)

	# Send local username request if not server
	if is_connected_to_session():
		var my_id = multiplayer.get_unique_id()
		if not is_server and my_id != 1:
			rpc_id(1, "request_username_change", my_id, _local_username if _local_username != "" else "")

func _request_scene_from_server():
	var ei = _get_editor_interface()
	if ei:
		var efs = ei.get_resource_filesystem()
		if efs:
			# Give a slight delay for scans to start/catch up
			await get_tree().create_timer(0.6).timeout
			# Wait for scanning to finish
			while efs.is_scanning():
				await get_tree().process_frame

		var scene_path = ""
		var current_scene = ei.get_edited_scene_root()
		if current_scene:
			scene_path = current_scene.scene_file_path
		else:
			var main_scene = ProjectSettings.get_setting("application/run/main_scene", "")
			if main_scene != "" and FileAccess.file_exists(main_scene):
				ei.open_scene_from_path(main_scene)
				scene_path = main_scene
		rpc_id(1, "request_push_scene", scene_path)
	else:
		rpc_id(1, "request_push_scene", "")

@rpc("any_peer", "reliable")
func sync_peer_info(id: int, info: Dictionary):
	# Only the server should dictate peer info to avoid race conditions and enforce color assignments.
	if not is_server and multiplayer.get_remote_sender_id() != 1:
		return
	peers[id] = info

	# Update 3D cursor labels if username changed
	if scene_sync and scene_sync.has_method("_update_cursor_username"):
		scene_sync._update_cursor_username(id, info["username"])
	if ui:
		ui.update_users_count(peers.size())

@rpc("any_peer", "reliable")
func update_max_file_size(size: int):
	if multiplayer.get_remote_sender_id() != 1:
		return
	max_file_size = size

@rpc("any_peer", "reliable")
func show_message(msg: String):
	if multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return
	if ui and ui.has_method("show_server_message"):
		ui.show_server_message(msg)

@rpc("authority", "call_remote", "reliable")
func show_popup(msg: String):
	if multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return

	var dialog = AcceptDialog.new()
	dialog.title = "Server Message"
	dialog.dialog_text = msg
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

	var ei = _get_editor_interface()
	if ei and ei.get_base_control():
		ei.get_base_control().add_child(dialog)
		dialog.call_deferred("popup_centered")
	else:
		# Fallback if plugin reference is not available (e.g. headless)
		get_tree().root.add_child(dialog)
		dialog.call_deferred("popup_centered")

@rpc("any_peer", "reliable")
func request_username_change(id: int, new_username: String):
	if is_server:
		if peers.has(id) and (multiplayer.get_remote_sender_id() == id or multiplayer.get_remote_sender_id() == 0):
			if new_username != "":
				peers[id]["username"] = new_username
			rpc("sync_peer_info", id, peers[id])
			# Server updates its own
			sync_peer_info(id, peers[id])
			if not peers[id].get("has_broadcast_join", false):
				peers[id]["has_broadcast_join"] = true
				broadcast_join_message(id)

func _on_connection_failed():
	tc_print("Connection to server failed.")
	disconnect_peer()

func _on_server_disconnected():
	tc_print("Server disconnected.")
	disconnect_peer()

func _update_ui_state():
	if ui:
		var connected_to_standalone = false
		if peers.has(1) and peers[1].has("is_standalone") and peers[1]["is_standalone"]:
			connected_to_standalone = true
		ui.set_connected(is_server, connected_to_standalone)
		var my_id = multiplayer.get_unique_id() if is_connected_to_session() else 1
		var username = get_username(my_id)
		var protocol = "Server" if connected_to_standalone else "LAN"
		ui.status_label.text = "Status: " + username + " Connected (" + protocol + ")"
		ui.update_users_count(peers.size())

func push_current_scene():
	if scene_sync:
		scene_sync.push_current_scene()

func push_current_scene_to_peer(id: int):
	if scene_sync:
		scene_sync.push_current_scene_to_peer(id)

@rpc("any_peer", "reliable")
func request_push_scene(client_scene_path: String = ""):
	if is_server:
		var sender_id = multiplayer.get_remote_sender_id()
		if client_scene_path != "":
			_record_peer_scene(sender_id, client_scene_path)
		if scene_sync and client_scene_path != "":
			scene_sync.push_specific_scene_to_peer(client_scene_path, sender_id)
		else:
			push_current_scene_to_peer(sender_id)

var _user_cameras_by_name = {}

func report_current_scene(scene_path: String, camera_data: Dictionary = {}):
	if not is_connected_to_session():
		return
	var my_id = multiplayer.get_unique_id()
	if is_server:
		_record_peer_scene(my_id, scene_path, camera_data)
	elif my_id != 1:
		rpc_id(1, "report_current_scene_remote", scene_path, camera_data)

@rpc("any_peer", "reliable")
func report_current_scene_remote(scene_path: String, camera_data: Dictionary = {}):
	if not is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	_record_peer_scene(sender_id, scene_path, camera_data)

func _record_peer_scene(peer_id: int, scene_path: String, camera_data: Dictionary = {}):
	if peers.has(peer_id):
		peers[peer_id]["current_scene"] = scene_path
		var username = peers[peer_id].get("username", "")
		if username != "" and not camera_data.is_empty():
			if not _user_cameras_by_name.has(username):
				_user_cameras_by_name[username] = {}
			_user_cameras_by_name[username][scene_path] = camera_data


# Maps dummy resource paths back to original paths
var _dummy_path_to_original = {}
var _original_to_dummy_path = {}

func _get_or_create_dummy_resource(original_path: String, type: String) -> String:
	if _original_to_dummy_path.has(original_path):
		return _original_to_dummy_path[original_path]

	var md5 = original_path.md5_text()
	var dummy_path = "user://tc_dummy_" + md5 + ".tres"

	_dummy_path_to_original[dummy_path] = original_path
	_original_to_dummy_path[original_path] = dummy_path

	if not FileAccess.file_exists(dummy_path):
		var res = null

		# If type is empty/generic, try to infer it from the extension
		if type == "" or type == "Resource":
			var ext = original_path.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp", "svg", "bmp"]: type = "Texture2D"
			elif ext in ["obj", "blend", "gltf", "glb"]: type = "ArrayMesh"
			elif ext in ["material"]: type = "StandardMaterial3D"
			elif ext in ["wav", "mp3", "ogg"]: type = "AudioStreamWAV" # AudioStream

		if "Texture" in type:
			res = GradientTexture2D.new()
		elif "Material" in type:
			res = StandardMaterial3D.new()
		elif "Mesh" in type:
			res = ArrayMesh.new()
		elif "Audio" in type:
			res = AudioStreamWAV.new()
		elif "Script" in type:
			res = GDScript.new()
		elif ClassDB.can_instantiate(type):
			res = ClassDB.instantiate(type)

		if not res:
			res = Resource.new()
		ResourceSaver.save(res, dummy_path)

	return dummy_path

func _restore_dummy_paths_in_file(file_path: String):
	if _dummy_path_to_original.is_empty():
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file: return
	var text = file.get_as_text()
	file.close()

	var modified = false
	for dummy_path in _dummy_path_to_original:
		if text.find(dummy_path) != -1:
			var orig = _dummy_path_to_original[dummy_path]
			text = text.replace(dummy_path, orig)
			modified = true

	if modified:
		var wfile = FileAccess.open(file_path, FileAccess.WRITE)
		if wfile:
			wfile.store_string(text)
			wfile.close()

func sync_project_settings():
	if file_sync:
		file_sync.sync_project_settings()

func sync_all_files():
	if file_sync:
		file_sync.sync_all_files()

func sync_all_files_to_peer(id: int):
	if file_sync:
		file_sync.sync_all_files_to_peer(id)

# Unique ID management for nodes (Using node paths with UUID fallback for robustness across renames/reparenting)
static func assign_unique_id(node: Node) -> String:
	if not is_instance_valid(node):
		return ""

	var root: Node = null
	if node.owner:
		root = node.owner
	elif node.is_inside_tree():
		var tree = node.get_tree()
		if tree and tree.edited_scene_root:
			root = tree.edited_scene_root

	if not node.has_meta("_tc_uuid"):
		var uid = str(ResourceUID.create_id())
		node.set_meta("_tc_uuid", uid)
	elif root and root != node:
		# Check for UUID collision within the same scene (e.g. from node duplication)
		var existing = _find_node_by_uuid(root, str(node.get_meta("_tc_uuid")))
		if existing and existing != node:
			var uid = str(ResourceUID.create_id())
			node.set_meta("_tc_uuid", uid)

	if root:
		if node == root:
			return "."
		return str(root.get_path_to(node))
	if node.is_inside_tree():
		return str(node.get_path())
	return "."

static func _find_node_by_uuid(parent: Node, uuid: String) -> Node:
	if not is_instance_valid(parent):
		return null
	if parent.has_meta("_tc_uuid") and parent.get_meta("_tc_uuid") == uuid:
		return parent
	for child in parent.get_children():
		var found = _find_node_by_uuid(child, uuid)
		if found:
			return found
	return null

static func get_node_by_unique_id(root: Node, id: String) -> Node:
	if not is_instance_valid(root):
		return null
	if id == ".":
		return root
	if root.has_node(id):
		return root.get_node(id)
	return _find_node_by_uuid(root, id)

func _get_random_color(rng: RandomNumberGenerator) -> Color:
	return Color.from_hsv(rng.randf(), 0.8, 0.9)


func _get_random_name(rng: RandomNumberGenerator) -> String:
	return ADJECTIVES[rng.randi() % ADJECTIVES.size()] + NOUNS[rng.randi() % NOUNS.size()] + str(rng.randi() % 100)


func _generate_peer_info(id: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = id

	var color
	if _color_assignment_counter < 4:
		var initial_colors = [Color.BLUE, Color.GREEN, Color.RED, Color.PURPLE]
		var available_colors = []
		for c in initial_colors:
			if not _assigned_colors.has(c):
				available_colors.append(c)
		var rand_index = rng.randi() % available_colors.size()
		color = available_colors[rand_index]
		_assigned_colors.append(color)
		_color_assignment_counter += 1
	else:
		color = _get_random_color(rng)

	var username = _local_username if id == 1 and _local_username != "" else _get_random_name(rng)
	if id == 1 and is_standalone_server:
		username = "Server"
	var info = {"username": username, "color": color}
	if id == 1 and is_standalone_server:
		info["is_standalone"] = true
	return info

func _get_default_peer_info(id: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = id
	var color = _get_random_color(rng)
	var my_id = multiplayer.get_unique_id() if is_connected_to_session() else 1
	var username = _local_username if id == my_id and _local_username != "" else _get_random_name(rng)
	var info = {"username": username, "color": color}
	if id == 1 and is_standalone_server:
		info["is_standalone"] = true
	return info

# User Info management
func get_user_color(id: int) -> Color:
	if peers.has(id):
		return peers[id]["color"]
	return _get_default_peer_info(id)["color"]

func get_username(id: int) -> String:
	if peers.has(id):
		return peers[id]["username"]
	return _get_default_peer_info(id)["username"]




# Chat System
func _load_chat_history():
	if FileAccess.file_exists(CHAT_HISTORY_FILE):
		var file = FileAccess.open(CHAT_HISTORY_FILE, FileAccess.READ)
		if file:
			var text_content = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(text_content) == OK:
				if typeof(json.data) == TYPE_ARRAY:
					chat_history = json.data
					# find highest id
					for m in chat_history:
						if m.has("id") and m["id"] >= chat_id_counter:
							chat_id_counter = int(m["id"]) + 1

func _save_chat_history():
	var file = FileAccess.open(CHAT_HISTORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(chat_history))
		file.close()

func _update_local_chat_ui():
	if chat_window:
		chat_window.set_messages(chat_history)

func _add_message_to_local_ui(msg: Dictionary):
	if chat_window:
		chat_window.add_message(msg)

@rpc("any_peer", "reliable")
func sync_chat_history(history: Array):
	if multiplayer.get_remote_sender_id() != 1: return
	chat_history = history
	_save_chat_history()
	_update_local_chat_ui()

	# Check for any missing images in history and request them from server
	for m in chat_history:
		if m.get("type", "") == "image":
			var img_hash = m.get("image_hash", "")
			if img_hash != "":
				var cache_path = "user://team_create_chat".path_join(img_hash + ".png")
				if not FileAccess.file_exists(cache_path):
					rpc_id(1, "request_cached_chat_image", img_hash)

@rpc("any_peer", "reliable")
func request_cached_chat_image(img_hash: String):
	if not is_server: return
	var sender_id = multiplayer.get_remote_sender_id()
	var cache_path = "user://team_create_chat".path_join(img_hash + ".png")
	if FileAccess.file_exists(cache_path):
		var bytes = FileAccess.get_file_as_bytes(cache_path)
		if bytes.size() > 0:
			rpc_id(sender_id, "receive_cached_chat_image", img_hash, bytes)

@rpc("any_peer", "reliable")
func receive_cached_chat_image(img_hash: String, bytes: PackedByteArray):
	var sender_id = multiplayer.get_remote_sender_id()
	if not is_server and sender_id != 1: return
	var cache_dir = "user://team_create_chat"
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	var cache_path = cache_dir.path_join(img_hash + ".png")
	var f = FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()
		_update_local_chat_ui()

func send_chat_message(text: String, image_path: String = ""):
	if not is_connected_to_session():
		tc_print("Cannot send message. Not connected to a server.")
		return

	var my_id = multiplayer.get_unique_id()
	if image_path != "":
		_send_image_message(my_id, image_path)
		return

	if is_server:
		if text.begins_with("/"):
			if is_standalone_server or admins.has(my_id):
				_process_console_command(text)
				return
			else:
				tc_print("You do not have permission to use admin commands.")
				return
		if not chat_locked:
			_process_new_chat_message(my_id, text)
	else:
		if my_id == 1 or my_id == 0:
			tc_print("Cannot send message. Not connected to a server.")
			return
		rpc_id(1, "request_chat_message", text)

func _send_image_message(sender_id: int, image_path: String):
	if not chat_images_enabled:
		tc_print("Chat images are currently disabled on this server.")
		return
	var img = Image.load_from_file(image_path)
	if not img or img.is_empty():
		var global_path = ProjectSettings.globalize_path(image_path)
		img = Image.load_from_file(global_path)
	if not img or img.is_empty():
		if ResourceLoader.exists(image_path):
			var res = load(image_path)
			if res is Texture2D:
				img = res.get_image()
	if not img or img.is_empty():
		tc_print("Failed to load image from path: ", image_path)
		return

	# Downscale if exceeding 1920x1080
	if img.get_width() > 1920 or img.get_height() > 1080:
		var aspect = float(img.get_width()) / float(img.get_height())
		if aspect > 1.0:
			img.resize(1920, int(1920.0 / aspect), Image.INTERPOLATE_LANCZOS)
		else:
			img.resize(int(1080.0 * aspect), 1080, Image.INTERPOLATE_LANCZOS)

	var img_bytes = img.save_png_to_buffer()
	if img_bytes.size() > 5 * 1024 * 1024:
		tc_print("Image too large to send (exceeds 5MB).")
		return

	var img_hash = img_bytes.hex_encode().md5_text()
	var cache_dir = "user://team_create_chat"
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	var cache_path = cache_dir.path_join(img_hash + ".png")
	var f = FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_buffer(img_bytes)
		f.close()

	if is_server:
		_process_new_chat_image(sender_id, img_hash, img_bytes)
	else:
		rpc_id(1, "request_chat_image", img_hash, img_bytes)

@rpc("any_peer", "reliable")
func request_chat_image(img_hash: String, img_bytes: PackedByteArray):
	if not is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if chat_locked or muted_users.has(sender_id) or not chat_images_enabled:
		return
	if img_bytes.size() > 5 * 1024 * 1024:
		return
	_process_new_chat_image(sender_id, img_hash, img_bytes)

func _process_new_chat_image(sender_id: int, img_hash: String, img_bytes: PackedByteArray):
	var cache_dir = "user://team_create_chat"
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	var cache_path = cache_dir.path_join(img_hash + ".png")
	if not FileAccess.file_exists(cache_path):
		var f = FileAccess.open(cache_path, FileAccess.WRITE)
		if f:
			f.store_buffer(img_bytes)
			f.close()

	var username = get_username(sender_id)
	var color = get_user_color(sender_id)
	var msg = {
		"id": chat_id_counter,
		"type": "image",
		"sender_id": sender_id,
		"sender_name": username,
		"sender_color": color.to_html(false),
		"image_hash": img_hash,
		"pinned": false
	}
	chat_id_counter += 1
	chat_history.append(msg)
	_save_chat_history()
	tc_print("[Chat] " + username + " sent an image (hash: " + img_hash.substr(0, 8) + ")")

	rpc("receive_chat_image", msg, img_bytes)
	receive_chat_image(msg, img_bytes)

@rpc("any_peer", "reliable")
func receive_chat_image(msg: Dictionary, img_bytes: PackedByteArray):
	var sender_id = multiplayer.get_remote_sender_id()
	if not is_server and sender_id != 1 and sender_id != 0:
		return

	var img_hash = msg.get("image_hash", "")
	if img_hash != "":
		var cache_dir = "user://team_create_chat"
		if not DirAccess.dir_exists_absolute(cache_dir):
			DirAccess.make_dir_recursive_absolute(cache_dir)
		var cache_path = cache_dir.path_join(img_hash + ".png")
		if not FileAccess.file_exists(cache_path) and img_bytes.size() > 0:
			var f = FileAccess.open(cache_path, FileAccess.WRITE)
			if f:
				f.store_buffer(img_bytes)
				f.close()

	if not is_server:
		chat_history.append(msg)
		_save_chat_history()

	_add_message_to_local_ui(msg)

@rpc("any_peer", "reliable")
func request_chat_image_by_hash(img_hash: String):
	if not is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var cache_path = "user://team_create_chat".path_join(img_hash + ".png")
	if FileAccess.file_exists(cache_path):
		var f = FileAccess.open(cache_path, FileAccess.READ)
		if f:
			var bytes = f.get_buffer(f.get_length())
			f.close()
			rpc_id(sender_id, "deliver_chat_image_by_hash", img_hash, bytes)

@rpc("any_peer", "reliable")
func deliver_chat_image_by_hash(img_hash: String, img_bytes: PackedByteArray):
	if multiplayer.get_remote_sender_id() != 1:
		return
	var cache_dir = "user://team_create_chat"
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	var cache_path = cache_dir.path_join(img_hash + ".png")
	var f = FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_buffer(img_bytes)
		f.close()
	if chat_window and chat_window.has_method("refresh_images"):
		chat_window.refresh_images()

func get_chat_image_path(img_hash: String) -> String:
	var path = "user://team_create_chat".path_join(img_hash + ".png")
	if FileAccess.file_exists(path):
		return path
	if not is_server and multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc_id(1, "request_chat_image_by_hash", img_hash)
	return ""

@rpc("any_peer", "reliable")
func request_chat_message(text: String, legacy_image_path: String = ""):
	if not is_server: return
	var sender_id = multiplayer.get_remote_sender_id()

	if text.begins_with("/"):
		if admins.has(sender_id):
			_process_console_command(text)
		return

	if chat_locked: return
	if muted_users.has(sender_id): return
	_process_new_chat_message(sender_id, text)

func _process_new_chat_message(sender_id: int, text: String):
	var username = get_username(sender_id)
	var color = get_user_color(sender_id)

	var msg = {
		"id": chat_id_counter,
		"type": "text",
		"sender_id": sender_id,
		"sender_name": username,
		"sender_color": color.to_html(false),
		"pinned": false,
		"text": text
	}
	chat_id_counter += 1
	tc_print("[Chat] " + username + ": " + text)

	chat_history.append(msg)
	_save_chat_history()

	# Send to all peers
	rpc("receive_chat_message", msg)
	# Local server gets it too
	_add_message_to_local_ui(msg)

@rpc("any_peer", "reliable")
func receive_chat_message(msg: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	# If we're not the server, only accept from server. (0 means local call)
	if not is_server and sender_id != 1 and sender_id != 0: return

	# Client-side: if we didn't add it ourselves (we aren't server), append it
	if not is_server:
		chat_history.append(msg)
		_save_chat_history()

	_add_message_to_local_ui(msg)

func clear_chat():
	if is_server:
		chat_history.clear()
		_save_chat_history()
		rpc("sync_chat_history", [])
		_update_local_chat_ui()
		tc_print("Chat history cleared.")
	else:
		rpc_id(1, "request_clear_chat")

@rpc("any_peer", "reliable")
func request_clear_chat():
	if is_server:
		var sender_id = multiplayer.get_remote_sender_id()
		if admins.has(sender_id):
			clear_chat()

func toggle_pin_message(msg_id: int):
	if is_server:
		_process_toggle_pin(msg_id)
	else:
		rpc_id(1, "request_toggle_pin", msg_id)

@rpc("any_peer", "reliable")
func request_toggle_pin(msg_id: int):
	if is_server:
		_process_toggle_pin(msg_id)

func _process_toggle_pin(msg_id: int):
	for m in chat_history:
		if m.has("id") and m["id"] == msg_id:
			m["pinned"] = not m.get("pinned", false)
			_save_chat_history()
			rpc("sync_chat_history", chat_history)
			_update_local_chat_ui()
			break

func broadcast_join_message(id: int):
	if not joins_enabled: return
	var username = get_username(id)
	var msg = {
		"id": chat_id_counter,
		"type": "join",
		"text": username + " joined the session",
		"pinned": false
	}
	chat_id_counter += 1
	chat_history.append(msg)
	_save_chat_history()
	rpc("receive_chat_message", msg)
	receive_chat_message(msg)

# --- Node Locking Coordination ---
@rpc("any_peer", "reliable")
func request_node_lock(node_id: String, scene_path: String = ""):
	if not is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	if not node_locks.has(node_id) or node_locks[node_id] == sender_id:
		node_locks[node_id] = sender_id
		rpc("sync_node_lock", node_id, sender_id, scene_path)
		sync_node_lock(node_id, sender_id, scene_path)
	else:
		rpc_id(sender_id, "node_lock_denied", node_id)

@rpc("any_peer", "reliable")
func release_node_lock(node_id: String, scene_path: String = ""):
	if not is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	if node_locks.has(node_id) and node_locks[node_id] == sender_id:
		node_locks.erase(node_id)
		rpc("sync_node_unlock", node_id, scene_path)
		sync_node_unlock(node_id, scene_path)

@rpc("any_peer", "reliable")
func sync_node_lock(node_id: String, peer_id: int, scene_path: String = ""):
	if scene_sync and scene_sync.has_method("set_node_lock"):
		scene_sync.set_node_lock(node_id, peer_id)

@rpc("any_peer", "reliable")
func sync_node_unlock(node_id: String, scene_path: String = ""):
	if scene_sync and scene_sync.has_method("remove_node_lock"):
		scene_sync.remove_node_lock(node_id)

@rpc("any_peer", "reliable")
func node_lock_denied(node_id: String):
	if scene_sync and scene_sync.has_method("on_node_lock_denied"):
		scene_sync.on_node_lock_denied(node_id)

# --- Manual Scene Save Synchronization ---
func on_local_scene_saved(filepath: String):
	if multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if FileAccess.file_exists(filepath):
			var bytes = FileAccess.get_file_as_bytes(filepath)
			if is_server:
				rpc("receive_manual_save", filepath, bytes)
			else:
				rpc_id(1, "receive_manual_save", filepath, bytes)

@rpc("any_peer", "reliable")
func receive_manual_save(filepath: String, bytes: PackedByteArray):
	var sender_id = multiplayer.get_remote_sender_id()
	if is_server and sender_id != 0:
		for pid in multiplayer.get_peers() if multiplayer else []:
			if pid != sender_id:
				rpc_id(pid, "receive_manual_save", filepath, bytes)

	if bytes.size() > 0:
		if file_sync and file_sync.has_method("backup_scene"):
			file_sync.backup_scene(filepath)
		var f = FileAccess.open(filepath + ".tmp", FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
			if DirAccess.remove_absolute(filepath) == OK or not FileAccess.file_exists(filepath):
				DirAccess.rename_absolute(filepath + ".tmp", filepath)
			tc_print("Team Create: Synchronized manual save from peer for: ", filepath)
		if is_standalone_server and scene_sync:
			if scene_sync._server_tracked_scenes.has(filepath):
				var s = scene_sync._server_tracked_scenes[filepath]
				if is_instance_valid(s):
					s.queue_free()
				scene_sync._server_tracked_scenes.erase(filepath)
			var res = scene_sync._safe_load_headless(filepath)
			if res.packed and res.packed is PackedScene:
				var inst = res.packed.instantiate()
				if inst:
					inst.set_meta("scene_file_path", filepath)
					scene_sync._server_tracked_scenes[filepath] = inst
					get_tree().root.add_child(inst)
		else:
			var iface = _get_editor_interface()
			if iface:
				if iface.get_resource_filesystem():
					iface.get_resource_filesystem().reimport_files(PackedStringArray([filepath]))
				if iface.has_method("reload_scene_from_path"):
					iface.reload_scene_from_path(filepath)

func create_server_backup(target_path: String = ""):
	var backed_up = []
	if target_path != "":
		if file_sync and file_sync.has_method("backup_scene"):
			var res = file_sync.backup_scene(target_path, true)
			if res != "": backed_up.append(res)
	else:
		if scene_sync and scene_sync._server_tracked_scenes.size() > 0:
			for path in scene_sync._server_tracked_scenes.keys():
				if file_sync and file_sync.has_method("backup_scene"):
					var res = file_sync.backup_scene(path, true)
					if res != "": backed_up.append(res)
		elif file_sync:
			for f in file_sync.get_all_files("res://"):
				if f.ends_with(".tscn") or f.ends_with(".scn"):
					var res = file_sync.backup_scene(f, true)
					if res != "": backed_up.append(res)

	if backed_up.size() > 0:
		tc_print_rich("[color=green]Backup created (" + str(backed_up.size()) + " files):[/color]")
		for b in backed_up:
			tc_print_rich("  [color=cyan]" + b + "[/color]")
	else:
		tc_print_rich("[color=yellow]No scene files found to back up.[/color]")

@rpc("any_peer", "reliable")
func request_server_backup(target_path: String = ""):
	if not is_server:
		return
	create_server_backup(target_path)

func create_backup(target_path: String = "") -> Array:
	var backed_up = []
	var path_to_backup = target_path
	if path_to_backup == "":
		var ei = _get_editor_interface()
		if ei and ei.get_edited_scene_root():
			path_to_backup = ei.get_edited_scene_root().scene_file_path

	if path_to_backup != "" and file_sync and file_sync.has_method("backup_scene"):
		var res = file_sync.backup_scene(path_to_backup, true)
		if res != "":
			backed_up.append(res)

	if multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if is_server:
			create_server_backup(path_to_backup)
		else:
			rpc_id(1, "request_server_backup", path_to_backup)

	return backed_up

