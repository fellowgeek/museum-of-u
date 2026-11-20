extends Node
## One selected gamepad owns gameplay while connected; desktop shortcuts remain available.
signal device_changed
signal controller_action(action: StringName)

const STICK_DEADZONE := 0.20
const LOOK_RADIANS_PER_SECOND := 2.6
const BUTTON_ACTIONS := {
	JOY_BUTTON_A: &"jump", JOY_BUTTON_X: &"flashlight",
	JOY_BUTTON_START: &"cursor", JOY_BUTTON_BACK: &"screenshot",
	JOY_BUTTON_Y: &"interact", JOY_BUTTON_TOUCHPAD: &"debug",
}
const HELD_BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_START,
	JOY_BUTTON_BACK, JOY_BUTTON_Y, JOY_BUTTON_TOUCHPAD, JOY_BUTTON_B, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]

var active_device := -1
var controller_name := ""
var _report_chord := false
var armed := false
var focused := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Godot supplies controller navigation, but accept/cancel default to keyboard only.
	var menu_buttons := {&"ui_accept": JOY_BUTTON_A, &"ui_cancel": JOY_BUTTON_B}
	for action in menu_buttons:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = menu_buttons[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	Input.joy_connection_changed.connect(_on_connection_changed)
	refresh_devices()

func connected_devices() -> Array[int]:
	return Array(Input.get_connected_joypads(), TYPE_INT, "", null)

func device_name(device: int) -> String:
	return Input.get_joy_name(device)

func axis_value(axis: JoyAxis) -> float:
	return Input.get_joy_axis(active_device, axis)

func button_down(button: JoyButton) -> bool:
	return Input.is_joy_button_pressed(active_device, button)

func refresh_devices(excluded_device: int = -1) -> void:
	var devices := connected_devices()
	devices.erase(excluded_device)
	# Retain the selected pad while it remains connected, avoiding second-pad interruptions.
	var selected := active_device if devices.has(active_device) else (-1 if devices.is_empty() else devices[0])
	if selected == active_device:
		return
	active_device = selected
	controller_name = device_name(selected) if selected >= 0 else ""
	armed = false
	print("INPUT_DEVICE ", controller_name if using_controller() else "Keyboard and mouse")
	device_changed.emit()

func _on_connection_changed(device: int, connected: bool) -> void:
	refresh_devices(-1 if connected else device)

func using_controller() -> bool:
	return active_device >= 0

static func deadzone(raw: Vector2) -> Vector2:
	var strength := minf(raw.length(), 1.0)
	if strength <= STICK_DEADZONE:
		return Vector2.ZERO
	return raw.normalized() * ((strength - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))

func stick(right: bool = false) -> Vector2:
	return deadzone(Vector2(axis_value(JOY_AXIS_RIGHT_X if right else JOY_AXIS_LEFT_X),
		axis_value(JOY_AXIS_RIGHT_Y if right else JOY_AXIS_LEFT_Y)))

func _process(_delta: float) -> void:
	if not using_controller() or not focused: return
	var left := axis_value(JOY_AXIS_TRIGGER_LEFT)
	var right := axis_value(JOY_AXIS_TRIGGER_RIGHT)
	if armed:
		if left<0.25 and right<0.25: _report_chord=false
		elif left>0.75 and right>0.75 and not _report_chord:
			_report_chord=true
			controller_action.emit(&"bug_report")
		return
	if left>0.25 or right>0.25: return
	# New connections and focus returns must be neutral before gameplay resumes.
	if stick() != Vector2.ZERO or stick(true) != Vector2.ZERO:
		return
	for button: int in HELD_BUTTONS:
		if button_down(button):
			return
	_report_chord = false
	armed = true

func movement() -> Vector2:
	if not focused:
		return Vector2.ZERO
	if using_controller():
		return stick() if armed else Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")

func look() -> Vector2:
	return stick(true) if using_controller() and focused and armed else Vector2.ZERO

func held(action: StringName) -> bool:
	if not focused:
		return false
	if not using_controller():
		return Input.is_action_pressed(action)
	if not armed:
		return false
	if action == &"crouch":
		return button_down(JOY_BUTTON_B)
	if action == &"sprint":
		return button_down(JOY_BUTTON_LEFT_STICK) or button_down(JOY_BUTTON_LEFT_SHOULDER)
	return false

func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.mode = Window.MODE_WINDOWED if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN

func _input(event: InputEvent) -> void:
	if event is InputEventKey and focused and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_F11 and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
	if get_meta("menu_context", false):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if not focused or not armed or event.device != active_device: get_viewport().set_input_as_handled()
			elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:
				var application:=get_tree().root.get_node_or_null("Application")
				if application and application.switch_tab(-1 if event.button_index==JOY_BUTTON_LEFT_SHOULDER else 1):
					get_viewport().set_input_as_handled()
			elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
				var application := get_tree().root.get_node_or_null("Application")
				if application and application.screen == "pause": application.resume()
				get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.device == active_device and focused and armed:
		if event.pressed and BUTTON_ACTIONS.has(event.button_index):
			controller_action.emit(BUTTON_ACTIONS[event.button_index])

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		focused = false
		armed = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		focused = true
		armed = false
