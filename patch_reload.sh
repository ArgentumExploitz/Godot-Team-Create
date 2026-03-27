cat << 'INNER_EOF' > patch_reload.patch
--- addons/team_create/scene_sync.gd
+++ addons/team_create/scene_sync.gd
@@ -677,9 +677,10 @@
			if file:
				file.store_buffer(bytes)
				file.close()
-			editor.reload_scene_from_path(path)
-			print("Team Create: Applying received scene to active view.")
			_is_reloading_scene = true
			_force_full_sync_next_frame = true
+
+			editor.reload_scene_from_path(path)
+			print("Team Create: Applying received scene to active view.")

			get_tree().create_timer(0.5).timeout.connect(func():
INNER_EOF
patch addons/team_create/scene_sync.gd < patch_reload.patch
