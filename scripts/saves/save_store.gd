extends RefCounted
## Immutable validated revisions; index is a hint, recovery scans published revisions.
const Journal = preload("res://scripts/saves/interaction_journal.gd")
const Model = preload("res://scripts/settings/menu_settings.gd")
const MAX_BYTES := 2097152
const VERSION := 1
const MAX_SLOTS := 10
var root := "user://saves"
var error := ""
var last_write_ms := 0.0

static func identifier() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func valid_id(id: String) -> bool:
	return id.length() == 32 and id.is_valid_hex_number(false)

static func valid_name(value: Variant) -> bool:
	return value is String and value.strip_edges().length() in range(1,81) and not "\n" in value and not "\r" in value

static func read_json(path: String, limit: int = MAX_BYTES) -> Variant:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > limit: return null
	return JSON.parse_string(file.get_as_text())

static func write_json(path: String, data: Dictionary) -> String:
	var bytes := JSON.stringify(data,"",true).to_utf8_buffer()
	if bytes.size()>MAX_BYTES: return "Save exceeds 2 MiB limit"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return "Cannot write storage (%s)" % error_string(FileAccess.get_open_error())
	file.store_buffer(bytes)
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK: return "Storage write failed (%s)" % error_string(status)
	if read_json(path) != JSON.parse_string(bytes.get_string_from_utf8()): return "Storage readback failed"
	return ""

static func validate(data: Variant) -> String:
	if not data is Dictionary: return "Damaged save"
	if data.get("version") != VERSION: return "Unsupported save format; original preserved"
	if data.get("generator") != GameSettings.GENERATOR_VERSION: return "Different Generator Required"
	if data.get("settings_version") != 1 or data.get("interaction_version") != 1: return "Unsupported save schema"
	if not valid_name(data.get("name")) or not valid_id(str(data.get("slot",""))): return "Invalid run identity"
	if not data.get("settings") is Dictionary: return "Missing world configuration"
	var problem := Model.strict(data.settings)
	if not problem.is_empty(): return problem
	for key in ["seed", "original_seed"]:
		if not SettingsLoader.valid_leaf(data.get(key),SettingsSchema.RULES["world.seed"]): return "Invalid saved seed"
	if not SettingsLoader._number(data.get("transitions")) or data.transitions < 0 or data.transitions != floor(data.transitions): return "Invalid transition count"
	var expected_id := GameSettings.stored_identity(data.settings, int(data.seed))
	if expected_id.is_empty() or data.get("generation_id") != expected_id: return "Saved generation identity does not match its configuration"
	if int(data.settings.world.seed)!=int(data.seed) or data.settings.world.seed_mode!="fixed": return "Saved active seed mismatch"
	if not data.get("saved") is String or data.saved.length()>40: return "Invalid save timestamp"
	if not data.get("pose") is Dictionary: return "Missing exploration bookmark"
	for key in ["position", "rotation", "neck_rotation", "camera_rotation"]:
		var vector: Variant = data.pose.get(key)
		if not vector is Array or vector.size()!=3: return "Invalid player pose"
		for n in vector:
			if not SettingsLoader._number(n) or absf(n)>10000000.0: return "Invalid player coordinate"
	if not data.pose.get("crouching") is bool or not data.pose.get("flashlight_on") is bool: return "Invalid player state"
	var museum_origin: Variant=data.pose.get("museum_origin_wing",0)
	if not SettingsLoader._number(museum_origin) or museum_origin<0 or museum_origin!=floor(museum_origin) or museum_origin>2147483600: return "Invalid museum origin"
	problem = Journal.validate(data.get("journal"))
	if not problem.is_empty(): return problem
	return preload("res://scripts/session/run_memory.gd").validate_records(data.journal.records)

func revisions(slot: String) -> Array:
	var found: Array = []
	if not valid_id(slot): return found
	var path := root.path_join(slot).path_join("revisions")
	for filename in DirAccess.get_files_at(path):
		if not filename.ends_with(".json"): continue
		var data: Variant = read_json(path.path_join(filename))
		var problem := validate(data)
		found.append({"file":filename,"data":data if problem.is_empty() else {},"error":problem})
	found.sort_custom(func(a,b): return a.file>b.file)
	return found

func list_slots() -> Array:
	var slots: Array = []
	if not DirAccess.dir_exists_absolute(root): return slots
	for slot in DirAccess.get_directories_at(root):
		if not valid_id(slot): continue
		var entries := revisions(slot)
		var valid: Dictionary = {}
		for entry in entries:
			if entry.error.is_empty(): valid=entry; break
		if valid.is_empty(): slots.append({"slot":slot,"name":"Unavailable run","error":"Damaged or incompatible; no usable revision", "saved":""})
		else:
			var data: Dictionary = valid.data
			slots.append({"slot":slot,"name":data.name,"saved":data.get("saved",""),"error":"", "recovery":entries[0]!=valid,"revision":valid.file,"data":data})
	slots.sort_custom(func(a,b): return a.get("revision","")>b.get("revision",""))
	return slots

func has_capacity() -> bool:
	var count:=0
	if DirAccess.dir_exists_absolute(root):
		for slot in DirAccess.get_directories_at(root):
			if valid_id(slot): count+=1
	return count<MAX_SLOTS

func save(data: Dictionary, kind := "manual") -> bool:
	error=validate(data)
	if not error.is_empty(): return false
	if DirAccess.make_dir_recursive_absolute(root)!=OK:
		error="Cannot create save storage."; return false
	# Serialize capacity checks across processes, including first-slot creation.
	var lock:=root.path_join("slots.lock")
	if DirAccess.make_dir_absolute(lock)!=OK:
		error="Save storage is locked by another writer or an interrupted save."; return false
	var result:=false
	var replaced: Array = []
	var original_slot: String = data.slot
	if not DirAccess.dir_exists_absolute(root.path_join(data.slot)) and not has_capacity():
		# Reuse the least recently written slot. Publish a validated new revision
		# before retiring its previous exploration, so a failed write loses nothing.
		var oldest: Dictionary = list_slots().back()
		data.slot = oldest.slot
		replaced = revisions(data.slot)
	result=_save_revision(data,kind)
	if original_slot != data.slot:
		if result:
			var folder := root.path_join(data.slot)
			for entry in replaced:
				DirAccess.remove_absolute(folder.path_join("revisions").path_join(entry.file))
			for bucket in ["manual", "auto"]:
				DirAccess.remove_absolute(folder.path_join(bucket + ".jpg"))
		else: data.slot = original_slot
	DirAccess.remove_absolute(lock)
	return result

func _save_revision(data: Dictionary, kind: String) -> bool:
	error = validate(data)
	if not error.is_empty(): return false
	var started := Time.get_ticks_usec()
	var folder := root.path_join(data.slot)
	var revision_dir := folder.path_join("revisions")
	if DirAccess.make_dir_recursive_absolute(revision_dir) != OK:
		error="Cannot create save folder. Check storage permissions and free space."; return false
	# Directory creation is an exclusive cross-process lock. A stale lock is preserved,
	# so another process cannot silently steal ownership after a crash.
	var lock := folder.path_join("writer.lock")
	if DirAccess.make_dir_absolute(lock) != OK:
		error="This run is locked by another writer or an interrupted save. Return to Saved Games and try again later."; return false
	var existing := revisions(data.slot)
	for entry in existing:
		if entry.error.begins_with("Unsupported"):
			error="A newer save format exists in this slot; choose another saved game."
			DirAccess.remove_absolute(lock)
			return false
	var revision := "%020d-%s-%s.json" % [int(Time.get_unix_time_from_system()*1000000),kind,identifier()]
	var temporary := revision_dir.path_join(revision+".tmp")
	error=write_json(temporary,data)
	if error.is_empty(): error=validate(read_json(temporary))
	if error.is_empty() and DirAccess.rename_absolute(temporary,revision_dir.path_join(revision))!=OK: error="Cannot publish save revision"
	if error.is_empty():
		# A failed index replacement cannot lose the independently published revision.
		var index_temp := folder.path_join("index.json.tmp")
		var index_error := write_json(index_temp,{"latest":revision,"name":data.name})
		if index_error.is_empty(): DirAccess.rename_absolute(index_temp,folder.path_join("index.json"))
		# The lock keeps the validated preflight list stable. The new revision
		# already passed readback and validation before publication.
		existing.append({"file":revision,"error":""})
		existing.sort_custom(func(a,b): return a.file>b.file)
		var counts := {"manual":0,"auto":0}
		for entry in existing:
			if not entry.error.is_empty(): continue
			var bucket := "auto" if "-auto-" in entry.file else "manual"
			counts[bucket]+=1
			if counts[bucket]>1: DirAccess.remove_absolute(revision_dir.path_join(entry.file))
	else: DirAccess.remove_absolute(temporary)
	DirAccess.remove_absolute(lock)
	last_write_ms=(Time.get_ticks_usec()-started)/1000.0
	return error.is_empty()

func delete(slot: String) -> bool:
	if not valid_id(slot): return false
	var folder := root.path_join(slot)
	if DirAccess.dir_exists_absolute(folder.path_join("writer.lock")): return false
	for filename in DirAccess.get_files_at(folder.path_join("revisions")):
		if filename.ends_with(".json") or filename.ends_with(".tmp"): DirAccess.remove_absolute(folder.path_join("revisions").path_join(filename))
	DirAccess.remove_absolute(folder.path_join("revisions"))
	for kind in ["manual","auto"]:
		DirAccess.remove_absolute(folder.path_join(kind+".jpg"))
		DirAccess.remove_absolute(folder.path_join(kind+".jpg.tmp"))
	DirAccess.remove_absolute(folder.path_join("index.json"))
	DirAccess.remove_absolute(folder.path_join("index.json.tmp"))
	return DirAccess.remove_absolute(folder)==OK
