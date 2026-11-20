extends RefCounted
## Six turning plans with three collection galleries on the retained three-meter grid.
const GRID := 3.0
const STRIDE := 42.0
const NAMES := ["Arrival Gallery", "Sculpture Hall", "Garden Lounge", "Cross Gallery", "Back Hall", "Storage", "Preparation", "Collection Gallery", "Plant Room", "Pipe Passage"]
const ANNEX_NAMES := ["Northlight Studio", "Print Cabinet", "Park Loggia"]
const Garden = preload("res://scripts/museum/outdoor_plan.gd")
var rooms: Array[Dictionary] = []
var cells: Dictionary = {}
var walls: Array[Dictionary] = []
var boundaries: Array[Dictionary] = []
var portals: Array[Dictionary] = []
var windows: Array[Dictionary] = []
var variant := 0
var annex := -1
var service_anchor := 0.0
var service_doors: Array[Dictionary] = []
var garden_gate := Vector3.ZERO

func add_room(id: int, strips: Array, height: float, sky: Rect2) -> void:
	var rects: Array[Rect2] = []
	for strip in strips:
		var rect := Rect2(strip[0]*GRID,strip[2]*GRID,(strip[1]-strip[0])*GRID,(strip[3]-strip[2])*GRID)
		rects.append(rect)
		for x in range(strip[0],strip[1]):
			for z in range(strip[2],strip[3]):
				var cell:=Vector2i(x,z)
				assert(not cells.has(cell),"Gallery footprints cannot overlap")
				cells[cell]=id
	rooms.append({"id":id,"name":NAMES[id],"rects":rects,"height":height,"sky":sky})

func populate(index: int, seed_value: int, expanded: bool) -> void:
	variant=posmod(index/2+seed_value-1930,6)
	var arrival: Array=[[-2,2,0,3],[-2,3,3,6]]
	var sculpture: Array=[[-6,-4,0,2],[-8,-2,2,4],[-7,-2,4,6]]
	var court: Array=[[-7,-2,6,8],[-8,-2,8,12],[-7,-2,12,14]]
	var returning: Array=[[-2,2,8,10],[-2,4,10,12],[-2,2,12,14]]
	if variant==1:
		arrival=[[-2,2,0,6]]
		sculpture=[[-8,-2,0,6]]
		court=[[-8,-2,6,14]]
		returning=[[-2,2,8,12],[-2,3,12,14]]
	elif variant==2:
		arrival=[[-2,2,0,2],[-2,3,2,4],[-2,1,4,6]]
		sculpture=[[-7,-2,0,2],[-8,-2,2,4],[-7,-2,4,6]]
		returning=[[-2,2,8,10],[-2,3,10,12],[-2,2,12,14]]
	elif variant==3:
		arrival=[[-2,2,0,3],[-2,4,3,6]]
		sculpture=[[-7,-2,0,2],[-8,-2,2,6]]
		returning=[[-2,2,8,10],[-2,4,10,12],[-2,3,12,14]]
	elif variant==4:
		arrival=[[-2,2,0,2],[-2,4,2,4],[-2,2,4,6]]
		sculpture=[[-7,-2,0,2],[-9,-2,2,4],[-7,-2,4,6]]
		court=[[-8,-2,6,8],[-9,-2,8,12],[-8,-2,12,14]]
		returning=[[-2,2,8,10],[-2,5,10,12],[-2,2,12,14]]
	elif variant==5:
		arrival=[[-2,2,0,2],[-2,3,2,4],[-2,4,4,6]]
		sculpture=[[-8,-2,0,6]]
		court=[[-8,-2,6,12],[-7,-2,12,14]]
		returning=[[-2,3,8,10],[-2,4,10,12],[-2,3,12,14]]
	add_room(0,arrival,6,Rect2(-3,3,6,6))
	add_room(1,sculpture,6,Rect2(-18,6,6,6))
	add_room(2,court,9,Rect2(-19.5,25.5,9,9))
	add_room(3,returning,6,Rect2(-3,30,6,6))
	# Service rooms remain three meters short of the next wing's public footprint.
	var entrance_x: int=returning[-1][1]
	var anchor:=entrance_x
	for strip in returning: anchor=maxi(anchor,strip[1])
	service_anchor=anchor*GRID
	var hall: Array=[[anchor,anchor+1,8,12],[entrance_x,anchor+1,12,13]]
	var storage: Array=[[anchor+1,anchor+4,10,13]]
	var preparation: Array=[[anchor+1,anchor+4,7,10]]
	if variant%3==1:
		storage=[[anchor+1,anchor+4,10,12],[anchor+1,anchor+3,12,13]]
	elif variant%3==2:
		preparation=[[anchor+1,anchor+3,7,8],[anchor+1,anchor+4,8,10]]
	add_room(4,hall,3,Rect2())
	add_room(5,storage,3,Rect2())
	add_room(6,preparation,3,Rect2())
	service_doors=[{"at":Vector3(entrance_x*GRID,0,37.5),"key":"hall","paint":"sage"},
		{"at":Vector3(service_anchor+3,0,34.5),"key":"store","paint":"slate"},
		{"at":Vector3(service_anchor+3,0,25.5),"key":"prep","paint":"sage"}]
	portals=[{"at":Vector3(-6,0,10.5),"turn":true},
		{"at":Vector3(-16.5,0,18),"turn":false},
		{"at":Vector3(-6,0,31.5),"turn":true},
		{"at":Vector3(0,0,42),"turn":false}]
	if index>0: portals.append({"at":Vector3(0,0,0),"turn":false})
	if expanded:
		annex = posmod(index + index / 12 + posmod(seed_value - 1930, 3), 3)
		var strips: Array
		var sky := Rect2()
		var height := 6.0
		match annex:
			0:
				strips = [[4,8,3,6],[-2,8,6,7],[anchor,anchor+1,7,8]]
				sky = Rect2(15,12,6,6)
			1:
				strips = [[6,9,2,4],[5,9,4,6],[-2,9,6,7],[anchor,anchor+1,7,8]]
				height = 4.5
			2:
				strips = [[5,8,1,3],[4,8,3,6],[-2,8,6,7],[anchor,anchor+1,7,8]]
		# Reach the exhibition from the garden and the existing end of Back Hall.
		add_room(7, strips, height, sky)
		rooms[7].name = ANNEX_NAMES[annex]
		add_room(8, [[anchor+4,anchor+7,8,11]], 6, Rect2())
		add_room(9, [[anchor+7,anchor+8,8,11],[anchor+4,anchor+8,11,13]], 3, Rect2())
		portals.append({"at":Vector3(-6,0,19.5),"turn":true,"width":2.25,"rise":.8})
		service_doors.append_array([{"at":Vector3(service_anchor+12,0,25.5),"key":"plant","paint":"oxide"},
			{"at":Vector3(service_anchor+21,0,28.5),"key":"pipe","paint":"oxide","reverse_swing":true},
			{"at":Vector3(service_anchor+12,0,34.5),"key":"return","paint":"slate"},
			{"at":Vector3(service_anchor+1.5,0,24),"axis":2,"key":"exhibition","paint":"sage"}])

func create(index: int, seed_value: int, expanded: bool) -> RefCounted:
	populate(index,seed_value,expanded)
	var edges: Dictionary={}
	var room_edges: Dictionary={}
	for cell: Vector2i in cells:
		var id: int=cells[cell]
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var neighbor: int=cells.get(cell+direction,-1)
			if neighbor==id: continue
			var axis:=0 if direction.x!=0 else 2
			var value: float=(cell.x+(1 if direction.x>0 else 0))*GRID if axis==0 else (cell.y+(1 if direction.y>0 else 0))*GRID
			var start: float=cell.y*GRID if axis==0 else cell.x*GRID
			var inward:=-Vector3(direction.x,0,direction.y)
			var boundary_key:="%d:%d:%.1f:%s"%[id,axis,value,inward]
			if not room_edges.has(boundary_key): room_edges[boundary_key]=[]
			room_edges[boundary_key].append({"axis":axis,"value":value,"start":start,"end":start+GRID,"room":id,"inward":inward})
			if neighbor>=0 and neighbor<id: continue
			# Keep the established photo sequence on incoming ends as each wing now
			# supplies its own side of the shared wall.
			var incoming := index>0 and axis==2 and ((index%2==0 and id==0 and is_zero_approx(value)) or (index%2==1 and id==3 and is_equal_approx(value,STRIDE)))
			var height: float=maxf(rooms[id].height,rooms[neighbor].height if neighbor>=0 else 0)
			var key: String="%d:%.1f:%.1f:%d:%d"%[axis,value,height,id,neighbor]
			if not edges.has(key): edges[key]=[]
			edges[key].append({"axis":axis,"value":value,"start":start,"end":start+GRID,"height":height,"room":id,"neighbor":neighbor,"hangable":not incoming,"inward":-Vector3(direction.x,0,direction.y)})
	walls=merge_edges(edges)
	boundaries=merge_edges(room_edges)
	if index % 3 == 0:
		for edge in walls:
			if edge.room == 2 and edge.neighbor < 0 and edge.inward == Vector3.RIGHT and edge.start < Garden.GATE_Z and edge.end > Garden.GATE_Z:
				garden_gate = Vector3(edge.value, 0, Garden.GATE_Z)
				portals.append({"at": garden_gate, "turn": true})
				break
	for candidate in [[6.0,4.5,4.8],[-6.0,22.5,6.5]]:
		for edge in walls:
			if edge.axis==0 and edge.neighbor<0 and is_equal_approx(edge.value,candidate[0]) and edge.start<=candidate[1]-1.2 and edge.end>=candidate[1]+1.2:
				windows.append({"at":Vector3(candidate[0],0,candidate[1]),"width":2.4,"bottom":1.0,"top":candidate[2],"inward":edge.inward})
	# Reserve the longest park-facing bay in each picture-free room.
	for room_id in [1, 2]:
		var bay: Dictionary = {}
		for edge in walls:
			if edge.room != room_id or edge.neighbor >= 0 or edge.inward != Vector3.RIGHT: continue
			if bay.is_empty() or edge.end - edge.start > bay.end - bay.start:
				bay = edge
		var width := minf(9.0 if room_id == 2 else 6.0, bay.end - bay.start - 1.2)
		windows.append({"at": Vector3(bay.value, 0, (bay.start + bay.end) * .5),
			"width": width, "bottom": 1.0, "top": 6.5 if room_id == 2 else 4.8, "inward": bay.inward})
	if expanded:
		windows.append({"at":Vector3(2,0,21),"axis":2,"width":8.4,"bottom":1.12,
			"top":3.66,"inward":Vector3.FORWARD})
	if annex in [0,2]:
		windows.append({"at":Vector3(24,0,15 if annex==0 else 10.5),"width":4.8 if annex==0 else 11.4,
			"bottom":1.0,"top":4.8,"inward":Vector3.LEFT})
	return self

static func merge_edges(groups: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for group: Array in groups.values():
		group.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.start<b.start)
		var merged: Dictionary=group[0].duplicate()
		for i in range(1,group.size()):
			if is_equal_approx(merged.end,group[i].start): merged.end=group[i].end
			else:
				result.append(merged); merged=group[i].duplicate()
		result.append(merged)
	return result

func room_id_at(point: Vector3) -> int:
	return cells.get(Vector2i(floori(point.x/GRID),floori(point.z/GRID)),-1)

func room_at(point: Vector3) -> String:
	var id := room_id_at(point)
	if id>=0: return rooms[id].name
	var garden_room := outdoor_room_at(point)
	if not garden_room.is_empty(): return garden_room
	return "Museum"

func outdoor_room_at(point: Vector3) -> String:
	if garden_gate == Vector3.ZERO: return ""
	return Garden.room_at(Vector2(garden_gate.x - point.x, garden_gate.z - point.z))
