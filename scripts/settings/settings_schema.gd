extends RefCounted
class_name SettingsSchema
## Authoritative public launch settings: default followed by bounds or allowed values.
const RULES: Dictionary = {
	"schema_version": [2, [2]],
	"world.seed_mode": ["fixed", ["fixed", "random"]],
	"world.seed": [1930, -2147483648, 2147483647],
	"layout.museum_annexes": [false],
	"lighting.shadows_enabled": [true],
	"environment.ssao.enabled": [true],
	"environment.fog.enabled": [true],
	"player.camera.fov_degrees": [75.0, 50.0, 110.0],
	"player.camera.sensitivity": [0.002, 0.0001, 0.02],
	"player.camera.bob_amplitude": [0.04, 0.0, 0.12],
	"player.camera.bob_frequency": [2.4, 0.5, 5.0],
	"player.camera.invert_y": [false],
	"player.movement.walk_speed": [2.0, 0.5, 8.0],
	"player.movement.sprint_speed": [4.0, 0.5, 12.0],
	"player.movement.crouch_speed": [1.6, 0.2, 5.0],
	"player.movement.jump_velocity": [4.2, 0.0, 8.0],
	"player.movement.gravity": [14.0, 1.0, 30.0],
	"player.flashlight.initially_on": [false],
	"player.stamina.maximum": [100.0, 1.0, 500.0],
	"ui.show_controls_guide": [true],
	"diagnostics.overlay_toggle_enabled": [true],
	"diagnostics.overlay_visible": [false],
	"audio.impacts.enabled": [true],
	"audio.impacts.gain_db": [0.0, -60.0, 6.0],
	"audio.impacts.muted": [false],
	"audio.master.gain_db": [0.0, -60.0, 6.0],
	"audio.master.muted": [false],
	"audio.music.gain_db": [-13.9794, -60.0, 0.0],
	"audio.music.muted": [false],
	"audio.footsteps.gain_db": [0.0, -60.0, 6.0],
	"audio.footsteps.muted": [false],
	"render.quality": ["high", ["low", "medium", "high"]],
	"render.scale": [1.0, 0.5, 1.5],
	"render.mesh_lod_threshold": [1.0, 0.0, 8.0],
	"render.msaa": [4, [0, 2, 4, 8]],
	"render.fxaa": [false],
	"display.vsync": [true],
	"display.fps_cap_enabled": [true],
	"display.window_mode": ["project", ["project", "windowed", "fullscreen", "exclusive_fullscreen"]],
	"display.resolution": ["native", ["native", "1280x720", "1280x800", "1600x900", "1920x1080", "1920x1200", "2560x1440", "2560x1600", "3840x2160"]],
	"display.width": [1920, 640, 7680],
	"display.height": [1080, 360, 4320],
	"diagnostics.write_manifest": [true],
	"diagnostics.bug_capture_enabled": [true],
	"diagnostics.capture_location": ["sibling", ["sibling", "user"]]
}

static func defaults(platform := OS.get_name()) -> Dictionary:
	var result: Dictionary = {}
	for path: String in RULES:
		put(result, path, RULES[path][0])
	match platform:
		"macOS": result.display.resolution = "1280x720"
		"Windows": result.display.resolution = "1920x1080"
	return result

static func new_exploration_defaults() -> Dictionary:
	var result:=defaults()
	result.layout.museum_annexes = true
	return result

static func put(target: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var cursor := target
	for i in range(parts.size() - 1):
		if not cursor.get(parts[i]) is Dictionary: cursor[parts[i]] = {}
		cursor = cursor[parts[i]]
	cursor[parts[-1]] = value.duplicate(true) if value is Array or value is Dictionary else value
