"""Import an LBA viewer GLB, rebuild its Eevee palette material, save a .blend.

Run with: blender -b --factory-startup --python tools/import_lba1_glb.py -- input.glb output.blend
"""

import sys
import json
import math
import struct
import tempfile
import zlib
from pathlib import Path

import bpy
from mathutils import Vector


def input_paths():
    if "--" not in sys.argv:
        raise SystemExit("Usage: blender -b --python tools/import_lba1_glb.py -- INPUT.glb OUTPUT.blend [--no-platform]")
    arguments = sys.argv[sys.argv.index("--") + 1 :]
    if len(arguments) not in (2, 3) or (len(arguments) == 3 and arguments[2] != "--no-platform"):
        raise SystemExit("Usage: blender -b --python tools/import_lba1_glb.py -- INPUT.glb OUTPUT.blend [--no-platform]")
    return arguments[0], arguments[1], "--no-platform" not in arguments


def repair_embedded_glb_images(source_path):
    """Blender 5.0 can leave valid embedded GLB PNGs as empty image datablocks."""
    data = Path(source_path).read_bytes()
    if data[:4] != b"glTF":
        raise RuntimeError("Input is not a binary glTF file")
    json_size = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20 : 20 + json_size])
    binary_start = 20 + json_size + 8
    with tempfile.TemporaryDirectory(prefix="lba-glb-images-") as folder:
        for image_info in document.get("images", []):
            old = bpy.data.images.get(image_info.get("name", ""))
            if old is None or "bufferView" not in image_info:
                continue
            view = document["bufferViews"][image_info["bufferView"]]
            start = binary_start + view.get("byteOffset", 0)
            end = start + view["byteLength"]
            path = Path(folder) / f"image-{image_info['bufferView']}.png"
            path.write_bytes(data[start:end])
            loaded = bpy.data.images.load(str(path), check_existing=False)
            if loaded.size[0] == 0:
                raise RuntimeError(f"Embedded image {old.name} could not be loaded")
            loaded.pack(data=data[start:end], data_len=view["byteLength"])
            for material in bpy.data.materials:
                if material.node_tree:
                    for node in material.node_tree.nodes:
                        if node.type == "TEX_IMAGE" and node.image == old:
                            node.image = loaded
            bpy.data.images.remove(old)


def math_node(nodes, operation, first, second, label):
    node = nodes.new("ShaderNodeMath")
    node.operation = operation
    node.label = label
    if isinstance(first, bpy.types.NodeSocket):
        links.new(first, node.inputs[0])
    else:
        node.inputs[0].default_value = first
    if isinstance(second, bpy.types.NodeSocket):
        links.new(second, node.inputs[1])
    else:
        node.inputs[1].default_value = second
    return node.outputs[0]


def render_dimension(nodes, scene, axis):
    value = nodes.new("ShaderNodeValue")
    value.label = f"Live render {axis} pixels"
    socket = value.outputs[0]
    driver = socket.driver_add("default_value").driver
    driver.expression = "dimension * percentage / 100"
    dimension = driver.variables.new()
    dimension.name = "dimension"
    dimension.type = "SINGLE_PROP"
    dimension.targets[0].id_type = "SCENE"
    dimension.targets[0].id = scene
    dimension.targets[0].data_path = f"render.resolution_{axis.lower()}"
    percentage = driver.variables.new()
    percentage.name = "percentage"
    percentage.type = "SINGLE_PROP"
    percentage.targets[0].id_type = "SCENE"
    percentage.targets[0].id = scene
    percentage.targets[0].data_path = "render.resolution_percentage"
    return socket


def camera_ortho_scale(nodes, scene):
    value = nodes.new("ShaderNodeValue")
    value.label = "Live orthographic camera height"
    socket = value.outputs[0]
    driver = socket.driver_add("default_value").driver
    driver.expression = "scale"
    scale = driver.variables.new()
    scale.name = "scale"
    scale.type = "SINGLE_PROP"
    scale.targets[0].id_type = "SCENE"
    scale.targets[0].id = scene
    scale.targets[0].data_path = "camera.data.ortho_scale"
    return socket


def smoothstep(nodes, value, low, high, label):
    unit = math_node(nodes, "DIVIDE", math_node(nodes, "SUBTRACT", value, low, label), high - low, label)
    unit = math_node(nodes, "MINIMUM", math_node(nodes, "MAXIMUM", unit, 0.0, label), 1.0, label)
    return math_node(nodes, "MULTIPLY", math_node(nodes, "MULTIPLY", unit, unit, label),
                     math_node(nodes, "SUBTRACT", 3.0, math_node(nodes, "MULTIPLY", unit, 2.0, label), label), label)


def shader_hash(x, y):
    return (math.sin(x * 127.1 + y * 311.7) * 43758.5453) % 1.0


def soft_dither_image():
    """The viewer's rotated 8x8 model-space threshold, packed as an indexed PNG."""
    existing = bpy.data.images.get("LBA_Soft_Dither_1024")
    if existing:
        return existing
    size = 1024
    rows = bytearray()
    # PNG rows run top-down; the UV image origin is at the bottom left.
    for y in range(size - 1, -1, -1):
        cell_y = y - size // 2
        rows.append(0)
        for x in range(size):
            cell_x = x - size // 2
            tile_x, tile_y = cell_x // 8, cell_y // 8
            local_x, local_y = cell_x % 8, cell_y % 8
            turn = int(shader_hash(tile_x + 19, tile_y + 7) * 4)
            if turn == 1:
                local_x, local_y = 7 - local_y, local_x
            elif turn == 2:
                local_x, local_y = 7 - local_x, 7 - local_y
            elif turn == 3:
                local_x, local_y = local_y, 7 - local_x
            rows.append(round(shader_hash(local_x + tile_x * 37, local_y + tile_y * 53) * 255))
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))
    with tempfile.TemporaryDirectory(prefix="lba-soft-dither-") as folder:
        path = Path(folder) / "lba-soft-dither.png"
        path.write_bytes(png)
        image = bpy.data.images.load(str(path), check_existing=False)
        image.name = "LBA_Soft_Dither_1024"
        image.pack(data=png, data_len=len(png))
    image.colorspace_settings.name = "Non-Color"
    return image


def mix_color(nodes, factor, first, second, label):
    node = nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.label = label
    links.new(factor, node.inputs[0])
    links.new(first, node.inputs[6])
    links.new(second, node.inputs[7])
    return node.outputs[2]


def palette_sample(nodes, palette_image, index, label):
    coordinate = math_node(nodes, "DIVIDE", math_node(nodes, "ADD", index, 0.5, label), 256.0, label)
    uv = nodes.new("ShaderNodeCombineXYZ")
    links.new(coordinate, uv.inputs["X"])
    uv.inputs["Y"].default_value = 0.5
    image = nodes.new("ShaderNodeTexImage")
    image.label = label
    image.image = palette_image
    image.interpolation = "Closest"
    image.extension = "CLIP"
    links.new(uv.outputs[0], image.inputs["Vector"])
    return image.outputs["Color"]


def reconstruct_palette_material(mesh_obj, palette_image, is_lba2):
    global links
    material = bpy.data.materials.new("LBA Palette · Eevee soft model dither")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    links = material.node_tree.links

    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = mesh_obj.data.uv_layers[0].name
    uv_split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(uv.outputs["UV"], uv_split.inputs[0])
    # Blender flips glTF V on import. UV.y holds source face metadata, so
    # restore its original direction before decoding the packed values.
    source_v = math_node(nodes, "SUBTRACT", 1.0, uv_split.outputs["Y"], "Restore GLB face metadata V")
    palette_value = math_node(nodes, "SUBTRACT", math_node(nodes, "MULTIPLY", uv_split.outputs["X"], 256.0, "Palette coordinate"), 0.5, "Palette index")
    base = math_node(nodes, "FLOOR", palette_value, 0.0, "Lower palette index")
    fraction = math_node(nodes, "FRACT", palette_value, 0.0, "Fractional shade")

    lower_color = palette_sample(nodes, palette_image, base, "Lower palette colour")
    upper_index = math_node(nodes, "MODULO", math_node(nodes, "ADD", base, 1.0, "Next palette index"), 256.0, "Wrap palette")
    upper_color = palette_sample(nodes, palette_image, upper_index, "Upper palette colour")
    smooth_color = mix_color(nodes, fraction, lower_color, upper_color, "Smooth palette blend")

    if len(mesh_obj.data.uv_layers) > 1:
        anchor = nodes.new("ShaderNodeUVMap")
        anchor.uv_map = mesh_obj.data.uv_layers[1].name
        anchor.label = "Rest-pose model coordinates (GLB UV2)"
        anchor_split = nodes.new("ShaderNodeSeparateXYZ")
        links.new(anchor.outputs["UV"], anchor_split.inputs[0])
        anchor_vector = nodes.new("ShaderNodeCombineXYZ")
        links.new(anchor_split.outputs["X"], anchor_vector.inputs["X"])
        links.new(math_node(nodes, "SUBTRACT", 1.0, anchor_split.outputs["Y"], "Restore GLB dither V"), anchor_vector.inputs["Y"])
        dither = nodes.new("ShaderNodeTexImage")
        dither.image = soft_dither_image()
        dither.interpolation = "Closest"
        dither.extension = "REPEAT"
        dither.label = "Viewer rotated 8x8 threshold"
        links.new(anchor_vector.outputs[0], dither.inputs["Vector"])
        threshold = nodes.new("ShaderNodeSeparateXYZ")
        links.new(dither.outputs["Color"], threshold.inputs[0])
        increment = math_node(nodes, "GREATER_THAN", fraction, threshold.outputs["X"], "Choose next palette colour")
        stepped_color = mix_color(nodes, increment, lower_color, upper_color, "Model-anchored palette step")

        encoded_type = math_node(nodes, "MULTIPLY", source_v, 16.0, "Face type and shade slope")
        gradient = math_node(nodes, "MULTIPLY", math_node(nodes, "MAXIMUM", math_node(nodes, "SUBTRACT", math_node(nodes, "FRACT", encoded_type, 0.0, "Packed slope"), 0.125, "Slope origin"), 0.0, "Positive slope"), 64.0, "Shade change per model unit")
        height = render_dimension(nodes, bpy.context.scene, "Y")
        camera_height = camera_ortho_scale(nodes, bpy.context.scene)
        units_per_pixel = math_node(nodes, "DIVIDE", camera_height, height, "Model units per render pixel")
        footprint = math_node(nodes, "MULTIPLY", units_per_pixel, 256.0, "Pattern cells per pixel")
        footprint_weight = math_node(nodes, "SUBTRACT", 1.0, smoothstep(nodes, footprint, 0.75, 1.5, "Pattern resolution fade"), "Visible pattern")
        distance = nodes.new("ShaderNodeVectorMath")
        distance.operation = "DISTANCE"
        distance.label = "Palette colour gap"
        links.new(lower_color, distance.inputs[0])
        links.new(upper_color, distance.inputs[1])
        visible_change = math_node(nodes, "MULTIPLY", math_node(nodes, "MULTIPLY", distance.outputs["Value"], gradient, "Colour and shade slope"), math_node(nodes, "MULTIPLY", units_per_pixel, 64.0, "Viewer transition scale"), "Visible palette transition")
        transition = smoothstep(nodes, visible_change, 0.08, 0.22, "Only dither palette transitions")
        coverage = math_node(nodes, "MULTIPLY", math_node(nodes, "MULTIPLY", transition, footprint_weight, "Transition and distance"), 0.56, "Viewer soft dither strength")
        soft_color = mix_color(nodes, coverage, smooth_color, stepped_color, "Subtle soft dither")
    else:
        # Older GLBs have no model anchor or slope; their palette stays smooth.
        soft_color = smooth_color

    if is_lba2:
        final_color = soft_color
    else:
        # LBA1's soft path is confined to source shaded faces (type >= 7).
        face_type = math_node(nodes, "FLOOR", math_node(nodes, "MULTIPLY", source_v, 16.0, "Source face type"), 0.0, "Whole face type")
        use_soft = math_node(nodes, "GREATER_THAN", face_type, 6.5, "LBA1 shaded face")
        ordinary = math_node(nodes, "FLOOR", math_node(nodes, "ADD", palette_value, 0.5, "Nearest index"), 0.0, "Solid palette index")
        ordinary_color = palette_sample(nodes, palette_image, ordinary, "LBA1 solid colour")
        final_color = mix_color(nodes, use_soft, ordinary_color, soft_color, "Source face mode")
    emission = nodes.new("ShaderNodeEmission")
    links.new(final_color, emission.inputs["Color"])
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(emission.outputs[0], output.inputs["Surface"])
    # The first GLB surface is palette shaded. Keep later LBA2 texture surfaces.
    if not mesh_obj.data.materials:
        raise RuntimeError("Character mesh has no palette material slot")
    mesh_obj.data.materials[0] = material


def reconstruct_platform_material():
    """Keep the viewer's yellow top and shadowed orange rim editable in Eevee."""
    global links
    material = bpy.data.materials.new("LBA Display Platform · warm shade")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    links = material.node_tree.links
    geometry = nodes.new("ShaderNodeNewGeometry")
    position = nodes.new("ShaderNodeSeparateXYZ")
    normal = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Position"], position.inputs[0])
    links.new(geometry.outputs["Normal"], normal.inputs[0])
    height = nodes.new("ShaderNodeMapRange")
    height.inputs["From Min"].default_value = -0.105
    height.inputs["From Max"].default_value = -0.005
    links.new(position.outputs["Z"], height.inputs["Value"])
    side_level = math_node(nodes, "ADD", math_node(nodes, "MULTIPLY", height.outputs["Result"], 0.56, "Rim height"), 0.26, "Warm rim light")
    is_top = math_node(nodes, "GREATER_THAN", normal.outputs["Z"], 0.7, "Yellow top")
    level = nodes.new("ShaderNodeMix")
    level.data_type = "FLOAT"
    links.new(is_top, level.inputs[0])
    links.new(side_level, level.inputs[2])
    level.inputs[3].default_value = 0.96
    colors = nodes.new("ShaderNodeMix")
    colors.data_type = "RGBA"
    links.new(level.outputs[0], colors.inputs[0])
    colors.inputs[6].default_value = (0.42, 0.15, 0.015, 1.0)
    colors.inputs[7].default_value = (0.98, 0.68, 0.075, 1.0)
    emission = nodes.new("ShaderNodeEmission")
    links.new(colors.outputs[2], emission.inputs["Color"])
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(emission.outputs[0], output.inputs["Surface"])
    return material


def make_all_actions_cyclic():
    curves_updated = 0
    for action in bpy.data.actions:
        action.use_fake_user = True
        for layer in action.layers:
            for strip in layer.strips:
                for channelbag in strip.channelbags:
                    for curve in channelbag.fcurves:
                        cycles = curve.modifiers.new("CYCLES")
                        # Actor travel must accumulate on later loops, while
                        # rotations and child-bone poses repeat in place.
                        repeat_mode = "REPEAT_OFFSET" if curve.data_path in ("location", 'pose.bones["Group_00"].location') else "REPEAT"
                        cycles.mode_before = repeat_mode
                        cycles.mode_after = repeat_mode
                        curves_updated += 1
    return curves_updated


def main():
    source_path, blend_path, include_platform = input_paths()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=source_path,bone_heuristic='FORTUNE')
    repair_embedded_glb_images(source_path)
    helper_collection = bpy.data.collections.get("glTF_not_exported")
    if helper_collection:
        for imported_helper in list(helper_collection.objects):
            bpy.data.objects.remove(imported_helper, do_unlink=True)
    characters = sorted(
        (obj for obj in bpy.data.objects if obj.type == "MESH" and obj.name.startswith("CharacterMesh")),
        key=lambda obj: obj.name,
    )
    shadow = bpy.data.objects.get("LBA1ActorShadow")
    if not characters:
        raise RuntimeError("GLB does not contain character meshes")
    images = [image for image in bpy.data.images if image.size[:] == (256, 1)]
    if not images:
        raise RuntimeError("GLB has no embedded 256-color palette")
    is_lba2 = any(obj.name.startswith("LBA2_Character") for obj in bpy.data.objects)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    for character in characters:
        palette_image = next(
            (
                node.image
                for node in character.data.materials[0].node_tree.nodes
                if node.type == "TEX_IMAGE" and node.image and node.image.size[:] == (256, 1)
            ),
            images[0],
        )
        reconstruct_palette_material(character, palette_image, is_lba2)
        for texture_material in character.data.materials[1:]:
            if texture_material and texture_material.use_nodes:
                for node in texture_material.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image:
                        node.interpolation = "Closest"
                        node.extension = "REPEAT"
                        if not node.image.packed_file:
                            node.image.pack()

    if include_platform:
        bpy.ops.object.select_all(action="DESELECT")
        bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.75, depth=0.10, location=(0, 0, -0.055))
        platform = bpy.context.object
        platform.name = "DisplayPlatform"
        platform.data.materials.append(reconstruct_platform_material())

    camera_data = bpy.data.cameras.new("Orbit preview camera")
    camera = bpy.data.objects.new("Orbit preview camera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (3.4, -5.5, 3.2)
    target = Vector((0.0, 0.0, 1.12))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 5.5
    scene.camera = camera
    scene.world.color = (0.10, 0.13, 0.18)

    # Preserve imported glTF action slots on the armature. The current clip is
    # the first one; all source-associated actions remain available in the file.
    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError("GLB has no usable armature")
    cyclic_curves = make_all_actions_cyclic() if bpy.data.actions else 0
    if bpy.data.actions and cyclic_curves == 0:
        raise RuntimeError("Imported actions have no curves to cycle")
    idle_actions = sorted((action for action in bpy.data.actions if action.name.startswith("Idle_ANIM_")), key=lambda action: action.name)
    preview_actions = idle_actions or sorted(bpy.data.actions, key=lambda action: action.name)
    if preview_actions:
        armature = armatures[0]
        armature.animation_data_create()
        armature.animation_data.action = preview_actions[0]
        armature.animation_data.action_slot = preview_actions[0].slots[0]
        scene.frame_set(1)
    scene.render.film_transparent = False
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    texture_materials = sum(max(0, len(character.data.materials) - 1) for character in characters)
    print(f"SAVED {blend_path}: {len(bpy.data.actions)} cyclic clips, {cyclic_curves} cyclic channels, {len(armatures[0].data.bones)} bones, {len(characters)} body variants, palette, {texture_materials} texture materials, shadow={shadow is not None}", flush=True)


if __name__ == "__main__":
    main()
