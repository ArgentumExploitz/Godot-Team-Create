import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # scene_sync.gd push_current_scene and push_current_scene_to_peer
    content = content.replace(
        '''\t\t\t\tvar bytes = FileAccess.get_file_as_bytes(path)\n\t\t\t\tif bytes:''',
        '''\t\t\t\tif FileAccess.file_exists(path):\n\t\t\t\t\tvar bytes = FileAccess.get_file_as_bytes(path)'''
    )

    with open(filepath, 'w') as f:
        f.write(content)

patch_file('addons/team_create/scene_sync.gd')
