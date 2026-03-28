extends Node

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
