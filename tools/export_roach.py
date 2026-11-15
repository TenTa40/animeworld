# Run by the CI: blender -b tools/Roach.blend --python tools/export_roach.py
import bpy, os

out = os.path.abspath("assets/enemies/roach.glb")
os.makedirs(os.path.dirname(out), exist_ok=True)
tries = [
    dict(export_format='GLB', export_animations=True, export_animation_mode='ACTIONS'),
    dict(export_format='GLB', export_animations=True),
    dict(export_format='GLB'),
]
for kw in tries:
    try:
        bpy.ops.export_scene.gltf(filepath=out, **kw)
        print("EXPORTED", kw)
        break
    except Exception as e:
        print("export failed", kw, e)
