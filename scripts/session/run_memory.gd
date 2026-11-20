extends Node
## Per-visit door state. The journal follows the visit across streamed wings.
const Journal = preload("res://scripts/saves/interaction_journal.gd")
var active := false
var journal := Journal.new()

static func vector(v: Vector3) -> Array: return [v.x,v.y,v.z]
static func vec(v: Array) -> Vector3: return Vector3(v[0],v[1],v[2])

static func validate_records(records: Dictionary) -> String:
	for id in records:
		var state: Dictionary = records[id].state
		if state.get("kind") != "door" or not state.get("open") is bool:
			return "Invalid door state"
		if not state.get("world") is String or state.world.length() != 64 or not id.begins_with(state.world + ":door:"):
			return "Invalid door identity"
	return ""

func begin(data: Dictionary = {}) -> void:
	journal=Journal.new()
	if not data.is_empty(): journal.restore(data)
	active=true

func end() -> void:
	active=false

func key(kind: String, id: String) -> String:
	return GameSettings.active_generation_id()+":"+kind+":"+id

func get_state(kind: String, id: String) -> Dictionary:
	journal.prune()
	return journal.records.get(key(kind,id),{}).get("state",{})

func door_changed(id: String, opened: bool) -> void:
	if not active: return
	if not opened: journal.erase(key("door",id)); return
	journal.change(key("door",id),{"kind":"door","world":GameSettings.active_generation_id(),"open":opened})

func _physics_process(delta: float) -> void:
	if active: journal.clock += delta
