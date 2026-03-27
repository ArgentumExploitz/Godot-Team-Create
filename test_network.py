with open('addons/team_create/network.gd', 'r') as f:
    content = f.read()

if "if typeof(cand) == TYPE_DICTIONARY and cand.has(\"media\") and cand.has(\"index\") and cand.has(\"name\"):" in content:
    print("Patch successful!")
else:
    print("Patch failed.")
