import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # In `remote_node_removed`
    orig = """		var node = network.get_node_by_unique_id(current_scene, id)
		if node and node != current_scene:
			_node_names.erase(node.get_instance_id())
			node.get_parent().remove_child(node)
			node.queue_free()"""

    new = """		var node = network.get_node_by_unique_id(current_scene, id)
		if is_instance_valid(node) and node != current_scene:
			_node_names.erase(node.get_instance_id())
			var parent = node.get_parent()
			if is_instance_valid(parent):
				parent.remove_child(node)
			node.queue_free()"""

    content = content.replace(orig, new)

    with open(filepath, 'w') as f:
        f.write(content)

patch_file('addons/team_create/scene_sync.gd')
