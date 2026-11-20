extends RefCounted
const Plan = preload("res://scripts/museum/outdoor_plan.gd")
const Terrain = preload("res://scripts/museum/outdoor_terrain.gd")
const Planting = preload("res://scripts/museum/woodland_planting.gd")
const MARINA := preload("res://assets/models/museum/marina_bench/marina_bench.glb")
const HARDWOOD := preload("res://assets/models/museum/hardwood_park_bench/hardwood_park_bench.glb")
const Geometry = preload("res://scripts/museum/museum_geometry.gd")
const POST_WIDTH := .09
const ENTRY_JOINT := .018

static func install(builder: RefCounted, seed_value: int) -> void:
	var gate: Vector3 = builder.plan.garden_gate
	var garden := Node3D.new()
	garden.name = "OutdoorGarden"
	garden.transform = Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), gate)
	builder.wing.add_child(garden)
	# The threshold, cheeks and gallery floor share the same exposed-face inventory.
	var landing := Vector3(Plan.ENTRY_LENGTH*.5, -.12, 0)
	builder.box(garden.transform * landing, Vector3(Plan.ENTRY_LENGTH,.24,Plan.ENTRY_HALF_WIDTH*2), builder.concrete, true)
	for sign_z in [-1.0,1.0]:
		var z: float = sign_z*(Plan.ENTRY_HALF_WIDTH+.10)
		builder.box(garden.transform*Vector3(3,.53,z),Vector3(6,1.06,.20),builder.garden_plaster)
		builder.box(garden.transform*Vector3(3,1.105,z),Vector3(6,.09,.23),builder.concrete)
	Terrain.install(garden)
	var stone: Material = builder.concrete
	var fixtures := Geometry.new()
	pool(garden, fixtures, stone, builder.bronze)
	woodland_sculpture(garden, fixtures, builder.plinth_stone, builder.bronze, seed_value)
	fixtures.box(Vector3(15.65,.095,7.02),Vector3(4.45,.19,.84),stone)
	fixtures.box(Vector3(15.65,.204,7.02),Vector3(4.31,.028,.70),builder.soil)
	fixtures.build(garden)
	seat(garden, MARINA, Vector2(12.2,-1.25), 0)
	seat(garden, HARDWOOD, Vector2(40.1,22.45), -2.40)
	seat(garden, HARDWOOD, Vector2(41.2,18.55), -1.12)
	enclose(garden, builder.oak, builder.bronze)
	Planting.new().plant(garden, seed_value)

static func pool(garden: Node3D, fixtures: RefCounted, stone: Material, metal: Material) -> void:
	var center := Vector3(Plan.POOL.get_center().x,0,Plan.POOL.get_center().y)
	var inner := Plan.POOL.size
	const RIM := .24
	for side in [-1.0,1.0]:
		var x: float = side*(inner.x+RIM)*.5
		var z: float = side*(inner.y+RIM)*.5
		fixtures.box(center+Vector3(x,.22,0),Vector3(RIM,.44,inner.y+2*RIM),stone)
		fixtures.box(center+Vector3(0,.22,z),Vector3(inner.x,.44,RIM),stone)
	pool_guard(garden, center, inner+Vector2.ONE*RIM, metal)
	# The projecting bronze lip sits on a limestone inlet at the head of the basin.
	fixtures.box(center+Vector3(-4.72,.53,0),Vector3(.36,1.06,.82),stone)
	fixtures.box(center+Vector3(-4.45,.935,0),Vector3(.50,.075,.30),metal)
	var water := MeshInstance3D.new()
	water.name = "ReflectingPool"
	var surface := PlaneMesh.new()
	surface.size = inner
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/reflecting_pool.gdshader")
	mat.set_shader_parameter("court_view",preload("res://assets/textures/museum/woodland/pool_reflection.jpg"))
	surface.material = mat
	water.mesh = surface
	water.position = center + Vector3.UP*.36
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	garden.add_child(water)
	var inlet := AudioStreamPlayer3D.new()
	inlet.name = "Inlet"
	inlet.stream = preload("res://assets/audio/outdoor/water_rill.wav")
	inlet.position = center + Vector3(-3.7,.4,0)
	inlet.unit_size = 2.6
	inlet.max_distance = 18.0
	inlet.process_mode = Node.PROCESS_MODE_ALWAYS
	garden.add_child(inlet)
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sheet := ShaderMaterial.new()
	sheet.shader = preload("res://assets/shaders/water_spill.gdshader")
	ribbon.set_material(sheet)
	for step in 11:
		var t := step/10.0
		for edge in [-1.0,1.0]:
			ribbon.set_uv(Vector2(edge*.5+.5,t))
			ribbon.set_normal(Vector3(1.16*t,.5,0).normalized())
			ribbon.add_vertex(center+Vector3(-4.20+.52*t, .965-.61*t*t, edge*(.146-.042*t)))
		if step > 0:
			var i := step*2
			for vertex in [i-2,i-1,i,i-1,i+1,i]: ribbon.add_index(vertex)
	var spill := MeshInstance3D.new()
	spill.mesh = ribbon.commit()
	spill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	garden.add_child(spill)

static func pool_guard(garden: Node3D, center: Vector3, span: Vector2, bronze: Material) -> void:
	var rail: Array[Transform3D] = []
	var faces := PackedVector3Array()
	var half := span*.5
	var corners := [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i+1)%corners.size()]
		var start := center+Vector3(a.x,0,a.y)
		var end := center+Vector3(b.x,0,b.y)
		var stations: Array[Vector3] = []
		if i == 3:
			# Terminate either side of the inlet so the bronze lip pours freely.
			stations = [start,Vector3(start.x,0,center.z+.50),Vector3(start.x,0,center.z-.50),end]
		else:
			var count := ceili(start.distance_to(end)/1.9)
			for j in range(count+1): stations.append(start.lerp(end,float(j)/count))
		for j in range(stations.size()-1):
			var foot := stations[j]
			var next := stations[j+1]
			rail.append(Transform3D(Basis.from_scale(Vector3(.045,.56,.045)),foot+Vector3.UP*.72))
			if i == 3 and j == 1: continue
			var along := (next-foot).normalized().abs()
			var bar := (next-foot).abs() - along*.045 + Vector3(along.z*.032,.038,along.x*.032)
			rail.append(Transform3D(Basis.from_scale(bar),foot.lerp(next,.5)+Vector3.UP*.974))
		# Collision has four vertical faces and no top. A jump from the spout
		# or high-jump settings cannot turn the water into a walkable surface.
		var up := Vector3.UP*36.0
		faces.append_array(PackedVector3Array([start,end,end+up,start,end+up,start+up]))
	timber_batch(garden,rail,bronze,"PoolRail")
	var body := StaticBody3D.new()
	body.name = "PoolGuard"
	var mesh := ConcavePolygonShape3D.new()
	mesh.backface_collision = true
	mesh.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = mesh
	body.add_child(collision)
	garden.add_child(body)

const GARDEN_WORKS := ["bear_sculpture","horse_statue","wooden_elephant"]

static func woodland_sculpture(garden: Node3D, fixtures: RefCounted, stone: Material, bronze: Material, seed_value: int) -> void:
	var id: String = GARDEN_WORKS[posmod(seed_value,GARDEN_WORKS.size())]
	var model := load("res://assets/models/museum/%s/%s.glb"%[id,id]).instantiate() as Node3D
	var base := Vector3(34.35,0,20.75)
	var viewer := Vector3(40.0,0,21.0)-base
	model.rotation.y = atan2(viewer.x,viewer.z) + (0.0 if id == "wooden_elephant" else PI*.5)
	var bounds: AABB = model.transform * preload("res://scripts/museum/asset_library.gd").visual_bounds(model)
	var top := Vector3(maxf(bounds.size.x+.30,1.38), .45, maxf(bounds.size.z+.30,1.38))
	fixtures.box(base+Vector3.UP*.035,Vector3(top.x-.1,.07,top.z-.1),bronze)
	fixtures.box(base+Vector3.UP*.26,Vector3(top.x,.38,top.z),stone)
	model.position = base+Vector3.UP*top.y
	model.name = "WoodlandSculpture"
	model.set_meta("museum_asset_id",id)
	garden.add_child(model)

static func seat(garden: Node3D, model: PackedScene, at: Vector2, angle: float) -> void:
	var bench := model.instantiate() as Node3D
	bench.name = "GardenSeat"
	bench.position = Vector3(at.x,0,at.y)
	bench.rotation.y = angle
	bench.set_meta("museum_asset_id", model.resource_path.get_file().get_basename())
	garden.add_child(bench,true)

static func fence_layout() -> Dictionary:
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	var screen: Array[Transform3D] = []
	var a := Plan.GROUNDS.position
	var b := Plan.GROUNDS.end
	# The two terminal posts stand just beyond the stone ends, centered on each cheek.
	var front := Plan.ENTRY_LENGTH + POST_WIDTH*.5 + ENTRY_JOINT
	var cheek := Plan.ENTRY_HALF_WIDTH + .10
	var fence := [Vector2(front,-cheek),Vector2(front,a.y),Vector2(19.5,a.y),
			Vector2(b.x,a.y),b,Vector2(front,b.y),Vector2(front,cheek)]
	for i in range(fence.size()-1):
		var start: Vector2 = fence[i]
		var end: Vector2 = fence[i+1]
		var direction := (end-start).normalized()
		var length := start.distance_to(end)
		var count := maxi(1, ceili(length/2.25))
		for j in range(count+1):
			var point := start.lerp(end,float(j)/count)
			var base := Terrain.height_at(point,Terrain.path_distance(point))
			var p := Vector3(point.x,base,point.y)
			if j < count or i == fence.size()-2:
				var height := 1.97 if i == 1 or (i == 2 and j == 0) else 1.16
				posts.append(Transform3D(Basis.from_scale(Vector3(POST_WIDTH,height,POST_WIDTH)),p+Vector3.UP*(height*.5-.02)))
			if j == count: continue
			var bay := length/count
			var next := point+direction*bay
			var rise := Terrain.height_at(next,Terrain.path_distance(next))-base
			var across := Vector3(direction.x,rise/bay,direction.y)
			var clear := bay-POST_WIDTH
			if i == 1:
				# This bay is a palisade. Slats take the place of the two open rails.
				var slats := maxi(1,roundi(clear/.158))
				for k in slats:
					var offset := POST_WIDTH*.5 + (k+.5)*clear/slats
					var at := p + across*offset
					var height := 1.90 + .08*sin((at.x-front)*.76)
					screen.append(Transform3D(Basis.from_scale(Vector3(.116,height,.073)),at+Vector3.UP*(height*.5-.015)))
				continue
			# Shear the span up the grade. Its end cuts remain parallel to the plumb posts.
			var side := Vector3(-direction.y,0,direction.x)
			var rail_basis := Basis(across*(clear-.004),Vector3.UP*.062,side*.055)
			for h in [.51,.98]:
				rails.append(Transform3D(rail_basis,p+across*bay*.5+Vector3.UP*h))
	return {"outline":fence,"FencePosts":posts,"FenceRails":rails,"TimberScreen":screen}

static func enclose(garden: Node3D, wood: Material, bronze: Material) -> void:
	var layout := fence_layout()
	var body := StaticBody3D.new()
	body.name = "GardenBoundary"
	garden.add_child(body)
	for i in range(layout.outline.size()-1):
		var start: Vector2 = layout.outline[i]
		var end: Vector2 = layout.outline[i+1]
		var along := end-start
		var middle := (start+end)*.5
		var guard := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(along.length()+.10,3.0,.10)
		guard.shape = shape
		guard.transform = Transform3D(Basis(Vector3.UP,atan2(-along.y,along.x)),Vector3(middle.x,1.49,middle.y))
		body.add_child(guard)
	for sign_z in [-1.0,1.0]:
		var guard := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(Plan.ENTRY_LENGTH,3,.14)
		guard.shape = shape
		guard.position = Vector3(Plan.ENTRY_LENGTH*.5,1.5,sign_z*(Plan.ENTRY_HALF_WIDTH+.10))
		body.add_child(guard)
	for batch_name: StringName in [&"FencePosts",&"FenceRails",&"TimberScreen"]:
		timber_batch(garden,layout[batch_name],bronze if batch_name == &"FencePosts" else wood,batch_name)

static func timber_batch(parent: Node3D, transforms: Array[Transform3D], material: Material, batch_name: StringName) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.material = material
	batch.mesh = box
	batch.instance_count = transforms.size()
	for i in transforms.size(): batch.set_instance_transform(i,transforms[i])
	var pieces := MultiMeshInstance3D.new()
	pieces.name = batch_name
	pieces.multimesh = batch
	parent.add_child(pieces)
