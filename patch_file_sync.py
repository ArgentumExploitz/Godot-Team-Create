import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # file_sync.gd
    content = content.replace(
        '''\tvar bytes = FileAccess.get_file_as_bytes(path)\n\tif bytes:''',
        '''\tif FileAccess.file_exists(path):\n\t\tvar bytes = FileAccess.get_file_as_bytes(path)'''
    )

    with open(filepath, 'w') as f:
        f.write(content)

patch_file('addons/team_create/file_sync.gd')
