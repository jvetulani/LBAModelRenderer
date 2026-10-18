"""Reopen and inspect a converted LBA1 Blender file in Blender 5.x."""

import sys

import bpy


if "--" not in sys.argv:
    raise SystemExit("Pass a .blend path after --")
path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.open_mainfile(filepath=path)

character = bpy.data.objects["CharacterMesh"]
platform = bpy.data.objects["DisplayPlatform"]
assert platform.data.materials[0] == character.data.materials[0]
platform_shades = {round(loop.uv.x, 6) for loop in platform.data.uv_layers.active.data}
assert len(platform_shades) > 3, "Platform has no mesh-normal palette lighting"
assert bpy.data.objects["LBA1ActorShadow"].type == "MESH"
assert any(image.size[:] == (256, 1) and image.packed_file for image in bpy.data.images)
assert bpy.data.images["LBA1_Dither_4x4"].packed_file
idle_actions = [action for action in bpy.data.actions if action.name.startswith("Idle_ANIM_")]
if idle_actions:
    armature = bpy.data.objects["LBA1_Character"]
    assert armature.animation_data.action in idle_actions, "Idle is not the selected Blender action"

curve_count = 0
for action in bpy.data.actions:
    action_curves = 0
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                for curve in channelbag.fcurves:
                    cycles = [modifier for modifier in curve.modifiers if modifier.type == "CYCLES"]
                    assert len(cycles) == 1
                    assert cycles[0].mode_before == "REPEAT" and cycles[0].mode_after == "REPEAT"
                    action_curves += 1
    assert action_curves > 0, action.name
    curve_count += action_curves

walk = bpy.data.actions.get("Walk_ANIM_109")
if walk:
    curve = walk.layers[0].strips[0].channelbags[0].fcurves[0]
    first = curve.keyframe_points[0].co.x
    last = curve.keyframe_points[-1].co.x
    sample = first + (last - first) * 0.27
    assert abs(curve.evaluate(sample) - curve.evaluate(sample + last - first)) < 1e-4

print(f"PASS: reopened {path}, {len(bpy.data.actions)} cyclic actions, {curve_count} repeating channels, shared palette platform and packed images", flush=True)
