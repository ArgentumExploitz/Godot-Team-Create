import re

with open('addons/team_create/file_sync.gd', 'r') as f:
    content = f.read()

# Add _known_files variable
content = re.sub(
    r'var _receiving_files: Dictionary = \{\}',
    r'var _receiving_files: Dictionary = {}\nvar _known_files: Array = []',
    content
)

# Update _on_filesystem_changed()
on_fs_changed_new = """func _on_filesystem_changed():
\tif _is_syncing_files or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
\t\treturn

\t# Automatically sync files whenever Godot detects a local file system change.
\tsync_all_files()

\t# Check for local deletions and broadcast them
\tvar current_files = get_all_files("res://")
\tfor known_path in _known_files:
\t\tif not current_files.has(known_path):
\t\t\trpc("remote_delete_file", known_path)
\t
\t_known_files = current_files.duplicate()"""

content = re.sub(
    r'func _on_filesystem_changed\(\):.*?sync_all_files\(\)',
    on_fs_changed_new,
    content,
    flags=re.DOTALL
)

# Update compare_and_sync_files
content = re.sub(
    r'downloading_files\.append_array\(files_to_request\)',
    r'downloading_files.append_array(files_to_request)\n\n\t_known_files = local_files.duplicate()',
    content
)

# Also in receive_file
content = re.sub(
    r'\t\t\tsync_completed\.emit\(\)',
    r'\t\t\t_known_files = get_all_files("res://")\n\t\t\tsync_completed.emit()',
    content
)

# Add remote_delete_file RPC
remote_delete = """
@rpc("any_peer", "reliable")
func remote_delete_file(path: String):
\tif multiplayer.get_remote_sender_id() != 1:
\t\treturn # Only server can dictate deletions for security
\t
\tif path.begins_with("res://addons/team_create") or path.begins_with("res://.godot") or path.begins_with("res://webrtc"):
\t\treturn
\tif not path.begins_with("res://") or ".." in path:
\t\treturn
\t
\tif FileAccess.file_exists(path):
\t\tDirAccess.remove_absolute(path)
\t\tprint("Team Create: Replicated file deletion: ", path)
\t\t
\t\t# Remove from known files
\t\tif _known_files.has(path):
\t\t\t_known_files.erase(path)
"""

content += remote_delete

with open('addons/team_create/file_sync.gd', 'w') as f:
    f.write(content)
