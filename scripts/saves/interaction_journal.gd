extends RefCounted
## Sparse latest-state changes. Expiry removes records, never alters live nodes.
const RETENTION := 1800.0
const MAX_RECORDS := 4096
const MAX_BYTES := 1048576
var clock := 0.0
var records: Dictionary = {}
var trimmed := false
var _batch_depth := 0
var _dirty := false
var _encoded_bytes := 2

func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> void:
	assert(_batch_depth > 0, "Journal batches must be balanced")
	_batch_depth -= 1
	if _batch_depth == 0: prune()

func advance(delta: float) -> void:
	clock += maxf(delta, 0.0)
	prune()

func change(id: String, payload: Dictionary) -> void:
	if records.has(id) and records[id].state == payload: return
	records[id] = {"changed":clock, "state":payload.duplicate(true)}
	_dirty = true
	if _batch_depth == 0: prune()

func erase(id: String) -> void:
	if records.erase(id): _dirty = true

func prune() -> void:
	for id in records.keys():
		if clock - float(records[id].changed) >= RETENTION: erase(id)
	if not _dirty: return
	_encoded_bytes = JSON.stringify(records).to_utf8_buffer().size()
	_dirty = false
	if records.size() <= MAX_RECORDS and _encoded_bytes <= MAX_BYTES: return
	var keys := records.keys()
	keys.sort_custom(func(a,b):
		return str(a)<str(b) if records[a].changed == records[b].changed else records[a].changed<records[b].changed)
	for id in keys:
		# JSON object bytes are the encoded entries, commas and two braces.
		# Encode only the evicted entry; do not re-encode the remaining journal.
		_encoded_bytes -= JSON.stringify({id:records[id]}).to_utf8_buffer().size()-2
		if records.size() > 1: _encoded_bytes -= 1
		records.erase(id)
		trimmed = true
		if records.size() <= MAX_RECORDS and _encoded_bytes <= MAX_BYTES: break

func snapshot() -> Dictionary:
	prune()
	return {"clock":clock, "records":records.duplicate(true), "trimmed":trimmed}

static func validate(data: Variant) -> String:
	if not data is Dictionary or not data.get("records") is Dictionary: return "Invalid interaction journal"
	if not SettingsLoader._number(data.get("clock")) or data.clock < 0.0: return "Invalid exploration clock"
	if data.records.size() > MAX_RECORDS or JSON.stringify(data.records).to_utf8_buffer().size() > MAX_BYTES: return "Interaction journal exceeds storage limits"
	for id in data.records:
		var record: Variant = data.records[id]
		if not id is String or id.length() > 256 or not record is Dictionary: return "Invalid interaction identity"
		if not SettingsLoader._number(record.get("changed")) or record.changed < 0 or record.changed > data.clock: return "Invalid interaction age"
		if not record.get("state") is Dictionary: return "Invalid interaction state"
	return ""

func restore(data: Dictionary) -> void:
	clock = data.clock
	records = data.records.duplicate(true)
	trimmed = data.get("trimmed",false)
	_batch_depth = 0
	_dirty = true
	prune()
