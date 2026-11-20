extends RefCounted
## Oat grass in the exterior beds. One instanced draw per bed and one shared mesh.
static var tuft: ArrayMesh

static func plant(parent: Node3D, opening: Dictionary) -> void:
	if tuft == null: tuft = make_tuft()
	var rng := RandomNumberGenerator.new()
	rng.seed = roundi(opening.at.z * 100.0)
	var plants := MultiMesh.new()
	plants.transform_format = MultiMesh.TRANSFORM_3D
	plants.mesh = tuft
	var columns := maxi(3, floori(opening.width / .36))
	plants.instance_count = columns * 3
	var along_axis := Vector3(absf(opening.inward.z),0,absf(opening.inward.x))
	for i in plants.instance_count:
		var along: float = ((i % columns + rng.randf_range(.18, .82)) / columns - .5) * opening.width
		var depth := .42 + .40 * floori(float(i) / columns) + rng.randf_range(-.09, .09)
		var at: Vector3 = opening.at - opening.inward * depth + Vector3.UP*.68 + along_axis*along
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * rng.randf_range(.73, 1.18))
		plants.set_instance_transform(i, Transform3D(basis, at))
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = plants
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(grass)

static func make_tuft() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = .89
	surface.set_material(mat)
	for i in 40:
		var angle := i * 2.39996
		var radial := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-radial.z, 0, radial.x)
		var base := radial * rng.randf_range(.015, .14)
		var spike := i % 5 == 0
		var height := rng.randf_range(.87, 1.23) if spike else rng.randf_range(.38, .9)
		var spread := rng.randf_range(.13, .34)
		var width := .006 if spike else rng.randf_range(.011, .023)
		var tip := Color("d3af77") if spike else Color("a7a15f").lerp(Color("c5b285"), rng.randf())
		var left := base - side * width
		var right := base + side * width
		var color := Color("575b36")
		for step in range(1, 6):
			var t := step / 5.0
			var mid := base + Vector3.UP * height * (t - (.07 if spike else .39) * t * t) + radial * spread * t * t
			var radius := width * (1.0 - t)
			if spike and step == 4: radius = .023
			var next_left := mid - side * radius
			var next_right := mid + side * radius
			var next_color := Color("575b36").lerp(tip, t)
			for vertex in [[left, color], [next_left, next_color], [right, color],
					[right, color], [next_left, next_color], [next_right, next_color]]:
				surface.set_color(vertex[1])
				surface.set_normal((radial + Vector3.UP * .55).normalized())
				surface.add_vertex(vertex[0])
			left = next_left
			right = next_right
			color = next_color
	return surface.commit()
