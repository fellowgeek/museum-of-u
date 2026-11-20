"""Export the pinned Blendkit flashlight for the VR right-hand aim pose."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "third_party_assets/blendkit/flashlight/source.blend"
OUTPUT = ROOT / "local_models/flashlight.glb"
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False, use_scripts=False)
obj = bpy.context.scene.objects["Flashlight"]
assert obj.type == "MESH" and len(obj.data.vertices) == 987
# Source lens faces -Y. Reverse X/Y so glTF's -Z points out of the lens.
# Center the length on XY while retaining the authored grounded Z=0 base.
y_mid = (min(v.co.y for v in obj.data.vertices) + max(v.co.y for v in obj.data.vertices)) / 2
for vertex in obj.data.vertices:
    vertex.co.x = -vertex.co.x
    vertex.co.y = -(vertex.co.y - y_mid)
obj.data.update()
# The source mapping is identity and all PBR/normal textures are packed.
# Explicit UV links export directly; displacement is omitted for this low-poly mesh.
for material in obj.data.materials:
    tree = material.node_tree
    uv = tree.nodes.new("ShaderNodeUVMap")
    uv.uv_map = obj.data.uv_layers.active.name
    for node in tree.nodes:
        if node.type == "TEX_IMAGE":
            assert node.image.packed_file
            tree.links.new(uv.outputs["UV"], node.inputs["Vector"])
    output = next(n for n in tree.nodes if n.type == "OUTPUT_MATERIAL")
    for link in list(output.inputs["Displacement"].links):
        tree.links.remove(link)
for image in bpy.data.images:
    if image.size[0] > 1024:
        image.scale(1024, 1024)
        image.pack()
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", use_selection=True,
                          export_apply=True, export_yup=True, export_extras=False)
print("VR_FLASHLIGHT_EXPORT_OK", OUTPUT, tuple(obj.dimensions))
