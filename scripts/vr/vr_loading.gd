extends Node3D
## Camera-local loading feedback shared by world preparation and seed travel.
var label := Label3D.new()
var spinner := Node3D.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector3(0, -0.03, -1.2)
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.95, 0.38)
	panel.mesh = quad
	panel.material_override = flat_material(Color(0.025, 0.022, 0.015, 0.98), 124)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	spinner.position = Vector3(0, 0.075, 0.003)
	add_child(spinner)
	for index in 8:
		var dot := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.008
		mesh.height = 0.016
		dot.mesh = mesh
		dot.position = Vector3(cos(index * TAU / 8), sin(index * TAU / 8), 0) * 0.04
		dot.material_override = flat_material(Color(1, 0.86, 0.58, 0.2 + index * 0.1), 125)
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spinner.add_child(dot)
	label.position = Vector3(0, -0.065, 0.004)
	label.font_size = 36
	label.pixel_size = 0.0009
	label.width = 950
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.no_depth_test = true
	label.render_priority = 126
	label.modulate = Color(1, 0.95, 0.85)
	add_child(label)
	hide()

func flat_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color
	material.render_priority = priority
	return material

func begin(message: String) -> void:
	label.text = message + "\nPlease wait…"
	show()

func _process(delta: float) -> void:
	if visible: spinner.rotation.z -= delta * 3.0

static func present(tree: SceneTree) -> void:
	# The camera/panel can be freed by a disconnect while this frame is submitted.
	await tree.process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
