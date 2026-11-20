extends Node
## Retains the application/VR presentation interface with neutral photographic color.
var screen_layer: CanvasLayer
func configure(environment: Environment, _settings: Dictionary={}) -> void:
	environment.fog_enabled=bool(GameSettings.value("environment.fog.enabled"))
	environment.fog_density=.0008
	environment.fog_light_color=Color(.76,.79,.82)
	environment.fog_light_energy=.35
	environment.fog_sky_affect=0.0
	environment.volumetric_fog_enabled=false
	environment.ssao_enabled=bool(GameSettings.value("environment.ssao.enabled"))
	var sun: DirectionalLight3D = get_parent().get_node("Sun")
	var shadows := bool(GameSettings.value("lighting.shadows_enabled"))
	sun.shadow_enabled = shadows
	# Without shadow maps the sun reaches through solid walls. Keep a soft key
	# for sculpture modeling and project the overhead openings onto the floors.
	sun.light_energy = 1.28 if shadows else .34
	for wing in get_parent().get_node("ChunkManager")._active_chunks.values():
		for floor_material: ShaderMaterial in wing.get_meta("daylight_floors"):
			floor_material.set_shader_parameter("shadowless", not shadows)
