extends RefCounted
## Versioned ownership is shared by preferences, presets, and settings screens.
const VERSION := 1
const GALLERY_AUDIO := ["audio.master.gain_db", "audio.music.gain_db", "audio.footsteps.gain_db", "audio.impacts.gain_db"]
const GALLERY_TABS := ["Display", "Graphics", "Audio", "Controls & Comfort"]

static func category(path: String) -> String:
	if path.begins_with("display."): return "Display"
	if path.begins_with("render.") or path in ["lighting.shadows_enabled", "environment.ssao.enabled", "environment.fog.enabled"]: return "Graphics"
	if path.begins_with("audio.") and (path.ends_with(".gain_db") or path.ends_with(".muted")): return "Audio"
	if path.begins_with("player.camera.") or path == "ui.show_controls_guide": return "Controls & Comfort"
	return ""

static func get_value(data: Dictionary, path: String) -> Variant:
	var value: Variant = data
	for part in path.split("."):
		if not value is Dictionary or not value.has(part): return null
		value = value[part]
	return value

static func strict(data: Dictionary, complete := true) -> String:
	data = SettingsLoader.migrate(data)
	var loader := SettingsLoader.new()
	loader.validate(data)
	if not loader.warnings.is_empty(): return "\n".join(loader.warnings)
	if complete:
		for path in SettingsSchema.RULES:
			if path.begins_with("audio.music."): continue # Optional in older saved visits.
			if path in ["display.resolution", "layout.museum_annexes"]: continue
			if get_value(data, path) == null: return "Missing setting: " + path
	return ""

static func select(data: Dictionary, categories: Array) -> Dictionary:
	var result := {}
	for path in SettingsSchema.RULES:
		if category(path) in categories:
			var value: Variant = get_value(data, path)
			if value != null: SettingsSchema.put(result, path, value)
	return result

static func overlay(base: Dictionary, partial: Dictionary, categories: Array) -> Dictionary:
	var result := base.duplicate(true)
	var tier: Variant = get_value(partial,"render.quality")
	if "Graphics" in categories and tier is String and SettingsLoader.PRESETS.has(tier): quality(result,tier)
	for path in SettingsSchema.RULES:
		if category(path) not in categories: continue
		var value: Variant = get_value(partial, path)
		if value != null: SettingsSchema.put(result, path, value)
	return result

static func quality(data: Dictionary, tier: String) -> void:
	for path in quality_fields(): SettingsSchema.put(data, path, SettingsLoader.PRESETS[tier].get(path,SettingsSchema.RULES[path][0]))
	SettingsSchema.put(data, "render.quality", tier)

static func quality_label(data: Dictionary) -> String:
	for tier in SettingsLoader.PRESETS:
		var matches := true
		for path in quality_fields():
			if get_value(data,path) != SettingsLoader.PRESETS[tier].get(path,SettingsSchema.RULES[path][0]): matches = false
		if matches: return tier.capitalize()
	return "Custom"

static func label(path: String) -> String:
	var labels := {"display.resolution":"Resolution", "display.width":"Window width", "display.height":"Window height",
		"display.window_mode":"Window mode", "display.vsync":"VSync", "display.fps_cap_enabled":"Limit to 60 FPS",
		"lighting.shadows_enabled":"Shadows", "environment.ssao.enabled":"Ambient occlusion", "environment.fog.enabled":"Distance haze",
		"render.scale":"Render scale", "render.mesh_lod_threshold":"Geometry simplification", "render.fxaa":"FXAA", "render.msaa":"MSAA",
		"player.camera.fov_degrees":"Field of view", "player.camera.sensitivity":"Mouse sensitivity",
		"player.camera.invert_y":"Invert vertical look", "player.camera.bob_amplitude":"Head bob amount", "player.camera.bob_frequency":"Head bob frequency",
		"ui.show_controls_guide":"Show control hints"}
	return labels.get(path, path.get_slice(".", 1).capitalize())

static func quality_fields() -> Array:
	var fields: Array=[]
	for tier in SettingsLoader.PRESETS.values():
		for path in tier:
			if path not in fields: fields.append(path)
	return fields

static func basic(path: String) -> bool:
	return path in ["display.resolution", "display.window_mode", "display.vsync", "display.fps_cap_enabled", "render.scale",
		"lighting.shadows_enabled", "player.camera.sensitivity", "player.camera.invert_y", "player.camera.fov_degrees",
		"player.camera.bob_amplitude", "ui.show_controls_guide"] or path in GALLERY_AUDIO
