extends CharacterBody3D
const InteriorDoor = preload("res://scripts/props/interior_door.gd")
const FLASHLIGHT_CLICKS := [preload("res://assets/audio/events/flashlight_on.wav"), preload("res://assets/audio/events/flashlight_off.wav")]
var flashlight_audio: AudioStreamPlayer
var flashlight_sound_events := 0
var door_prompt: Label

const InputRouter = preload("res://scripts/player/input_router.gd")
@onready var game_input: InputRouter = get_node("/root/GameInput")


# Movement speeds
const WALK_SPEED = 2.0
const SPRINT_SPEED = 4.0
const CROUCH_SPEED = 1.6
const JUMP_VELOCITY = 4.2
const GRAVITY = 14.0

# Mouse sensitivity
@export var mouse_sensitivity: float = 0.002

# Camera Bobbing
const BOB_FREQ = 2.4
const BOB_AMP = 0.04
var _bob_timer: float = 0.0
var _step_cooldown: float = 0.0

# Crouching
const STAND_HEIGHT = 1.8
const CROUCH_HEIGHT = 1.1
const STAND_CAM_Y = 1.6
const CROUCH_CAM_Y = 0.9
var _is_crouching: bool = false
var _standing_shape := CapsuleShape3D.new()

# Legacy stamina value retained for capture/replay compatibility.
var stamina: float = 100.0
const MAX_STAMINA = 100.0

# Nodes
@onready var neck: Node3D = $Neck
@onready var camera: Camera3D = $Neck/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var flashlight: SpotLight3D = $Neck/Camera3D/Flashlight
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio

# Audio resources
var footstep_sounds: Array[AudioStream] = [
	preload("res://assets/audio/footstep_carpet_1.wav"),
	preload("res://assets/audio/footstep_carpet_2.wav"),
	preload("res://assets/audio/footstep_carpet_3.wav")
]
var _cursor_locked: bool = true
var _controller_jump := false
var vr: Node3D = null

var walk_speed: float = WALK_SPEED
var sprint_speed: float = SPRINT_SPEED
var crouch_speed: float = CROUCH_SPEED
var jump_velocity: float = JUMP_VELOCITY
var gravity: float = GRAVITY
var bob_frequency: float = BOB_FREQ
var bob_amplitude: float = BOB_AMP
var max_stamina: float = MAX_STAMINA
var invert_y: bool = false

func _ready() -> void:
	walk_speed = GameSettings.value("player.movement.walk_speed")
	sprint_speed = GameSettings.value("player.movement.sprint_speed")
	crouch_speed = GameSettings.value("player.movement.crouch_speed")
	jump_velocity = GameSettings.value("player.movement.jump_velocity")
	gravity = GameSettings.value("player.movement.gravity")
	bob_frequency = GameSettings.value("player.camera.bob_frequency")
	bob_amplitude = GameSettings.value("player.camera.bob_amplitude")
	max_stamina = GameSettings.value("player.stamina.maximum")
	mouse_sensitivity = GameSettings.value("player.camera.sensitivity")
	invert_y = GameSettings.value("player.camera.invert_y")
	camera.fov = GameSettings.value("player.camera.fov_degrees")
	flashlight.visible = GameSettings.value("player.flashlight.initially_on")
	flashlight.shadow_enabled = GameSettings.value("lighting.shadows_enabled")
	flashlight_audio = AudioStreamPlayer.new()
	flashlight_audio.bus = "Settings_impacts"
	add_child(flashlight_audio)
	stamina = max_stamina
	footstep_audio.bus = "Settings_footsteps"
	game_input.device_changed.connect(_on_input_device_changed)
	game_input.controller_action.connect(_on_controller_action)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	call_deferred("_ensure_mouse_capture")
	var door_layer := CanvasLayer.new()
	add_child(door_layer)
	door_prompt = Label.new()
	door_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	door_prompt.position = Vector2(-150,35)
	door_prompt.size = Vector2(300,32)
	door_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	door_layer.add_child(door_prompt)
	door_prompt.hide()
	if not GameSettings.replay_report.is_empty():
		restore_bug_pose(GameSettings.replay_report.player)

	if "--vr" in OS.get_cmdline_user_args() and not get_parent().get_parent().has_method("attach_vr_menu"):
		call_deferred("_start_vr")

func _start_vr() -> void:
	if vr != null: return
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		push_warning("VR unavailable. Connect the headset and select Enter VR from the menu.")
		return
	var adapter = preload("res://scripts/vr/vr_game.gd").new()
	adapter.player = self
	add_child(adapter)
	if adapter.active:
		vr = adapter
	else:
		adapter.queue_free()

func bug_pose() -> Dictionary:
	var format = SettingsLoader.BugReport
	return {"position": format.vector(global_position), "rotation": format.vector(rotation),
		"neck_position": format.vector(neck.position), "neck_rotation": format.vector(neck.rotation),
		"camera_position": format.vector(camera.position), "camera_rotation": format.vector(camera.rotation),
		"camera_fov": camera.fov, "velocity": format.vector(velocity), "crouching": _is_crouching,
		"capsule_height": collision_shape.shape.height, "stamina": stamina,
		"bob_timer": _bob_timer, "flashlight_on": flashlight.visible}

func restore_bug_pose(pose: Dictionary) -> void:
	var format = SettingsLoader.BugReport
	global_position = format.to_vector(pose.position)
	rotation = format.to_vector(pose.rotation)
	neck.position = format.to_vector(pose.neck_position)
	neck.rotation = format.to_vector(pose.neck_rotation)
	camera.position = format.to_vector(pose.camera_position)
	camera.rotation = format.to_vector(pose.camera_rotation)
	camera.fov = pose.camera_fov
	velocity = format.to_vector(pose.velocity)
	_is_crouching = pose.crouching
	collision_shape.shape = collision_shape.shape.duplicate()
	collision_shape.shape.height = pose.capsule_height
	collision_shape.position.y = pose.capsule_height * 0.5
	stamina = pose.stamina
	_bob_timer = pose.bob_timer
	flashlight.visible = pose.flashlight_on

func _ensure_mouse_capture() -> void:
	if _cursor_locked:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_controller_jump = false
		velocity.x = 0.0
		velocity.z = 0.0
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if _cursor_locked:
			call_deferred("_ensure_mouse_capture")

func _on_input_device_changed() -> void:
	_controller_jump = false
	# Remove carried horizontal motion from the previous device immediately.
	velocity.x = 0.0
	velocity.z = 0.0

func _on_controller_action(action: StringName) -> void:
	if get_tree().paused or vr != null:
		return
	match action:
		&"jump": _controller_jump = true
		&"flashlight": toggle_flashlight()
		&"cursor": _toggle_cursor()
		&"interact":
			if _cursor_locked:
				interact()

func interact(origin: Node3D = null) -> void:
	var source := camera if origin == null else origin
	var door := InteriorDoor.target(source, self)
	if door != null: door.interact()

func toggle_flashlight() -> void:
	flashlight.visible = not flashlight.visible
	if GameSettings.value("audio.impacts.enabled"):
		flashlight_audio.stream = FLASHLIGHT_CLICKS[0 if flashlight.visible else 1]
		flashlight_audio.play()
		flashlight_sound_events += 1

func _toggle_cursor() -> void:
	var application := get_tree().root.get_node_or_null("Application")
	if application and application.has_method("pause_menu"):
		application.pause_menu()
		get_viewport().set_input_as_handled()
		return
	_cursor_locked = not _cursor_locked
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _cursor_locked else Input.MOUSE_MODE_VISIBLE)

func _apply_look(amount: Vector2) -> void:
	neck.rotate_y(-amount.x)
	camera.rotation.x = clamp(camera.rotation.x - amount.y * (-1.0 if invert_y else 1.0), deg_to_rad(-85.0), deg_to_rad(85.0))
	camera.rotation.y = 0.0
	camera.rotation.z = 0.0

func _input(event: InputEvent) -> void:
	if vr != null:
		return
	# Click window to capture cursor if it lost focus or was unlocked
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not _cursor_locked:
			_cursor_locked = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Mouse look
	if event is InputEventMouseMotion:
		if _cursor_locked and game_input.focused and not game_input.using_controller():
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_apply_look(event.relative * mouse_sensitivity)

	# Escape to toggle cursor lock
	if event is InputEventKey and not event.echo and event.is_action_pressed("ui_cancel"):
		_toggle_cursor()

	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E and _cursor_locked and game_input.focused and not game_input.using_controller():
		interact()

	# Flashlight toggle
	if not game_input.using_controller() and game_input.focused and event is InputEventKey and event.pressed and event.keycode == KEY_F and not event.echo:
		if flashlight:
			toggle_flashlight()

func _physics_process(delta: float) -> void:
	if door_prompt != null:
		door_prompt.hide()
		if vr == null and _cursor_locked and game_input.focused and $UI/HintLabel.is_visible_in_tree():
			var key := "Triangle / Y" if game_input.using_controller() else "E"
			var door := InteriorDoor.target(camera,self)
			if door != null:
				if door.obstructed(): door_prompt.text = "Doorway obstructed"
				elif door.moving: door_prompt.text = "Opening…" if door.target_open else "Closing…"
				else: door_prompt.text = key + (" — Close" if door.target_open else " — Open")
				door_prompt.modulate.a = $UI/HintLabel.modulate.a
				door_prompt.show()
	if vr != null:
		vr.tick(delta)
		return
	if _cursor_locked:
		_apply_look(game_input.look() * game_input.LOOK_RADIANS_PER_SECOND * delta)
	var jump_requested := _controller_jump if game_input.using_controller() else Input.is_action_just_pressed("jump")
	_controller_jump = false
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	# Crouch handling
	var wants_crouch := game_input.held("crouch")
	_is_crouching = wants_crouch or (collision_shape.shape.height < STAND_HEIGHT - 0.01 and not can_stand())
	var target_cam_y = CROUCH_CAM_Y if _is_crouching else STAND_CAM_Y
	neck.position.y = lerp(neck.position.y, target_cam_y, minf(delta * 10.0, 1.0))
	
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var target_height = CROUCH_HEIGHT if _is_crouching else STAND_HEIGHT
		collision_shape.shape.height = lerp(collision_shape.shape.height, target_height, minf(delta * 10.0, 1.0))
		collision_shape.position.y = collision_shape.shape.height * 0.5

	neck.position.y = minf(neck.position.y, collision_shape.shape.height - 0.15)
	if game_input.focused and jump_requested and is_on_floor() and not _is_crouching:
		velocity.y = jump_velocity

	# Unlimited sprint
	var wants_sprint = game_input.held("sprint") and not _is_crouching and is_on_floor()
	
	var current_speed = walk_speed
	if _is_crouching:
		current_speed = crouch_speed
	elif wants_sprint:
		current_speed = sprint_speed

	# Movement Input
	var input_dir = game_input.movement()
	var direction = neck.transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	
	if direction != Vector3.ZERO:
		velocity.x = lerp(velocity.x, direction.x * current_speed, delta * 12.0)
		velocity.z = lerp(velocity.z, direction.z * current_speed, delta * 12.0)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 14.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 14.0)

	_try_stair_step(Vector3(velocity.x,0,velocity.z) * delta)
	move_and_slide()

	# Head Bob & Footsteps
	_process_head_bob(delta, direction.length() > 0.1 and is_on_floor(), current_speed)
	

func _process_head_bob(delta: float, is_moving: bool, current_speed: float) -> void:
	if is_moving:
		var speed_mult = 1.4 if current_speed == sprint_speed else (0.8 if _is_crouching else 1.0)
		_bob_timer += delta * bob_frequency * speed_mult * math_pi_mult()
		var bob_offset_y = sin(_bob_timer * 2.0) * bob_amplitude * 0.5
		var bob_offset_x = cos(_bob_timer) * bob_amplitude * 0.3
		camera.position.y = bob_offset_y
		camera.position.x = bob_offset_x
		
		# Footstep sound on bottom of bob cycle
		_step_cooldown -= delta
		if sin(_bob_timer * 2.0) < -0.85 and _step_cooldown <= 0.0:
			_play_footstep()
			_step_cooldown = 0.35 / speed_mult
	else:
		_bob_timer = 0.0
		camera.position = camera.position.lerp(Vector3.ZERO, delta * 10.0)

func math_pi_mult() -> float:
	return 3.14159

func _play_footstep() -> void:
	if footstep_audio and footstep_sounds.size() > 0:
		var snd = footstep_sounds[randi() % footstep_sounds.size()]
		footstep_audio.stream = snd
		footstep_audio.pitch_scale = randf_range(0.92, 1.08)
		footstep_audio.volume_db = -8.0 if _is_crouching else (-3.0 if game_input.held("sprint") else -5.0)
		footstep_audio.play()

func can_stand() -> bool:
	_standing_shape.radius = collision_shape.shape.radius
	_standing_shape.height = STAND_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _standing_shape
	query.transform = global_transform
	query.transform.origin += Vector3.UP * (STAND_HEIGHT * 0.5 + 0.015)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.005
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _try_stair_step(motion: Vector3) -> void:
	if not is_on_floor() or velocity.y > 0.0 or motion.length_squared() < 0.000001: return
	var obstruction := KinematicCollision3D.new()
	if not test_move(global_transform, motion, obstruction): return
	var obstacle := obstruction.get_collider() as Node
	if obstacle == null or not obstacle.is_in_group("walkable_stairs"): return
	var raised := global_transform
	if test_move(raised, Vector3.UP * 0.22): return
	raised.origin.y += 0.22
	if test_move(raised, motion): return
	# Probe the tread ahead of the capsule's rounded foot; an edge contact normal
	# is slanted even though the actual tread is horizontal.
	var probe: Vector3 = global_position + motion.normalized() * (collision_shape.shape.radius + 0.06)
	var query := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.22, probe - Vector3.UP * 0.02, collision_mask, [get_rid()])
	var landing := get_world_3d().direct_space_state.intersect_ray(query)
	if landing.is_empty() or not landing.collider.is_in_group("walkable_stairs"): return
	var rise: float = landing.position.y - global_position.y
	if rise > 0.01 and rise <= 0.22: global_position.y += rise + 0.001
