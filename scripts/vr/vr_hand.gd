extends Node3D
## Mesh-only controller hand. Sample the CC0 poses without toolkit locomotion.
var skeleton: Skeleton3D
var poses: Dictionary = {}
var is_left := false
var controller_profile := ""

func configure(left_hand: bool) -> void:
	is_left = left_hand
	var side := "left" if is_left else "right"
	var model: Node3D = load("res://assets/models/xr_hands/Hand_low_%s.gltf" % ("L" if is_left else "R")).instantiate()
	add_child(model)
	model.position = Vector3(0.01 if is_left else -0.01, 0, 0.05)
	skeleton = model.find_child("Skeleton3D", true, false)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.13, 0.15)
	material.roughness = 0.92
	material.normal_enabled = true
	material.normal_texture = preload("res://assets/models/xr_hands/glove_normal.png")
	material.normal_scale = 0.1
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
	for pose in ["Grip", "Grip 5", "Grip Shaft", "Sign_Point"]:
		var animation: Animation = load("res://assets/models/xr_hands/%s/%s.res" % [side, pose])
		var rotations: Dictionary = {}
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
			var path := animation.track_get_path(track)
			var bone := skeleton.find_bone(path.get_subname(0))
			if bone >= 0: rotations[bone] = animation.rotation_track_interpolate(track, 0.0)
		poses[pose] = rotations
	update_pose(0, 0, false)
	apply_profile("")

func apply_profile(profile: String) -> void:
	controller_profile = profile
	# XR Tools palm calibration: Touch grip is steeper than the Index/default grip.
	rotation.x = deg_to_rad(-60.0 if profile in ["/interaction_profiles/oculus/touch_controller", "/interaction_profiles/facebook/touch_controller_pro", "/interaction_profiles/meta/touch_controller_plus"] else -45.0)

func update_profile(controller: XRController3D) -> void:
	var tracker := XRServer.get_tracker(controller.tracker) as XRControllerTracker
	if tracker != null and tracker.profile != controller_profile:
		apply_profile(tracker.profile)

func update_pose(trigger: float, grip: float, pointing: bool) -> void:
	if skeleton == null: return
	var base: Dictionary = poses["Grip Shaft" if is_left else "Sign_Point" if pointing else "Grip 5"]
	var closed: Dictionary = poses["Grip"]
	for bone: int in base:
		var index := "Index_" in skeleton.get_bone_name(bone)
		# The left hand always holds the flashlight; only a slight squeeze is visible.
		var amount := (0.78 + 0.04 * (trigger if index else grip)) if is_left else (trigger if index else grip)
		skeleton.set_bone_pose_rotation(bone, base[bone].slerp(closed.get(bone, base[bone]), clampf(amount, 0, 1)))
