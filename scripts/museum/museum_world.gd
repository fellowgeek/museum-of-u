extends Node3D
## Museum daylight, display lighting and the two-track gallery soundtrack.
const SOUNDTRACK: Array[AudioStreamMP3] = [
	preload("res://assets/audio/music/music1.mp3"),
	preload("res://assets/audio/music/music2.mp3"),
]
var track_index := 0

func _enter_tree() -> void:
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_SKY
	var panorama:=PanoramaSkyMaterial.new()
	panorama.panorama=preload("res://assets/textures/museum/autumn_park_4k.hdr")
	panorama.energy_multiplier = .62
	var sky:=Sky.new(); sky.sky_material=panorama
	environment.sky=sky
	# Align the park panorama's afternoon sun with the directional light.
	environment.sky_rotation.y = deg_to_rad(-28.0)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("e4e9f3")
	environment.ambient_light_energy=.30
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure=1.02
	environment.ssao_enabled=true; environment.ssao_radius=.65; environment.ssao_intensity=1.2
	environment.ssao_light_affect=.2
	$WorldEnvironment.environment=environment
	if not GameSettings.replay_report.is_empty():
		$Player.position=SettingsLoader.BugReport.to_vector(GameSettings.replay_report.player.position)

func _ready() -> void:
	$VisualEffects.configure($WorldEnvironment.environment)
	if GameSettings.replay_report.is_empty(): $Player.neck.rotation.y=PI
	$Player.flashlight.visible=false
	$Music.bus = GameSettings.AUDIO_BUSES.music
	$Music.finished.connect(advance_track)
	$Music.stream = SOUNDTRACK[0]
	$Music.play()

func advance_track() -> void:
	track_index = (track_index + 1) % SOUNDTRACK.size()
	$Music.stream = SOUNDTRACK[track_index]
	$Music.play()
