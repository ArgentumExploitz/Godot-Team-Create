@tool
extends EditorPlugin

var dock: Control
var network: Node

func _enter_tree() -> void:
	print("Team Create initialized.")

	# Load UI script and instantiate it.
	# We're building the UI dynamically to ensure stability and match the screenshot.
	var ui_script = preload("res://addons/team_create/ui.gd")
	dock = ui_script.new()
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

	# Load network manager script and instantiate it as a child.
	var network_script = preload("res://addons/team_create/network.gd")
	network = network_script.new()
	add_child(network)

	# Link UI and network
	dock.network = network
	network.ui = dock

	network.plugin = self

func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
	if network:
		network.queue_free()
