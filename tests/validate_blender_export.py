"""Reopen and inspect a converted LBA Blender file in Blender 5.x."""

import sys

import bpy


if "--" not in sys.argv:
    raise SystemExit("Pass a .blend path after --")
arguments = sys.argv[sys.argv.index("--") + 1:]
if not arguments:
    raise SystemExit("Pass a .blend path after --")
path = arguments[0]
expect_textures = "--expect-textures" in arguments[1:]
expect_no_platform = "--expect-no-platform" in arguments[1:]
bpy.ops.wm.open_mainfile(filepath=path)

character = bpy.data.objects["CharacterMesh"]
if expect_no_platform:
    assert "DisplayPlatform" not in bpy.data.objects, "Disabled platform was exported"
else:
    platform = bpy.data.objects["DisplayPlatform"]
    platform_material = platform.data.materials[0]
    assert platform_material.name.startswith("LBA Display Platform")
    assert any(node.type == "MIX" and node.data_type == "RGBA" for node in platform_material.node_tree.nodes), "Platform lost its warm color gradient"
is_lba2 = "LBA1ActorShadow" not in bpy.data.objects
if is_lba2:
    if expect_textures:
        assert len(character.data.materials) > 1, "LBA2 textured surfaces were lost"
        assert any(node.type == "TEX_IMAGE" and node.image and node.interpolation == "Closest" and node.image.packed_file
                   for material in character.data.materials[1:] for node in material.node_tree.nodes)
else:
    assert bpy.data.objects["LBA1ActorShadow"].type == "MESH"
assert any(image.size[:] == (256, 1) and image.packed_file for image in bpy.data.images)
assert len(character.data.uv_layers) > 1, "Model-space dither coordinates were lost"
soft_dither = bpy.data.images["LBA_Soft_Dither_1024"]
assert tuple(soft_dither.size) == (1024, 1024) and soft_dither.packed_file
palette_material = character.data.materials[0]
assert any(node.type == "UVMAP" and node.uv_map == character.data.uv_layers[1].name for node in palette_material.node_tree.nodes)
assert not any(node.type == "TEX_IMAGE" and node.image and node.image.name == "LBA1_Dither_4x4" for node in palette_material.node_tree.nodes)
idle_actions = [action for action in bpy.data.actions if action.name.startswith("Idle_ANIM_")]
if idle_actions:
    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    assert len(armatures) == 1, "Expected one imported character armature"
    armature = armatures[0]
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
                    expected = "REPEAT_OFFSET" if curve.data_path in ("location", 'pose.bones["Group_00"].location') else "REPEAT"
                    assert cycles[0].mode_before == expected and cycles[0].mode_after == expected
                    action_curves += 1
    assert action_curves > 0, action.name
    curve_count += action_curves

walks = sorted((action for action in bpy.data.actions
                if action.name.startswith("Walk_ANIM_") and not action.name.endswith("_loop")),
               key=lambda action: action.name)
motion = walks[0] if walks else next(iter(bpy.data.actions), None)
assert motion is not None, "No character action survived export"
walk = motion
if walk.name == "Walk_ANIM_109":
    curve = walk.layers[0].strips[0].channelbags[0].fcurves[0]
    first = curve.keyframe_points[0].co.x
    last = curve.keyframe_points[-1].co.x
    sample = first + (last - first) * 0.27
    expected_offset = curve.keyframe_points[-1].co.y - curve.keyframe_points[0].co.y if curve.data_path in ("location", 'pose.bones["Group_00"].location') else 0.0
    assert abs(curve.evaluate(sample + last - first) - curve.evaluate(sample) - expected_offset) < 1e-4

armature = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
armature.animation_data_create()
armature.animation_data.action = walk
armature.animation_data.action_slot = walk.slots[0]
first, last = walk.frame_range
poses = []
for fraction in (0.0, 0.25, 0.5, 0.75):
    frame = first + (last - first) * fraction
    bpy.context.scene.frame_set(int(frame), subframe=frame % 1.0)
    poses.append(tuple(round(value, 4) for bone in armature.pose.bones
                       for row in bone.matrix for value in row))
assert len(set(poses)) > 1, "Walk action has keys but does not move the exported rig"

print(f"PASS: reopened {path}, {len(bpy.data.actions)} cyclic actions, {curve_count} repeating channels, moving rig, platform={'off' if expect_no_platform else 'on'} and packed model-space dither", flush=True)
