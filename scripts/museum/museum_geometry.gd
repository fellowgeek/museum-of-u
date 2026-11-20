extends RefCounted
## Solid assembly with covered axis-aligned faces removed before triangulation.
const EPS := 0.00001
const STRIDE := preload("res://scripts/museum/gallery_plan.gd").STRIDE
var solids: Array[Dictionary] = []
var arches: Array[Dictionary] = []
var roof_corners: Array[Dictionary] = []
var masks: Array[AABB] = []
var streams: Dictionary = {}
var exposed: Array[Dictionary] = []
# At streamed joins each wing owns only its half of the wall and arch.
# The neighboring floor/wall/roof section masks the covered ends of our solids.
var join_sections: Dictionary = {}
var lantern_collision: Array[PackedVector3Array] = []
var plane_blockers: Array[Dictionary] = [{}, {}, {}]

## The ribs seat between two bronze upstands. Only their four long faces are
## exposed. The rectangular sockets remove the hidden faces of the upstands.
func roof_lantern(rect: Rect2, height: float, timber: Material, bronze: Material) -> void:
	var center := rect.get_center()
	var half_span := rect.size.x * .5 + .14
	var spring := height + .36
	var rib_height := .29
	var thickness := .115
	var rise := rect.size.x * .16
	var faces := PackedVector3Array()
	for side in [-1.0, 1.0]:
		box(Vector3(center.x + side * (half_span + .08), height + .475, center.y),
			Vector3(.16, .45, rect.size.y), bronze)
	var count := roundi(rect.size.y / .75)
	for index in count:
		var z := rect.position.y + (index + .5) * rect.size.y / count
		for side in [-1.0, 1.0]:
			masks.append(AABB(Vector3(center.x + side * half_span, spring, z - thickness * .5),
				Vector3(0, rib_height, thickness)))
		var previous: Array[Vector3] = []
		for segment in 25:
			var t := segment / 24.0
			var x := center.x + lerpf(-half_span, half_span, t)
			var y := spring + 4.0 * rise * t * (1.0 - t)
			var ring: Array[Vector3] = [Vector3(x, y, z - thickness * .5), Vector3(x, y, z + thickness * .5),
				Vector3(x, y + rib_height, z + thickness * .5), Vector3(x, y + rib_height, z - thickness * .5)]
			if segment > 0:
				for i in 4:
					var j := (i + 1) % 4
					var normal := (ring[i] - previous[i]).cross(previous[j] - previous[i]).normalized()
					emit([previous[i], ring[i], ring[j], previous[j]], normal, timber)
					faces.append_array(PackedVector3Array([previous[i], ring[i], ring[j], previous[i], ring[j], previous[j]]))
			previous = ring
	lantern_collision.append(faces)

func set_join(z: float, adjacent: RefCounted) -> void:
	var sections: Array[Rect2] = []
	var row := 0 if is_zero_approx(z) else roundi(z/adjacent.GRID)-1
	for cell: Vector2i in adjacent.cells:
		if cell.y != row: continue
		var height: float = adjacent.rooms[adjacent.cells[cell]].height
		var left: float = -(cell.x+1)*adjacent.GRID
		sections.append(Rect2(left,-.24,adjacent.GRID,height+.49))
		sections.append(Rect2(left-.1,0,adjacent.GRID+.2,height))
	join_sections[z] = sections

func clip_join_solids() -> void:
	for solid in solids:
		var b: AABB = solid.bounds
		var low := maxf(0,b.position.z) if join_sections.has(0.0) else b.position.z
		var high := minf(STRIDE,b.end.z) if join_sections.has(STRIDE) else b.end.z
		b.position.z = low
		b.size.z = high-low
		solid.bounds = b

func box(at: Vector3, size: Vector3, material: Material, floor_surface := false, face_finishes := {}) -> void:
	var solid := {"bounds":AABB(at-size/2,size),"material":material,"floor":floor_surface}
	if not face_finishes.is_empty(): solid["face_finishes"] = face_finishes
	solids.append(solid)

func round_skylight(rect: Rect2, height: float, radius: float, material: Material) -> void:
	for sx in [-1,1]:
		for sz in [-1,1]:
			var corner:=Vector2(rect.position.x if sx<0 else rect.end.x,rect.position.y if sz<0 else rect.end.y)
			var center:=corner-Vector2(sx,sz)*radius
			var low:=Vector2(minf(corner.x,center.x),minf(corner.y,center.y))
			masks.append(AABB(Vector3(low.x,height,low.y),Vector3(radius,.25,radius)))
			roof_corners.append({"corner":corner,"center":center,"sx":sx,"sz":sz,"radius":radius,"height":height,"material":material})

func build_roof_corner(parent: Node3D, p: Dictionary) -> void:
	var faces:=PackedVector3Array()
	for i in 24:
		var a0: float=i*PI/48
		var a1: float=(i+1)*PI/48
		var a: Vector2=p.center+Vector2(p.sx*cos(a0),p.sz*sin(a0))*p.radius
		var b: Vector2=p.center+Vector2(p.sx*cos(a1),p.sz*sin(a1))*p.radius
		for h in [p.height,p.height+.25]:
			# Horizontal faces use the same clipping/overlap inventory as the slabs.
			axis_face([Vector2(p.corner.y,p.corner.x),Vector2(a.y,a.x),Vector2(b.y,b.x)],1,h,-1 if h==p.height else 1,p.material,-1)
			faces.append_array(PackedVector3Array([Vector3(p.corner.x,h,p.corner.y),Vector3(a.x,h,a.y),Vector3(b.x,h,b.y)]))
		var edge: Array=[Vector3(a.x,p.height,a.y),Vector3(b.x,p.height,b.y),Vector3(b.x,p.height+.25,b.y),Vector3(a.x,p.height+.25,a.y)]
		var inward: Vector2=(p.center-(a+b)/2).normalized()
		emit(edge,Vector3(inward.x,0,inward.y),p.material)
		faces.append_array(PackedVector3Array([edge[0],edge[1],edge[2],edge[0],edge[2],edge[3]]))
	var body:=StaticBody3D.new()
	var shape:=ConcavePolygonShape3D.new(); shape.backface_collision=true; shape.set_faces(faces)
	var collision:=CollisionShape3D.new(); collision.shape=shape
	body.add_child(collision); parent.add_child(body)

func arch(at: Vector3, width: float, spring: float, rise: float, height: float, material: Material, surround: Material, turn := false) -> void:
	arches.append({"at":at,"width":width,"spring":spring,"rise":rise,"height":height,"material":material,"surround":surround,"turn":turn})
	var size := Vector3(width+.48,height-spring,.2)
	if turn: size=Vector3(.2,height-spring,width+.48)
	for side in [-1,1]:
		var jamb_size:=Vector3(.24,spring,.36) if not turn else Vector3(.36,spring,.24)
		var jamb_at:=Vector3(side*(width/2+.12),spring/2,0) if not turn else Vector3(0,spring/2,side*(width/2+.12))
		# Stone owns the coincident opening face, ahead of the plaster backing.
		solids.push_front({"bounds":AABB(at+jamb_at-jamb_size/2,jamb_size),"material":surround,"floor":false})
	masks.append(AABB(at+Vector3(0,(height+spring)/2,0)-size/2,size))

static func clip(poly: Array, axis: int, limit: float, above: bool) -> Array:
	var result: Array = []
	if poly.is_empty(): return result
	var previous: Vector2=poly[-1]
	var previous_in: bool=previous[axis]>=limit if above else previous[axis]<=limit
	for point: Vector2 in poly:
		var inside: bool=point[axis]>=limit if above else point[axis]<=limit
		if inside != previous_in:
			var fraction: float=(limit-previous[axis])/(point[axis]-previous[axis])
			var intersection:=previous.lerp(point,fraction)
			intersection[axis]=limit
			result.append(intersection)
		if inside: result.append(point)
		previous=point; previous_in=inside
	return result

static func area(poly: Array) -> float:
	var result := 0.0
	if poly.size()<3: return result
	# Local coordinates avoid cancellation for narrow clipped strips far from zero.
	var origin: Vector2=poly[0]
	for i in range(1,poly.size()-1): result += (Vector2(poly[i])-origin).cross(Vector2(poly[i+1])-origin)
	return absf(result)*.5

static func subtract(poly: Array, rect: Rect2) -> Array:
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for point: Vector2 in poly: bounds = bounds.expand(point)
	var overlap := bounds.intersection(rect)
	if overlap.size.x <= EPS or overlap.size.y <= EPS: return [poly]
	if rect.grow(EPS).encloses(bounds): return []
	var result: Array = []
	var remaining := poly
	for edge in [[0,rect.position.x,false],[0,rect.end.x,true],[1,rect.position.y,false],[1,rect.end.y,true]]:
		var axis: int = edge[0]
		var plane: float = edge[1]
		# Coplanar boxes can round to opposite sides of a join by a few microns.
		if absf(plane-bounds.position[axis]) <= EPS: plane = bounds.position[axis]
		elif absf(plane-bounds.end[axis]) <= EPS: plane = bounds.end[axis]
		var outside := clip(remaining,axis,plane,edge[2])
		if area(outside)>EPS: result.append(outside)
		remaining=clip(remaining,axis,plane,not edge[2])
		if area(remaining)<=EPS: break
	return result

func emit(points: Array, normal: Vector3, material: Material) -> void:
	if points.size()<3: return
	if not streams.has(material):
		var tool:=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(material)
		streams[material]=tool
	var surface: SurfaceTool=streams[material]
	for i in range(1,points.size()-1):
		var triangle: Array=[points[0],points[i],points[i+1]]
		if (Vector3(triangle[1])-Vector3(triangle[0])).cross(Vector3(triangle[2])-Vector3(triangle[0])).dot(normal)>0:
			triangle.reverse()
		for point: Vector3 in triangle:
			surface.set_normal(normal)
			surface.set_uv(Vector2(point.x+point.z,point.y+point.z))
			surface.add_vertex(point)

func axis_face(poly: Array, axis: int, value: float, direction: float, material: Material, owner: int) -> void:
	var u := (axis+1)%3
	var v := (axis+2)%3
	var parts: Array=[poly]
	if axis == 2 and join_sections.has(value):
		for section: Rect2 in join_sections[value]:
			var visible: Array = []
			for part in parts: visible.append_array(subtract(part,section))
			parts = visible
			if parts.is_empty(): return
	var face_bounds:=Rect2(poly[0],Vector2.ZERO)
	for point: Vector2 in poly: face_bounds=face_bounds.expand(point)
	if not plane_blockers[axis].has(value):
		var candidates: Array = []
		for index in solids.size():
			var bounds: AABB = solids[index].bounds
			if bounds.position[axis] <= value+EPS and bounds.end[axis] >= value-EPS:
				candidates.append([bounds,index])
		for mask in masks:
			if mask.position[axis] <= value+EPS and mask.end[axis] >= value-EPS:
				candidates.append([mask,-1])
		plane_blockers[axis][value] = candidates
	for blocker in plane_blockers[axis][value]:
		if owner >= 0 and owner == blocker[1]: continue
		var b: AABB=blocker[0]
		# A shared coplanar exterior is emitted once, by the earlier solid.
		# This also covers collinear wall runs meeting different room owners.
		var earlier: bool=owner>=0 and (blocker[1]<0 or blocker[1]<owner)
		if direction>0 and b.end[axis]<=value+EPS:
			if not (earlier and absf(b.end[axis]-value)<EPS): continue
		if direction<0 and b.position[axis]>=value-EPS:
			if not (earlier and absf(b.position[axis]-value)<EPS): continue
		var rect := Rect2(Vector2(b.position[u],b.position[v]),Vector2(b.size[u],b.size[v]))
		if not face_bounds.intersects(rect): continue
		var next: Array=[]
		for part in parts: next.append_array(subtract(part,rect))
		parts=next
	var normal := Vector3.ZERO
	normal[axis]=direction
	for part in parts:
		var points: Array=[]
		for point: Vector2 in part:
			var at := Vector3.ZERO
			at[axis]=value; at[u]=point.x; at[v]=point.y
			points.append(at)
		exposed.append({"axis":axis,"value":value,"direction":direction,"polygon":part,"material":material})
		emit(points,normal,material)

func build(parent: Node3D) -> void:
	clip_join_solids()
	for index in solids.size():
		var solid: Dictionary=solids[index]
		var b: AABB=solid.bounds
		var finishes: Dictionary = solid.get("face_finishes",{})
		for axis in 3:
			var u := (axis+1)%3
			var v := (axis+2)%3
			var poly: Array=[Vector2(b.position[u],b.position[v]),Vector2(b.end[u],b.position[v]),Vector2(b.end[u],b.end[v]),Vector2(b.position[u],b.end[v])]
			axis_face(poly,axis,b.position[axis],-1,finishes.get(axis*2,solid.material),index)
			axis_face(poly,axis,b.end[axis],1,finishes.get(axis*2+1,solid.material),index)
		var body:=StaticBody3D.new()
		body.position=b.get_center()
		if solid.floor: body.add_to_group("museum_floor")
		var collision:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=b.size; collision.shape=shape
		body.add_child(collision); parent.add_child(body)
	for portal in arches: build_arch(parent,portal)
	for corner in roof_corners: build_roof_corner(parent,corner)
	for faces in lantern_collision:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var body := StaticBody3D.new()
		body.add_child(collision)
		parent.add_child(body)
	for material in streams:
		var tool: SurfaceTool=streams[material]
		tool.generate_tangents()
		var instance:=MeshInstance3D.new()
		instance.mesh=tool.commit()
		if material is StandardMaterial3D and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)
	plane_blockers = [{}, {}, {}]

func arch_point(portal: Dictionary, x: float, y: float, depth: float) -> Vector3:
	return portal.at + (Vector3(depth,y,x) if portal.turn else Vector3(x,y,depth))

func arch_height(x: float, half: float, spring: float, rise: float) -> float:
	var radius: float=(half*half+rise*rise)/(2*rise)
	return spring+rise-radius+sqrt(maxf(0,radius*radius-x*x))

func arch_face(p: Dictionary, points: Array, depth: float, mat: Material) -> void:
	var poly: Array=[]
	var axis:=0 if p.turn else 2
	for point: Vector2 in points:
		var at:=arch_point(p,point.x,point.y,depth)
		poly.append(Vector2(at[(axis+1)%3],at[(axis+2)%3]))
	axis_face(poly,axis,p.at[axis]+depth,signf(depth),mat,-1)

func build_arch(parent: Node3D, p: Dictionary) -> void:
	var half: float=p.width/2
	var segments:=48
	var sides := [-1,1]
	if not p.turn and join_sections.has(p.at.z):
		sides = [1] if is_zero_approx(p.at.z) else [-1]
	var low: float = minf(0,sides.front())
	var high: float = maxf(0,sides.back())
	for i in segments:
		var t0:=lerpf(-1,1,float(i)/segments)
		var t1:=lerpf(-1,1,float(i+1)/segments)
		var x0:=half*t0; var x1:=half*t1
		var y0:=arch_height(x0,half,p.spring,p.rise)
		var y1:=arch_height(x1,half,p.spring,p.rise)
		var ox0:=(half+.24)*t0; var ox1:=(half+.24)*t1
		var oy0:=arch_height(ox0,half+.24,p.spring,p.rise+.24)
		var oy1:=arch_height(ox1,half+.24,p.spring,p.rise+.24)
		# The stone ring replaces the plaster underneath; only its raised returns remain exposed.
		for side in sides:
			var depth: float = side*.1
			arch_face(p,[Vector2(ox0,oy0),Vector2(ox1,oy1),Vector2(ox1,p.height),Vector2(ox0,p.height)],depth,p.material)
		for side in sides:
			var depth: float = side*.18
			arch_face(p,[Vector2(x0,y0),Vector2(x1,y1),Vector2(ox1,oy1),Vector2(ox0,oy0)],depth,p.surround)
		var top: Array=[]
		for point in [arch_point(p,ox0,p.height,low*.1),arch_point(p,ox1,p.height,low*.1),arch_point(p,ox1,p.height,high*.1),arch_point(p,ox0,p.height,high*.1)]:
			top.append(Vector2(point.z,point.x))
		axis_face(top,1,p.height,1,p.material,-1)
		var lower: Array=[arch_point(p,x0,y0,low*.18),arch_point(p,x1,y1,low*.18),arch_point(p,x1,y1,high*.18),arch_point(p,x0,y0,high*.18)]
		var slope:=Vector3(y1-y0,-(x1-x0),0).normalized()
		if p.turn: slope=Vector3(0,slope.y,slope.x)
		emit(lower,slope,p.surround)
		var outward:=Vector3(oy0-oy1,ox1-ox0,0).normalized()
		if p.turn: outward=Vector3(0,outward.y,outward.x)
		for side in sides:
			emit([arch_point(p,ox0,oy0,side*.1),arch_point(p,ox1,oy1,side*.1),arch_point(p,ox1,oy1,side*.18),arch_point(p,ox0,oy0,side*.18)],outward,p.surround)
		var points:=PackedVector3Array(lower)
		for x in [x0,x1]:
			for depth in [low*.1,high*.1]: points.append(arch_point(p,x,p.height,depth))
		var body:=StaticBody3D.new()
		var collision:=CollisionShape3D.new()
		var shape:=ConvexPolygonShape3D.new()
		shape.points=points; collision.shape=shape
		body.add_child(collision); parent.add_child(body)
