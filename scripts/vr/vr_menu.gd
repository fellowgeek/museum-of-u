extends Node3D
## Persistent headset menu: native Controls rendered on a world-space flat panel.
const PIXELS := Vector2i(1200, 900)
const SIZE := Vector2(1.4, 1.05)
var app: Node
var ui := SubViewport.new()
var origin := XROrigin3D.new()
var head := XRCamera3D.new()
var pointer := XRController3D.new()
var left := XRController3D.new()
var right := XRController3D.new()
var panel := MeshInstance3D.new()
var dot := MeshInstance3D.new()
var beam := MeshInstance3D.new()
var opened := false
var armed := false
var menu_held := false
var trigger_held := false
var mouse_down := false
var last_pixel := Vector2.ZERO
var scroll_wait := 0.0
var focused := false
var synthetic := false
var loading_indicator := preload("res://scripts/vr/vr_loading.gd").new()

func configure(application: Node, source_test := false) -> void:
	app = application
	synthetic = source_test
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui.size = PIXELS
	ui.disable_3d = true
	ui.gui_embed_subwindows = true
	ui.transparent_bg = false
	ui.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(ui)
	app.canvas.reparent(ui)
	add_child(origin)
	origin.add_child(head)
	head.add_child(loading_indicator)
	head.current = false
	for controller in [pointer, left, right]:
		controller.tracker = &"left_hand" if controller == left else &"right_hand"
		controller.pose = &"aim" if controller == pointer else &"grip"
		origin.add_child(controller)
		if controller != pointer:
			var glove := preload("res://scripts/vr/vr_hand.gd").new()
			controller.add_child(glove)
			glove.configure(controller == left)
	var quad := QuadMesh.new()
	quad.size = SIZE
	panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = ui.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 120
	panel.material_override = material
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	var sphere := SphereMesh.new()
	sphere.radius = 0.006
	sphere.height = 0.012
	dot.mesh = sphere
	var cursor_material := StandardMaterial3D.new()
	cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_material.albedo_color = Color(1, 0.8, 0.4)
	cursor_material.no_depth_test = true
	cursor_material.render_priority = 121
	dot.material_override = cursor_material
	add_child(dot)
	var line := CylinderMesh.new()
	line.top_radius = 0.001
	line.bottom_radius = 0.001
	beam.mesh = line
	beam.material_override = cursor_material
	pointer.add_child(beam)
	panel.hide(); dot.hide(); beam.hide(); left.hide(); right.hide()
	if not synthetic:
		var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
		focused = xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
		xr.session_focussed.connect(func(): focused = true; reset_input())
		for event in [xr.session_visible, xr.session_synchronized]:
			event.connect(func(): focused = false; reset_input())

func game_rig() -> Node3D:
	if not is_instance_valid(app.world): return null
	return app.world.get_node("Player").vr

func show_panel() -> void:
	loading_indicator.hide()
	panel.show()
	if opened: return
	var rig := game_rig()
	if rig != null:
		origin.global_transform = rig.global_transform
		if synthetic: head.transform = rig.camera.transform
		rig.suspend_input()
		rig.fade.hide()
	opened = true
	ui.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	origin.current = true
	head.current = true
	if not synthetic: get_viewport().use_xr = true
	# Place once in front of the current gaze; head motion does not drag the window.
	panel.global_transform = head.global_transform.translated_local(Vector3(0, 0, -1.4))
	panel.show()
	reset_input()

func hide_panel() -> void:
	loading_indicator.hide()
	if not opened: return
	reset_input()
	opened = false
	panel.hide(); dot.hide(); beam.hide(); left.hide(); right.hide()
	ui.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rig := game_rig()
	if rig != null:
		rig.current = true
		rig.camera.current = true
		rig.fade.visible = rig.lean_blocked
		rig.suspend_input()

func show_loading(message: String) -> void:
	show_panel()
	panel.hide()
	reset_input()
	loading_indicator.begin(message)

func reset_input() -> void:
	# Release outside all Controls, so tracking loss cannot complete a pressed button.
	if mouse_down:
		var away := InputEventMouseMotion.new()
		away.position = Vector2(-100, -100)
		away.global_position = away.position
		away.button_mask = MOUSE_BUTTON_MASK_LEFT
		ui.push_input(away, true)
		send_button(false, away.position)
	armed = false
	menu_held = false
	trigger_held = false
	dot.hide(); beam.hide()

func _process(delta: float) -> void:
	if opened:
		origin.current = true
		head.current = true
	if synthetic: return
	var tracker := XRServer.get_tracker("head") as XRPositionalTracker
	var pose := tracker.get_pose("default") if tracker != null else null
	var available := focused and pose != null and pose.has_tracking_data and pointer.get_has_tracking_data() and left.get_has_tracking_data() and right.get_has_tracking_data()
	if opened:
		for controller in [left, right]:
			controller.visible = available
			var glove = controller.get_child(0)
			glove.update_profile(controller)
			glove.update_pose(controller.get_float("trigger"), controller.get_float("grip"), controller == right)
	tick_input(available, right.is_button_pressed("menu_toggle"), right.get_float("trigger"), right.get_vector2("turn").y, delta)

func tick_input(available: bool, menu_pressed: bool, trigger: float, scroll_axis: float, delta: float) -> void:
	if not available:
		reset_input()
		return
	if not armed:
		armed = not menu_pressed and trigger < 0.2 and absf(scroll_axis) < 0.2
		return
	if menu_pressed and not menu_held:
		menu_held = true
		app.menu_back()
		return
	menu_held = menu_pressed
	if not opened or loading_indicator.visible: return
	var pixel := ray_pixel(pointer.global_transform)
	var hit := pixel.x >= 0
	dot.visible = hit
	beam.visible = hit
	if hit:
		var point := panel.to_global(Vector3((pixel.x / PIXELS.x - 0.5) * SIZE.x, (0.5 - pixel.y / PIXELS.y) * SIZE.y, 0.005))
		dot.global_position = point
		var distance := pointer.global_position.distance_to(point)
		beam.mesh.height = distance
		beam.position.z = -distance * 0.5
		beam.rotation.x = PI / 2
	var motion := InputEventMouseMotion.new()
	motion.position = pixel if hit else Vector2(-100, -100)
	motion.global_position = motion.position
	motion.relative = motion.position - last_pixel
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse_down else 0
	ui.push_input(motion, true)
	last_pixel = motion.position
	if trigger > 0.75 and not trigger_held:
		trigger_held = true
		if hit: send_button(true, pixel)
	elif trigger < 0.2:
		if mouse_down: send_button(false, last_pixel)
		trigger_held = false
	scroll_wait -= delta
	if hit and absf(scroll_axis) > 0.5 and scroll_wait <= 0:
		scroll_wait = 0.12
		var wheel := InputEventMouseButton.new()
		wheel.position = pixel
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if scroll_axis > 0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		ui.push_input(wheel, true)
		wheel = wheel.duplicate()
		wheel.pressed = false
		ui.push_input(wheel, true)

func ray_pixel(ray: Transform3D) -> Vector2:
	var from := panel.to_local(ray.origin)
	var direction := panel.global_basis.inverse() * -ray.basis.z
	if from.z <= 0 or direction.z >= -0.001: return Vector2(-1, -1)
	var distance := -from.z / direction.z
	if distance > 4.0: return Vector2(-1, -1)
	var point := from + direction * distance
	if absf(point.x) > SIZE.x * 0.5 or absf(point.y) > SIZE.y * 0.5: return Vector2(-1, -1)
	return Vector2((point.x / SIZE.x + 0.5) * PIXELS.x, (0.5 - point.y / SIZE.y) * PIXELS.y)

func send_button(pressed: bool, pixel: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse_down = pressed
	ui.push_input(event, true)
