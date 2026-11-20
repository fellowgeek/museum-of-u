extends Node3D
class_name MuseumManager
## Endless repeating wings with bounded residency and a rebased physical origin.
const Library = preload("res://scripts/museum/photo_library.gd")
const Builder = preload("res://scripts/museum/gallery_builder.gd")
@export var player: Node3D
var world_seed := 1930
var spread_preparation := false
var last_load_ms := 0.0
var peak_load_ms := 0.0
var loaded_total := 0
var _last_player_chunk := Vector2i.ZERO
var _active_chunks: Dictionary = {}
var _chunks_to_load: Array[Vector2i] = []
var library: Node
var origin_wing := 0
var frames: Dictionary = {}
var photo_directory_override := ""
var initialized := false
var realization_times: Array[float] = []

func _ready() -> void:
	world_seed=GameSettings.active_seed()
	if not player: player=get_parent().get_node("Player")
	library=Library.new(); library.directory=photo_directory_override
	library.catalog_ready.connect(_catalog_ready)
	library.texture_ready.connect(_texture_ready)
	library.texture_failed.connect(_texture_failed)
	add_child(library)
	# A guaranteed floor is present even in direct source/developer launches.
	_last_player_chunk=world_to_chunk_coords(player.position)
	_load_chunk(_last_player_chunk)

func _catalog_ready() -> void:
	# Populate the initial geometry once the external catalog is available.
	for chunk in _active_chunks.values(): chunk.free()
	_active_chunks.clear(); frames.clear()
	_last_player_chunk=world_to_chunk_coords(player.position)
	_update_chunks(true)
	initialized=true
	print("MUSEUM CATALOG: %d photos, %d skipped; endless repeating wings; folder=%s"%[library.entries.size(),library.rejected.size(),library.directory])

func world_to_chunk_coords(pos: Vector3) -> Vector2i:
	return Vector2i(0,maxi(0,origin_wing+floori(pos.z/Builder.STRIDE)))

func required_chunks_at(center: Vector2i) -> Dictionary:
	var result: Dictionary={}
	for index in range(maxi(0,center.y-1),center.y+2): result[Vector2i(0,index)]=true
	return result

func _update_chunks(immediate: bool) -> void:
	var required:=required_chunks_at(_last_player_chunk)
	_chunks_to_load.clear()
	var retiring: Array[Vector2i]=[]
	for coord in _active_chunks:
		if not required.has(coord): retiring.append(coord)
	_unload_chunks(retiring)
	for coord in required:
		if not _active_chunks.has(coord):
			if immediate: _load_chunk(coord)
			else: _chunks_to_load.append(coord)
	retain_photos()

func _load_chunk(coord: Vector2i) -> void:
	var started:=Time.get_ticks_usec()
	var builder:=Builder.new()
	var sun: DirectionalLight3D = get_parent().get_node("Sun")
	var wing: Node3D=builder.build(coord.y,world_seed,sun.basis.z)
	wing.position.z=(coord.y-origin_wing)*Builder.STRIDE+(Builder.STRIDE if coord.y%2==1 else 0.0)
	add_child(wing)
	_active_chunks[coord]=wing
	if library != null and library.scanned and not library.entries.is_empty():
		var capacity: int = wing.get_meta("photo_slots").size()
		var stored := Builder.STORAGE_PHOTOS.size() if wing.get_meta("plan").annex >= 0 else 0
		for position in capacity + stored:
			var storage_index := position - capacity
			var slot: int = Builder.STORAGE_PHOTOS[storage_index] if storage_index >= 0 else position
			var index: int=posmod(coord.y*capacity+slot,library.entries.size())
			var frame: Node3D=Builder.frame(wing,library.entries[index],slot,storage_index)
			frame.set_meta("photo_index",index)
			if library.textures.has(index):
				frame.get_node("Print").material_override.albedo_texture=library.textures[index]
				frame.get_node("Print").material_override.albedo_color=Color.WHITE
	last_load_ms=(Time.get_ticks_usec()-started)/1000.0
	realization_times.append(last_load_ms)
	if realization_times.size()>64: realization_times.pop_front()
	peak_load_ms=maxf(peak_load_ms,last_load_ms); loaded_total+=1
	retain_photos()

func retain_photos() -> void:
	if library==null or not library.scanned: return
	frames.clear()
	for wing in _active_chunks.values():
		for frame in wing.get_children():
			if not frame.has_meta("photo_index"): continue
			var index: int=frame.get_meta("photo_index")
			if not frames.has(index): frames[index]=[]
			frames[index].append(frame.get_node("Print"))
	var retained: Array[int]=[]
	for index in frames: retained.append(index)
	library.retain(retained)

func _texture_ready(index: int, texture: Texture2D) -> void:
	for frame in frames.get(index,[]):
		if not is_instance_valid(frame): continue
		var mat: StandardMaterial3D=frame.material_override
		mat.albedo_texture=texture; mat.albedo_color=Color.WHITE

func _texture_failed(index: int) -> void:
	for frame in frames.get(index,[]):
		if not is_instance_valid(frame): continue
		for node in frame.get_parent().get_children():
			if node is Label3D: node.text += "\nImage unavailable — replace the file and restart"

func rebase_if_needed() -> void:
	if absf(player.position.z)<Builder.STRIDE*4: return
	var shift_wings:=maxi(-origin_wing,floori(player.position.z/Builder.STRIDE))
	if shift_wings==0: return
	var offset:=Vector3(0,0,shift_wings*Builder.STRIDE)
	origin_wing+=shift_wings
	player.position-=offset
	# The tracked origin is top-level and therefore does not follow its parent.
	if player.vr != null:
		player.vr.global_position-=offset
		player.vr.reset_physics_interpolation()
	for wing in _active_chunks.values():
		wing.position-=offset
		wing.reset_physics_interpolation()
	player.reset_physics_interpolation()

func _process(_delta: float) -> void:
	if not initialized or not is_instance_valid(player): return
	rebase_if_needed()
	var current:=world_to_chunk_coords(player.global_position)
	if current!=_last_player_chunk:
		_last_player_chunk=current; _update_chunks(false)
	if not _chunks_to_load.is_empty(): _load_chunk(_chunks_to_load.pop_front())

func finish_preparation() -> void:
	while not initialized: await get_tree().process_frame
	while not _chunks_to_load.is_empty():
		_load_chunk(_chunks_to_load.pop_front())
		await get_tree().process_frame

func museum_room_at(point: Vector3) -> String:
	var coord:=world_to_chunk_coords(point)
	var wing: Node3D=_active_chunks.get(coord)
	if wing==null: return "Gallery"
	return wing.get_meta("plan").room_at(wing.to_local(point))

func outdoor_garden_at(point: Vector3) -> Node3D:
	var wing: Node3D = _active_chunks.get(world_to_chunk_coords(point))
	if wing == null or wing.get_meta("plan").outdoor_room_at(wing.to_local(point)).is_empty(): return null
	return wing.get_node("OutdoorGarden")

func museum_spawn(actor: CharacterBody3D, desired: Vector3, validator: RefCounted) -> Dictionary:
	await finish_preparation()
	var candidates: Array[Vector3]=[desired,Vector3(0,.04,5)]
	for point in candidates:
		if validator.cancelled: return {}
		_last_player_chunk=world_to_chunk_coords(point)
		_update_chunks(true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var garden := outdoor_garden_at(point)
		if garden != null:
			var local := garden.to_local(point)
			var basin: Rect2 = preload("res://scripts/museum/outdoor_plan.gd").POOL
			if basin.grow(.30).has_point(Vector2(local.x,local.z)):
				# Older visits could save from the basin or its coping.
				local.z = basin.position.y - .95
				local.y = .04
				point = garden.to_global(local)
		validator.space=actor.get_world_3d().direct_space_state
		validator.player=actor; validator.shape.radius=.38; validator.shape.height=1.8
		var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*3,1,[actor.get_rid()])
		var hit: Dictionary=validator.space.intersect_ray(query)
		if hit.is_empty() or not hit.collider.is_in_group("museum_floor") or hit.normal.y<.94: continue
		if hit.collider.is_in_group("woodland_ground") and outdoor_garden_at(point) == null: continue
		var at: Vector3=hit.position+Vector3.UP*.04
		if not validator.clear(at): continue
		# Authored public circulation is separately tested with capsule sweeps.
		validator.details={"position":[at.x,at.y,at.z],"relocated":at.distance_to(desired)>.2,"museum":true}
		return {"position":at}
	return {}

func active_chunks_snapshot() -> Dictionary:
	var result := _active_chunks.duplicate()
	result.make_read_only()
	return result

func _unload_chunks(coords: Array[Vector2i]) -> void:
	if coords.is_empty(): return
	for coord in coords:
		var wing: Node3D = _active_chunks[coord]
		_active_chunks.erase(coord)
		wing.queue_free()
