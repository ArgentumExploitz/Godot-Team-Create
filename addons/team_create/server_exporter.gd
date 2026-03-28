@tool
extends Node

const SERVER_SCRIPT_TEMPLATE = """extends Node
class DummyEditorInterface:
	func get_editor_settings():
		return self
	func has_setting(name):
		return false
	func get_setting(name):
		return ""
	func set_setting(name, val):
		pass
	func get_resource_filesystem():
		return self
	func is_scanning():
		return false
	func scan():
		pass
	func get_edited_scene_root():
		return null
	func get_editor_main_screen():
		var n = Node.new()
		n.name = "DummyMainScreen"
		return n
	func open_scene_from_path(path):
		pass
	func reload_scene_from_path(path):
		pass
	func save_scene():
		pass
	func mark_scene_as_unsaved():
		pass

class DummyEditorPlugin extends Node:
	var ei = DummyEditorInterface.new()
	func get_editor_interface():
		return ei

func _ready():
	print("Starting Godot Team Create Headless Server...")
	var network_script = load("res://addons/team_create/network.gd")
	if not network_script:
		print("Failed to load network.gd")
		get_tree().quit(1)
		return

	var network = network_script.new()
	network.name = "TeamCreateNetwork"

	var dummy_plugin = DummyEditorPlugin.new()
	dummy_plugin.name = "DummyPlugin"
	add_child(dummy_plugin)

	network.plugin = dummy_plugin
	get_tree().root.call_deferred("add_child", network)

	print("Hosting server on port ", network.PORT)
	network.call_deferred("host_server")
"""

const TSCN_TEMPLATE = """[gd_scene load_steps=2 format=3 uid="uid://teamcreateserver01"]

[ext_resource type="Script" path="res://addons/team_create/server.gd" id="1_1"]

[node name="Server" type="Node"]
script = ExtResource("1_1")
"""

const PRESETS_TEMPLATE = """[preset.0]
name="Linux/X11"
platform="Linux/X11"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="TeamCreateServer.x86_64"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=1

[preset.0.options]
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/embed_pck=false

[preset.1]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="TeamCreateServer.exe"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=1

[preset.1.options]
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/embed_pck=false
"""

const PROJECT_TEMPLATE = """; Engine configuration file.
config_version=5

[application]
config/name="Team Create Server"
run/main_scene="res://addons/team_create/server.tscn"
config/features=PackedStringArray("4.3", "Forward Plus")

[editor_plugins]
enabled=PackedStringArray("res://addons/team_create/plugin.cfg")
"""

static func copy_dir_recursive(from_path: String, to_path: String) -> void:
	if not DirAccess.dir_exists_absolute(from_path):
		return
	if not DirAccess.dir_exists_absolute(to_path):
		DirAccess.make_dir_recursive_absolute(to_path)

	var dir = DirAccess.open(from_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				if dir.current_is_dir():
					copy_dir_recursive(from_path + "/" + file_name, to_path + "/" + file_name)
				else:
					var f_in = FileAccess.open(from_path + "/" + file_name, FileAccess.READ)
					var f_out = FileAccess.open(to_path + "/" + file_name, FileAccess.WRITE)
					if f_in and f_out:
						f_out.store_buffer(f_in.get_buffer(f_in.get_length()))
						f_in.close()
						f_out.close()
			file_name = dir.get_next()
		dir.list_dir_end()

static func export_server(target_dir: String, caller_ui: Control) -> void:
	print("Exporting Standalone Server to: ", target_dir)
	caller_ui.export_btn.text = "Exporting Server..."
	caller_ui.export_btn.disabled = true

	# Create a temporary project directory
	var temp_dir = OS.get_user_data_dir() + "/team_create_server_export"
	if DirAccess.dir_exists_absolute(temp_dir):
		# Clean it up first
		var d = DirAccess.open(temp_dir)
		if d:
			# Not full recursive delete implemented, just making sure it exists.
			# Best to just create unique name or assume overwrite is fine.
			pass
	else:
		DirAccess.make_dir_recursive_absolute(temp_dir)

	# Copy plugin files
	var plugin_dest = temp_dir + "/addons/team_create"
	DirAccess.make_dir_recursive_absolute(plugin_dest)

	copy_dir_recursive("res://addons/team_create", plugin_dest)

	# Overwrite with server specific files
	var script_file = FileAccess.open(plugin_dest + "/server.gd", FileAccess.WRITE)
	if script_file:
		script_file.store_string(SERVER_SCRIPT_TEMPLATE)
		script_file.close()

	var tscn_file = FileAccess.open(plugin_dest + "/server.tscn", FileAccess.WRITE)
	if tscn_file:
		tscn_file.store_string(TSCN_TEMPLATE)
		tscn_file.close()

	var proj_file = FileAccess.open(temp_dir + "/project.godot", FileAccess.WRITE)
	if proj_file:
		proj_file.store_string(PROJECT_TEMPLATE)
		proj_file.close()

	var preset_file = FileAccess.open(temp_dir + "/export_presets.cfg", FileAccess.WRITE)
	if preset_file:
		preset_file.store_string(PRESETS_TEMPLATE)
		preset_file.close()

	var godot_exec = OS.get_executable_path()

	print("Building Linux Server via OS.execute...")
	var linux_args = ["--path", temp_dir, "--headless", "--export-release", "Linux/X11", target_dir + "/TeamCreateServer.x86_64"]
	var linux_out = []
	OS.execute(godot_exec, linux_args, linux_out, true)
	print(linux_out)

	print("Building Windows Server via OS.execute...")
	var win_args = ["--path", temp_dir, "--headless", "--export-release", "Windows Desktop", target_dir + "/TeamCreateServer.exe"]
	var win_out = []
	OS.execute(godot_exec, win_args, win_out, true)
	print(win_out)

	print("Export complete! Built executables in: " + target_dir)
	caller_ui.export_btn.text = "Export Headless Server"
	caller_ui.export_btn.disabled = false
