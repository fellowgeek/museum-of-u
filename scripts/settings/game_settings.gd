extends Node
class_name GameSettings
## Immutable launch provenance, immutable run configuration, and allowlisted presentation state.
const Schema = preload("res://scripts/settings/settings_schema.gd")
const Loader = preload("res://scripts/settings/settings_loader.gd")
const GENERATOR_VERSION := "65-museum-viewing-backstage"
const DESKTOP_FPS_CAP := 60
static var _values: Dictionary = Schema.defaults()
static var _value_cache: Dictionary = {}
static var _run_values: Dictionary = {}
static var _presentation: Dictionary = {}
static var resolved_seed: int = 1930
static var loaded := false
static var generation_id := ""
static var _launch_seed := 1930
static var _launch_generation_id := ""
static var replay_report: Dictionary = {}
var loader := Loader.new()

func _ready() -> void:
	_values = loader.load_launch(OS.get_cmdline_user_args(), OS.get_executable_path(),
		not OS.has_feature("template"), ProjectSettings.globalize_path("res://"))
	if not loader.fatal_error.is_empty():
		push_error(loader.fatal_error)
		get_tree().quit(2)
		return
	replay_report = loader.replay_report
	_value_cache.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	resolved_seed = resolve_seed(_values, rng)
	generation_id = identity_for(_values,resolved_seed)
	if not replay_report.is_empty() and (replay_report.generator_version != GENERATOR_VERSION or replay_report.generation_id != stored_identity(replay_report.settings, resolved_seed)):
		push_error("Bug replay generation identity differs. Use the matching game build; refusing to restore a pose into a different world.")
		get_tree().quit(2)
		return
	_launch_seed = resolved_seed
	_launch_generation_id = generation_id
	_freeze(_values)
	loaded = true
	apply_viewport(get_tree().root)
	_setup_audio_buses()
	print("SETTINGS source=%s seed=%d generator=%s layout=%s" % [loader.selected_path, resolved_seed, GENERATOR_VERSION, generation_id])
	for warning in loader.warnings: push_warning(warning)
	if value("diagnostics.write_manifest"): write_manifest()

static func resolve_seed(settings: Dictionary, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(-2147483648, 2147483647) if settings.world.seed_mode == "random" else int(settings.world.seed)

static func value(path: String) -> Variant:
	# Launch configuration is immutable; avoid splitting hot-path keys on every query.
	if _value_cache.has(path): return _value_cache[path]
	var cursor: Variant = effective_snapshot()
	for part in path.split("."): cursor = cursor[part]
	if cursor is Dictionary or cursor is Array: _freeze(cursor)
	_value_cache[path] = cursor
	return cursor

static func snapshot() -> Dictionary:
	return effective_snapshot()

static func color(path: String) -> Color:
	var rgb: Array = value(path)
	return Color(rgb[0], rgb[1], rgb[2])

static func _freeze(item: Variant) -> void:
	if item is Dictionary:
		for child in item.values(): _freeze(child)
		item.make_read_only()
	elif item is Array:
		item.make_read_only()

static func apply_frame_pacing(xr_active: bool) -> void:
	Engine.max_fps = 0 if xr_active or not value("display.fps_cap_enabled") else DESKTOP_FPS_CAP
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if xr_active or not value("display.vsync") else DisplayServer.VSYNC_ENABLED)

static func apply_render_quality(viewport: Viewport, xr_active: bool) -> void:
	if viewport is Window: apply_resolution(viewport, xr_active)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = value("render.scale")
	viewport.mesh_lod_threshold = value("render.mesh_lod_threshold")
	viewport.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}[int(value("render.msaa"))]
	# Godot 4.7.2 FXAA + bilinear scaling uses single-view intermediate framebuffers.
	# Bypass that path for stereo; preserve the requested desktop setting and MSAA.
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value("render.fxaa") and not xr_active else Viewport.SCREEN_SPACE_AA_DISABLED

static func apply_resolution(viewport: Window, xr_active: bool) -> void:
	var selected: String = value("display.resolution")
	viewport.content_scale_factor = 1.0
	if selected == "native" or xr_active:
		viewport.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		viewport.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		viewport.content_scale_size = Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width", 1600),
			ProjectSettings.get_setting("display/window/size/viewport_height", 900))
	else:
		# Fix the rendered backing image, including screen effects, independently
		# of desktop/Retina window dimensions. Preserve aspect without distortion.
		viewport.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		viewport.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		viewport.content_scale_size = Vector2i(int(selected.get_slice("x", 0)), int(selected.get_slice("x", 1)))

static func apply_viewport(viewport: Window) -> void:
	apply_render_quality(viewport, viewport.use_xr)
	apply_frame_pacing(viewport.use_xr)
	if DisplayServer.get_name() != "headless":
		match value("display.window_mode"):
			"windowed": viewport.mode = Window.MODE_WINDOWED
			"fullscreen": viewport.mode = Window.MODE_FULLSCREEN
			"exclusive_fullscreen": viewport.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		if viewport.mode == Window.MODE_WINDOWED:
			var requested := Vector2i(
				ProjectSettings.get_setting("display/window/size/window_width_override", 1920),
				ProjectSettings.get_setting("display/window/size/window_height_override", 1080))
			if value("display.window_mode") == "windowed":
				requested = Vector2i(int(value("display.width")), int(value("display.height")))
			# macOS window coordinates use the maximum Retina backing scale.
			# Convert desktop points to backing pixels without disabling sharp HiDPI rendering.
			var desktop_scale := DisplayServer.screen_get_max_scale() if OS.get_name() == "macOS" else 1.0
			if value("display.window_mode") == "project" and "--resolution" in OS.get_cmdline_args():
				requested = viewport.size
				desktop_scale = 1.0
			var usable := DisplayServer.screen_get_usable_rect(viewport.current_screen)
			if usable.size.x > 0 and usable.size.y > 0:
				# Keep the title bar and borders inside the desktop work area too.
				var borders := viewport.get_size_with_decorations() - viewport.size
				viewport.size = fitted_window_size(requested, desktop_scale, usable.size, borders)
				viewport.position = usable.position + (usable.size - viewport.get_size_with_decorations()) / 2
			else:
				viewport.size = Vector2i(Vector2(requested) * desktop_scale)

static func fitted_window_size(requested: Vector2i, desktop_scale: float, usable: Vector2i, borders: Vector2i) -> Vector2i:
	return Vector2i(Vector2(requested) * desktop_scale).min((usable - borders).max(Vector2i.ONE))

const AUDIO_BUSES := {"master": &"Master", "music": &"Settings_music", "footsteps": &"Settings_footsteps", "impacts": &"Settings_impacts"}

static func set_channel_volume(channel: String, gain_db: float, muted: bool) -> void:
	var index := AudioServer.get_bus_index(AUDIO_BUSES[channel])
	AudioServer.set_bus_volume_db(index, gain_db)
	AudioServer.set_bus_mute(index, muted)

func _setup_audio_buses() -> void:
	for channel: String in AUDIO_BUSES:
		set_channel_volume(channel, value("audio." + channel + ".gain_db"), value("audio." + channel + ".muted"))

func write_manifest() -> void:
	var file := FileAccess.open(loader.report_path, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write settings manifest: %s" % loader.report_path)
		return
	file.store_string(JSON.stringify({"settings": snapshot(), "resolved_seed": resolved_seed,
		"generation_id": generation_id, "generator_version": GENERATOR_VERSION,
		"source": loader.selected_path, "warnings": loader.warnings,
		"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method()}, "\t", true))
	print("SETTINGS manifest=%s" % ProjectSettings.globalize_path(loader.report_path))

static func active_seed() -> int:
	return resolved_seed

static func identity_for(settings: Dictionary, seed_value: int) -> String:
	var layout := {"generator_version": GENERATOR_VERSION, "seed": seed_value,
		"museum_annexes": settings.get("layout", {}).get("museum_annexes", false)}
	return JSON.stringify(layout, "", true).sha256_text()

# Verify the historical layout hash before translating a saved visit or report.
static func stored_identity(settings: Dictionary, seed_value: int) -> String:
	if settings.get("schema_version") != 1: return identity_for(settings, seed_value)
	var identity := {"generator_version": GENERATOR_VERSION, "seed": seed_value}
	for group in ["layout", "verticality", "ceilings", "props"]:
		if not settings.get(group) is Dictionary: return ""
		identity[group] = settings[group].duplicate(true)
	for option in ["varied_arrangements", "continuous_corridor_slants", "fuller_closed_rooms", "hotel_lounge_clearance", "museum_annexes"]:
		if not identity.layout.get(option, false): identity.layout.erase(option)
	var decals: Variant = settings.get("decals")
	if not decals is Dictionary: return ""
	identity.decals = {}
	for key in ["enabled", "density_multiplier", "wetness_threshold"]:
		if not decals.has(key): return ""
		identity.decals[key] = decals[key]
	# JSON numbers parse as floats. Restore integer fields before hashing them.
	for path in ["verticality.max_tier", "layout.expansion.coverage_region_size_cells", "layout.expansion.region_size_cells", "layout.expansion.hotel.door_count"]:
		var value: Variant = preload("res://scripts/settings/menu_settings.gd").get_value(identity, path)
		if not SettingsLoader._number(value): return ""
		Schema.put(identity, path, int(value))
	return JSON.stringify(identity, "", true).sha256_text()

static func active_generation_id() -> String:
	return generation_id

static func launch_snapshot() -> Dictionary:
	return _values.duplicate(true)

static func run_snapshot() -> Dictionary:
	return (_values if _run_values.is_empty() else _run_values).duplicate(true)

static func effective_snapshot() -> Dictionary:
	return preload("res://scripts/settings/menu_settings.gd").overlay(run_snapshot(), _presentation,
		["Display", "Graphics", "Audio", "Controls & Comfort"])

static func begin_run(settings: Dictionary) -> String:
	var error := preload("res://scripts/settings/menu_settings.gd").strict(settings)
	if not error.is_empty(): return error
	_run_values = Loader.new().validate(settings)
	_freeze(_run_values)
	_presentation.clear()
	_value_cache.clear()
	resolved_seed = int(settings.world.seed)
	generation_id = identity_for(_run_values, resolved_seed)
	return ""

static func end_run() -> void:
	_run_values = {}
	_presentation = {}
	_value_cache.clear()
	resolved_seed = _launch_seed
	generation_id = _launch_generation_id

static func presentation(settings: Dictionary) -> void:
	_presentation = preload("res://scripts/settings/menu_settings.gd").select(settings,
		["Display", "Graphics", "Audio", "Controls & Comfort"])
	_value_cache.clear()
