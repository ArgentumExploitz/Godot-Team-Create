@tool
extends Control

var network: Node

# UI Elements
var status_label: Label
var users_label: RichTextLabel
var ip_edit: LineEdit
var host_btn: Button
var join_btn: Button
var disconnect_btn: Button

# WebRTC UI
var webrtc_host_btn: Button
var webrtc_join_btn: Button
var webrtc_instructions: Label
var webrtc_text: TextEdit
var webrtc_confirm_btn: Button
var push_scene_btn: Button
var sync_settings_btn: Button
var sync_files_btn: Button
var update_btn: Button

func _init() -> void:
	name = "LAN Sync"

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Status Label
	status_label = Label.new()
	status_label.text = "Status: Disconnected"
	status_label.add_theme_color_override("font_color", Color.GRAY)
	vbox.add_child(status_label)

	# Users Label
	users_label = RichTextLabel.new()
	users_label.bbcode_enabled = true
	users_label.text = "Users: 1"
	users_label.fit_content = true
	users_label.scroll_active = false
	vbox.add_child(users_label)

	vbox.add_child(HSeparator.new())

	# LAN Section Header
	var lan_label = Label.new()
	lan_label.text = "LAN Connection"
	lan_label.add_theme_font_override("font", get_theme_font("bold", "Label"))
	vbox.add_child(lan_label)

	# IP Edit
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "Host IP Address (e.g., 127.0.0.1)"
	ip_edit.tooltip_text = "Enter the IP address of the host you want to join over LAN."
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(ip_edit)

	# HBox for Host and Join buttons
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	host_btn = Button.new()
	host_btn.text = "Host"
	host_btn.tooltip_text = "Start a new LAN server on port 12345."
	host_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host_pressed)
	hbox.add_child(host_btn)

	join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.tooltip_text = "Join an existing LAN server using the IP above."
	join_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_pressed)
	hbox.add_child(join_btn)

	vbox.add_child(HSeparator.new())

	# WebRTC Section Header
	var webrtc_label = Label.new()
	webrtc_label.text = "WebRTC Connection"
	webrtc_label.add_theme_font_override("font", get_theme_font("bold", "Label"))
	vbox.add_child(webrtc_label)

	# WebRTC UI
	var webrtc_hbox = HBoxContainer.new()
	vbox.add_child(webrtc_hbox)

	webrtc_host_btn = Button.new()
	webrtc_host_btn.text = "Host WebRTC"
	webrtc_host_btn.tooltip_text = "Start a WebRTC session and generate a connection offer."
	webrtc_host_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	webrtc_host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	webrtc_host_btn.pressed.connect(_on_webrtc_host_pressed)
	webrtc_hbox.add_child(webrtc_host_btn)

	webrtc_join_btn = Button.new()
	webrtc_join_btn.text = "Join WebRTC"
	webrtc_join_btn.tooltip_text = "Join a WebRTC session and paste the host's offer below."
	webrtc_join_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	webrtc_join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	webrtc_join_btn.pressed.connect(_on_webrtc_join_pressed)
	webrtc_hbox.add_child(webrtc_join_btn)

	webrtc_text = TextEdit.new()
	webrtc_text.custom_minimum_size = Vector2(0, 100)
	webrtc_text.placeholder_text = "Paste WebRTC connection data here..."
	webrtc_text.tooltip_text = "Copy/paste connection strings here to establish WebRTC peer connections."
	webrtc_text.wrap_mode = TextEdit.LINE_WRAP_BOUNDARY
	vbox.add_child(webrtc_text)

	webrtc_confirm_btn = Button.new()
	webrtc_confirm_btn.text = "Confirm Connection Data"
	webrtc_confirm_btn.tooltip_text = "Process the connection data pasted above."
	webrtc_confirm_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	webrtc_confirm_btn.pressed.connect(_on_webrtc_confirm_pressed)
	vbox.add_child(webrtc_confirm_btn)

	# Disconnect Button
	disconnect_btn = Button.new()
	disconnect_btn.text = "Disconnect"
	disconnect_btn.tooltip_text = "Disconnect from the current session."
	disconnect_btn.disabled = true
	disconnect_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	disconnect_btn.add_theme_color_override("font_color", Color.INDIAN_RED)
	disconnect_btn.pressed.connect(_on_disconnect_pressed)
	vbox.add_child(disconnect_btn)

	vbox.add_child(HSeparator.new())

	# Action buttons
	push_scene_btn = Button.new()
	push_scene_btn.text = "Push Current Scene"
	push_scene_btn.tooltip_text = "(Server only) Force push your currently active scene to all clients."
	push_scene_btn.disabled = true
	push_scene_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	push_scene_btn.pressed.connect(_on_push_scene_pressed)
	vbox.add_child(push_scene_btn)

	sync_settings_btn = Button.new()
	sync_settings_btn.text = "Sync Project Settings"
	sync_settings_btn.tooltip_text = "(Server only) Force push project.godot to all clients."
	sync_settings_btn.disabled = true
	sync_settings_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sync_settings_btn.pressed.connect(_on_sync_settings_pressed)
	vbox.add_child(sync_settings_btn)

	sync_files_btn = Button.new()
	sync_files_btn.text = "Sync All Project Files"
	sync_files_btn.tooltip_text = "Compare and sync all project files across the network."
	sync_files_btn.disabled = true
	sync_files_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sync_files_btn.pressed.connect(_on_sync_files_pressed)
	vbox.add_child(sync_files_btn)

	vbox.add_child(HSeparator.new())

	update_btn = Button.new()
	update_btn.text = "Check for Updates"
	update_btn.tooltip_text = "Check GitHub for newer versions of the Godot Team Create plugin."
	update_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	update_btn.pressed.connect(_on_update_pressed)
	vbox.add_child(update_btn)

func _ready() -> void:
	pass

func set_connected(is_host: bool) -> void:
	host_btn.disabled = true
	join_btn.disabled = true
	webrtc_host_btn.disabled = true
	webrtc_join_btn.disabled = true
	webrtc_confirm_btn.disabled = true
	disconnect_btn.disabled = false
	push_scene_btn.disabled = false
	sync_settings_btn.disabled = false
	sync_files_btn.disabled = false

	if is_host:
		status_label.text = "Status: Peer Host Connected"
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		status_label.text = "Status: Peer Client Connected"
		status_label.add_theme_color_override("font_color", Color.GREEN)

func set_disconnected() -> void:
	host_btn.disabled = false
	join_btn.disabled = false
	webrtc_host_btn.disabled = false
	webrtc_join_btn.disabled = false
	webrtc_confirm_btn.disabled = false
	webrtc_confirm_btn.text = "Confirm Connection Data"
	disconnect_btn.disabled = true
	push_scene_btn.disabled = true
	sync_settings_btn.disabled = true
	sync_files_btn.disabled = true

	update_webrtc_instructions("Click 'Host WebRTC' or 'Join WebRTC' to start.")
	update_webrtc_text("")

	status_label.text = "Status: Disconnected"
	status_label.add_theme_color_override("font_color", Color.GRAY)
	users_label.text = "Users: 1"

func update_users_count(count: int) -> void:
	if network:
		var text = "Users: " + str(count) + "\n"
		for peer_id in network.peers:
			var username = network.get_username(peer_id)
			var color = network.get_user_color(peer_id).to_html()
			if peer_id == network.multiplayer.get_unique_id():
				text += "[color=#" + color + "]" + username + " (You)[/color]\n"
			else:
				text += "[color=#" + color + "]" + username + "[/color]\n"
		users_label.text = text
	else:
		users_label.text = "Users: " + str(count)

func _on_host_pressed() -> void:
	if network:
		network.host_server()

func _on_join_pressed() -> void:
	if network:
		network.join_server(ip_edit.text)

func _on_webrtc_host_pressed() -> void:
	if network:
		network.webrtc_host()

func _on_webrtc_join_pressed() -> void:
	if network:
		network.webrtc_join()

func _on_webrtc_confirm_pressed() -> void:
	if network:
		network.webrtc_confirm(webrtc_text.text)

func disable_webrtc_confirm() -> void:
	if webrtc_confirm_btn:
		webrtc_confirm_btn.disabled = true
		webrtc_confirm_btn.text = "Confirming..."

func enable_webrtc_confirm() -> void:
	if webrtc_confirm_btn:
		webrtc_confirm_btn.disabled = false
		webrtc_confirm_btn.text = "Confirm Connection Data"

func update_webrtc_text(text: String) -> void:
	if webrtc_text:
		webrtc_text.text = text

func _on_disconnect_pressed() -> void:
	if network:
		network.disconnect_peer()

func _on_push_scene_pressed() -> void:
	if network:
		network.push_current_scene()

func _on_sync_settings_pressed() -> void:
	if network:
		network.sync_project_settings()

func _on_sync_files_pressed() -> void:
	if network:
		network.sync_all_files()

func _on_update_pressed() -> void:
	if network and network.plugin:
		if update_btn.text == "Update Available!":
			network.plugin.download_update()
		else:
			network.plugin.check_for_updates()
