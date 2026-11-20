extends RefCounted
## Save-state capture and restoration of player pose after a validated arrival.
const Memory = preload("res://scripts/session/run_memory.gd")

static func capture(run: Dictionary, world: Node3D, memory: Node) -> Dictionary:
	var data:=run.duplicate(true)
	data.settings=GameSettings.snapshot()
	data.seed=GameSettings.active_seed()
	data.settings.world.seed=data.seed
	data.settings.world.seed_mode="fixed"
	data["generation_id"]=GameSettings.active_generation_id()
	data["pose"]=pose_for(world.get_node("Player"))
	var manager:=world.get_node("ChunkManager")
	if manager.has_method("rebase_if_needed"):
		data.pose["museum_origin_wing"]=manager.origin_wing
	data.journal=memory.journal.snapshot()
	data["saved"]=Time.get_datetime_string_from_system()
	data["build"]=GameSettings.GENERATOR_VERSION
	data.erase("sound")
	return data

static func pose_for(player: Node3D) -> Dictionary:
	var camera_rotation: Vector3 = Vector3.ZERO if player.vr != null else player.camera.rotation
	var neck_rotation: Vector3 = Vector3(0, player.vr.rotation.y, 0) if player.vr != null else player.neck.rotation
	return {
		"position": Memory.vector(player.global_position),
		"rotation": Memory.vector(player.rotation),
		"neck_rotation": Memory.vector(neck_rotation),
		"camera_rotation": Memory.vector(camera_rotation),
		"crouching": player._is_crouching,
		"flashlight_on": player.flashlight.visible,
	}

static func restore_pose(player: Node3D, pose: Dictionary) -> void:
	player.rotation=Memory.vec(pose.rotation)
	player.neck.rotation=Memory.vec(pose.neck_rotation)
	player.camera.rotation=Memory.vec(pose.camera_rotation)
	player.flashlight.visible=pose.flashlight_on
	player._is_crouching=pose.crouching
	if player._is_crouching:
		player.collision_shape.shape=player.collision_shape.shape.duplicate()
		player.collision_shape.shape.height=1.0
		player.collision_shape.position.y=0.5
