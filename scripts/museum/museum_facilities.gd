extends RefCounted
## Hydronic plant and adjacent pipe passage. Coordinates are relative to the service wing.
static var equipment: PackedScene
var room := Node3D.new()
var body := StaticBody3D.new()
var surfaces: Dictionary = {}
var iron := finish("454e50", .48)
var enamel := finish("587c76", .24)
var copper := finish("a96846", .57)
var blue := finish("5a7c91", .42)
var brass := finish("c49858", .63)
var red := finish("a44c3c", .30)
var porcelain := finish("eeead6", .10)
var concrete := finish("938e81", .0)

static func finish(tint: String, metal: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint)
	mat.metallic = metal
	mat.roughness = .40 if metal > .1 else .74
	return mat

func surface(mat: Material) -> SurfaceTool:
	if not surfaces.has(mat):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(mat)
		surfaces[mat] = tool
	return surfaces[mat]

func part(mesh: PrimitiveMesh, transform: Transform3D, mat: Material) -> void:
	var arrays := mesh.get_mesh_arrays()
	var tool := surface(mat)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in arrays[Mesh.ARRAY_INDEX]:
		tool.set_normal((transform.basis * normals[i]).normalized())
		tool.add_vertex(transform * vertices[i])

func collider(shape: Shape3D, at: Transform3D) -> void:
	var c := CollisionShape3D.new()
	c.shape = shape
	c.transform = at
	body.add_child(c)

func block(at: Vector3, size: Vector3, mat: Material, solid := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var transform := Transform3D(Basis.IDENTITY,at)
	part(mesh,transform,mat)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		collider(shape,transform)

func cylinder(a: Vector3, b: Vector3, radius: float, mat: Material, solid := false) -> void:
	var direction := (b-a).normalized()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 32 if radius > .4 else 16
	mesh.rings = 0
	var at := Transform3D(Basis(Quaternion(Vector3.UP,direction)),(a+b)*.5)
	part(mesh,at,mat)
	if solid:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = mesh.height
		collider(shape,at)

func torus(at: Vector3, normal: Vector3, radius: float, thickness: float, mat: Material) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = radius-thickness
	ring.outer_radius = radius+thickness
	ring.rings = 24
	ring.ring_segments = 8
	part(ring,Transform3D(Basis(Quaternion(Vector3.UP,normal)),at),mat)

func pipe(corners: Array, radius: float, mat: Material, solid := false) -> void:
	# Fillet each elbow on the centerline, then sweep one continuous, uncapped tube.
	var points: Array[Vector3] = [corners[0]]
	for i in range(1,corners.size()-1):
		var corner: Vector3 = corners[i]
		var turn := minf(.32, minf(corner.distance_to(corners[i-1]),corner.distance_to(corners[i+1]))*.4)
		var a := corner.move_toward(corners[i-1],turn)
		var b := corner.move_toward(corners[i+1],turn)
		for step in 7:
			var t := step/6.0
			points.append(a.lerp(corner,t).lerp(corner.lerp(b,t),t))
	points.append(corners.back())
	var tool := surface(mat)
	var previous := PackedVector3Array()
	var side := Vector3.UP
	if absf(side.dot(points[0].direction_to(points[1]))) > .9: side = Vector3.RIGHT
	for i in points.size():
		var axis := points[maxi(0,i-1)].direction_to(points[mini(i+1,points.size()-1)])
		side = (side-axis*side.dot(axis)).normalized()
		var cross_axis := axis.cross(side)
		var ring := PackedVector3Array()
		for j in 16:
			var angle := TAU*j/16.0
			ring.append(side*cos(angle)+cross_axis*sin(angle))
		if i > 0:
			for j in 16:
				var k := (j+1)%16
				for v in [[i-1,previous[j]],[i,ring[j]],[i,ring[k]],
						[i-1,previous[j]],[i,ring[k]],[i-1,previous[k]]]:
					tool.set_normal(v[1])
					tool.add_vertex(points[v[0]] + v[1]*radius)
			if solid:
				var length := points[i].distance_to(points[i-1])
				var shape := CapsuleShape3D.new()
				shape.radius = radius
				shape.height = length+2*radius
				collider(shape,Transform3D(Basis(Quaternion(Vector3.UP,points[i-1].direction_to(points[i]))),(points[i-1]+points[i])*.5))
		previous = ring

func gauge(at: Vector3, angle: float) -> void:
	# Glassless enamel dial, raised bezel, and a contrasting pointer on the front.
	cylinder(at,at+Vector3.FORWARD*.075,.148,brass)
	var face := at+Vector3.FORWARD*.078
	cylinder(face,face+Vector3.FORWARD*.008,.126,porcelain)
	for i in 7:
		var phi := deg_to_rad(-120+i*40)
		var toward := Vector3(sin(phi),cos(phi),0)
		cylinder(face+toward*.088+Vector3.FORWARD*.009,face+toward*.108+Vector3.FORWARD*.009,.004,iron)
	var needle := Vector3(sin(angle),cos(angle),0)
	cylinder(face+Vector3.FORWARD*.014,face+needle*.083+Vector3.FORWARD*.014,.009,red)

func wheel(at: Vector3) -> void:
	cylinder(at+Vector3.BACK*.24,at,.035,brass)
	torus(at,Vector3.FORWARD,.19,.022,red)
	for i in 3:
		var angle := TAU*i/3
		cylinder(at,at+Vector3(cos(angle),sin(angle),0)*.173,.014,red)
	cylinder(at+Vector3.BACK*.035,at+Vector3.FORWARD*.035,.045,brass)

func station(x: float, top: float, line: Material) -> void:
	var z := 31.4
	block(Vector3(x,.12,z),Vector3(2.08,.24,2.08),concrete,true)
	cylinder(Vector3(x,.24,z),Vector3(x,.42,z),.68,iron,true)
	cylinder(Vector3(x,.42,z),Vector3(x,2.94,z),.78,enamel,true)
	var cap := SphereMesh.new()
	cap.radius = .78
	cap.height = .66
	cap.radial_segments = 32
	cap.rings = 12
	part(cap,Transform3D(Basis.IDENTITY,Vector3(x,2.94,z)),enamel)
	for y in [.51,1.68,2.91]: cylinder(Vector3(x,y-.023,z),Vector3(x,y+.023,z),.794,iron)
	for y in [.91,2.20]:
		cylinder(Vector3(x,y,z-.72),Vector3(x,y,z-.93),.093,brass)
	gauge(Vector3(x,2.20,z-.93),.53 if x<16 else -.38)
	wheel(Vector3(x,.91,z-1.10))
	var feed_z := 26.6 if x < 16 else 27.45
	pipe([Vector3(x,3.24,z),Vector3(x,top,z),Vector3(x,top,feed_z),Vector3(19.8,top,feed_z),
		Vector3(19.8,top-1.9,feed_z),Vector3(20.90,top-1.9,feed_z)],.112,line)
	cylinder(Vector3(x,3.29,z),Vector3(x,3.36,z),.174,brass)
	cylinder(Vector3(20.84,top-1.9,feed_z),Vector3(20.90,top-1.9,feed_z),.21,iron)
	for at_z in [28.55,30.05]:
		torus(Vector3(x,top,at_z),Vector3.BACK,.124,.016,iron)
		for dx in [-.17,.17]:
			cylinder(Vector3(x+dx,top-.14,at_z),Vector3(x+dx,6,at_z),.012,iron)
		block(Vector3(x,top-.155,at_z),Vector3(.39,.04,.075),iron)
	var pump_z := 28.95
	block(Vector3(x,.135,pump_z),Vector3(1.52,.27,.82),concrete,true)
	block(Vector3(x,.34,pump_z),Vector3(1.22,.14,.56),iron,true)
	cylinder(Vector3(x-.52,.63,pump_z),Vector3(x+.20,.63,pump_z),.255,enamel,true)
	for i in 7:
		var at_x := x-.45+i*.085
		cylinder(Vector3(at_x,.63,pump_z),Vector3(at_x+.035,.63,pump_z),.28,iron)
	cylinder(Vector3(x+.20,.63,pump_z),Vector3(x+.50,.63,pump_z),.32,line,true)
	block(Vector3(x-.22,.93,pump_z),Vector3(.32,.11,.26),enamel)
	for dx in [-.58,.58]:
		for dz in [-.21,.21]:
			cylinder(Vector3(x+dx,.41,pump_z+dz),Vector3(x+dx,.45,pump_z+dz),.034,brass)
	pipe([Vector3(x+.37,.88,pump_z),Vector3(x+.37,1.22,pump_z),
		Vector3(x,1.22,pump_z),Vector3(x,1.22,z-.74)],.079,line,true)
	cylinder(Vector3(x,1.22,z-.92),Vector3(x,1.22,z-.86),.123,brass)

func work_light(at: Vector3, ceiling: float, energy: float) -> void:
	for dx in [-.53,.53]:
		cylinder(at+Vector3(dx,.09,0),Vector3(at.x+dx,ceiling,at.z),.015,iron)
	block(at+Vector3.UP*.055,Vector3(1.46,.11,.27),iron)
	block(at-Vector3.UP*.022,Vector3(1.34,.044,.205),porcelain)
	var light := OmniLight3D.new()
	light.position = at-Vector3.UP*.15
	light.light_color = Color("ffe7cd")
	light.light_energy = energy
	light.omni_range = 8.5
	light.omni_attenuation = .88
	room.add_child(light)

static func install(parent: Node3D, anchor: float) -> void:
	var instance: Node3D
	if equipment == null:
		# All wings use this equipment. Share the baked meshes and collision shapes.
		var builder = new()
		instance = builder.assemble()
		for part_node in instance.find_children("*", "", true, false):
			part_node.owner = instance
		equipment = PackedScene.new()
		var packed := equipment.pack(instance)
		assert(packed == OK)
	else:
		instance = equipment.instantiate()
	instance.position.x = anchor
	parent.add_child(instance)

func assemble() -> Node3D:
	room.name = "BuildingServices"
	room.add_child(body)
	porcelain.emission_enabled = true
	porcelain.emission = Color("e7e0c9")
	porcelain.emission_energy_multiplier = .22
	station(14.15,4.42,copper)
	station(17.35,4.82,blue)
	# Three insulated lines wrap the L-shaped passage, returning to the store wall.
	for i in 3:
		var y := .74+i*.52
		var x := 23.50
		var z := 38.47
		var mat: Material = [copper,blue,enamel][i]
		pipe([Vector3(x,y,24.10),Vector3(x,y,z),Vector3(12.10,y,z)],.084+i*.015,mat,true)
		for at_z in [25.0,28.0,31.0,34.0,37.0]:
			cylinder(Vector3(x,y,at_z-.045),Vector3(x,y,at_z+.045),.13+i*.015,brass)
			block(Vector3(23.74,y,at_z),Vector3(.30,.065,.075),iron)
		for at_x in [14.0,17.0,20.0,22.25]:
			cylinder(Vector3(at_x-.045,y,z),Vector3(at_x+.045,y,z),.13+i*.015,brass)
			block(Vector3(at_x,y,38.71),Vector3(.075,.065,.32),iron)
	# Pressure panel on a solid wall, away from the three door swings.
	block(Vector3(16,1.50,24.28),Vector3(2.1,1.4,.32),iron,true)
	for i in 3:
		var at := Vector3(15.40+i*.60,1.68,24.46)
		# Gauges face the aisle on this side of the plant.
		cylinder(at,at+Vector3.BACK*.055,.135,brass)
		cylinder(at+Vector3.BACK*.055,at+Vector3.BACK*.064,.114,porcelain)
		cylinder(at+Vector3.BACK*.077,at+Vector3(.055,.055,.077),.009,red)
		block(at+Vector3(0,-.32,.025),Vector3(.22,.08,.065),enamel)
	work_light(Vector3(16.5,3.72,26.0),6,3.10)
	work_light(Vector3(18.0,4.64,30),6,2.55)
	for at in [Vector3(22.48,2.51,27.6),Vector3(22.48,2.51,34.8),Vector3(15.7,2.51,36.2)]:
		work_light(at,3,1.55)
	for mat in surfaces:
		var tool: SurfaceTool = surfaces[mat]
		tool.index()
		var mesh := MeshInstance3D.new()
		mesh.mesh = tool.commit()
		room.add_child(mesh)
	return room
