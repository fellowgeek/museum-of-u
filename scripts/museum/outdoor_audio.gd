extends AudioStreamPlayer
## Apply location gain before the visitor's music bus and keep the soundtrack clock running.
const FADE_SECONDS := 3.0
var outdoor_mix := 0.0
var layers: Array[AudioStreamPlayer] = []
var inlet: AudioStreamPlayer3D
@onready var manager: MuseumManager = $"../ChunkManager"

func _ready() -> void:
	var source_run := not OS.has_feature("template")
	var install := SettingsLoader.default_path(OS.get_executable_path(), source_run, ProjectSettings.globalize_path("res://")).get_base_dir()
	var folders := PackedStringArray([install.path_join("third_party_assets")])
	# A promoted local build can hear the author's next recording on its next visit.
	if not source_run and install.get_file() == "build" and FileAccess.file_exists(install.get_base_dir().path_join("project.godot")):
		folders.append(install.get_base_dir().path_join("third_party_assets"))
	load_layers(folders)
	var garden := manager.outdoor_garden_at(manager.player.global_position)
	if garden != null:
		inlet = garden.get_node("Inlet")
		outdoor_mix = 1.0
	apply_mix()

func load_layers(folders: PackedStringArray) -> void:
	for label in ["birds","insects"]:
		var sample := load_recording(folders, label)
		if sample == null and label == "birds": sample = preload("res://assets/audio/outdoor/woodland_birds.ogg")
		if sample == null: continue
		var layer := AudioStreamPlayer.new()
		layer.name = label
		layer.stream = sample
		add_child(layer)
		layers.append(layer)

static func load_recording(folders: PackedStringArray, label: String) -> AudioStream:
	for folder in folders:
		for ext in ["ogg","wav","mp3"]:
			var path := folder.path_join(label + "." + ext)
			if not FileAccess.file_exists(path): continue
			var sound: AudioStream
			match ext:
				"ogg": sound = AudioStreamOggVorbis.load_from_file(path)
				"mp3": sound = AudioStreamMP3.load_from_file(path)
				"wav": sound = AudioStreamWAV.load_from_file(path, {"edit/loop_mode": 2})
			if sound == null or sound.get_length() <= 0: continue
			if sound is AudioStreamOggVorbis or sound is AudioStreamMP3: sound.loop = true
			return sound
	return null

func _process(delta: float) -> void:
	var garden := manager.outdoor_garden_at(manager.player.global_position)
	if garden != null and (not is_instance_valid(inlet) or garden != inlet.get_parent()):
		if is_instance_valid(inlet): inlet.stop()
		inlet = garden.get_node("Inlet")
		apply_mix()
	var target := 1.0 if garden != null else 0.0
	if is_equal_approx(outdoor_mix,target): return
	outdoor_mix = move_toward(outdoor_mix, target, delta/FADE_SECONDS)
	apply_mix()

func apply_mix() -> void:
	var level := smoothstep(0.0,1.0,outdoor_mix)
	volume_linear = 1.0 - level
	for layer in layers:
		layer.volume_linear = (.21 if layer.name == &"birds" else .12) * level
		if level > 0 and not layer.playing: layer.play()
		elif level == 0 and layer.playing: layer.stop()
	if is_instance_valid(inlet):
		inlet.volume_linear = .45 * level
		if level > 0 and not inlet.playing: inlet.play()
		elif level == 0 and inlet.playing: inlet.stop()
