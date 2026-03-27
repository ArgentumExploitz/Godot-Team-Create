import re

with open('addons/team_create/file_sync.gd', 'r') as f:
    content = f.read()

content = content.replace("""			if _pending_files_to_receive <= 0:
				call_deferred("_hide_sync_blocker")
				call_deferred("_hide_sync_blocker")
				_known_files = get_all_files("res://")
				sync_completed.emit()""", """			if _pending_files_to_receive <= 0:
				call_deferred("_hide_sync_blocker")
				_known_files = get_all_files("res://")
				sync_completed.emit()""")

with open('addons/team_create/file_sync.gd', 'w') as f:
    f.write(content)
