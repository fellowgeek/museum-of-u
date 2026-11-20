"""Export the approved BlenderKit door, preserving sampled hinge/handle motion."""
from pathlib import Path
import bpy
from mathutils import Matrix
ROOT = Path(__file__).resolve().parents[2]
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'third_party_assets/blendkit/interior_door/source.blend'), use_scripts=False)
scene = bpy.context.scene
source = list(scene.objects)
meshes = [o for o in source if o.type == 'MESH']
hinge = bpy.data.objects['Door']
scale = Matrix.Scale(1.2, 4)
samples = {}
for frame in range(1, 55):
    scene.frame_set(frame)
    samples[frame] = {o.name: scale @ o.matrix_world @ scale.inverted() for o in meshes + [hinge]}
scene.frame_set(1)
depsgraph = bpy.context.evaluated_depsgraph_get()
evaluated_meshes = {o.name: bpy.data.meshes.new_from_object(
    o.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph) for o in meshes}
# Rebuild clean nodes: no source scripts, constraints, drivers, or custom properties.
output = bpy.data.scenes.new('DoorExport')
bpy.context.window.scene = output
pivot = bpy.data.objects.new('Hinge', None)
output.collection.objects.link(pivot)
for o in meshes:
    mesh = evaluated_meshes[o.name]
    mesh.transform(scale)
    node = bpy.data.objects.new('Leaf' if o.name == 'Door.001' else o.name.replace(' ', '_'), mesh)
    output.collection.objects.link(node)
    moving = o.parent == hinge
    if moving:
        node.parent = pivot
    for frame in (range(1,55) if moving else [1]):
        node.matrix_local = samples[frame]['Door'].inverted() @ samples[frame][o.name] if moving else samples[frame][o.name]
        if moving:
            node.keyframe_insert('location', frame=frame)
            node.keyframe_insert('rotation_euler', frame=frame)
for frame in range(1,55):
    pivot.matrix_local = samples[frame]['Door']
    pivot.keyframe_insert('location', frame=frame)
    pivot.keyframe_insert('rotation_euler', frame=frame)
output.frame_start = 1
output.frame_end = 54
output.render.fps = 60
output.frame_set(1)
path = ROOT / 'local_models/door.glb'
path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_active_scene=True,
    export_animations=True, export_animation_mode='SCENE', export_frame_range=True,
    export_force_sampling=True, export_anim_scene_split_object=False,
    export_yup=True, export_cameras=False, export_lights=False)
assert path.exists()
print('INTERIOR DOOR EXPORT PASS', path.stat().st_size)
