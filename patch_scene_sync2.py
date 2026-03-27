import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # scene_sync.gd request_scene_state
    content = content.replace(
        '''\t\t\t\tvar bytes = FileAccess.get_file_as_bytes(temp_path)\n\t\t\t\tif bytes:''',
        '''\t\t\t\tif FileAccess.file_exists(temp_path):\n\t\t\t\t\tvar bytes = FileAccess.get_file_as_bytes(temp_path)'''
    )

    with open(filepath, 'w') as f:
        f.write(content)

patch_file('addons/team_create/scene_sync.gd')
