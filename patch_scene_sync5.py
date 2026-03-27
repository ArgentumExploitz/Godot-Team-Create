import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # In update_peer_selection
    orig_update_clear = """	# Clear previous indicators
	for node in current_scene.get_tree().get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
		node.queue_free()"""

    new_update_clear = """	# Clear previous indicators
	var tree = current_scene.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
			if is_instance_valid(node):
				node.queue_free()"""

    content = content.replace(orig_update_clear, new_update_clear)

    # In update_peer_selection - outline adding loop
    orig_update_add_1 = """				outline.mesh = box_mesh
				outline.material_override = mat
				node.add_child(outline)"""
    new_update_add_1 = """				outline.mesh = box_mesh
				outline.material_override = mat
				if is_instance_valid(node) and node.is_inside_tree():
					node.add_child(outline)"""
    content = content.replace(orig_update_add_1, new_update_add_1)

    orig_update_add_2 = """				# Ensure it doesn't block mouse
				outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
				node.add_child(outline)"""
    new_update_add_2 = """				# Ensure it doesn't block mouse
				outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if is_instance_valid(node) and node.is_inside_tree():
					node.add_child(outline)"""
    content = content.replace(orig_update_add_2, new_update_add_2)


    # In clear_peer_selections
    orig_clear = """	for node in current_scene.get_tree().get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
		node.queue_free()"""
    new_clear = """	var tree = current_scene.get_tree()
	if tree:
		for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines_" + str(peer_id)):
			if is_instance_valid(node):
				node.queue_free()"""
    content = content.replace(orig_clear, new_clear)


    # In request_scene_state
    orig_request_state = """		# Temporarily remove selection outlines so they aren't packed
		var outlines = []
		for node in current_scene.get_tree().get_nodes_in_group("TeamCreateSelectionOutlines"):
			outlines.append({"node": node, "parent": node.get_parent()})"""

    new_request_state = """		# Temporarily remove selection outlines so they aren't packed
		var outlines = []
		var tree = current_scene.get_tree()
		if tree:
			for node in tree.get_nodes_in_group("TeamCreateSelectionOutlines"):
				if is_instance_valid(node):
					outlines.append({"node": node, "parent": node.get_parent()})"""

    content = content.replace(orig_request_state, new_request_state)


    # In request_scene_state restore loop
    orig_restore = """		# Restore outlines
		for data in outlines:
			data["parent"].add_child(data["node"])"""

    new_restore = """		# Restore outlines
		for data in outlines:
			if is_instance_valid(data["parent"]) and is_instance_valid(data["node"]):
				data["parent"].add_child(data["node"])"""

    content = content.replace(orig_restore, new_restore)


    with open(filepath, 'w') as f:
        f.write(content)

patch_file('addons/team_create/scene_sync.gd')
