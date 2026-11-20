extends Node
## Bounded two-second samples in the existing local vr-game.log; no upload.
var rig: Node3D
var intervals: Array[float] = []
var elapsed := 0.0
var since_sample := 0.0
var previous_usec := 0

func _ready() -> void:
	previous_usec = Time.get_ticks_usec()
	print("VR_CONFIG ", JSON.stringify({"walk_mps": rig.WALK_SPEED, "run_mps": rig.RUN_SPEED,
		"desktop_walk_mps": rig.player.walk_speed, "desktop_run_mps": rig.player.sprint_speed,
		"seed": GameSettings.active_seed(), "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"render_scale": get_viewport().scaling_3d_scale, "msaa": get_viewport().msaa_3d,
		"screen_space_aa": get_viewport().screen_space_aa, "requested_fxaa": GameSettings.value("render.fxaa"),
		"shadows": GameSettings.value("lighting.shadows_enabled")}))

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - previous_usec) / 1000.0
	if intervals.size() < 1200:
		intervals.append(frame_ms)
	previous_usec = now
	elapsed += frame_ms / 1000.0
	since_sample += frame_ms / 1000.0
	if since_sample < 2.0: return
	since_sample = 0.0
	print("VR_PERF ", JSON.stringify(sample()))
	intervals.clear()

func sample() -> Dictionary:
	var ordered := intervals.duplicate()
	ordered.sort()
	var manager: Node = rig.player.get_parent().get_node_or_null("ChunkManager")
	var result := {"seconds": snappedf(elapsed, 0.1), "fps": Engine.get_frames_per_second(),
		"frame_p95_ms": ordered[int((ordered.size() - 1) * 0.95)] if not ordered.is_empty() else 0.0,
		"frame_max_ms": ordered.back() if not ordered.is_empty() else 0.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"memory_bytes": OS.get_static_memory_usage(),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"focused": rig.focused, "running": rig.running, "flashlight": rig.player.flashlight.visible,
		"refresh_hz": rig.interface.display_refresh_rate if rig.interface != null else 0.0}
	if manager != null:
		result.merge({"active_chunks": manager._active_chunks.size(), "pending_chunks": manager._chunks_to_load.size(),
			"loaded_total": manager.loaded_total, "last_load_ms": manager.last_load_ms, "peak_load_ms": manager.peak_load_ms})
	return result
