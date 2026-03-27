import re

with open('addons/team_create/file_sync.gd', 'r') as f:
    content = f.read()

# Fix receive_file so we set _known_files before emitting
content = re.sub(
    r'\t\t\t\t_known_files = get_all_files\("res://"\)\n\t\t\tsync_completed\.emit\(\)',
    r'\t\t\t\tcall_deferred("_hide_sync_blocker")\n\t\t\t\t_known_files = get_all_files("res://")\n\t\t\t\tsync_completed.emit()\n',
    content
)

# Fix receive_file the other place
content = content.replace("""			if _pending_files_to_receive <= 0:
				call_deferred("_hide_sync_blocker")
				_known_files = get_all_files("res://")
			sync_completed.emit()""", """			if _pending_files_to_receive <= 0:
				call_deferred("_hide_sync_blocker")
				_known_files = get_all_files("res://")
				sync_completed.emit()""")

with open('addons/team_create/file_sync.gd', 'w') as f:
    f.write(content)
