extends RefCounted
## Select the visitor's library and install the bundled originals into an empty album.
const SAMPLES := "res://sample"
const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
static var _setup_mutex := Mutex.new()

static func photo_directory() -> String:
	var source_run := not OS.has_feature("template")
	var install := SettingsLoader.default_path(OS.get_executable_path(), source_run, ProjectSettings.globalize_path("res://")).get_base_dir()
	var user_home := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	if user_home.is_empty() and OS.get_name() == "Windows":
		user_home = OS.get_environment("HOMEDRIVE") + OS.get_environment("HOMEPATH")
	if user_home.is_empty(): user_home = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).get_base_dir()
	return select_directory(OS.get_cmdline_user_args(), user_home, install, source_run)

static func select_directory(args: PackedStringArray, user_home: String, install: String, source_run := false) -> String:
	for i in args.size():
		var override := ""
		if args[i].begins_with("--photos="): override = args[i].trim_prefix("--photos=")
		elif args[i] == "--photos" and i + 1 < args.size() and not args[i + 1].begins_with("--"):
			override = args[i + 1]
		if not override.is_empty():
			var path := ProjectSettings.globalize_path(override)
			if not path.is_absolute_path(): path = DirAccess.open(".").get_current_dir().path_join(path)
			return path.simplify_path()
	var personal := user_home.path_join("Museum of U").simplify_path()
	if DirAccess.dir_exists_absolute(personal): return personal
	for name in ["photos", "Photos"]:
		var portable := install.path_join(name)
		if DirAccess.dir_exists_absolute(portable):
			# An empty portable folder with a scan guard should not override the home library.
			if source_run and FileAccess.file_exists(portable.path_join(".gdignore")) and not contains_photos(portable):
				continue
			return portable
	return personal

static func contains_photos(folder: String) -> bool:
	return not photo_paths(folder, true).is_empty()

static func photo_paths(folder: String, first_only := false, rejected: Array = []) -> PackedStringArray:
	var result := PackedStringArray()
	var pending: Array[String] = [""]
	while not pending.is_empty():
		var relative: String = pending.pop_back()
		var path := folder.path_join(relative)
		var dir := DirAccess.open(path)
		if dir == null:
			rejected.append({"path":path, "reason":"Cannot read folder"})
			continue
		for name in dir.get_files():
			if not name.begins_with(".") and name.get_extension().to_lower() in EXTENSIONS and not dir.is_link(name):
				result.append(relative.path_join(name))
				if first_only: return result
		for name in dir.get_directories():
			if not name.begins_with(".") and not dir.is_link(name): pending.append(relative.path_join(name))
	return result

static func prepare(folder: String, samples := SAMPLES) -> Error:
	# The title screen and a visit can both request the first-run album.
	_setup_mutex.lock()
	var problem := DirAccess.make_dir_recursive_absolute(folder)
	if problem == OK and not contains_photos(folder): problem = _install_samples(folder, samples)
	_setup_mutex.unlock()
	return problem

static func _install_samples(folder: String, samples: String) -> Error:
	var originals := photo_paths(samples)
	if originals.is_empty(): return ERR_FILE_NOT_FOUND
	var destination := DirAccess.open(folder)
	if destination == null: return DirAccess.get_open_error()
	var album := "Sample"
	var number := 1
	while destination.dir_exists(album) or destination.file_exists(album) or destination.is_link(album):
		number += 1
		album = "Sample %d" % number
	# Publish the whole album together so a gallery scan sees a complete collection.
	var staging := folder.path_join(".museum-samples-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var problem := DirAccess.make_dir_absolute(staging)
	if problem != OK: return problem
	for relative in originals:
		var target := staging.path_join(relative)
		problem = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if problem == OK: problem = _copy_original(samples.path_join(relative), target)
		if problem != OK: break
	if problem == OK and not contains_photos(folder):
		problem = DirAccess.rename_absolute(staging, folder.path_join(album))
		if problem == OK: return OK
		if contains_photos(folder): problem = OK
	_discard_staging(staging)
	return problem

static func _copy_original(source: String, target: String) -> Error:
	# FileAccess can read the original from a mounted PCK as well as from the editor.
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null: return FileAccess.get_open_error()
	var output := FileAccess.open(target, FileAccess.WRITE)
	if output == null: return FileAccess.get_open_error()
	var remaining := input.get_length()
	while remaining > 0:
		var count := mini(remaining, 1024 * 1024)
		var bytes := input.get_buffer(count)
		if bytes.size() != count: return ERR_FILE_CANT_READ
		if not output.store_buffer(bytes): return ERR_FILE_CANT_WRITE
		remaining -= count
	output.flush()
	return output.get_error()

static func _discard_staging(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for name in dir.get_files(): dir.remove(name)
	for name in dir.get_directories():
		if dir.is_link(name): dir.remove(name)
		else: _discard_staging(path.path_join(name))
	DirAccess.remove_absolute(path)
