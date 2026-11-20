extends Node
const InputRouter = preload("res://scripts/player/input_router.gd")
@onready var game_input: InputRouter = get_node("/root/GameInput")
## Player-triggered captures and a paused, inspectable replay entry point.
const Format = preload("res://scripts/diagnostics/bug_report.gd")
var busy := false
var replay_paused := false
var last_result: Dictionary = {}
var status_label: Label
var _status_seconds := 0.0
var _player: CharacterBody3D
var _manager: MuseumManager

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_input.controller_action.connect(_on_controller_action)
	_player = get_parent().get_node("Player")
	_manager = get_parent().get_node("ChunkManager")
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	status_label = Label.new()
	status_label.position = Vector2(20, 20)
	status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	status_label.add_theme_constant_override("shadow_offset_x", 2)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(status_label)
	if not GameSettings.replay_report.is_empty():
		replay_paused = true
		get_tree().paused = true
		_notify("Bug replay paused at saved pose. Press Enter or Options / Start to resume.", 0.0)
		print("BUG_REPLAY restored=", JSON.stringify(_player.bug_pose()))
		print("BUG_REPLAY generation_id=", GameSettings.active_generation_id())

func _process(delta: float) -> void:
	if _status_seconds > 0:
		_status_seconds -= delta
		if _status_seconds <= 0: status_label.hide()

func _on_controller_action(action: StringName) -> void:
	if action == &"cursor" and replay_paused:
		_resume_replay()
	elif action == &"screenshot": capture(false)
	elif action == &"bug_report" and GameSettings.value("diagnostics.bug_capture_enabled"): capture(true)

func _resume_replay() -> void:
	replay_paused = false
	get_tree().paused = false
	_notify("Bug replay resumed", 3.0)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_ENTER and replay_paused:
		_resume_replay()
		get_viewport().set_input_as_handled()
	elif key == KEY_B and GameSettings.value("diagnostics.bug_capture_enabled"):
		capture(true)
		get_viewport().set_input_as_handled()
	elif key == KEY_P:
		capture(false)
		get_viewport().set_input_as_handled()

func capture(bug_report: bool) -> void:
	if busy: return
	busy = true
	status_label.hide()
	if DisplayServer.get_name() == "headless":
		_finish({"error": "Screenshot capture requires a graphical renderer."}, bug_report)
		return
	# Sample the pose and pixels together after the same rendered frame.
	await RenderingServer.frame_post_draw
	var report := make_report() if bug_report else {}
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_finish({"error": "The rendered frame is unavailable; no capture saved."}, bug_report)
		return
	var category := "bug-reports" if bug_report else "screenshots"
	var roots := output_roots(category)
	var result: Dictionary = {}
	for index in range(roots.size()):
		result = Format.save_bundle(roots[index], report, image) if bug_report else Format.save_screenshot(roots[index], image)
		if result.has("path"):
			result["fallback"] = index > 0
			break
	_finish(result, bug_report)

static func output_roots(category: String) -> Array[String]:
	var fallback := ProjectSettings.globalize_path("user://" + category)
	if GameSettings.value("diagnostics.capture_location") == "user": return [fallback]
	var sibling := SettingsLoader.default_path(OS.get_executable_path(), not OS.has_feature("template"), ProjectSettings.globalize_path("res://")).get_base_dir()
	return [sibling.path_join(category), fallback]

func make_report() -> Dictionary:
	var settings := GameSettings.snapshot()
	var original_mode: String = settings.world.seed_mode
	settings.world.seed_mode = "fixed"
	settings.world.seed = GameSettings.active_seed()
	var launch = get_node("/root/LaunchSettings")
	var active: Array = []
	for coord: Vector2i in _manager._active_chunks: active.append([coord.x, coord.y])
	var pending: Array = []
	for coord: Vector2i in _manager._chunks_to_load: pending.append([coord.x, coord.y])
	var chunk := _manager.world_to_chunk_coords(_player.global_position)
	return {"report_version": Format.VERSION, "captured_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"settings": settings, "resolved_seed": GameSettings.active_seed(), "original_seed_mode": original_mode,
		"generation_id": GameSettings.active_generation_id(), "generator_version": GameSettings.GENERATOR_VERSION,
		"player": _player.bug_pose(), "screenshot": "screenshot.png",
		"launch": {"settings_source": launch.loader.selected_path, "warnings": launch.loader.warnings},
		"runtime": {"engine": Engine.get_version_info(), "os": OS.get_name(), "os_version": OS.get_version(),
			"renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(),
			"exported": OS.has_feature("template"), "project_version": ProjectSettings.get_setting("application/config/version", "unversioned"),
			"window_size": [get_tree().root.size.x, get_tree().root.size.y],
			"viewport_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
			"physics_ticks_per_second": Engine.physics_ticks_per_second, "uptime_ms": Time.get_ticks_msec()},
		"soundscape": get_parent().get_node("WorldDiagnostics").snapshot(),
		"streaming": {"player_chunk": [chunk.x, chunk.y], "active_chunks": active, "pending_chunks": pending},
		"replay_limits": ["Use the same game build and assets.", "Restores generated world and player state; not door states, soundtrack position, input history or streaming history.", "Pixels can differ across renderer, GPU and window size."]}

func _finish(result: Dictionary, bug_report: bool) -> void:
	last_result = result
	busy = false
	if result.has("error"):
		push_warning(result.error)
		_notify("Capture failed: " + str(result.error), 10.0)
	else:
		var label := "Bug report" if bug_report else "Screenshot"
		var location := " (user data fallback)" if result.get("fallback", false) else ""
		print("CAPTURE %s=%s%s" % [label, result.path, location])
		_notify("%s saved%s:\n%s" % [label, location, result.path], 10.0)

func _notify(message: String, seconds: float) -> void:
	status_label.text = message
	status_label.show()
	_status_seconds = seconds
