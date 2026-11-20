extends Label
const InputRouter = preload("res://scripts/player/input_router.gd")
@onready var game_input: InputRouter = get_node("/root/GameInput")
## Brief startup controls hint, independent of the remaining HUD.

const DISPLAY_SECONDS := 30.0
const FADE_SECONDS := 1.0

var _fade: Tween

func _ready() -> void:
	game_input.device_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if _fade:
		_fade.kill()
	modulate.a = 1.0
	if game_input.using_controller():
		text = "Controller: Left stick: Move | Right stick: Look\nCross / A: Jump | Circle / B: Hold crouch\nL3 or L1 / LB: Hold sprint | Square / X: Flashlight\nTriangle / Y: Open / close door | Options / Start: Cursor / resume replay\nShare / Back: Screenshot | L2 + R2: Bug report\nTrackpad click: Debug OSD"
	else:
		text = "WASD: Move | Shift: Sprint\nC / Ctrl: Crouch | F: Flashlight | Space: Jump\nE: Open / close door\nEsc / Left click: Release / capture mouse"
	if get_tree().root.has_node("Application"):
		text = text.replace("Options / Start: Cursor / resume replay", "Options / Start: Pause menu").replace("Esc / Left click: Release / capture mouse", "Esc: Pause menu")
	text += "\nF11: Fullscreen | P: Screenshot"
	if GameSettings.value("diagnostics.bug_capture_enabled"):
		text += " | B: Bug report"
	if GameSettings.value("diagnostics.overlay_toggle_enabled"):
		text += "\nKeyboard X: Show / hide diagnostics"
	visible = GameSettings.value("ui.show_controls_guide")
	if not visible:
		return
	_fade = create_tween()
	_fade.tween_interval(DISPLAY_SECONDS)
	_fade.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_fade.tween_callback(hide)
