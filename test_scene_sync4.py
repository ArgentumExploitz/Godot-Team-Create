with open('addons/team_create/scene_sync.gd', 'r') as f:
    content = f.read()

if "if current_scene and current_scene.scene_file_path == pending.scene_path:" in content:
    print("Patch successful!")
else:
    print("Patch failed.")
