extends RefCounted
## Spatial batches keep the meadow, understory and canopy independently cullable.
const Plan = preload("res://scripts/museum/outdoor_plan.gd")
const Terrain = preload("res://scripts/museum/outdoor_terrain.gd")
const SPECIMENS := {
	"birch_23": preload("res://assets/models/museum/woodland/silver_birch_23.glb"),
	"birch_47": preload("res://assets/models/museum/woodland/silver_birch_47.glb"),
	"fir": preload("res://assets/models/museum/woodland/fir_tree.glb"),
	"maple": preload("res://assets/models/museum/woodland/ahorn_tree.glb"),
	"fern": preload("res://assets/models/museum/woodland/fern.glb"),
	"grass": preload("res://assets/models/museum/woodland/high_grass.glb"),
	"rock": preload("res://assets/models/museum/woodland/moss_stone.glb"),
}
# Measured trunk centers (X, Z) and radii at capsule height in the imported meshes.
const STEMS := {
	"fir": Vector3(-.026,.16,.089), "maple": Vector3(-.164,.30,-.067),
	"birch_23": Vector3(-.063,.14,.050), "birch_47": Vector3(.003,.13,.025),
}
const ROOT_BAND_HEIGHT := .15
const FIR_ROOT_BAND_HEIGHT := .36
const ROOT_BURIAL := .025
static var meshes := {}
static var root_vertices := {}
var batches := {}
var rng := RandomNumberGenerator.new()

func place(kind: String, p: Vector2, scale_factor: float, parent: Node3D, trunk := false, lift := 0.0) -> void:
	var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE*scale_factor)
	var height: float
	if STEMS.has(kind):
		height = Terrain.surface_height_at(p)
		for vertex: Vector3 in roots(kind):
			var offset := basis*vertex
			var ground := Terrain.surface_height_at(p+Vector2(offset.x,offset.z))
			height = minf(height, ground-offset.y)
	else:
		height = Terrain.height_at(p, Terrain.path_distance(p))
	var at := Vector3(p.x, height-ROOT_BURIAL+lift, p.y)
	var key := Vector2i(floori(p.x/16.0), floori(p.y/16.0))
	if not batches.has(kind): batches[kind] = {}
	if not batches[kind].has(key): batches[kind][key] = []
	batches[kind][key].append(Transform3D(basis, at))
	if trunk and Plan.GROUNDS.grow(.4).has_point(p):
		var stem := CylinderShape3D.new()
		var cross_section: Vector3 = STEMS[kind]
		stem.height = 2.9 * minf(scale_factor,1.0)
		stem.radius = cross_section.y * scale_factor
		var hit := CollisionShape3D.new()
		hit.shape = stem
		var center := at + basis*Vector3(cross_section.x,0,cross_section.z)
		center.y = Terrain.surface_height_at(Vector2(center.x,center.z)) - ROOT_BURIAL + stem.height*.5
		hit.position = center
		parent.add_child(hit)

static func specimen_mesh(specimen: Node3D) -> Mesh:
	var model := specimen as MeshInstance3D
	if model == null: model = specimen.find_children("*","MeshInstance3D",true,false)[0]
	return model.mesh

static func roots(kind: String) -> PackedVector3Array:
	if not root_vertices.has(kind):
		# The scanned fir has raised root tips beyond its lowest vertices.
		# Include those tips so the base stays seated when it turns on a slope.
		var band := FIR_ROOT_BAND_HEIGHT if kind == "fir" else ROOT_BAND_HEIGHT
		var specimen: Node3D = SPECIMENS[kind].instantiate()
		var mesh := specimen_mesh(specimen)
		var unique := {}
		for surface in mesh.get_surface_count():
			for vertex: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if vertex.y <= band: unique[vertex] = true
		root_vertices[kind] = PackedVector3Array(unique.keys())
		specimen.free()
	return root_vertices[kind]

func allowed(p: Vector2, margin: float) -> bool:
	return not Plan.COURT.grow(margin).has_point(p) and p.distance_to(Plan.GLADE) > Plan.GLADE_RADIUS + margin and Terrain.path_distance(p) > Plan.PATH_HALF_WIDTH + margin

func tree_site(p: Vector2, trees: Array[Vector2], spacing: float) -> bool:
	for pocket: Vector2 in Plan.SUN_POCKETS:
		if p.distance_squared_to(pocket) < 10.0: return false
	if Plan.GROUNDS.grow(.8).has_point(p) and not Plan.GROUNDS.grow(-.8).has_point(p): return false
	for tree in trees:
		if tree.distance_squared_to(p) < spacing*spacing: return false
	return true

func plant_canopy(kind: String, p: Vector2, size: float, trunks: Node3D) -> void:
	if kind == "maple":
		# Low maple sprays reach nearly five meters from the trunk at source scale.
		var crown := 4.9*size
		var room := allowed(p,crown)
		for pocket: Vector2 in Plan.SUN_POCKETS:
			if p.distance_to(pocket) < crown+1.15: room = false
		if not room: kind = "birch_23"
	place(kind,p,size,trunks,true)

func plant_back_woods(trunks: Node3D, trees: Array[Vector2]) -> void:
	# Stagger mixed-age stands beyond the loop, with lighter birch pockets among the firs.
	# Continue beyond the far fence so the wooded horizon has depth from inside the grove.
	for x in range(28,99,4):
		for z in range(-12,46,4):
			var p := Vector2(x+rng.randf_range(-1.6,1.6),z+rng.randf_range(-1.6,1.6))
			if not allowed(p,1.85) or not tree_site(p,trees,3.05): continue
			var species := rng.randf()
			var birch_wood := sin(p.x*.16+p.y*.13) > .22
			var kind := "fir"
			if birch_wood and species < .55: kind = "birch_23" if rng.randf()<.5 else "birch_47"
			elif species > .78: kind = "maple"
			trees.append(p)
			plant_canopy(kind,p,rng.randf_range(.62,1.17),trunks)
	# Fern colonies and small patches of regeneration leave open leaf litter between them.
	for i in 145:
		var p := Vector2(rng.randf_range(43.0,88.0),rng.randf_range(-6.0,36.0))
		if i%4 == 0 and tree_site(p,trees,1.8):
			place("fir",p,rng.randf_range(.19,.42),trunks,true)
			trees.append(p)
		var kind := "fern" if sin(p.x*.27-p.y*.18)+rng.randf_range(-.55,.55) > -.30 else "grass"
		for j in rng.randi_range(3,7):
			var q := p+Vector2(rng.randf_range(-1.4,1.4),rng.randf_range(-.85,.85))
			place(kind,q,rng.randf_range(.67,1.31),trunks)
	for pocket: Vector2 in Plan.SUN_POCKETS:
		var angle := rng.randf_range(0,TAU)
		for i in 5:
			angle += rng.randf_range(.72,1.40)
			var patch := pocket+Vector2.from_angle(angle)*rng.randf_range(3.8,6.1)
			if tree_site(patch,trees,1.65):
				place("birch_47" if i%3 == 0 else "fir",patch,rng.randf_range(.22,.43),trunks,true)
				trees.append(patch)
			for j in 10:
				var root := patch+Vector2(rng.randf_range(-1.35,1.35),rng.randf_range(-1.0,1.0))
				place("fern",root,rng.randf_range(1.05,2.05),trunks)

func plant(garden: Node3D, seed_value: int) -> void:
	rng.seed = seed_value
	var trunks := StaticBody3D.new()
	trunks.name = "TreeTrunks"
	garden.add_child(trunks)
	# One canopy just beyond the water; taller firs lead into the loop.
	for item in [["maple",Vector2(10,13),.88],["fir",Vector2(23.8,8.9),.86],
			["maple",Vector2(45.4,20.7),1.04],["fir",Vector2(32.6,18.3),.84],
			["birch_23",Vector2(39.8,27.7),.87],["birch_47",Vector2(42.1,27.9),.78],
			["birch_47",Vector2(17.8,13.2),.85]]:
		place(item[0], item[1], item[2], trunks, true)
	var trees: Array[Vector2] = [Vector2(10,13),Vector2(23.8,8.9),Vector2(45.4,20.7),Vector2(32.6,18.3), Vector2(39.8,27.7),Vector2(42.1,27.9),Vector2(17.8,13.2)]
	for i in range(7, 67, 5):
		var spread := smoothstep(18.0,32.0,i)
		for j in range(-18, 51, 5):
			var p := Vector2(i+rng.randf_range(-1.8,1.8), j+rng.randf_range(-1.8,1.8))
			if p.y < -3.4-15.0*spread or p.y > 37.5+13.0*spread or not allowed(p,2.0): continue
			if not tree_site(p,trees,3.87): continue
			trees.append(p)
			var kind := "fir" if rng.randf() < .58 else "maple"
			if kind == "maple" and rng.randf() < .37:
				kind = "birch_23" if trees.size()%2 == 0 else "birch_47"
			plant_canopy(kind,p,rng.randf_range(.66,1.22),trunks)
	# Young firs and fern colonies fill the sheltered banks between mature trees.
	for i in 50:
		var p := Vector2(rng.randf_range(18.8,53),rng.randf_range(.8,33))
		if not allowed(p,1.15) or Terrain.path_distance(p) > 7.5 or not tree_site(p,trees,1.25): continue
		trees.append(p)
		place("fir",p,rng.randf_range(.23,.48),trunks,true)
		for j in 4:
			var off := p+Vector2(rng.randf_range(-1.1,1.1),rng.randf_range(-1.1,1.1))
			if allowed(off,.1): place("fern",off,rng.randf_range(.83,1.4),trunks)
	# Small colonies have gaps between them, with denser patches along the path margins.
	# Reeds break the line of the pool and screen, with clustered ferns at their feet.
	for i in 26:
		var p := Vector2(15.65 + rng.randf_range(-1.98,1.98), 7.02+rng.randf_range(-.22,.22))
		place("sedge", p, rng.randf_range(.52,.83), trunks, false,.22)
	for i in 22:
		var p := Vector2(6.7+i*.59,-3.45+rng.randf_range(-.12,.12))
		place("sedge",p,rng.randf_range(.65,1.15),trunks)
	for i in 350:
		var center := Vector2(rng.randf_range(6.5,54), rng.randf_range(-3.1,37.4))
		if not allowed(center,.09): continue
		var kind: String = ["fern","sedge","grass","grass"][rng.randi_range(0,3)]
		for j in rng.randi_range(2,6):
			var p := center + Vector2(rng.randf_range(-1.15,1.15),rng.randf_range(-.86,.86))
			if p.x < 6.1 or p.y < -3.3 or not allowed(p,.06): continue
			var size := rng.randf_range(.48, .91) if kind == "sedge" else rng.randf_range(.74,1.58)
			place(kind,p,size,trunks)
	for p in [Vector2(16,11),Vector2(26,8.6),Vector2(38.4,14.8),Vector2(31,26.8),
			Vector2(22.5,18),Vector2(13,17),Vector2(42.4,24.6),Vector2(20,4.8)]:
		place("rock",p,rng.randf_range(.58,1.1),trunks)
	# Plant the sheltered strip behind the entrance parapet and the banks
	# beyond the fence, leaving the neighboring service rooms clear.
	for i in 17:
		var p := Vector2(.7+i*.29,-3.12+rng.randf_range(-.14,.14))
		place("fern" if i%3 == 0 else "grass",p,rng.randf_range(.9,1.6),trunks)
	for i in 30:
		var p := Vector2(rng.randf_range(18.0,52.0),rng.randf_range(-24.0,-5.0))
		if i%5 == 0: place("fir",p,rng.randf_range(.27,.6),trunks)
		for j in 4:
			place("fern" if j%2 == 0 else "grass",p+Vector2(rng.randf_range(-1,1),rng.randf_range(-1,1)),rng.randf_range(.9,1.6),trunks)
	plant_back_woods(trunks,trees)
	if not meshes.has("sedge"):
		meshes["sedge"] = preload("res://scripts/museum/window_grasses.gd").make_tuft()
	for kind: String in batches:
		if not meshes.has(kind):
			var specimen: Node3D = SPECIMENS[kind].instantiate()
			var mesh := specimen_mesh(specimen)
			if kind.begins_with("birch"):
				mesh = mesh.duplicate()
				for surface in mesh.get_surface_count():
					var mat := ShaderMaterial.new()
					if mesh.surface_get_material(surface).resource_name.begins_with("Birch bark"):
						mat.shader = preload("res://assets/shaders/birch_bark.gdshader")
						mat.set_shader_parameter("bark",preload("res://assets/textures/museum/woodland/birch_bark.jpg"))
					else:
						mat.shader = preload("res://assets/shaders/birch_leaves.gdshader")
					mesh.surface_set_material(surface,mat)
			if kind in ["fir","maple"]:
				mesh = mesh.duplicate()
				for surface in mesh.get_surface_count():
					var original := mesh.surface_get_material(surface) as StandardMaterial3D
					if not original.resource_name.contains("cutout"): continue
					var leaves := ShaderMaterial.new()
					leaves.shader = preload("res://assets/shaders/woodland_needles_leaves.gdshader")
					leaves.set_shader_parameter("spray", original.albedo_texture)
					leaves.set_shader_parameter("amplitude", .043 if kind == "fir" else .072)
					mesh.surface_set_material(surface,leaves)
			meshes[kind] = mesh
			specimen.free()
		for instances: Array in batches[kind].values():
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = meshes[kind]
			multi.instance_count = instances.size()
			for i in instances.size(): multi.set_instance_transform(i,instances[i])
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = multi
			batch.name = kind
			if kind in ["fern","grass","sedge","rock"]:
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				batch.visibility_range_end = 43.0
				batch.visibility_range_end_margin = 3.0
			garden.add_child(batch, true)
