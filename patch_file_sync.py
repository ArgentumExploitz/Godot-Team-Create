import re

with open("addons/team_create/file_sync.gd", "r") as f:
    content = f.read()

# Fix request_file sending empty bytes -> fixed to check if total_size == 0
# Actually receive_file should check bytes.size() > 0 before FileAccess.WRITE

# In receive_file
old_write_file = """	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
		print("Received file: ", path)"""

new_write_file = """	if bytes.size() > 0:
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
			file.close()
			print("Received file: ", path)"""

content = content.replace(old_write_file, new_write_file)

# We also have an intercept block for open scenes in receive_file:
old_intercept_write = """			var file = FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_buffer(bytes)
				file.close()"""

new_intercept_write = """			if bytes.size() > 0:
				var file = FileAccess.open(path, FileAccess.WRITE)
				if file:
					file.store_buffer(bytes)
					file.close()"""

content = content.replace(old_intercept_write, new_intercept_write)

with open("addons/team_create/file_sync.gd", "w") as f:
    f.write(content)
