extends Node3D
## Chunk-owned animated door; open state survives streaming for this game session.
const MODEL = preload("res://scenes/props/door.tscn")
const OPEN_SOUNDS := [preload("res://assets/audio/events/door_open_01.wav"),preload("res://assets/audio/events/door_open_02.wav"),preload("res://assets/audio/events/door_open_03.wav")]
const CLOSE_SOUND = preload("res://assets/audio/events/door_close.wav")
const BLOCKED_SOUNDS := [preload("res://assets/audio/events/door_blocked_01.wav"),preload("res://assets/audio/events/door_blocked_02.wav")]
const SWEEP_STEPS := 32
const CLOSE_LEAD := 0.130125
const COLORS := {"red":Color(0.48,0.10,0.075),"brown":Color(0.28,0.15,0.075)}
var color_variant := "white"
var voice: AudioStreamPlayer3D
var sound_events := 0
var last_sound := ""
var _close_started := false
var _open_count := 0
var _blocked_count := 0
var _sweep: Array[Transform3D] = []
var _sweep_shape: BoxShape3D
var state_key := ""
var target_open := false
var moving := false
var animation: AnimationPlayer
var clip: StringName
var hinge: Node3D
var leaf_body: AnimatableBody3D
var progress := 0.0
var duration := 0.0

func _ready() -> void:
	add_to_group("interactive_doors")
	var model := preload("res://scripts/museum/asset_library.gd").local_scene("door", MODEL).instantiate()
	add_child(model)
	apply_color(model)
	voice = AudioStreamPlayer3D.new()
	voice.position = Vector3(0,1.2,0)
	voice.bus = "Settings_impacts"
	voice.max_distance = 12.0
	voice.unit_size = 2.0
	voice.max_db = -3.0
	voice.volume_db = -3.0
	add_child(voice)
	hinge = model.find_child("Hinge", true, false)
	animation = model.find_child("AnimationPlayer", true, false)
	for candidate in animation.get_animation_list():
		if candidate != "RESET": clip = candidate; break
	duration = animation.get_animation(clip).length
	# Sample the imported clip explicitly on physics ticks so visuals and hull agree.
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play(clip)
	animation.seek(0.0, true)
	leaf_body = AnimatableBody3D.new()
	leaf_body.sync_to_physics = false
	leaf_body.set_meta("door", self)
	hinge.add_child(leaf_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.97536, 2.4184, 0.04572)
	shape.shape = box
	leaf_body.add_child(shape)
	shape.global_position = to_global(Vector3(0,1.2292,0.046656))
	# Sample the actual hinge path; widen the thin slab to cover between samples.
	_sweep_shape = BoxShape3D.new()
	_sweep_shape.size = Vector3(0.97536,2.4184,0.10)
	for step in range(SWEEP_STEPS+1):
		animation.seek(duration*step/SWEEP_STEPS,true)
		_sweep.append(global_transform.affine_inverse()*shape.global_transform)
	animation.seek(0.0,true)
	for x in [-0.5053,0.5053]:
		_add_frame_hull(Vector3(x,1.23708,0.0053),Vector3(0.0353,2.47416,0.12))
	_add_frame_hull(Vector3(0,2.45628,0.0053),Vector3(0.9753,0.03576,0.12))
	var states: Dictionary = get_tree().get_meta("door_states", {})
	target_open = states.get(state_key, false) if not state_key.is_empty() else false
	var memory := get_node_or_null("/root/RunMemory")
	if memory and memory.active: target_open = memory.get_state("door",state_key).get("open",false)
	progress = duration if target_open else 0.0
	animation.seek(progress, true)

func _add_frame_hull(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("door", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = at
	body.add_child(shape)
	add_child(body)

func obstructed() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sweep_shape
	query.margin = 0.002
	var opening := target_open if moving else not target_open
	var current := clampi(roundi(progress/duration*SWEEP_STEPS),0,SWEEP_STEPS)
	var first := maxi(0,current-1) if opening else 0
	var last := SWEEP_STEPS if opening else mini(SWEEP_STEPS,current+1)
	for step in range(first,last+1):
		query.transform = global_transform*_sweep[step]
		for hit in get_world_3d().direct_space_state.intersect_shape(query,64):
			if hit.collider is CharacterBody3D or hit.collider is RigidBody3D: return true
	return false

func interact() -> bool:
	if moving: return false
	if obstructed():
		if not voice.playing:

			play_sound(BLOCKED_SOUNDS[_blocked_count%BLOCKED_SOUNDS.size()])
			_blocked_count += 1
		return false
	_start_motion(not target_open)
	return true

func _start_motion(opening: bool) -> void:
	target_open = opening
	moving = true
	_close_started = false
	voice.stop()

	voice.stream_paused = false
	if target_open:
		play_sound(OPEN_SOUNDS[(absi(state_key.hash())+_open_count)%OPEN_SOUNDS.size()])
		_open_count += 1

func _physics_process(delta: float) -> void:
	if not moving: return
	var blocked := obstructed()
	voice.stream_paused = blocked
	if blocked: return
	progress = move_toward(progress, duration if target_open else 0.0, delta)
	animation.seek(progress, true)
	if not target_open and not _close_started and progress <= CLOSE_LEAD:
		_close_started = true
		play_sound(CLOSE_SOUND)
	if is_equal_approx(progress,duration if target_open else 0.0):
		moving = false
		if not state_key.is_empty():
			var memory := get_node_or_null("/root/RunMemory")
			if memory and memory.active: memory.door_changed(state_key,target_open)
			else:
				var states: Dictionary = get_tree().get_meta("door_states", {})
				if target_open: states[state_key] = true
				else: states.erase(state_key)
				get_tree().set_meta("door_states", states)

static func target(camera: Node3D, player: CollisionObject3D) -> Node3D:
	var from := camera.global_position
	var to := from-camera.global_basis.z*2.2
	var query := PhysicsRayQueryParameters3D.create(from,to,1,[player.get_rid()])
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var nearest: Node3D = null
	var distance := 2.2
	if not hit.is_empty():
		distance = from.distance_to(hit.position)
		if hit.collider.has_meta("door"): nearest = hit.collider.get_meta("door")
	# A stationary, two-sided aperture stays usable after the leaf swings away.
	# The first physical hit still blocks interaction through walls or furniture.
	for door in camera.get_tree().get_nodes_in_group("interactive_doors"):
		var local_from: Vector3 = door.to_local(from)
		var local_to: Vector3 = door.to_local(to)
		var direction := local_to-local_from
		if absf(direction.z)<0.0001: continue
		var fraction := -local_from.z/direction.z
		if fraction<0.0 or fraction>1.0: continue
		var point := local_from+direction*fraction
		if absf(point.x)>float(door.get_meta("aperture_half_width",0.49)) or point.y<0.02 or point.y>2.44: continue
		var candidate_distance: float = from.distance_to(door.to_global(point))
		if candidate_distance<distance:
			distance=candidate_distance
			nearest=door
	return nearest

func play_sound(stream: AudioStream) -> void:
	if not GameSettings.value("audio.impacts.enabled"): return
	voice.stream = stream
	voice.play()
	sound_events += 1
	last_sound = stream.resource_path

static func variant_for(key: String) -> String:
	var roll := absi((key+":paint").hash())%100
	return "white" if roll<70 else "red" if roll<85 else "brown"

func apply_color(model: Node3D) -> void:
	assert(color_variant == "white" or COLORS.has(color_variant))
	var paint: StandardMaterial3D
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(surface)
			if original.resource_name != "Material": continue
			if paint == null:
				paint = original.duplicate()
				if color_variant != "white": paint.albedo_color = COLORS[color_variant]
				paint.metallic = 0.0
				paint.roughness = 0.88
				paint.roughness_texture = null
				paint.metallic_specular = 0.2
				paint.clearcoat_enabled = false
			mesh.set_surface_override_material(surface,paint)
