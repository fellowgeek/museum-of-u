extends Node3D
## Neutral world statistics shared by desktop and the opt-in VR hand guide.
const VERSION := "1-museum-diagnostics"
var visible_marks := false
var _debug_label: Label
var player: Node3D
var manager: MuseumManager
var seed := 0
var _refresh_wait := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_parent().get_node("Player")
	manager = get_parent().get_node("ChunkManager")
	seed = manager.world_seed
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_debug_label = Label.new()
	_debug_label.position = Vector2(20,210)
	_debug_label.add_theme_color_override("font_color",Color(0.85,0.95,1.0))
	_debug_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_debug_label.add_theme_constant_override("shadow_offset_x",2)
	_debug_label.add_theme_constant_override("shadow_offset_y",2)
	overlay.add_child(_debug_label)
	set_marks_visible(GameSettings.value("diagnostics.overlay_visible"))
	get_node("/root/GameInput").controller_action.connect(func(action):
		if action == &"debug": cycle_debug())

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	if not get_node("/root/GameInput").focused: return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if key == KEY_X:
		cycle_debug()
		get_viewport().set_input_as_handled()

func cycle_debug(require_window_focus := true) -> void:
	if require_window_focus and not get_node("/root/GameInput").focused: return
	if not GameSettings.value("diagnostics.overlay_toggle_enabled"): return
	set_marks_visible(not visible_marks)

func set_marks_visible(value: bool) -> void:
	visible_marks = value
	_refresh_debug_label()

func _process(delta: float) -> void:
	_refresh_wait -= delta
	if _refresh_wait <= 0.0:
		_refresh_wait = 0.25
		_refresh_debug_label()

func _refresh_debug_label() -> void:
	if not is_instance_valid(_debug_label): return
	_debug_label.visible = visible_marks
	if not visible_marks: return
	_debug_label.text="Room: %s | Photos: %d | Skipped: %d | Wing: %d | Endless\nResident wings: %d | FPS: %d\nX: hide diagnostics" % [manager.museum_room_at(player.global_position),manager.library.entries.size(),manager.library.rejected.size(),manager.world_to_chunk_coords(player.global_position).y+1,manager.active_chunks_snapshot().size(),Engine.get_frames_per_second()]

func snapshot() -> Dictionary:
	return {"version":VERSION,"seed":seed,"visible_marks":visible_marks,"active_chunks":manager.active_chunks_snapshot().size(),"pending_chunks":manager._chunks_to_load.size()}
