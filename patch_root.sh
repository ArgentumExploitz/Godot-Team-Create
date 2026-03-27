cat << 'INNER_EOF' > patch_root.patch
--- addons/team_create/scene_sync.gd
+++ addons/team_create/scene_sync.gd
@@ -69,7 +69,9 @@
		elif current_scene:
			scene_path = current_scene.scene_file_path

-		var root_node = current_scene
+		var root_node = node.owner if node.owner else current_scene
+		if node == current_scene:
+			root_node = node

		_pre_removal_paths[node.get_instance_id()] = {"id": network.assign_unique_id(node), "scene_path": scene_path, "root_node": root_node}
INNER_EOF
patch addons/team_create/scene_sync.gd < patch_root.patch
