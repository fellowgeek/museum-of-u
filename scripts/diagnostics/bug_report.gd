extends RefCounted
## Versioned JSON contract and filesystem operations shared by capture and replay.
const VERSION := 1
const MAX_BYTES := 1024 * 1024

static func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func to_vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func valid_vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(func(n): return number(n) and absf(n) <= 10000000.0)

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func read_report(path: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(path): path = path.path_join("report.json")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Cannot read bug report: " + path}
	if file.get_length() > MAX_BYTES: return {"error": "Bug report exceeds 1 MiB"}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return {"error": "Invalid bug report JSON"}
	var error := validate_report(json.data)
	return {"error": error} if not error.is_empty() else {"report": json.data, "path": path}

static func validate_report(data: Variant) -> String:
	if not data is Dictionary: return "Bug report must be an object"
	if not number(data.get("report_version")) or data.report_version != VERSION:
		return "Unsupported bug report version"
	if not data.get("settings") is Dictionary: return "Bug report settings are missing"
	var seed_value: Variant = data.get("resolved_seed")
	if not number(seed_value) or seed_value != floor(seed_value) or seed_value < -2147483648 or seed_value > 2147483647:
		return "Bug report seed must be a signed 32-bit integer"
	for key in ["generator_version", "generation_id"]:
		if not data.get(key) is String or data[key].is_empty(): return "Missing " + key
	var pose: Variant = data.get("player")
	if not pose is Dictionary: return "Bug report player pose is missing"
	for key in ["position", "rotation", "neck_position", "neck_rotation", "camera_position", "camera_rotation", "velocity"]:
		if not valid_vector(pose.get(key)): return "Invalid player " + key
	for key in ["crouching", "flashlight_on"]:
		if not pose.get(key) is bool: return "Invalid player " + key
	for key in ["capsule_height", "stamina", "bob_timer", "camera_fov"]:
		if not number(pose.get(key)): return "Invalid player " + key
	if pose.capsule_height < 1.1 or pose.capsule_height > 1.8: return "Invalid player capsule height"
	if pose.stamina < 0 or pose.stamina > 10000 or absf(pose.bob_timer) > 10000000: return "Invalid player movement state"
	if pose.camera_fov < 1 or pose.camera_fov > 179: return "Invalid player camera FOV"
	return ""

static func write_json(path: String, data: Dictionary) -> Error:
	return write_text(path, JSON.stringify(data, "\t", true, true) + "\n")

static func write_text(path: String, contents: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	return file.get_error()

static func reserve_directory(root: String, prefix: String) -> String:
	if FileAccess.file_exists(root): return ""
	if DirAccess.make_dir_recursive_absolute(root) != OK: return ""
	# Keep generated captures out of source imports. This file is harmless in exports.
	write_text(root.path_join(".gdignore"), "")
	var next := 1
	for name in DirAccess.get_directories_at(root):
		var suffix := name.trim_prefix(prefix)
		if name.begins_with(prefix) and suffix.is_valid_int(): next = maxi(next, suffix.to_int() + 1)
	# mkdir reserves the number atomically, including between two running games.
	for offset in range(1000):
		var path := root.path_join("%s%03d" % [prefix, next + offset])
		var error := DirAccess.make_dir_absolute(path)
		if error == OK: return path
		if error != ERR_ALREADY_EXISTS: return ""
	return ""

static func save_bundle(root: String, report: Dictionary, image: Image) -> Dictionary:
	var path := reserve_directory(root, "bug-report-")
	if path.is_empty(): return {"error": "Cannot create report folder in " + root}
	var error := image.save_png(path.path_join("screenshot.png"))
	if error == OK: error = write_json(path.path_join("settings.json"), report.settings)
	if error == OK:
		error = write_text(path.path_join("REPLAY.txt"), "Replay with the same game build:\n  <game executable> -- --replay-bug \"<this report folder>\"\n\nFrom source:\n  godot --path <project> -- --replay-bug \"<this report folder>\"\n\nReplay starts paused at the saved camera pose. Press Enter to resume.\nreport.json is authoritative; settings.json is a standalone fixed-seed settings copy.\nGenerated geometry and player state are restored. Moved props, light flicker phase, audio phase, input history and streaming history are not restored.\nDescribe the observed and expected behavior when sharing this folder.\n")
	# The manifest is the completion marker; never expose a replayable partial capture.
	if error == OK: error = write_json(path.path_join("report.json"), report)
	if error != OK:
		for name in ["screenshot.png", "settings.json", "REPLAY.txt", "report.json"]:
			if FileAccess.file_exists(path.path_join(name)): DirAccess.remove_absolute(path.path_join(name))
		DirAccess.remove_absolute(path)
		return {"error": "Cannot finish bug report (error %d) in %s" % [error, root]}
	return {"path": path}

static func save_screenshot(root: String, image: Image) -> Dictionary:
	# Reserve a unique basename with a temporary directory, then keep just the PNG.
	var reservation := reserve_directory(root, ".capture-")
	if reservation.is_empty(): return {"error": "Cannot create screenshot in " + root}
	var base := "screenshot-" + Time.get_datetime_string_from_system(true).replace(":", "-") + "-" + reservation.get_file().trim_prefix(".capture-")
	var path := root.path_join(base + ".png")
	var suffix := 1
	while FileAccess.file_exists(path):
		path = root.path_join("%s-%d.png" % [base, suffix])
		suffix += 1
	var error := image.save_png(path)
	DirAccess.remove_absolute(reservation)
	if error != OK:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		return {"error": "Cannot save screenshot (error %d) in %s" % [error, root]}
	return {"path": path}
