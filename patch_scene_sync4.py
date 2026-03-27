import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    orig = """		if ResourceLoader.exists(pending.value):
			var editor = network.plugin.get_editor_interface()
			var current_scene = editor.get_edited_scene_root()
			if current_scene:
				var node = network.get_node_by_unique_id(current_scene, pending.id)
				if node:
					var res = load(pending.value)
					if res:
						node.set(pending.prop_name, res)
			_pending_resource_properties.remove_at(i)"""

    new = """		if ResourceLoader.exists(pending.value):
			var editor = network.plugin.get_editor_interface()
			var current_scene = editor.get_edited_scene_root()
			if current_scene and current_scene.scene_file_path == pending.scene_path:
				var node = network.get_node_by_unique_id(current_scene, pending.id)
				if is_instance_valid(node):
					var res = load(pending.value)
					if res:
						node.set(pending.prop_name, res)
			_pending_resource_properties.remove_at(i)"""

    content = content.replace(orig, new)

    with open(filepath, 'w') as f:
        f.write(content)

patch_file('addons/team_create/scene_sync.gd')
