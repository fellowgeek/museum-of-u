extends RefCounted
class_name SettingsLoader

const Schema = preload("res://scripts/settings/settings_schema.gd")
const BugReport = preload("res://scripts/diagnostics/bug_report.gd")
const MAX_BYTES := 256 * 1024
const PRESETS := {
	"high": {},
	"medium": {"render.scale": 0.85, "render.msaa": 2, "render.mesh_lod_threshold": 2.0,
		"environment.ssao.enabled": false},
	"low": {"render.scale": 0.65, "render.msaa": 0, "render.fxaa": true,
		"render.mesh_lod_threshold": 4.0, "environment.ssao.enabled": false,
		"environment.fog.enabled": false,
		"lighting.shadows_enabled": false}
}
var warnings: Array[String] = []
var selected_path := ""
var report_path := "user://last-run.settings.json"
var replay_report: Dictionary = {}
var fatal_error := ""

static func default_path(executable: String, source_run: bool, project_dir: String) -> String:
	if source_run: return project_dir.path_join("museum.settings.json")
	var directory := executable.get_base_dir()
	if directory.get_file() == "MacOS" and directory.get_base_dir().get_file() == "Contents":
		var bundle := directory.get_base_dir().get_base_dir()
		if bundle.ends_with(".app"): directory = bundle.get_base_dir()
	return directory.path_join("museum.settings.json")

# Version-one snapshots included settings for rooms outside the museum.
static func migrate(raw: Dictionary) -> Dictionary:
	if raw.get("schema_version") != 1: return raw
	var result := supported_fields(raw, Schema.defaults())
	if raw.get("diagnostics") is Dictionary:
		for flag in ["toggle_enabled", "visible"]:
			if raw.diagnostics.has("sound_triggers_" + flag):
				Schema.put(result, "diagnostics.overlay_" + flag, raw.diagnostics["sound_triggers_" + flag])
	result.schema_version = 2
	return result

static func supported_fields(raw: Dictionary, template: Dictionary) -> Dictionary:
	var result := {}
	for key in template:
		if not raw.has(key): continue
		if template[key] is Dictionary and raw[key] is Dictionary:
			result[key] = supported_fields(raw[key], template[key])
		else:
			result[key] = raw[key]
	return result

func load_file(path: String) -> Dictionary:
	selected_path = path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if FileAccess.get_open_error() != ERR_FILE_NOT_FOUND:
			warnings.append("Cannot read settings at %s (error %s); using defaults" % [path, FileAccess.get_open_error()])
		return {}
	if file.get_length() > MAX_BYTES:
		warnings.append("Settings exceed 256 KiB; using defaults")
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		warnings.append("JSON line %d: %s; using defaults" % [json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		warnings.append("Settings root must be an object; using defaults")
		return {}
	return json.data

func load_launch(args: PackedStringArray, executable: String, source_run: bool, project_dir: String) -> Dictionary:
	warnings.clear()
	replay_report.clear()
	fatal_error = ""
	report_path = "user://last-run.settings.json"
	var path := default_path(executable, source_run, project_dir)
	if not FileAccess.file_exists(path):
		var previous := path.get_base_dir().path_join("backrooms.settings.json")
		if FileAccess.file_exists(previous): path = previous
	var replay_path := ""
	var replay_requested := false
	var settings_override := false
	var cli: Dictionary = {}
	var i := 0
	while i < args.size():
		var arg := args[i]
		var option := arg.get_slice("=", 0)
		if option in ["--world-settings", "--seed", "--quality", "--settings-report", "--replay-bug"]:
			if option == "--replay-bug": replay_requested = true
			if option in ["--world-settings", "--seed", "--quality"]: settings_override = true
			var value := ""
			if arg.contains("="):
				value = arg.substr(arg.find("=") + 1)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				i += 1
				value = args[i]
			if value.is_empty():
				warnings.append("Missing value for %s; ignored" % option)
			else:
				match option:
					"--replay-bug": replay_path = value
					"--world-settings": path = value
					"--seed":
						if value.is_valid_int() and value.to_int() >= -2147483648 and value.to_int() <= 2147483647:
							cli["world.seed"] = value.to_int()
							cli["world.seed_mode"] = "fixed"
						else: warnings.append("--seed requires a signed 32-bit integer; ignored")
					"--quality":
						if PRESETS.has(value): cli["render.quality"] = value
						else: warnings.append("--quality requires low, medium, or high; ignored")
					"--settings-report":
						if value.begins_with("user://") and not ".." in value:
							report_path = value
						else: warnings.append("--settings-report must stay inside user://; using default report path")
		elif option == "--photos":
			if not arg.contains("=") and i + 1 < args.size() and not args[i+1].begins_with("--"): i += 1
		elif arg in ["--vr", "--vr-performance"]:
			pass
		elif arg.begins_with("--"):
			warnings.append("Unknown user argument %s; ignored" % arg)
		i += 1
	if replay_requested:
		if replay_path.is_empty() or settings_override:
			fatal_error = "--replay-bug requires a report path and cannot be combined with --world-settings, --seed or --quality"
			return Schema.defaults()
		var result := BugReport.read_report(replay_path)
		if result.has("error"):
			fatal_error = result.error
			return Schema.defaults()
		var raw_settings: Dictionary = result.report.settings.duplicate(true)
		raw_settings = migrate(raw_settings)
		if raw_settings.get("display") is Dictionary and not raw_settings.display.has("resolution"):
			raw_settings.display.resolution = "native"
		# A replay must not silently substitute defaults for missing or invalid fields.
		for key: String in Schema.RULES:
			var cursor: Variant = raw_settings
			for part in key.split("."):
				cursor = cursor.get(part) if cursor is Dictionary else null
			# Additive fields preserve old presentation/geometry when omitted.
			if cursor == null and (key == "layout.museum_annexes" or key.begins_with("audio.music.")): continue
			if not valid_leaf(cursor, Schema.RULES[key]):
				fatal_error = "Replay has missing or invalid setting: " + key
				return Schema.defaults()
		var warning_start := warnings.size()
		var validated := validate(raw_settings)
		if warnings.size() != warning_start or validated.world.seed_mode != "fixed" or validated.world.seed != result.report.resolved_seed:
			fatal_error = "Replay settings are inconsistent; use the original complete report and matching game build"
			return Schema.defaults()
		replay_report = result.report
		selected_path = result.path
		return validated
	var raw := migrate(load_file(path))
	if raw.has("schema_version") and not valid_leaf(raw.schema_version, Schema.RULES.schema_version):
		warnings.append("Unsupported schema_version; rejecting file before CLI overrides")
		raw = {}
	for key: String in cli: Schema.put(raw, key, cli[key])
	# New launches include the collection galleries. Older saved/replayed snapshots
	# bypass this launch default and retain their original geometry and identity.
	if raw.get("layout", {}) is Dictionary and not raw.get("layout", {}).has("museum_annexes"):
		Schema.put(raw, "layout.museum_annexes", true)
	return validate(raw)

func validate(raw: Dictionary) -> Dictionary:
	raw = migrate(raw)
	var defaults := Schema.defaults()
	if raw.has("schema_version") and not valid_leaf(raw.schema_version, Schema.RULES.schema_version):
		warnings.append("Unsupported schema_version; rejecting entire file")
		return defaults
	var explicit: Dictionary = {}
	_collect(raw, defaults, "", explicit)
	var quality: String = explicit.get("render.quality", "high")
	var result := defaults.duplicate(true)
	for path: String in PRESETS[quality]: Schema.put(result, path, PRESETS[quality][path])
	for path: String in explicit: Schema.put(result, path, explicit[path])
	var movement: Dictionary = result.player.movement
	if movement.crouch_speed > movement.walk_speed or movement.walk_speed > movement.sprint_speed:
		result.player.movement = defaults.player.movement.duplicate(true)
		warnings.append("player.movement requires crouch <= walk <= sprint; restored group")
	return result

func _collect(raw: Dictionary, defaults: Dictionary, prefix: String, explicit: Dictionary) -> void:
	for key: String in raw:
		var path := key if prefix.is_empty() else prefix + "." + key
		if not defaults.has(key):
			warnings.append("Unknown setting %s; ignored" % path)
		elif defaults[key] is Dictionary:
			if raw[key] is Dictionary: _collect(raw[key], defaults[key], path, explicit)
			else: warnings.append("%s requires an object; using defaults" % path)
		elif valid_leaf(raw[key], Schema.RULES[path]):
			if defaults[key] is int: explicit[path] = int(raw[key])
			elif defaults[key] is float: explicit[path] = float(raw[key])
			elif defaults[key] is Array: explicit[path] = raw[key].map(func(component): return float(component))
			else: explicit[path] = raw[key]
		else:
			# Invalid explicit values restore the built-in field, even under a preset.
			explicit[path] = defaults[key]
			warnings.append("%s invalid value %s; expected %s; using default" % [path, str(raw[key]), str(Schema.RULES[path])])

static func valid_leaf(value: Variant, rule: Array) -> bool:
	var fallback: Variant = rule[0]
	if fallback is bool: return value is bool
	if fallback is String: return value is String and value in rule[1]
	if fallback is Array:
		if not value is Array or value.size() != 3: return false
		for component in value:
			if not _number(component) or float(component) < 0.0 or float(component) > 1.0: return false
		return true
	if not _number(value): return false
	if fallback is int and float(value) != floor(float(value)): return false
	if rule.size() == 2:
		return rule[1].any(func(choice): return float(choice) == float(value))
	return float(value) >= float(rule[1]) and float(value) <= float(rule[2])

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
