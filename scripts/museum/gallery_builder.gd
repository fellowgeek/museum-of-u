extends RefCounted
const Assets = preload("res://scripts/museum/asset_library.gd")
const Geometry = preload("res://scripts/museum/museum_geometry.gd")
const Door = preload("res://scripts/museum/service_door.gd")
const Plan = preload("res://scripts/museum/gallery_plan.gd")
const STRIDE := Plan.STRIDE
const ORIGINAL_CAPACITY := 28
const ANNEX_CAPACITY := 8
const STORAGE_PHOTOS := [4, 23]
const ORIGINAL_SCULPTURES := ["seated_sculpture", "horse_statue", "taihu_stone", "venus_statue", "bear_sculpture", "bathing_goddess", "female_bust", "seated_sculpture"]
const SCULPTURE_COLLECTIONS := [
	["expressive_stone", "canova_naiad", "tiki_stone", "jungling", "wooden_elephant", "bathing_goddess", "female_bust", "salmacis"],
	["sad_woman", "horse_statue", "guadeloupe_wood", "venus_statue", "bear_sculpture", "concrete_buddha", "female_bust", "expressive_stone"],
	["concrete_buddha", "canova_naiad", "taihu_stone", "salmacis", "wooden_elephant", "jungling", "tiki_stone", "seated_sculpture"],
]
const CABINET_DADO := .60
const FRAME_BORDER := .34
const PHOTO_MARGIN := .60
const DOOR_HALF_WIDTH := .5229663
const DOOR_HEIGHT := 2.4741629
var wall: ShaderMaterial
var partition_material: ShaderMaterial
var marble: Material
var plinth_stone: ShaderMaterial
var concrete: StandardMaterial3D = preload("res://assets/materials/museum/Concrete034/material.tres")
var soil: StandardMaterial3D = preload("res://assets/materials/museum/Ground048/material.tres")
var white := material(Color(.70,.67,.60))
var cornice := material(Color(.48,.44,.37))
var trim := material(Color(.34,.31,.26))
var brass := material(Color(.46,.35,.19))
var arch_stone: StandardMaterial3D = trim
var oak := ShaderMaterial.new()
var soffit: ShaderMaterial
var uprights: ShaderMaterial
var sash: ShaderMaterial
var clay: ShaderMaterial
var garden_plaster: ShaderMaterial
var annex_plaster: ShaderMaterial
var utility_tile := ShaderMaterial.new()
var cove := material(Color("ead6b3"))
var bronze := material(Color("54483b"))
var glass := material(Color(.79, .89, .91, .075))
var geometry: RefCounted
var wing: Node3D
var plan: RefCounted
var slots: Array[Dictionary] = []
var photo_obstacles: Array[AABB] = []

func _init() -> void:
	wall=ShaderMaterial.new()
	wall.shader=preload("res://assets/shaders/museum_plaster.gdshader")
	wall.set_shader_parameter("plaster_color",Color("d9d2bf"))
	wall.set_shader_parameter("plaster",preload("res://assets/materials/museum/PaintedPlaster017/albedo.jpg"))
	partition_material=wall.duplicate()
	partition_material.set_shader_parameter("plaster_color",Color(.17,.29,.28))
	clay = wall.duplicate()
	clay.set_shader_parameter("plaster_color", Color("ad6e55"))
	garden_plaster = wall.duplicate()
	garden_plaster.set_shader_parameter("plaster_color", Color("717c6a"))
	annex_plaster = wall.duplicate()
	utility_tile.shader = preload("res://assets/shaders/museum_service_tile.gdshader")
	marble=ShaderMaterial.new()
	marble.shader=preload("res://assets/shaders/museum_marble.gdshader")
	marble.set_shader_parameter("marble_color",preload("res://assets/materials/museum/Marble012/albedo.jpg"))
	plinth_stone = marble.duplicate()
	plinth_stone.set_shader_parameter("slabs", false)
	oak.shader = preload("res://assets/shaders/museum_oak.gdshader")
	oak.set_shader_parameter("oak", preload("res://assets/textures/museum/oak_veneer_01_diff_1k.jpg"))
	soffit = oak.duplicate()
	soffit.set_shader_parameter("boards", true)
	uprights = oak.duplicate()
	uprights.set_shader_parameter("grain_axis", Vector3.UP)
	sash = oak.duplicate()
	sash.set_shader_parameter("grain_axis", Vector3.BACK)
	cove.emission_enabled = true
	cove.emission = Color("ffe4b3")
	cove.emission_energy_multiplier = .68
	bronze.metallic = .58
	bronze.roughness = .37
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = .12

static func material(color: Color) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new()
	result.albedo_color=color; result.roughness=.65
	return result

static func mesh_box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var instance:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=size; instance.mesh=box; instance.material_override=mat
	instance.position=at; parent.add_child(instance)
	return instance

func box(at: Vector3, size: Vector3, mat: Material, floor_surface := false, face_finishes := {}) -> void:
	if size.x>.0001 and size.y>.0001 and size.z>.0001: geometry.box(at,size,mat,floor_surface,face_finishes)

func prop(id: String, at: Vector3, scale_value:=1.0, yaw:=0.0) -> Node3D:
	var model:=Assets.exhibit(id)
	model.position=at; model.scale*=scale_value; model.rotation.y=yaw
	model.set_meta("museum_asset_id",id); wing.add_child(model)
	if "plant" in id: model.add_to_group("museum_plants")
	return model

func bench(at: Vector3, target: Vector3, subject: String) -> void:
	var direction:=target-at
	var model:=prop("carved_bench",at,1.0,snappedf(atan2(direction.x,direction.z),PI/2))
	model.add_to_group("museum_benches")
	model.set_meta("view_target",target)
	model.set_meta("view_subject",subject)

func exhibit(id: String, at: Vector3, size: Vector3, scale_value: float, target: Vector3, front_yaw := 0.0) -> void:
	var toe := .065
	box(at + Vector3.UP * toe * .5, Vector3(size.x - .10, toe, size.z - .10), bronze)
	box(at + Vector3.UP * (toe + size.y) * .5, Vector3(size.x, size.y - toe, size.z), plinth_stone)
	var direction: Vector3=(target-at); direction.y=0; direction=direction.normalized()
	var facing:=snappedf(atan2(direction.x,direction.z),PI/2)
	var model:=prop(id,at+Vector3.UP*size.y,scale_value,facing-front_yaw)
	model.add_to_group("museum_exhibits")
	model.set_meta("view_target",target); model.set_meta("asset_front_yaw",front_yaw)
	model.set_meta("plinth",AABB(at-Vector3(size.x/2,0,size.z/2),size))

func add_slot(at: Vector3, normal: Vector3, room_id: int, max_width: float, span: Vector2, partition := false) -> void:
	slots.append({"at":at,"yaw":atan2(normal.x,normal.z),"room":room_id,"partition":partition,
		"max_width":max_width,"span":span,"margin":.50 if partition else PHOTO_MARGIN})

func partition(at: Vector3, length: float, turn: bool, room_id: int) -> void:
	var size:=Vector3(.32,3.3,length) if turn else Vector3(length,3.3,.32)
	box(at+Vector3.UP*1.65,size,partition_material)
	box(at+Vector3.UP*.10,Vector3(size.x+.12,.20,size.z+.12),trim)
	box(at+Vector3.UP*3.34,Vector3(size.x+.08,.08,size.z+.08),brass)
	for side in [-1,1]:
		var normal:=Vector3(side,0,0) if turn else Vector3(0,0,side)
		for offset in [-1.2,1.2]:
			var along:=Vector3(0,0,offset) if turn else Vector3(offset,0,0)
			var center: float=at.z if turn else at.x
			add_slot(at+along+normal*.145+Vector3.UP*1.75,normal,room_id,1.66,Vector2(center-length/2,center+length/2),true)
	var partitions: Array=wing.get_meta("partitions",[])
	partitions.append(AABB(at-Vector3(size.x/2,0,size.z/2),size))
	wing.set_meta("partitions",partitions)

func sky_window(opening: Dictionary) -> void:
	var at: Vector3 = opening.at
	var width: float = opening.width
	var height: float = opening.top - opening.bottom
	var middle: Vector3 = at + Vector3.UP * (opening.bottom + height * .5)
	var depth: Vector3 = opening.inward.abs()
	var along := Vector3(depth.z,0,depth.x)
	for side in [-1.0, 1.0]:
		box(middle + along * side * (width*.5-.055), depth*.34 + Vector3.UP*height + along*.11, uprights)
		box(middle + Vector3.UP * side * (height*.5-.055), depth*.34 + Vector3.UP*.11 + along*(width-.22), sash)
	var clear_width := width - .22
	var lights := maxi(2, roundi(clear_width / 1.48))
	for i in range(1, lights):
		var offset := clear_width * (float(i) / lights - .5)
		box(middle + along*offset, depth*.115 + Vector3.UP*(height-.22) + along*.047, bronze)
	var transom: float = opening.top - 1.05
	box(at + Vector3.UP*transom, depth*.10 + Vector3.UP*.052 + along*clear_width, bronze)
	box(middle, depth*.018 + Vector3.UP*(height-.22) + along*clear_width, glass)
	# Seat the projecting stone sill 15 mm into the timber rebate.
	box(at + opening.inward*.25 + Vector3.UP*(opening.bottom-.0525), depth*.48 + Vector3.UP*.135 + along*(width+.22), white)
	# The planted ledge provides real near-field parallax in stereo.
	var bed: Vector3 = at - opening.inward*.86
	box(bed + Vector3.UP*.32, depth*1.52 + Vector3.UP*.64 + along*(width+.54), cornice)
	box(bed + Vector3.UP*.66, depth*1.44 + Vector3.UP*.04 + along*(width+.46), soil)
	preload("res://scripts/museum/window_grasses.gd").plant(wing, opening)
	var bounce := OmniLight3D.new()
	bounce.position = at + opening.inward * .9 + Vector3.UP * (opening.bottom + height * .52)
	bounce.light_color = Color("ffebce")
	bounce.light_energy = 1.0 if width < 3.0 else 1.7
	bounce.omni_range = minf(11, width + 5)
	bounce.omni_attenuation = .7
	bounce.distance_fade_enabled = true
	bounce.distance_fade_begin = 16
	bounce.distance_fade_length = 6
	wing.add_child(bounce)

func wall_finish(room_id: int, exterior: bool, top: float) -> Material:
	if room_id == 1 and exterior: return clay
	if room_id == 2 and exterior: return garden_plaster
	if room_id == 7: return uprights if plan.annex == 1 and top <= CABINET_DADO else annex_plaster
	if room_id in [8,9]: return utility_tile
	return wall

func wall_piece(edge: Dictionary, start: float, end: float, bottom: float, top: float) -> void:
	if end<=start or top<=bottom: return
	var at:=Vector3(edge.value,(bottom+top)/2,(start+end)/2) if edge.axis==0 else Vector3((start+end)/2,(bottom+top)/2,edge.value)
	var size:=Vector3(.2,top-bottom,end-start) if edge.axis==0 else Vector3(end-start,top-bottom,.2)
	if (edge.room == 7 or edge.neighbor == 7) and plan.annex == 1 and bottom < CABINET_DADO and top > CABINET_DADO:
		wall_piece(edge, start, end, bottom, CABINET_DADO)
		wall_piece(edge, start, end, CABINET_DADO, top)
		return
	var inside := wall_finish(edge.room,edge.neighbor < 0 or edge.neighbor >= 7,top)
	var outside := wall_finish(edge.neighbor,false,top) if edge.neighbor >= 7 else inside
	if edge.neighbor < 0 and edge.room in [8,9]:
		outside = wall
	elif edge.neighbor >= 0 and (edge.room in [8,9] or edge.neighbor in [8,9]):
		var lower_roof := minf(plan.rooms[edge.room].height,plan.rooms[edge.neighbor].height)
		if bottom < lower_roof and top > lower_roof:
			wall_piece(edge,start,end,bottom,lower_roof)
			wall_piece(edge,start,end,lower_roof,top)
			return
		if bottom >= lower_roof:
			if plan.rooms[edge.room].height <= bottom: inside = wall
			else: outside = wall
	if inside == outside:
		wall_layer(at,size,inside,edge.axis)
	else:
		size[edge.axis] = .1
		wall_layer(at + edge.inward*.05,size,inside,edge.axis)
		wall_layer(at - edge.inward*.05,size,outside,edge.axis)

func wall_layer(at: Vector3, size: Vector3, finish: Material, wall_axis: int) -> void:
	if finish != utility_tile:
		box(at,size,finish)
		return
	# At a corner or roof step the narrow end of a tiled layer can face the garden.
	var along := 2-wall_axis
	var finishes := {}
	var bottom := at.y-size.y*.5
	var top := at.y+size.y*.5
	for side in [-1,1]:
		var probe := at
		probe[along] += side*(size[along]*.5+.025)
		var room: int = plan.room_id_at(probe)
		var roof: float = plan.rooms[room].height if room >= 0 else 0.0
		if roof > bottom+.0001 and roof < top-.0001:
			var lower := Vector3(size.x,roof-bottom,size.z)
			var upper := Vector3(size.x,top-roof,size.z)
			wall_layer(at-Vector3.UP*upper.y*.5,lower,finish,wall_axis)
			wall_layer(at+Vector3.UP*lower.y*.5,upper,finish,wall_axis)
			return
		if at.y > roof:
			finishes[along*2 + (1 if side>0 else 0)] = wall
	box(at,size,finish,false,finishes)

func wall_end(edge: Dictionary, at_start: bool) -> float:
	var end: float = edge.start if at_start else edge.end
	var direction := -1.0 if at_start else 1.0
	if plan.annex >= 0:
		# At a T-junction the receiving wall owns its uninterrupted room finish.
		var past := edge_point(edge,end+direction*.20,0)
		var receiving: int = plan.room_id_at(past+edge.inward*.20)
		if receiving >= 0 and receiving not in [edge.room,edge.neighbor] and receiving == plan.room_id_at(past-edge.inward*.20):
			if maxi(receiving,maxi(edge.room,edge.neighbor)) >= 7 and plan.rooms[receiving].height >= edge.height:
				return end
	return end+direction*.1

func envelope(to_sun: Vector3) -> void:
	var daylight_floors: Array[ShaderMaterial] = []
	for room_data in plan.rooms:
		var sky: Rect2=room_data.sky
		var ceiling: Material = soffit if room_data.id in [0, 3, 7] else wall
		var floor_finish: Material = marble if room_data.id == 7 else concrete
		if sky.has_area():
			var daylight: ShaderMaterial = marble.duplicate()
			daylight.set_shader_parameter("shadowless", not GameSettings.value("lighting.shadows_enabled"))
			daylight.set_shader_parameter("lantern", Vector4(sky.get_center().x, sky.get_center().y, sky.size.x / 2, room_data.height))
			daylight.set_shader_parameter("to_sun", to_sun)
			daylight_floors.append(daylight)
			floor_finish = daylight
		for rect: Rect2 in room_data.rects:
			var center:=rect.get_center()
			box(Vector3(center.x,-.12,center.y),Vector3(rect.size.x,.24,rect.size.y),floor_finish,true)
			var intersection:=rect.intersection(sky)
			var pieces: Array=[rect]
			if intersection.has_area():
				pieces=[Rect2(rect.position,Vector2(intersection.position.x-rect.position.x,rect.size.y)),Rect2(Vector2(intersection.end.x,rect.position.y),Vector2(rect.end.x-intersection.end.x,rect.size.y)),Rect2(Vector2(intersection.position.x,rect.position.y),Vector2(intersection.size.x,intersection.position.y-rect.position.y)),Rect2(Vector2(intersection.position.x,intersection.end.y),Vector2(intersection.size.x,rect.end.y-intersection.end.y))]
			for piece: Rect2 in pieces:
				var p:=piece.get_center()
				box(Vector3(p.x,room_data.height+.125,p.y),Vector3(piece.size.x,.25,piece.size.y),ceiling)
		if not sky.has_area(): continue
		geometry.round_skylight(sky,room_data.height,1.5,ceiling)
		geometry.roof_lantern(sky, room_data.height, oak, bronze)
		var light:=OmniLight3D.new()
		light.position=Vector3(sky.get_center().x,room_data.height-1,sky.get_center().y)
		light.light_color=Color("e2ecff"); light.light_energy=1.7; light.omni_range=room_data.height+6
		light.omni_attenuation=.85; light.shadow_enabled=false; wing.add_child(light)
	for edge in plan.walls:
		var openings: Array=[]
		for portal in plan.portals:
			var axis:=0 if portal.turn else 2
			var center: float=portal.at.z if axis==0 else portal.at.x
			if edge.axis==axis and is_equal_approx(edge.value,portal.at[axis]) and center>edge.start and center<edge.end:
				openings.append({"center":center,"width":portal.get("width",2.8),"bottom":0.0,"top":3.0,"arch":true,"rise":portal.get("rise",.9)})
		for window in plan.windows:
			var axis: int = window.get("axis",0)
			var center: float = window.at[2-axis]
			if edge.axis==axis and is_equal_approx(edge.value,window.at[axis]) and center>edge.start and center<edge.end:
				openings.append({"center":center,"width":window.width,"bottom":window.bottom,"top":window.top,"arch":false})
		for door in plan.service_doors:
			var axis: int = door.get("axis",0)
			var center: float = door.at[2-axis]
			if edge.axis==axis and is_equal_approx(edge.value,door.at[axis]) and edge.start<center and edge.end>center:
				openings.append({"center":center,"width":DOOR_HALF_WIDTH*2,"bottom":0.0,"top":DOOR_HEIGHT,"arch":false})
		openings.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.center<b.center)
		var start := wall_end(edge,true)
		for opening in openings:
			var left: float=opening.center-opening.width/2
			var right: float=opening.center+opening.width/2
			wall_piece(edge,start,left,0,edge.height)
			wall_piece(edge,left,right,0,opening.bottom)
			if opening.arch:
				var at:=Vector3(edge.value,0,opening.center) if edge.axis==0 else Vector3(opening.center,0,edge.value)
				var backing: Material = garden_plaster if plan.garden_gate != Vector3.ZERO and at.is_equal_approx(plan.garden_gate) else wall
				geometry.arch(at,opening.width,3,opening.rise,edge.height,backing,arch_stone,edge.axis==0)
			else: wall_piece(edge,left,right,opening.top,edge.height)
			start=right
		wall_piece(edge,start,wall_end(edge,false),0,edge.height)
	room_trim()
	for opening in plan.windows: sky_window(opening)
	wing.set_meta("daylight_floors", daylight_floors)

func edge_point(edge: Dictionary, along: float, height: float) -> Vector3:
	return Vector3(edge.value,height,along) if edge.axis==0 else Vector3(along,height,edge.value)

func room_trim() -> void:
	# Follow each room outline independently of shared-wall mesh ownership.
	for edge in plan.boundaries:
		var height: float=plan.rooms[edge.room].height
		if edge.room == 2 and edge.axis == 2 and is_equal_approx(edge.value, STRIDE):
			# The end screen catches raking daylight above the planted lounge.
			var bays := roundi((edge.end - edge.start) / 1.5)
			for i in bays:
				var along: float = lerpf(edge.start, edge.end, (i + .5) / bays)
				for offset in [-.155, 0.0, .155]:
					var depth := .21 if offset == 0 else .135
					var bottom := .235
					var top := height - .40
					var at := edge_point(edge, along + offset, (bottom + top) * .5) + Vector3(edge.inward) * (.1 + depth * .5)
					box(at, Vector3(.082, top - bottom, depth), uprights)
		var tiers := [[height-.09,.18,.15,cornice], [height-.25,.14,.11,cornice],
			[.10,.20,.08,trim], [.2175,.035,.08,brass]]
		if edge.room < 4 or edge.room == 7:
			tiers.append_array([[height-.344,.048,.08,brass], [height-.379,.022,.08,cove]])
		else:
			tiers.append([height-.355,.07,.08,brass])
		if edge.room == 7 and plan.annex == 1: tiers.append([CABINET_DADO+.02,.06,.065,bronze])
		for tier in tiers:
			var intervals: Array[Vector2]=[Vector2(edge.start,edge.end)]
			if tier[0]<1:
				for opening in edge_openings(edge,false): intervals=cut_intervals(intervals,opening)
			for interval in intervals:
				var ends:=interval
				for end_index in 2:
					var value: float=interval[end_index]
					if not is_equal_approx(value,edge.start if end_index==0 else edge.end): continue
					var direction:=-1.0 if end_index==0 else 1.0
					var probe: Vector3=edge_point(edge,value+direction*.3,0)+edge.inward*.3
					var room_id: int=plan.cells.get(Vector2i(floori(probe.x/3),floori(probe.z/3)),-1)
					# Outside corners stop at the perpendicular wall face; inside turns overlap and are union-clipped.
					ends[end_index]+=direction*(.1+tier[2] if room_id==edge.room else -.1)
				var at: Vector3=edge_point(edge,(ends.x+ends.y)/2,tier[0])+Vector3(edge.inward)*(.1+tier[2]/2)
				var size:=Vector3(tier[2],tier[1],ends.y-ends.x) if edge.axis==0 else Vector3(ends.y-ends.x,tier[1],tier[2])
				box(at,size,tier[3])
				geometry.solids[-1]["trim_room"]=edge.room

func edge_openings(edge: Dictionary, include_windows: bool) -> Array[Vector2]:
	var openings: Array[Vector2]=[]
	for portal in plan.portals:
		var axis:=0 if portal.turn else 2
		if edge.axis==axis and is_equal_approx(edge.value,portal.at[axis]):
			var center: float=portal.at.z if axis==0 else portal.at.x
			var margin: float = portal.get("width",2.8)*.5+.24
			openings.append(Vector2(center-margin,center+margin))
	if include_windows:
		for window in plan.windows:
			var axis: int = window.get("axis",0)
			if edge.axis==axis and is_equal_approx(edge.value,window.at[axis]):
				var center: float = window.at[2-axis]
				openings.append(Vector2(center-window.width/2-.1,center+window.width/2+.1))
	for door in plan.service_doors:
		var axis: int = door.get("axis",0)
		if edge.axis==axis and is_equal_approx(edge.value,door.at[axis]):
			var margin:=.12 if include_windows else 0.0
			var at: float = door.at[2-axis]
			openings.append(Vector2(at-DOOR_HALF_WIDTH-margin,at+DOOR_HALF_WIDTH+margin))
	return openings

static func cut_intervals(intervals: Array[Vector2], cut: Vector2) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for span in intervals:
		if cut.y<=span.x or cut.x>=span.y: result.append(span)
		else:
			if cut.x>span.x: result.append(Vector2(span.x,cut.x))
			if cut.y<span.y: result.append(Vector2(cut.y,span.y))
	return result

func storage(seed_value: int, index: int) -> void:
	var x: float=plan.service_anchor
	# Acquired furniture leaves a continuous central aisle and open door approaches.
	for z in [31.1,32.6,37.5]:
		prop("archive_shelves",Vector3(x+3.5,0,z),1.0,PI/2)
	for z in ([31.2,32.65] if plan.annex >= 0 else [31.3,33.0,34.7]):
		prop("drawer_cabinet",Vector3(x+11.5,0,z),1.0,-PI/2)
	if plan.annex >= 0: prop("drawer_cabinet",Vector3(x+8.15,0,38.55),1.0,PI)
	for at in [Vector3(x+7,0,31.2),Vector3(x+7,0,37.5)]:
		prop("wooden_crate",at)
		prop("archive_box",at+Vector3.UP*.65,.65)
	prop("storage_cart",Vector3(x+8.5,0,34.7),1.0,PI/2)
	prop("utility_ladder",Vector3(x+5.25,0,37.35),1.0,-PI/2)
	for z in [22.1,28.9]:
		prop("preparation_table",Vector3(x+6.5,0,z))
		prop("archive_box",Vector3(x+6,.95,z),.7)
	prop("watering_can",Vector3(x+7,.95,28.9),1.5)
	prop("drawer_cabinet",Vector3(x+3.5,0,22.4),1.0,PI/2)
	prop("archive_shelves",Vector3(x+11.5,0,27.7),1.0,-PI/2)
	prop("tool_cart",Vector3(x+10.05,0,28.4) if plan.annex >= 0 else Vector3(x+10.5,0,25.6),1.0,-PI/2)
	prop("preparation_table",Vector3(x+7,0,25.5),1.0,PI/2 if plan.variant%3==1 else 0.0)
	for z in [28.5,31.5,37.5]:
		prop("industrial_wall_lamp",Vector3(x+2.8102,1.9,z),1.0,-PI/2)
	for item in plan.service_doors:
		var door:=Door.new(); door.position=item.at; door.rotation.y=PI/2 if item.get("axis",0)==0 else 0.0
		if item.get("reverse_swing",false): door.rotation.y += PI
		door.state_key="museum:%d:%d:%s"%[seed_value,index,item.key]; door.paint_name=item.paint; wing.add_child(door)
	for at in [Vector3(x+1.5,2.1,26),Vector3(x+1.5,2.1,33),Vector3(x+1.5,2.1,37.5),Vector3(x+7.5,2.1,34.5),Vector3(x+7.5,2.1,25.5)]:
		prop("industrial_pendant",at)
		var light:=OmniLight3D.new(); light.position=at+Vector3.UP*.15
		light.light_color=Color(1,.88,.72); light.omni_range=8; light.light_energy=1.4; wing.add_child(light)
	wing.set_meta("service_at",plan.service_doors[0].at)

func sculpture_hall(index: int, seed_value: int) -> void:
	var ids := ORIGINAL_SCULPTURES
	if plan.annex >= 0:
		ids = SCULPTURE_COLLECTIONS[posmod(index + posmod(seed_value - 1930, 3), 3)]
	# Station center, plinth size and direction to the viewing aisle, in wing space.
	var stations := [
		[Vector3(-15,0,3), Vector3(1.6,.65,1.6), Vector3.BACK],
		[Vector3(-11,0,8), Vector3(1.9,.5,1.5), Vector3.BACK],
		[Vector3(-21,0,8), Vector3(1.5,.5,1.5), Vector3.RIGHT],
		[Vector3(-16,0,8), Vector3(1.5,.4,1.5), Vector3.BACK],
		[Vector3(-18.5,0,15), Vector3(2,.55,1.4), Vector3.RIGHT],
		[Vector3(-12,0,15), Vector3(1.6,.45,1.6), Vector3.FORWARD],
		[Vector3(-8.5,0,15), Vector3(1.25,1.1,1.25), Vector3.LEFT],
		[Vector3(-18.7,0,11.3), Vector3(1.6,.65,1.6), Vector3.RIGHT],
	]
	for i in stations.size():
		var id: String = ids[i]
		var at: Vector3 = stations[i][0]
		var size: Vector3 = stations[i][1]
		var toward: Vector3 = stations[i][2]
		var scale_value: float = {"taihu_stone": 1.3, "bear_sculpture": 1.2}.get(id, 1.0)
		var front_yaw: float = {"horse_statue": -PI/2, "bear_sculpture": -PI/2, "expressive_stone": PI/2}.get(id, 0.0)
		exhibit(id, at, size, scale_value, at + toward * 3.0, front_yaw)

func furnishings(index: int, seed_value: int) -> void:
	partition(Vector3(-1.5,0,14.5),5.4,false,0)
	partition(Vector3(1.5,0,35.5),5.4,false,3)
	# The picture galleries have a seat facing a displayed work, with a clear aisle behind.
	bench(Vector3(3.1,0,4.0),Vector3(2,1.6,7.0),"bathing_goddess")
	bench(Vector3(0,0,27.5),Vector3(.15,1.75,35.3),"picture")
	exhibit("bathing_goddess",Vector3(2,0,7.0),Vector3(1.6,.35,1.6),1.0,Vector3(-3,0,9))
	exhibit("venus_statue",Vector3(-3.2,0,5),Vector3(1.5,.4,1.5),1.0,Vector3(0,0,5))
	exhibit("female_bust",Vector3(-3.7,0,38.5),Vector3(1.25,1.05,1.25),1.0,Vector3(0,0,39))
	exhibit("seated_sculpture",Vector3(3.0,0,31.0),Vector3(1.6,.65,1.6),1.0,Vector3(0,0,31.0))
	if plan.variant>=3:
		var at:=Vector3(6.0 if plan.variant==5 else 8.5,0,[13.5,9.0,15.0][plan.variant-3])
		exhibit(["venus_statue","bathing_goddess","seated_sculpture"][plan.variant-3],at,Vector3(1.6,.45,1.6),1.0,at+Vector3.LEFT*4)
	sculpture_hall(index, seed_value)
	for item in [[Vector3(5,0,14) if plan.variant==0 else Vector3(.8,0,11.8),"antique_ceramic_vase",1.8],[Vector3(3.8,0,38.7),"ceramic_vase_01",1.5]]:
		exhibit(item[1],item[0],Vector3(.8,1,.8),item[2],item[0]+Vector3.FORWARD)
	exhibit("alba_ceramics",Vector3(3.5,0,27.0),Vector3(1.6,.85,1.6),1.0,Vector3(0,0,27.0))
	# This entire connecting court is devoted to seating and planting, without pictures or plinths.
	var center:=Vector3(-15,0,30)
	for at in [Vector3(-21,0,27),Vector3(-9,0,27),Vector3(-15,0,37),Vector3(-12,0,21)]:
		bench(at,center+Vector3.UP*2,"tree")
	var plants: Array=[Vector3(-8.5,0,33),Vector3(-4.5,0,16.8),Vector3(-19.5,0,34.5),
		Vector3(-19.5,0,21),Vector3(-8,0,21),Vector3(-8,0,24),Vector3(-22,0,32.2),
		Vector3(-22,0,30.5),Vector3(-22,0,34),Vector3(-19.5,0,40),Vector3(-8,0,40),
		Vector3(-8,0,36),Vector3(-19,0,37),Vector3(-19.5,0,24),Vector3(-11,0,40)]
	for i in plants.size(): prop(["calathea_plant","potted_plant_02","monstera_plant","potted_plant_01"][i%4],plants[i])
	box(center+Vector3.UP*.17,Vector3(3.4,.34,3.4),soil)
	for x in [-1.775,1.775]: box(center+Vector3(x,.225,0),Vector3(.15,.45,3.7),white)
	for z in [-1.775,1.775]: box(center+Vector3(0,.225,z),Vector3(3.4,.45,.15),white)
	var tree:=prop("court_magnolia" if index%2==0 else "court_palm",center+Vector3.UP*.08)
	tree.add_to_group("museum_court_trees"); tree.set_meta("soil_height",.34)
	wing.set_meta("tree_center",center)

func collect_photo_obstacles() -> void:
	for model in wing.get_children():
		if not model.has_meta("museum_asset_id"): continue
		var bounds: AABB=model.transform*Assets.visual_bounds(model)
		if model.has_meta("plinth"): bounds=bounds.merge(model.get_meta("plinth"))
		photo_obstacles.append(bounds)
	for solid in geometry.solids:
		if solid.get("gallery_pier", false): photo_obstacles.append(solid.bounds)

func collection_gallery() -> void:
	# A row of opal pendants leads from either public doorway into the exhibition.
	var h: float = plan.rooms[7].height
	for x in [1.5,7.5,13.5,19.5]:
		var y := minf(3.65,h-.55)
		box(Vector3(x,(h+y+.10)*.5,19.55),Vector3(.025,h-y-.10,.025),bronze)
		box(Vector3(x,y+.065,19.55),Vector3(1.14,.07,.15),bronze)
		box(Vector3(x,y,19.55),Vector3(1.04,.06,.11),cove)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,y-.12,19.55)
		lamp.light_color = Color("ffdfbd")
		lamp.light_energy = 1.5
		lamp.omni_range = 7
		wing.add_child(lamp)
	match plan.annex:
		0:
			bench(Vector3(19.8,0,14.6), Vector3(24,1.8,15),"studio window")
		1:
			bench(Vector3(21.1,0,14.4), Vector3(26.9,1.75,14.4),"cabinet feature print")
			for z in [7.5,10.5,13.5,16.5]:
				var west := 18.0 if z < 12 else 15.0
				box(Vector3((west+27)*.5,h-.105,z),Vector3(27-west-.2,.21,.16),oak)
			for z in [9.25,14.4,18.25]:
				box(Vector3(26.63,3.05,z),Vector3(.54,.055,.065),bronze)
				box(Vector3(26.39,3.03,z),Vector3(.10,.095,.76),brass)
				box(Vector3(26.39,2.97,z),Vector3(.06,.025,.64),cove)
				var light := SpotLight3D.new()
				light.position = Vector3(26.39,2.94,z)
				light.rotation = Transform3D.IDENTITY.looking_at(Vector3(.51,-1.2,0)).basis.get_euler()
				light.spot_angle = 54
				light.spot_range = 4
				light.light_energy = 2.3
				light.light_color = Color("ffe0ae")
				wing.add_child(light)
		2:
			bench(Vector3(18.5,0,12.2), Vector3(24,1.8,12.2),"loggia window")
			for z in [6.0,10.5,15.0]:
				box(Vector3(22.65,.17,z), Vector3(.67,.34,.67),plinth_stone)
				box(Vector3(22.65,2.865,z), Vector3(.40,5.05,.40),uprights)
				geometry.solids[-1].gallery_pier = true
				box(Vector3(22.65,5.48,z), Vector3(.62,.18,.62),bronze)
			box(Vector3(22.65,5.785,10.5),Vector3(.67,.43,10.05),sash)

func clear_photo_view(at: Vector3, normal: Vector3, width: float, room_id: int) -> bool:
	var viewing:=at+normal*2.4
	# Reserve standing space, including foliage that is below eye height.
	var margin := .70 if room_id == 7 else .50
	for dx in [-margin,margin]:
		for dz in [-margin,margin]:
			if plan.cells.get(Vector2i(floori((viewing.x+dx)/3),floori((viewing.z+dz)/3)),-1)!=room_id: return false
	var standing:=AABB(Vector3(viewing.x-.5,.05,viewing.z-.5),Vector3(1,1.8,1))
	var eye:=Vector3(viewing.x,1.6,viewing.z)
	var tangent:=Vector3(normal.z,0,-normal.x)
	for bounds in photo_obstacles:
		if bounds.intersects(standing): return false
		for y in [.875,1.75,2.625]:
			for side in [-1,0,1]:
				var target: Vector3=Vector3(at.x,y,at.z)+tangent*side*width/2
				if bounds.intersects_segment(eye,target)!=null: return false
	return true

func perimeter_slots() -> void:
	collect_photo_obstacles()
	for room_id in ([0,3,7] if plan.annex >= 0 else [0,3]):
		var count := ANNEX_CAPACITY if room_id == 7 else ORIGINAL_CAPACITY / 2
		if room_id == 7 and plan.annex == 1:
			for z in [9.25,14.4,18.25]:
				add_slot(Vector3(26.915,1.75,z),Vector3.LEFT,7,2.2,Vector2(6.1,20.9))
		var candidates: Array[Dictionary]=[]
		var chosen: Array[Dictionary]=[]
		for slot in slots:
			if slot.room==room_id: chosen.append(slot)
		for edge in plan.boundaries:
			if edge.room!=room_id: continue
			var owned:=false
			for wall_edge in plan.walls:
				if wall_edge.hangable and wall_edge.axis==edge.axis and is_equal_approx(wall_edge.value,edge.value) and wall_edge.start<edge.end and wall_edge.end>edge.start: owned=true
			if not owned: continue
			var intervals: Array[Vector2]=[Vector2(edge.start+.1,edge.end-.1)]
			for opening in edge_openings(edge,true): intervals=cut_intervals(intervals,opening)
			for span in intervals:
				var available:=span.y-span.x-2*PHOTO_MARGIN
				if available<1.5: continue
				var width:=minf(2.2,available-FRAME_BORDER)
				var first:=span.x+PHOTO_MARGIN+(width+FRAME_BORDER)/2
				var last:=span.y-PHOTO_MARGIN-(width+FRAME_BORDER)/2
				var positions: Array[float]=[(span.x+span.y)/2]
				var steps:=ceili((last-first)/.4)
				for i in steps+1: positions.append(lerpf(first,last,float(i)/maxi(1,steps)))
				for along in positions:
					var at:=edge_point(edge,along,1.75)+Vector3(edge.inward)*.085
					var spacing:=width+FRAME_BORDER+.50
					var capacity:=1+floori((last-first+.001)/spacing)
					var remaining:=1+floori((along-first+.001)/spacing)+floori((last-along+.001)/spacing)
					if clear_photo_view(at,edge.inward,width,room_id): candidates.append({"at":at,"normal":edge.inward,"width":width,"span":span,"packing_loss":capacity-remaining})
		while chosen.size()<count:
			var best:=-1; var best_score:=-INF
			for i in candidates.size():
				var distance:=1000.0
				for slot in chosen:
					distance=minf(distance,Vector3(slot.at).distance_squared_to(candidates[i].at))
					var delta: Vector3=slot.at-candidates[i].at
					var normal: Vector3=candidates[i].normal
					if absf(slot.yaw-atan2(normal.x,normal.z))<.01 and absf(delta.dot(normal))<.01 and delta.length()<(slot.max_width+candidates[i].width)/2+FRAME_BORDER+.50: distance=0
				if distance<5.06: continue
				# Avoid a midpoint that wastes enough space for another full-size frame.
				var score: float=distance-float(candidates[i].packing_loss)*10000
				if score>best_score: best=i; best_score=score
			assert(best>=0,"Gallery needs spaced photo positions: %s (%d)"%[room_id,chosen.size()])
			if best<0: break
			var selected: Dictionary=candidates.pop_at(best)
			add_slot(selected.at,selected.normal,room_id,selected.width,selected.span); chosen.append(slots[-1])

func accent_lights() -> void:
	# Suspended tracks attach outside the skylight; every fixture has visible support.
	for z in [8.5,33.0]:
		mesh_box(wing,Vector3(0,5.25,z),Vector3(7,.06,.08),trim)
		for x in [-3.4,3.4]: mesh_box(wing,Vector3(x,5.625,z),Vector3(.025,.75,.025),trim)
		spot(Vector3(-2.5,5.1,z),Vector3(-5.9,1.65,z-3),false,5.25)
		spot(Vector3(2.5,5.1,z),Vector3(-.4,1.75,14.3 if z<20 else 35.3),false,5.25)
	for item in [[Vector3(-15,5.1,4.5),Vector3(-15,1,3)],
		[Vector3(-16,5.1,12.5),Vector3(-16,1,8)],
		[Vector3(-12,5.1,16.5),Vector3(-12,1,15)],
		[Vector3(-19.5,5.1,13.25),Vector3(-18.7,1,11.3)]]:
		spot(item[0],item[1],true,6)
	if plan.annex >= 0:
		# Raking light brings out the grain and patina on the smaller aisle pieces.
		spot(Vector3(-16.9,4.9,13.8),Vector3(-18.5,1.05,15),false,6,23)
		spot(Vector3(-10.35,4.9,13.65),Vector3(-8.5,1.45,15),false,6,21)
	if plan.variant>=3:
		var z: float=[13.5,9.0,15.0][plan.variant-3]
		spot(Vector3(5.0 if plan.variant==5 else 7.5,5.1,z-1.5),Vector3(6.0 if plan.variant==5 else 8.5,1,z),false,6)
	mesh_box(wing,Vector3(-15,8.4,29),Vector3(10,.08,.08),trim)
	for x in [-20,-10]: mesh_box(wing,Vector3(x,8.7,29),Vector3(.035,.6,.035),trim)
	spot(Vector3(-15,8.15,29),Vector3(-15,0,30),true,8.4)

func spot(at: Vector3, target: Vector3, shadows: bool, support_height: float, beam_angle := 41.0) -> void:
	var light:=SpotLight3D.new(); wing.add_child(light); light.position=at
	light.rotation=Transform3D.IDENTITY.looking_at(target-at).basis.get_euler()
	light.light_color=Color("ffdfb5"); light.light_energy=3.4
	light.spot_range=12; light.spot_angle=beam_angle; light.spot_attenuation=.72
	light.shadow_enabled=shadows and bool(GameSettings.value("lighting.shadows_enabled"))
	light.shadow_bias=.05; light.shadow_normal_bias=.25; light.shadow_blur=1.5
	light.distance_fade_enabled=true; light.distance_fade_begin=20; light.distance_fade_length=8; light.distance_fade_shadow=18
	light.add_to_group("museum_accent_lights")
	mesh_box(wing,Vector3(at.x,(at.y+support_height)/2,at.z),Vector3(.025,support_height-at.y,.025),trim)
	var fixture:=MeshInstance3D.new(); var housing:=CylinderMesh.new()
	housing.top_radius=.10; housing.bottom_radius=.10; housing.height=.22
	fixture.mesh=housing; fixture.material_override=trim
	light.add_child(fixture); fixture.rotation.x=PI/2
	var lens:=MeshInstance3D.new(); var disk:=CylinderMesh.new()
	disk.top_radius=.078; disk.bottom_radius=.078; disk.height=.012
	lens.mesh=disk; lens.material_override=white; lens.rotation.x=PI/2; lens.position.z=-.112
	light.add_child(lens)

func build(index: int, seed_value: int, sun_direction: Vector3) -> Node3D:
	wing=Node3D.new(); wing.name="MuseumWing_%d"%index
	if index%2==1: wing.basis=Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD)
	plan=Plan.new().create(index,seed_value,GameSettings.value("layout.museum_annexes")); geometry=Geometry.new()
	# A reversed wing shares the same local end coordinate with its neighbor.
	for at in [0.0, STRIDE]:
		var step := 1 if (at == STRIDE) == (index%2 == 0) else -1
		if index+step < 0: continue
		var adjacent := Plan.new()
		adjacent.populate(index+step,seed_value,plan.annex >= 0)
		geometry.set_join(at,adjacent)
	if plan.annex >= 0:
		annex_plaster.set_shader_parameter("plaster_color", [Color("a1b3bb"),Color("b99470"),Color("83a7a2")][plan.annex])
	envelope(wing.basis.inverse() * sun_direction)
	storage(seed_value,index)
	furnishings(index, seed_value)
	if plan.annex >= 0:
		collection_gallery()
		preload("res://scripts/museum/museum_facilities.gd").install(wing, plan.service_anchor)
	perimeter_slots()
	accent_lights()
	if plan.garden_gate != Vector3.ZERO:
		preload("res://scripts/museum/outdoor_garden.gd").install(self, hash([seed_value, index, "woodland"]))
	geometry.build(wing)
	wing.set_meta("geometry",geometry); wing.set_meta("plan",plan); wing.set_meta("photo_slots",slots)
	wing.set_meta("layout_variant",plan.variant)
	wing.set_meta("window_count",plan.windows.size())
	wing.set_meta("reversed",index%2==1)
	wing.position.z=index*STRIDE+(STRIDE if index%2==1 else 0.0)
	return wing

static func frame(parent: Node3D, entry: Dictionary, index: int, storage_index := -1) -> Node3D:
	var ratio:=float(entry.width)/float(entry.height)
	var slot: Dictionary=parent.get_meta("photo_slots")[index]
	var aperture := Vector2(slot.max_width,1.5 if slot.partition else 1.75)
	if storage_index >= 0:
		aperture = [Vector2(.92,1.16),Vector2(1.16,.88)][storage_index]
	var height:=minf(aperture.y,aperture.x/ratio)
	var width:=height*ratio
	if storage_index < 0: aperture = Vector2(width,height)
	var holder:=Node3D.new()
	holder.name="StoredPhoto_%d"%storage_index if storage_index >= 0 else "Photo_%d"%index
	holder.position=slot.at
	holder.rotation.y=slot.yaw
	parent.add_child(holder)
	var mat:=material(Color(.92,.91,.87))
	mesh_box(holder,Vector3(0,0,.035),Vector3(aperture.x+.22,aperture.y+.22,.04),mat)
	var rail:=material([Color(.10,.12,.13),Color(.80,.80,.77),Color(.61,.42,.24)][index%3])
	for side in [-1,1]:
		mesh_box(holder,Vector3(0,side*(aperture.y/2+.14),.055),Vector3(aperture.x+.34,.06,.08),rail)
		mesh_box(holder,Vector3(side*(aperture.x/2+.14),0,.055),Vector3(.06,aperture.y+.22,.08),rail)
	if storage_index >= 0:
		var lean := deg_to_rad(13.0 if storage_index == 0 else 16.0)
		var outer := aperture + Vector2.ONE * FRAME_BORDER
		var x: float = parent.get_meta("plan").service_anchor + [8.45,10.12][storage_index]
		holder.rotation = Vector3(-lean,0,0)
		holder.position = Vector3(x,outer.y*.5*cos(lean)-.015*sin(lean),30.1+outer.y*.5*sin(lean)-.015*cos(lean))
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(outer.x,outer.y,.08)
		collision.shape = shape
		collision.position.z = .055
		body.add_child(collision)
		holder.add_child(body)
		holder.set_meta("stored_size", outer)
	var print_mesh:=MeshInstance3D.new()
	print_mesh.name="Print"
	var quad:=QuadMesh.new(); quad.size=Vector2(width,height)
	print_mesh.mesh=quad; print_mesh.position.z=.058
	var print_mat:=StandardMaterial3D.new()
	print_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	print_mat.albedo_color=Color(.82,.82,.79)
	print_mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	print_mesh.material_override=print_mat; holder.add_child(print_mesh)
	holder.set_meta("photo_index",index)
	holder.set_meta("image_size",Vector2(width,height))
	return holder
