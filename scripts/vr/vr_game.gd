extends "res://scripts/vr/vr_rig.gd"
## Optional full-world adapter using the existing player collision/streaming owner.
var player: CharacterBody3D
var interface: OpenXRInterface
var active := false
var focused := false
var step_distance := 0.0
const RUN_SPEED := 3.2
var running := false
var exit_requested := false
var clearance_shape := CapsuleShape3D.new()
var clearance_query := PhysicsShapeQueryParameters3D.new()
var head_query := PhysicsShapeQueryParameters3D.new()
var capsule_updates := 0
var face_buttons_armed := false
var held_face_buttons := Vector3i.ZERO
var debug_panel: Label3D
var diagnostics: Node
var developer_capture: Node
var panel_wait := 0.0
var use_armed := false
var use_held := false
var right_aim: XRController3D
var left_aim: XRController3D
var flashlight_mount: Node3D
var flashlight_lens: MeshInstance3D
var desktop_state: Dictionary = {}
var left_hand: Node3D
var right_hand: Node3D
var target_marker: MeshInstance3D
const HAND_CONTROLS := "LEFT stick: walk | RIGHT stick: 30° turn\nLEFT trigger: run | LEFT grip: flashlight\nRIGHT trigger: open door\nA: menu / back | X: debug | B: bug report | Y: screenshot"

func _ready() -> void:
	interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if interface == null or not interface.is_initialized():
		push_warning("OpenXR stopped before player setup; retaining desktop controls.")
		for node in [camera, left, right, body, fade]:
			node.free()
		return
	configure_player()
	get_viewport().use_xr = true
	GameSettings.apply_frame_pacing(true)
	connect_session_events()
	interface.pose_recentered.connect(recenter_heading)
	focused = interface.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	var telemetry = preload("res://scripts/vr/vr_performance.gd").new()
	telemetry.rig = self
	add_child(telemetry)

func connect_session_events() -> void:
	interface.session_focussed.connect(func(): set_focus(true))
	for event in [interface.session_visible, interface.session_synchronized]:
		event.connect(func(): set_focus(false))
	for event in [interface.session_stopping, interface.session_loss_pending, interface.instance_exiting]:
		event.connect(end_session)

func end_session() -> void:
	if exit_requested: return
	exit_requested = true
	active = false
	set_focus(false)
	get_viewport().use_xr = false
	var app := player.get_parent().get_parent()
	if app.has_method("exit_vr"):
		app.exit_vr.call_deferred("VR disconnected. Desktop controls are ready.")
	else:
		restore_desktop.call_deferred()

func restore_desktop() -> void:
	if desktop_state.is_empty(): return
	suspend_input()
	active = false
	get_viewport().use_xr = false
	player.vr = null
	player.camera = desktop_state.camera
	player.camera.current = true
	player.neck.global_rotation.y = camera.global_rotation.y
	player.camera.rotation.x = clampf(camera.global_rotation.x, -PI * 0.45, PI * 0.45)
	player.flashlight.reparent(desktop_state.light_parent, false)
	player.flashlight.transform = desktop_state.light_transform
	player.floor_snap_length = desktop_state.floor_snap
	player.velocity = Vector3.ZERO
	# Keep the current safe capsule height; desktop crouch handles standing clearance.
	player.neck.position.y = minf(player.neck.position.y, player.collision_shape.shape.height - 0.15)
	player.get_node("UI").show()
	diagnostics._debug_label.get_parent().show()
	developer_capture.status_label.get_parent().show()
	GameSettings.apply_frame_pacing(false)
	GameSettings.apply_render_quality(get_viewport(), false)
	player._cursor_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	desktop_state.clear()
	queue_free()

func configure_player() -> void:
	# Also used by source assertions without a physical OpenXR runtime.
	desktop_state = {"camera":player.camera, "light_parent":player.flashlight.get_parent(), "light_transform":player.flashlight.transform, "floor_snap":player.floor_snap_length}
	super._ready()
	active = true
	current = true
	# Desktop quality was applied before deferred XR startup; reapply stereo policy.
	GameSettings.apply_render_quality(get_viewport(), true)
	top_level = true
	global_position = player.global_position
	rotation.y = player.neck.global_rotation.y
	body.free()
	body = player
	player.collision_shape.shape = player.collision_shape.shape.duplicate()
	body.floor_snap_length = 0.25
	clearance_shape.radius = player.collision_shape.shape.radius
	clearance_query.shape = clearance_shape
	clearance_query.collision_mask = body.collision_mask
	clearance_query.exclude = [body.get_rid()]
	head_query.shape = head_shape
	head_query.collision_mask = body.collision_mask
	head_query.exclude = [body.get_rid()]
	player.camera.current = false
	player.camera = camera
	camera.current = true
	camera.far = 120.0
	# Hands and flashlight follow grip poses; interaction keeps the separate aim pose.
	for controller in [left, right]:
		controller.pose = &"grip"
		for child in controller.get_children():
			if child is MeshInstance3D: child.free()
		var hand := preload("res://scripts/vr/vr_hand.gd").new()
		hand.name = "Glove"
		controller.add_child(hand)
		hand.configure(controller == left)
		if controller == left: left_hand = hand
		else: right_hand = hand
	right_aim = XRController3D.new()
	right_aim.tracker = &"right_hand"
	right_aim.pose = &"aim"
	add_child(right_aim)
	left_aim = XRController3D.new()
	left_aim.tracker = &"left_hand"
	left_aim.pose = &"aim"
	add_child(left_aim)
	var mount := Node3D.new()
	flashlight_mount = mount
	mount.name = "FlashlightMount"
	# Aim space points forward independently of controller-specific glove rotations.
	left_aim.add_child(mount)
	left_hand.hide()
	player.flashlight.reparent(mount, false)
	var model: Node3D = preload("res://scripts/museum/asset_library.gd").local_scene("flashlight", preload("res://scenes/props/flashlight.tscn")).instantiate()
	model.name = "FlashlightModel"
	model.position = Vector3(0, -0.035, -0.04)
	mount.add_child(model)
	# Lens is at -0.185 m in mount space; light starts beyond its rim.
	player.flashlight.position = Vector3(0, 0, -0.19)
	flashlight_lens = MeshInstance3D.new()
	flashlight_lens.name = "LitLens"
	var lens := CylinderMesh.new()
	lens.top_radius = 0.026
	lens.bottom_radius = 0.026
	lens.height = 0.002
	flashlight_lens.mesh = lens
	flashlight_lens.rotation.x = PI / 2.0
	flashlight_lens.position = Vector3(0, 0, -0.184)
	var lens_material := StandardMaterial3D.new()
	lens_material.albedo_color = Color(1, 0.94, 0.75)
	lens_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_material.emission_enabled = true
	lens_material.emission = Color(1, 0.94, 0.75)
	lens_material.emission_energy_multiplier = 2.0
	flashlight_lens.material_override = lens_material
	flashlight_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mount.add_child(flashlight_lens)
	flashlight_lens.visible = player.flashlight.visible
	target_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.012
	marker_mesh.height = 0.024
	target_marker.mesh = marker_mesh
	var marker_material := material(Color(0.65, 1.0, 0.70))
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	target_marker.material_override = marker_material
	target_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(target_marker)
	target_marker.hide()
	player.get_node("UI").hide()
	# The desktop pass may have been created before the deferred XR startup.
	var effects := player.get_parent().get_node_or_null("VisualEffects")
	if effects != null and is_instance_valid(effects.screen_layer):
		effects.screen_layer.hide()
	interaction.connect(player.toggle_flashlight)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player._cursor_locked = false
	diagnostics = player.get_parent().get_node("WorldDiagnostics")
	developer_capture = player.get_parent().get_node("DeveloperCapture")
	# Keep the desktop labels as the shared text source, but display them in-world.
	diagnostics._debug_label.get_parent().hide()
	developer_capture.status_label.get_parent().hide()
	var panel := Node3D.new()
	panel.position = Vector3(-0.12, 0.23, -0.12)
	panel.rotation.x = -0.5
	left.add_child(panel)
	debug_panel = Label3D.new()
	debug_panel.font_size = 32
	debug_panel.pixel_size = 0.00065
	debug_panel.width = 900
	debug_panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_panel.modulate = Color(0.65, 1.0, 0.70)
	debug_panel.position.z = 0.002
	panel.add_child(debug_panel)
	refresh_debug_panel()

func _process(delta: float) -> void:
	if not active: return
	update_hand_feedback()
	panel_wait -= delta
	if panel_wait <= 0.0:
		panel_wait = 0.25
		refresh_debug_panel()

func refresh_debug_panel() -> void:
	if not is_instance_valid(debug_panel): return
	# The hand guide is opt-in through the existing X debug cycle.
	debug_panel.visible = diagnostics.visible_marks
	debug_panel.text = HAND_CONTROLS
	var door: Node3D = aimed_door()
	if door != null:
		debug_panel.text += "\n" + ("Doorway obstructed" if door.obstructed() else "Opening…" if door.moving and door.target_open else "Closing…" if door.moving else "RIGHT trigger — Close" if door.target_open else "RIGHT trigger — Open")
	if diagnostics.visible_marks:
		debug_panel.text += "\n\n" + diagnostics._debug_label.text
	if developer_capture.status_label.visible:
		debug_panel.text += "\n\n" + developer_capture.status_label.text

func tick_face_buttons(available: bool, debug_pressed: bool, report_pressed: bool, screenshot_pressed: bool) -> void:
	var pressed := Vector3i(int(debug_pressed), int(report_pressed), int(screenshot_pressed))
	if not available or not input_armed or lean_blocked:
		face_buttons_armed = false
		held_face_buttons = pressed
		return
	if not face_buttons_armed:
		face_buttons_armed = pressed == Vector3i.ZERO
		held_face_buttons = pressed
		return
	if debug_pressed and held_face_buttons.x == 0:
		# XR focus/tracking gates this path; the desktop mirror need not have focus.
		diagnostics.cycle_debug(false)
	if report_pressed and held_face_buttons.y == 0:
		developer_capture._on_controller_action(&"bug_report")
	if screenshot_pressed and held_face_buttons.z == 0:
		developer_capture._on_controller_action(&"screenshot")
	held_face_buttons = pressed
	refresh_debug_panel()

func suspend_input() -> void:
	use_armed = false
	use_held = false
	face_buttons_armed = false
	held_face_buttons = Vector3i.ZERO
	running = false
	if is_instance_valid(target_marker): target_marker.hide()
	super.suspend_input()

func update_tracking(available: bool, delta := 0.0) -> void:
	# Loss of either grip or the independent aim pose suspends every action.
	super.update_tracking(available and right_aim.get_has_tracking_data() and left_aim.get_has_tracking_data(), delta)

func poll_controls(delta: float) -> void:
	if right.is_button_pressed("menu_toggle"):
		suspend_input()
		return
	tick_game_controls(true, right.get_vector2("turn").x, left.get_float("trigger"),
		left.get_float("grip"), left.get_vector2("move"), delta, right.get_float("trigger"))
	tick_use_trigger(true, right.get_float("trigger"))
	tick_face_buttons(true, left.is_button_pressed("debug"), right.is_button_pressed("bug_report"), left.is_button_pressed("screenshot"))

func hand_reachable() -> bool:
	# Controller tracking can pass through geometry; never start a ray beyond a wall.
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, right_aim.global_position, 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func aimed_door() -> Node3D:
	if not input_armed or lean_blocked or not hand_reachable(): return null
	return player.InteriorDoor.target(right_aim, player)

func update_hand_feedback() -> void:
	left_aim.visible = left.visible
	flashlight_lens.visible = player.flashlight.visible
	# Keep text above the wrist and facing the head while the flashlight is aimed.
	var panel := debug_panel.get_parent() as Node3D
	panel.global_transform = Transform3D(camera.global_basis, left.global_position + camera.global_basis * Vector3(-0.12, 0.23, -0.12))
	var door := aimed_door()
	left_hand.update_profile(left)
	right_hand.update_profile(right)
	left_hand.update_pose(left.get_float("trigger"), left.get_float("grip"), false)
	right_hand.update_pose(right.get_float("trigger"), right.get_float("grip"), door != null)
	target_marker.visible = door != null and right.visible
	if target_marker.visible:
		# A depth-tested dot on the aimed surface also works on the open aperture.
		var from := right_aim.global_position
		var direction := -right_aim.global_basis.z
		var query := PhysicsRayQueryParameters3D.create(from, from + direction * 2.2, 1, [player.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider.get_meta("door", null) == door:
			target_marker.global_position = hit.position - direction * 0.015
			return
		var local_from: Vector3 = door.to_local(from)
		var local_direction: Vector3 = door.global_basis.inverse() * direction
		if absf(local_direction.z) > 0.001:
			var distance := -local_from.z / local_direction.z
			target_marker.global_position = from + direction * maxf(0, distance - 0.04)
		else: target_marker.hide()

func tick_use_trigger(available: bool, value: float) -> void:
	if not available or not input_armed or lean_blocked:
		use_armed = false
		use_held = false
		return
	if not use_armed:
		use_armed = value < 0.2
		return
	if value < 0.2:
		use_held = false
	elif value > 0.75 and not use_held:
		use_held = true
		if hand_reachable(): player.interact(right_aim)
		refresh_debug_panel()

func tick_game_controls(available: bool, turn: float, run_trigger: float, flashlight_grip: float, movement: Vector2, delta: float, use_trigger := 0.0) -> void:
	if not available or (not input_armed and (run_trigger >= 0.2 or use_trigger >= 0.2)):
		suspend_input()
		return
	running = input_armed and not lean_blocked and run_trigger > 0.75
	# Shared edge latch receives the left squeeze; left trigger remains independent.
	tick_controls(available, turn, flashlight_grip, movement, delta)

func set_focus(value: bool) -> void:
	focused = value and not exit_requested
	suspend_input()
	body.velocity = Vector3.ZERO

func tick(delta: float) -> void:
	if exit_requested: return
	update_tracking(focused, delta)

func move_body(motion: Vector3) -> void:
	# Room-scale following is horizontal. Only walkable upward slopes may
	# contribute height; a prop edge must never slide the tracked origin down.
	for attempt in 3:
		if motion.length_squared() < 0.00000001: return
		var hit := body.move_and_collide(motion)
		if hit == null: return
		collision_frames += 1
		motion = hit.get_remainder().slide(hit.get_normal())
		if hit.get_normal().y < cos(body.floor_max_angle):
			motion.y = 0.0
		else:
			motion.y = maxf(motion.y, 0.0)

func update_physical_body() -> void:
	# Physical crouch changes collision height; never animate the tracked camera.
	var height := clampf(camera.global_position.y - global_position.y + 0.12, 0.8, 2.3)
	var old_height: float = player.collision_shape.shape.height
	# Millimetre tracking noise should not rebuild a physics shape each frame.
	if absf(height - old_height) >= 0.01:
		if height > old_height:
			clearance_shape.height = height
			clearance_query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3.UP * height * 0.5)
			if not get_world_3d().direct_space_state.intersect_shape(clearance_query, 1).is_empty():
				height = old_height
		if not is_equal_approx(height, old_height):
			player.collision_shape.shape.height = height
			player.collision_shape.position.y = height * 0.5
			capsule_updates += 1
	player._is_crouching = height < 1.4
	var desired := Vector3(camera.global_position.x, body.global_position.y, camera.global_position.z)
	var previous_y := body.global_position.y
	move_body(desired - body.global_position)
	global_position.y += body.global_position.y - previous_y
	var separation := Vector2(desired.x - body.global_position.x, desired.z - body.global_position.z).length()
	head_query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	var amount := 0.0
	# A blocked foot/body (for example a low prop base) does not imply an
	# obstructed headset. Sweep at eye height to retain protection beyond walls.
	head_query.motion = Vector3.ZERO
	if not get_world_3d().direct_space_state.intersect_shape(head_query, 1).is_empty():
		amount = 1.0
	elif separation > 0.02:
		var anchor := Vector3(body.global_position.x, camera.global_position.y, body.global_position.z)
		head_query.transform.origin = anchor
		if not get_world_3d().direct_space_state.intersect_shape(head_query, 1).is_empty():
			amount = 1.0
		else:
			head_query.motion = camera.global_position - anchor
			var travel := get_world_3d().direct_space_state.cast_motion(head_query)
			if travel[0] < 1.0:
				amount = clampf((1.0 - travel[0]) * separation / 0.10, 0.0, 1.0)
	head_query.motion = Vector3.ZERO
	var blocked := amount > 0.0
	if blocked != lean_blocked:
		lean_blocked = blocked
		suspend_input()
	fade.visible = blocked
	fade_material.albedo_color.a = amount

func walk(stick: Vector2, delta: float) -> void:
	if not input_armed or lean_blocked or delta <= 0.0:
		return
	var direction := walk_velocity(stick, camera.global_basis)
	if running:
		direction *= RUN_SPEED / WALK_SPEED
	body.velocity.x = direction.x
	body.velocity.z = direction.z
	if not body.is_on_floor():
		body.velocity.y -= player.gravity * delta
	else:
		body.velocity.y = 0.0
	var before := body.global_position
	player._try_stair_step(Vector3(body.velocity.x, 0, body.velocity.z) * delta)
	body.move_and_slide()
	var applied := body.global_position - before
	global_position += applied
	smooth_distance += Vector2(applied.x, applied.z).length()
	step_distance += Vector2(applied.x, applied.z).length()
	if step_distance > 0.65 and body.is_on_floor():
		step_distance = 0.0
		player._play_footstep()
