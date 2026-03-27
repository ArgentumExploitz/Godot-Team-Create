with open('addons/team_create/scene_sync.gd', 'r') as f:
    content = f.read()

if "var tree = current_scene.get_tree()" in content:
    print("Patch successful!")
else:
    print("Patch failed.")
