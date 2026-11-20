extends RefCounted
## Capsule clearance at the museum's authored arrival points.
var cancelled := false
var details: Dictionary = {}
var space: PhysicsDirectSpaceState3D
var player: CharacterBody3D
var shape := CapsuleShape3D.new()

func find(owner: MuseumManager, actor: CharacterBody3D, desired: Vector3) -> Dictionary:
	return await owner.museum_spawn(actor, desired, self)

func clear(at: Vector3) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform.origin=at+Vector3.UP*0.9
	query.collision_mask=player.collision_mask
	query.exclude=[player.get_rid()]
	query.margin=0.002
	return space.intersect_shape(query,1).is_empty()
