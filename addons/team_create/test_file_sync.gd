extends SceneTree

# Standard standalone test runner for get_all_files in file_sync.gd

func _init():
	print("--- Running tests for file_sync.gd:get_all_files ---")

	var file_sync_script = load("res://addons/team_create/file_sync.gd")
	if not file_sync_script:
		printerr("FAIL: Could not load file_sync.gd")
		quit(1)
		return

	var file_sync = file_sync_script.new()

	var test_root = "user://test_file_sync_tmp"
	# Ensure the directory exists as a proper global path if needed,
	# but user:// should work with DirAccess.
	setup_test_env(test_root)

	var success = true

	# Test case 1: Basic file listing and recursion
	print("Running Test Case 1: Basic listing and recursion...")
	var files = file_sync.get_all_files(test_root)
	print("Found files: ", files)

	var expected_files = [
		test_root.path_join("file1.txt"),
		test_root.path_join("sub/file2.txt"),
		test_root.path_join("script.gd"), # from script.gd.tmp
		test_root.path_join("data.res"), # from data.tmp
	]

	for expected in expected_files:
		if not expected in files:
			printerr("FAIL: Expected file not found: ", expected)
			success = false

	for f in files:
		if ".hidden" in f or ".godot" in f:
			printerr("FAIL: Hidden file or directory was included: ", f)
			success = false

		if "excluded" in f and not "exclude_dirs" in f: # 'excluded' dir should be included if not in exclude_dirs
			pass

	# Test case 2: Custom exclusion
	print("Running Test Case 2: Custom exclusion...")
	var excluded_dir = test_root.path_join("excluded")
	var files_with_excl = file_sync.get_all_files(test_root, [excluded_dir])

	for f in files_with_excl:
		if f.begins_with(excluded_dir):
			printerr("FAIL: Excluded directory file was included: ", f)
			success = false

	# Test case 3: .tmp file handling
	print("Running Test Case 3: .tmp file renaming...")
	# This was already covered by expected_files in TC1, but let's be explicit
	if FileAccess.file_exists(test_root.path_join("script.gd.tmp")):
		printerr("FAIL: script.gd.tmp was not renamed")
		success = false
	if not FileAccess.file_exists(test_root.path_join("script.gd")):
		printerr("FAIL: script.gd does not exist after rename")
		success = false

	cleanup_test_env(test_root)

	if success:
		print("--- ALL TESTS PASSED ---")
	else:
		print("--- TESTS FAILED ---")

	quit(0 if success else 1)

func setup_test_env(path: String):
	cleanup_test_env(path) # Ensure clean start
	DirAccess.make_dir_recursive_absolute(path)
	DirAccess.make_dir_recursive_absolute(path.path_join("sub"))
	DirAccess.make_dir_recursive_absolute(path.path_join("excluded"))
	DirAccess.make_dir_recursive_absolute(path.path_join(".godot"))

	create_file(path.path_join("file1.txt"))
	create_file(path.path_join("sub/file2.txt"))
	create_file(path.path_join("excluded/file3.txt"))
	create_file(path.path_join(".hidden"))
	create_file(path.path_join("script.gd.tmp"))
	create_file(path.path_join("data.tmp"))

func create_file(path: String):
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("test")
		f.close()

func cleanup_test_env(path: String):
	if DirAccess.dir_exists_absolute(path):
		remove_recursive(path)

func remove_recursive(path: String):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				remove_recursive(path.path_join(file_name))
			else:
				DirAccess.remove_absolute(path.path_join(file_name))
			file_name = dir.get_next()
		DirAccess.remove_absolute(path)
