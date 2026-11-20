extends RefCounted
## Garden coordinates run west through the entrance, then north along the woodland.
const GATE_Z := 38.4
const ENTRY_LENGTH := 6.0
const ENTRY_HALF_WIDTH := 1.75
const GROUNDS := Rect2(6.0, -2.8, 74.0, 35.0)
const DEEP_WOODS_X := 48.0
const SUN_POCKETS := [Vector2(59,9), Vector2(71,24)]
const COURT := Rect2(6.0, -2.8, 12.6, 12.0)
const POOL := Rect2(8.65,3.25,8.6,3.0)
const GLADE := Vector2(38.0, 20.0)
const GLADE_RADIUS := 4.35
const PATH_HALF_WIDTH := 1.28
# Both ends of the walk meet the paved court. The pool sits between them.
const WALK := [
	Vector2(16, .7), Vector2(22, 1.5), Vector2(28, 5), Vector2(30, 10),
	Vector2(35, 13), GLADE, Vector2(34, 25.0), Vector2(26, 26.4),
	Vector2(20, 23), Vector2(19, 18), Vector2(14.5, 14), Vector2(12, 8.2),
]
static var _trail: Curve2D

static func trail() -> Curve2D:
	if _trail == null:
		_trail = Curve2D.new()
		_trail.bake_interval = .65
		for i in WALK.size():
			var tangent: Vector2 = (WALK[mini(i + 1, WALK.size() - 1)] - WALK[maxi(i - 1, 0)]) / 6.0
			_trail.add_point(WALK[i], -tangent, tangent)
	return _trail

static func room_at(p: Vector2) -> String:
	if p.x >= 0 and p.x <= ENTRY_LENGTH and absf(p.y) <= ENTRY_HALF_WIDTH: return "Reflection Court"
	if not GROUNDS.grow(.01).has_point(p): return ""
	if COURT.has_point(p): return "Reflection Court"
	if p.distance_to(GLADE) < GLADE_RADIUS: return "Woodland Court"
	if p.x >= DEEP_WOODS_X: return "Deep Woods"
	return "Forest Walk"
