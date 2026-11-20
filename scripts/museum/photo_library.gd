extends Node
## Catalog and decode visitor photos on one worker; upload textures on the main thread.
signal catalog_ready
signal texture_ready(index: int, texture: Texture2D)
signal texture_failed(index: int)
const Folders = preload("res://scripts/museum/photo_folders.gd")
const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_PIXELS := 64000000
const TEXTURE_EDGE := 1024
var directory := ""
var entries: Array = []
var rejected: Array = []
var scanned := false
var worker: Thread
var operation := ""
var working_index := -1
var requested: Array[int] = []
var wanted: Dictionary = {}
var textures: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if directory.is_empty(): directory = Folders.photo_directory()
	worker = Thread.new()
	operation = "scan"
	var problem := worker.start(prepare_and_scan.bind(directory))
	if problem != OK:
		rejected = [{"path":directory,"reason":"Could not start photo worker"}]
		scanned = true
		catalog_ready.emit()

static func prepare_and_scan(folder: String) -> Dictionary:
	var problem := Folders.prepare(folder)
	var catalog := scan(folder)
	if problem != OK:
		catalog.rejected.append({"path":folder, "reason":"Could not install sample photos: " + error_string(problem)})
		if catalog.entries.is_empty(): catalog.entries = scan(Folders.SAMPLES).entries
	return catalog

static func number(bytes: PackedByteArray, offset: int, count: int, little := false) -> int:
	if offset < 0 or offset + count > bytes.size(): return 0
	var value := 0
	for n in count:
		value = (value << 8) | bytes[offset + (count-1-n if little else n)]
	return value

static func exif_orientation(bytes: PackedByteArray, offset: int, end: int) -> int:
	if offset+8 > end: return 1
	var little := bytes[offset] == 73 and bytes[offset+1] == 73
	if not little and not (bytes[offset] == 77 and bytes[offset+1] == 77): return 1
	if number(bytes,offset+2,2,little) != 42: return 1
	var table := offset + number(bytes,offset+4,4,little)
	if table < offset+8 or table+2 > end: return 1
	for i in mini(number(bytes,table,2,little),512):
		var at := table+2+i*12
		if at+12 > end: break
		if number(bytes,at,2,little)==274 and number(bytes,at+2,2,little)==3 and number(bytes,at+4,4,little)==1:
			return clampi(number(bytes,at+8,2,little),1,8)
	return 1

static func header(bytes: PackedByteArray) -> Dictionary:
	var w := 0
	var h := 0
	var orientation := 1
	if bytes.size() >= 24 and bytes.slice(0,8) == PackedByteArray([137,80,78,71,13,10,26,10]):
		w = number(bytes,16,4); h = number(bytes,20,4)
	elif bytes.size() >= 4 and bytes[0]==255 and bytes[1]==216:
		var at := 2
		while at+4 <= bytes.size():
			if bytes[at] != 255: break
			while at < bytes.size() and bytes[at]==255: at += 1
			if at >= bytes.size(): break
			var marker := bytes[at]
			at += 1
			if marker in [217,218]: break
			if marker == 1 or (marker >= 208 and marker <= 215): continue
			var length := number(bytes,at,2)
			if length < 2 or at+length > bytes.size(): break
			if marker in [192,193,194] and length >= 8:
				h=number(bytes,at+3,2); w=number(bytes,at+5,2)
			if marker==225 and bytes.slice(at+2,at+8)==PackedByteArray([69,120,105,102,0,0]):
				orientation=exif_orientation(bytes,at+8,at+length)
			at += length
	elif bytes.size() >= 30 and bytes.slice(0,4).get_string_from_ascii()=="RIFF" and bytes.slice(8,12).get_string_from_ascii()=="WEBP":
		var kind := bytes.slice(12,16).get_string_from_ascii()
		if kind == "VP8X":
			# Animated WebP is intentionally excluded from a still-photo collection.
			if bytes[20] & 2: return {}
			w=number(bytes,24,3,true)+1; h=number(bytes,27,3,true)+1
		elif kind == "VP8 " and bytes.slice(23,26)==PackedByteArray([157,1,42]):
			w=number(bytes,26,2,true)&16383; h=number(bytes,28,2,true)&16383
		elif kind == "VP8L" and bytes[20]==47:
			var bits := number(bytes,21,4,true)
			w=(bits&16383)+1; h=((bits>>14)&16383)+1
	if w < 1 or h < 1 or w > 16384 or h > 16384 or w*h > MAX_PIXELS: return {}
	return {"width":h if orientation>=5 else w,"height":w if orientation>=5 else h,"orientation":orientation}

static func scan(folder: String) -> Dictionary:
	var found: Array = []
	var skipped: Array = []
	for relative in Folders.photo_paths(folder, false, skipped):
		var file_path := folder.path_join(relative)
		var file := FileAccess.open(file_path, FileAccess.READ)
		var info := {}
		if file != null and file.get_length() <= MAX_FILE_BYTES:
			info = header(file.get_buffer(mini(file.get_length(), 65536)))
			if info.is_empty() and file.get_length() > 65536:
				file.seek(0)
				info = header(file.get_buffer(mini(file.get_length(), 1024 * 1024)))
		if info.is_empty():
			skipped.append({"path":file_path, "reason":"Unsupported, unreadable or oversized image"})
		else:
			info.path = file_path
			info.title = relative.get_file().get_basename().replace("_", " ").replace("-", " ")
			info.relative = relative
			found.append(info)
	found.sort_custom(func(a,b):
		var order: int=a.relative.naturalnocasecmp_to(b.relative)
		return a.relative < b.relative if order==0 else order<0)
	return {"entries":found,"rejected":skipped}

static func orient(image: Image, orientation: int) -> void:
	match orientation:
		2: image.flip_x()
		3: image.rotate_180()
		4: image.flip_y()
		5: image.rotate_90(CLOCKWISE); image.flip_x()
		6: image.rotate_90(CLOCKWISE)
		7: image.rotate_90(CLOCKWISE); image.flip_y()
		8: image.rotate_90(COUNTERCLOCKWISE)

static func decode(entry: Dictionary) -> Image:
	var file := FileAccess.open(entry.path,FileAccess.READ)
	if file == null or file.get_length()>MAX_FILE_BYTES: return null
	var bytes := file.get_buffer(file.get_length())
	var current := header(bytes)
	if current.is_empty() or current.width!=entry.width or current.height!=entry.height or current.orientation!=entry.orientation: return null
	var image := Image.new()
	var problem := ERR_FILE_UNRECOGNIZED
	match entry.path.get_extension().to_lower():
		"jpg","jpeg": problem=image.load_jpg_from_buffer(bytes)
		"png": problem=image.load_png_from_buffer(bytes)
		"webp": problem=image.load_webp_from_buffer(bytes)
	if problem!=OK or image.is_empty(): return null
	orient(image,entry.orientation)
	var scale := minf(1.0,float(TEXTURE_EDGE)/maxi(image.get_width(),image.get_height()))
	if scale<1.0: image.resize(maxi(1,roundi(image.get_width()*scale)),maxi(1,roundi(image.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	return image

func retain(indices: Array[int]) -> void:
	wanted.clear()
	for index in indices:
		wanted[index]=true
		if not textures.has(index) and index!=working_index and index not in requested: requested.append(index)
	requested=requested.filter(func(i): return wanted.has(i))
	for index in textures.keys():
		if not wanted.has(index): textures.erase(index)

func _process(_delta: float) -> void:
	if worker != null and worker.is_started():
		if worker.is_alive(): return
		var result: Variant = worker.wait_to_finish()
		if operation=="scan":
			entries=result.entries; rejected=result.rejected; scanned=true
			catalog_ready.emit()
		elif wanted.has(working_index):
			if result is Image:
				var texture := ImageTexture.create_from_image(result)
				textures[working_index]=texture
				texture_ready.emit(working_index,texture)
			else:
				rejected.append({"path":entries[working_index].path,"reason":"Decode failed or file changed; restart to rescan"})
				texture_failed.emit(working_index)
		working_index=-1
	if scanned and not requested.is_empty():
		working_index=requested.pop_front()
		operation="decode"
		worker=Thread.new()
		worker.start(decode.bind(entries[working_index].duplicate()))

func _exit_tree() -> void:
	if worker != null and worker.is_started(): worker.wait_to_finish()
