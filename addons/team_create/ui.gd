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
var push_scene_btn: Button
var sync_settings_btn: Button
var sync_files_btn: Button

func _init() -> void:
	name = "LAN Sync"

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	add_child(vbox)

	# Status Label
	status_label = Label.new()
	status_label.text = "Status: Disconnected"
	vbox.add_child(status_label)

	# Users Label
	users_label = RichTextLabel.new()
	users_label.bbcode_enabled = true
	users_label.text = "Users: 1"
	users_label.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(users_label)

	# IP Edit
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	vbox.add_child(ip_edit)

	# HBox for Host and Join buttons
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	host_btn = Button.new()
	host_btn.text = "Host"
	host_btn.pressed.connect(_on_host_pressed)
	hbox.add_child(host_btn)

	join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_on_join_pressed)
	hbox.add_child(join_btn)

	# Disconnect Button
	disconnect_btn = Button.new()
	disconnect_btn.text = "Disconnect"
	disconnect_btn.disabled = true
	disconnect_btn.pressed.connect(_on_disconnect_pressed)
	vbox.add_child(disconnect_btn)

	# Action buttons
	push_scene_btn = Button.new()
	push_scene_btn.text = "Push Current Scene"
	push_scene_btn.disabled = true
	push_scene_btn.pressed.connect(_on_push_scene_pressed)
	vbox.add_child(push_scene_btn)

	sync_settings_btn = Button.new()
	sync_settings_btn.text = "Sync Project Settings"
	sync_settings_btn.disabled = true
	sync_settings_btn.pressed.connect(_on_sync_settings_pressed)
	vbox.add_child(sync_settings_btn)

	sync_files_btn = Button.new()
	sync_files_btn.text = "Sync All Project Files"
	sync_files_btn.disabled = true
	sync_files_btn.pressed.connect(_on_sync_files_pressed)
	vbox.add_child(sync_files_btn)

func _ready() -> void:
	pass

func set_connected(is_host: bool) -> void:
	host_btn.disabled = true
	join_btn.disabled = true
	disconnect_btn.disabled = false
	push_scene_btn.disabled = false
	sync_settings_btn.disabled = false
	sync_files_btn.disabled = false

	if is_host:
		status_label.text = "Status: Peer Host Connected"
	else:
		status_label.text = "Status: Peer Client Connected"

func set_disconnected() -> void:
	host_btn.disabled = false
	join_btn.disabled = false
	disconnect_btn.disabled = true
	push_scene_btn.disabled = true
	sync_settings_btn.disabled = true
	sync_files_btn.disabled = true

	status_label.text = "Status: Disconnected"
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
