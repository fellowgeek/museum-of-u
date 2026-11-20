extends RefCounted
const Plan = preload("res://scripts/museum/outdoor_plan.gd")
static var mesh: ArrayMesh
static var floor_shape: ConcavePolygonShape3D
static var grid_x: PackedFloat32Array
static var grid_z: PackedFloat32Array
static var grid_heights: PackedFloat32Array

static func path_distance(p: Vector2) -> float:
	return p.distance_to(Plan.trail().get_closest_point(p))

static func height_at(p: Vector2, trail_distance: float) -> float:
	var island := smoothstep(1.8, 4.4, trail_distance) * smoothstep(Plan.GLADE_RADIUS+.1, Plan.GLADE_RADIUS+2.8, p.distance_to(Plan.GLADE))
	var near_court := p.distance_to(p.clamp(Plan.COURT.position, Plan.COURT.end))
	var rise := (.20 + .12 * sin(p.x*.51 + p.y*.34) + .08 * cos(p.y*.72)) * island * smoothstep(.15, 2.8, near_court)
	rise += smoothstep(Plan.DEEP_WOODS_X-4,Plan.DEEP_WOODS_X+7,p.x) * (.27 + .33*sin(p.x*.17+p.y*.12) + .17*cos(p.y*.31-p.x*.08))
	var outside := p.distance_to(p.clamp(Plan.GROUNDS.position, Plan.GROUNDS.end))
	var bank := smoothstep(.3, 8.5, outside) * (1.5 + .72*sin(p.x*.22+p.y*.16) + .36*cos(p.y*.38))
	# The lawn continues under the foundations of the next wing. Keep the
	# service side below floor height even in the widest reversed layout.
	var lawn := smoothstep(-5.8,-2.8,p.y) * (1.0-smoothstep(32.2,38.0,p.y))
	var near_building := smoothstep(4.0,Plan.ENTRY_LENGTH,p.x) * maxf(lawn,smoothstep(16.5,22.5,p.x))
	return lerpf(-.18,(rise + bank) * smoothstep(Plan.ENTRY_LENGTH,Plan.ENTRY_LENGTH+1.6,p.x),near_building)

static func surface_height_at(p: Vector2) -> float:
	# Interpolate across the same diagonal as the rendered and collidable triangles.
	var i := clampi(grid_x.bsearch(p.x, false)-1, 0, grid_x.size()-2)
	var j := clampi(grid_z.bsearch(p.y, false)-1, 0, grid_z.size()-2)
	var x := clampf(inverse_lerp(grid_x[i],grid_x[i+1],p.x), 0.0, 1.0)
	var z := clampf(inverse_lerp(grid_z[j],grid_z[j+1],p.y), 0.0, 1.0)
	var first := i*grid_z.size()+j
	var next := first+grid_z.size()
	var low := grid_heights[first]
	var high := grid_heights[next+1]
	if x >= z:
		var edge := grid_heights[next]
		return low + x*(edge-low) + z*(high-edge)
	var edge := grid_heights[first+1]
	return low + z*(edge-low) + x*(high-edge)

static func install(parent: Node3D) -> void:
	if mesh == null:
		mesh = build_mesh()
		floor_shape = mesh.create_trimesh_shape()
	var land := MeshInstance3D.new()
	land.name = "WoodlandGround"
	land.mesh = mesh
	parent.add_child(land)
	var body := StaticBody3D.new()
	body.add_to_group("museum_floor")
	body.add_to_group("woodland_ground")
	var collision := CollisionShape3D.new()
	collision.shape = floor_shape
	body.add_child(collision)
	land.add_child(body)

static func build_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/woodland_ground.gdshader")
	mat.set_shader_parameter("leaf_litter", preload("res://assets/textures/museum/woodland/forest_leaves.jpg"))
	mat.set_shader_parameter("litter_normal", preload("res://assets/textures/museum/woodland/forest_leaves_normal.jpg"))
	mat.set_shader_parameter("meadow", preload("res://assets/textures/museum/woodland/meadow.jpg"))
	mat.set_shader_parameter("gravel", preload("res://assets/textures/museum/woodland/trail_gravel.jpg"))
	mat.set_shader_parameter("limestone", preload("res://assets/materials/museum/Concrete034/albedo.jpg"))
	mat.set_shader_parameter("court", Vector4(Plan.COURT.position.x, Plan.COURT.position.y, Plan.COURT.end.x, Plan.COURT.end.y))
	mat.set_shader_parameter("glade", Plan.GLADE)
	mat.set_shader_parameter("glade_radius", Plan.GLADE_RADIUS)
	mat.set_shader_parameter("deep_woods_x", Plan.DEEP_WOODS_X)
	surface.set_material(mat)
	# One welded grid passes under the museum and continues past the visible tree line.
	# Fine spacing follows the visitor route. Distance samples cost only a few rows.
	var xs := PackedFloat32Array([-182,-95,-45,-22,-9,-3,0,3,4,5.4])
	for i in 118: xs.append(Plan.ENTRY_LENGTH + i*(2.0/3.0))
	xs.append_array(PackedFloat32Array([91,100,119,158,192]))
	var zs := PackedFloat32Array([-185,-130,-96,-70,-49,-33,-23,-16,-12,-9,-7,-5,-3.6,-2.8,-2.3,-1.75])
	for j in 83: zs.append(lerpf(-1.4,39.6,j/82.0))
	zs.append(Plan.ENTRY_HALF_WIDTH)
	zs.sort()
	zs.append_array(PackedFloat32Array([41,45,51,62,77,98,131,184]))
	grid_x = xs
	grid_z = zs
	grid_heights.resize(xs.size()*zs.size())
	for i in xs.size():
		for j in zs.size():
			var p := Vector2(xs[i],zs[j])
			var distance := path_distance(p)
			surface.set_color(Color(1.0-smoothstep(.84, 1.68, distance), 0, 0))
			surface.set_uv(p)
			var k := i*zs.size()+j
			grid_heights[k] = height_at(p, distance)
			surface.add_vertex(Vector3(p.x, grid_heights[k], p.y))
			if i == 0 or j == 0: continue
			if xs[i-1] >= 0 and xs[i] <= Plan.ENTRY_LENGTH and zs[j-1] >= -Plan.ENTRY_HALF_WIDTH and zs[j] <= Plan.ENTRY_HALF_WIDTH:
				continue # The entrance slab owns this opening in the lawn.
			for index in [k-zs.size()-1, k-1, k, k-zs.size()-1, k, k-zs.size()]:
				surface.add_index(index)
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()
