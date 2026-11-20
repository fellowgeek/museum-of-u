extends RefCounted

# Bundled exhibit and maximum display envelope for each optional local model.
const EXHIBITS := {
	"alba_ceramics": ["ceramic_vase_02", Vector3(1.155, 0.650, 0.411)],
	"bathing_goddess": ["garden_statue", Vector3(0.628, 1.900, 0.808)],
	"calathea_plant": ["potted_plant_04", Vector3(1.064, 1.100, 1.136)],
	"canova_naiad": ["antique_ceramic_vase", Vector3(1.786, 0.780, 0.757)],
	"concrete_buddha": ["garden_statue", Vector3(0.918, 1.300, 0.537)],
	"expressive_stone": ["ceramic_vase_01", Vector3(1.051, 0.700, 1.380)],
	"female_bust": ["marble_bust_01", Vector3(0.654, 1.050, 0.519)],
	"guadeloupe_wood": ["ceramic_vase_02", Vector3(0.241, 1.300, 0.391)],
	"jungling": ["abstract_sculpture", Vector3(0.880, 1.850, 0.548)],
	"monstera_plant": ["potted_plant_02", Vector3(0.941, 1.500, 1.012)],
	"sad_woman": ["antique_ceramic_vase", Vector3(0.913, 1.800, 1.279)],
	"salmacis": ["bear_sculpture", Vector3(1.284, 1.280, 0.920)],
	"seated_sculpture": ["ceramic_vase_01", Vector3(0.911, 1.200, 0.760)],
	"taihu_stone": ["ceramic_vase_02", Vector3(0.622, 1.600, 0.818)],
	"tiki_stone": ["planter_pot_clay", Vector3(0.311, 1.380, 0.317)],
	"venus_statue": ["abstract_sculpture", Vector3(0.662, 2.100, 0.595)],
}

static func local_scene(id: String, bundled: PackedScene) -> PackedScene:
	var path := "res://local_models/%s.glb" % id
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return bundled

static func exhibit(id: String) -> Node3D:
	var source_id := id
	if EXHIBITS.has(id):
		var optional := local_scene(id, null)
		if optional:
			return optional.instantiate()
		source_id = EXHIBITS[id][0]
	var model := load("res://assets/models/museum/%s/%s.glb" % [source_id, source_id]).instantiate() as Node3D
	if EXHIBITS.has(id):
		var fit: Vector3 = EXHIBITS[id][1] / visual_bounds(model).size
		model.scale *= minf(fit.x, minf(fit.y, fit.z))
	return model

## Bounds in the subject's local coordinates, also valid before entering the scene tree.
static func visual_bounds(node: Node3D) -> AABB:
	var result:=AABB()
	var first:=true
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null: continue
		var transform:=mesh.transform
		var parent:=mesh.get_parent()
		while parent!=node:
			if parent is Node3D: transform=parent.transform*transform
			parent=parent.get_parent()
		var bounds: AABB=transform*mesh.get_aabb()
		result=bounds if first else result.merge(bounds)
		first=false
	return result
