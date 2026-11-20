extends XROrigin3D
## Shared tracked controls; the game adapter supplies grounded locomotion.
signal interaction
signal event_recorded(event: String)

const SNAP_ANGLE := PI / 6.0
var turn_ready := false
const WALK_SPEED := 1.5
const DEADZONE := 0.2
const BODY_RADIUS := 0.22
const BODY_CENTER := 0.85

var camera := XRCamera3D.new()
var left := XRController3D.new()
var right := XRController3D.new()
var body := CharacterBody3D.new()
var fade := MeshInstance3D.new()
var fade_material := StandardMaterial3D.new()
var head_shape := SphereShape3D.new()
var lean_blocked := false
var smooth_distance := 0.0
var snap_turn_radians := 0.0
var collision_frames := 0
var input_armed := false
var left_ready := false
var interaction_count := 0

func _ready() -> void:
	camera.name = "Head"
	camera.near = 0.05
	add_child(camera)
	for hand in [left, right]:
		hand.tracker = &"left_hand" if hand == left else &"right_hand"
		hand.pose = &"aim"
		add_child(hand)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, 0.06, 0.16)
		var model := MeshInstance3D.new()
		model.mesh = mesh
		model.material_override = material(Color.CYAN if hand == left else Color.CORAL)
		hand.add_child(model)
	body.top_level = true
	body.collision_layer = 0
	body.collision_mask = 1
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_child(body)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = 1.6
	shape.shape = capsule
	body.add_child(shape)
	body.global_position = Vector3(0, BODY_CENTER, 0)
	head_shape.radius = 0.12
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4)
	fade.mesh = quad
	fade.position.z = -0.1
	fade_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_material.no_depth_test = true
	fade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fade_material.render_priority = 127
	fade_material.albedo_color = Color(0, 0, 0, 0)
	fade.material_override = fade_material
	fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(fade)
	fade.hide()
	suspend_input()

static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	return result

func suspend_input() -> void:
	input_armed = false
	left_ready = false
	turn_ready = false
	left.visible = false
	right.visible = false

func tick_controls(active: bool, stick: float, test_trigger: float, move_stick := Vector2.ZERO, delta := 0.0) -> void:
	if not active:
		suspend_input()
		return
	if not input_armed:
		# Never carry held controls across session focus or tracking loss.
		input_armed = absf(stick) <= DEADZONE and test_trigger < 0.2 and move_stick.length() <= DEADZONE
		left_ready = input_armed
		turn_ready = input_armed
		return
	if lean_blocked:
		return
	snap_turn(stick)
	if test_trigger < 0.2:
		left_ready = true
	if left_ready and test_trigger > 0.75:
		left_ready = false
		interaction_count += 1
		interaction.emit()
		event_recorded.emit("left_trigger")
	walk(move_stick, delta)

func snap_turn(stick: float) -> void:
	if not input_armed or lean_blocked:
		return
	if absf(stick) <= DEADZONE:
		turn_ready = true
	if turn_ready and absf(stick) >= 0.7:
		turn_ready = false
		var angle := -signf(stick) * SNAP_ANGLE
		rotate_around_head(angle)
		snap_turn_radians += absf(angle)

func rotate_around_head(angle: float) -> void:
	var pivot := camera.global_position
	rotate_y(angle)
	var correction := pivot - camera.global_position
	correction.y = 0.0
	global_position += correction

func recenter_heading() -> void:
	var backward := camera.global_basis.z
	if Vector2(backward.x, backward.z).length() > 0.01:
		rotate_around_head(-atan2(backward.x, backward.z))
	suspend_input()

func update_tracking(active: bool, delta := 0.0) -> void:
	var tracked := left.get_has_tracking_data() and right.get_has_tracking_data() and head_tracked()
	left.visible = active and left.get_has_tracking_data()
	right.visible = active and right.get_has_tracking_data()
	if not active or not tracked:
		suspend_input()
		return
	update_physical_body()
	poll_controls(delta)

func poll_controls(delta: float) -> void:
	tick_controls(true, right.get_vector2("turn").x, left.get_float("trigger"), left.get_vector2("move"), delta)

func head_tracked() -> bool:
	var head := XRServer.get_tracker("head") as XRPositionalTracker
	if head == null:
		return false
	var pose := head.get_pose("default")
	return pose != null and pose.has_tracking_data

static func walk_velocity(stick: Vector2, head_basis: Basis) -> Vector3:
	var strength := clampf((stick.length() - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	if strength == 0.0:
		return Vector3.ZERO
	var forward := -head_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		# Preserve heading while looking straight up/down using the tracked right axis.
		forward = Vector3.UP.cross(head_basis.x)
	forward = forward.normalized()
	var sideways := forward.cross(Vector3.UP)
	# OpenXR thumbstick Y is positive when pushed forward.
	return (sideways * stick.normalized().x + forward * stick.normalized().y) * strength * WALK_SPEED

func move_body(motion: Vector3) -> void:
	for attempt in 3:
		if motion.length_squared() < 0.00000001:
			return
		var hit := body.move_and_collide(motion)
		if hit == null:
			return
		collision_frames += 1
		motion = hit.get_remainder().slide(hit.get_normal())

func update_physical_body() -> void:
	var desired := Vector3(camera.global_position.x, BODY_CENTER, camera.global_position.z)
	move_body(desired - body.global_position)
	var separation := desired.distance_to(body.global_position)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = head_shape
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	query.collision_mask = 1
	var head_inside := not get_world_3d().direct_space_state.intersect_shape(query).is_empty()
	var amount := clampf((separation - 0.02) / 0.10, 0.0, 1.0)
	if head_inside:
		amount = 1.0
	var blocked := amount > 0.0
	if blocked != lean_blocked:
		lean_blocked = blocked
		suspend_input()
		event_recorded.emit("lean_blocked" if blocked else "lean_clear")
	fade.visible = blocked
	fade_material.albedo_color.a = amount

func walk(stick: Vector2, delta: float) -> void:
	if not input_armed or lean_blocked or delta <= 0.0:
		return
	var before := body.global_position
	move_body(walk_velocity(stick, camera.global_basis) * minf(delta, 0.05))
	var applied := body.global_position - before
	global_position += applied
	smooth_distance += applied.length()
