with open('addons/team_create/scene_sync.gd', 'r') as f:
    content = f.read()

if "if is_instance_valid(node) and node != current_scene:" in content:
    print("Patch successful!")
else:
    print("Patch failed.")
