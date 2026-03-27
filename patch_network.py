import sys

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    orig = """	if data.has("candidates"):
		print("Adding ICE candidates to remote connection...")
		print("Adding ", data["candidates"].size(), " ICE candidates...")
		for cand in data["candidates"]:
			webrtc_connection.add_ice_candidate(cand["media"], cand["index"], cand["name"])"""

    new = """	if data.has("candidates"):
		print("Adding ICE candidates to remote connection...")
		print("Adding ", data["candidates"].size(), " ICE candidates...")
		for cand in data["candidates"]:
			if typeof(cand) == TYPE_DICTIONARY and cand.has("media") and cand.has("index") and cand.has("name"):
				webrtc_connection.add_ice_candidate(cand["media"], cand["index"], cand["name"])
			else:
				print("Invalid ICE candidate format.")"""

    content = content.replace(orig, new)

    with open(filepath, 'w') as f:
        f.write(content)

patch_file('addons/team_create/network.gd')
