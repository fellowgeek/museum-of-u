extends "res://scripts/props/interior_door.gd"
## Shared interactive door with museum service-room paint.
const PAINTS := {"sage":Color(.24,.34,.29),"slate":Color(.16,.23,.29),"oxide":Color("815b50")}
var paint_name := "sage"

func apply_color(model: Node3D) -> void:
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original: Material=mesh.get_active_material(surface)
			if original.resource_name!="Material": continue
			var paint:=original.duplicate() as StandardMaterial3D
			paint.albedo_color=PAINTS[paint_name]; paint.metallic=0; paint.roughness=.82
			mesh.set_surface_override_material(surface,paint)
