"""Import an LBA viewer GLB, rebuild its Eevee palette material, save a .blend.

Run with: blender -b --factory-startup --python tools/import_lba1_glb.py -- input.glb output.blend
"""

import sys
import json
import struct
import tempfile
from pathlib import Path

import bpy
from mathutils import Vector


def input_paths():
    if "--" not in sys.argv or len(sys.argv[sys.argv.index("--") + 1 :]) != 2:
        raise SystemExit("Usage: blender -b --python tools/import_lba1_glb.py -- INPUT.glb OUTPUT.blend")
    return sys.argv[sys.argv.index("--") + 1 :]


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


def reconstruct_palette_material(mesh_obj, palette_image):
    global links
    material = bpy.data.materials.new("LBA1 Palette · Eevee pixel dither")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    links = material.node_tree.links

    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = mesh_obj.data.uv_layers[0].name
    uv_split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(uv.outputs["UV"], uv_split.inputs[0])
    palette_value = math_node(nodes, "SUBTRACT", math_node(nodes, "MULTIPLY", uv_split.outputs["X"], 256.0, "Palette coordinate"), 0.5, "Palette index")
    base = math_node(nodes, "FLOOR", palette_value, 0.0, "Lower palette index")
    fraction = math_node(nodes, "FRACT", palette_value, 0.0, "Fractional shade")

    # LBA1 distributes fractional palette steps in screen space. Eevee cannot
    # reproduce the original scanline prefix sum, so this 4x4 ordered threshold
    # is a resolution-independent approximation, packed inside the .blend.
    thresholds = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]
    image = bpy.data.images.new("LBA1_Dither_4x4", width=4, height=4, alpha=False, float_buffer=False)
    pixels = []
    for row in reversed(thresholds):
        for value in row:
            gray = (value + 0.5) / 16.0
            pixels.extend((gray, gray, gray, 1.0))
    image.pixels[:] = pixels
    image.pack()
    image.colorspace_settings.name = "Non-Color"

    screen = nodes.new("ShaderNodeTexCoord")
    screen_split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(screen.outputs["Window"], screen_split.inputs[0])
    width = render_dimension(nodes, bpy.context.scene, "X")
    height = render_dimension(nodes, bpy.context.scene, "Y")
    cell_x = math_node(nodes, "DIVIDE", math_node(nodes, "MULTIPLY", screen_split.outputs["X"], width, "Screen X pixels"), 4.0, "Pattern X")
    cell_y = math_node(nodes, "DIVIDE", math_node(nodes, "MULTIPLY", screen_split.outputs["Y"], height, "Screen Y pixels"), 4.0, "Pattern Y")
    combine = nodes.new("ShaderNodeCombineXYZ")
    links.new(cell_x, combine.inputs["X"])
    links.new(cell_y, combine.inputs["Y"])
    dither = nodes.new("ShaderNodeTexImage")
    dither.image = image
    dither.interpolation = "Closest"
    dither.extension = "REPEAT"
    links.new(combine.outputs[0], dither.inputs["Vector"])
    dither_split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(dither.outputs["Color"], dither_split.inputs[0])
    increment = math_node(nodes, "GREATER_THAN", fraction, dither_split.outputs["X"], "Dither next index")
    dithered = math_node(nodes, "ADD", base, increment, "Dithered palette index")

    # UV.y carries the original polygon render type. Spheres and line pieces
    # carry zero; Gouraud and source dithered polygons carry nine or more.
    face_type = math_node(nodes, "MULTIPLY", uv_split.outputs["Y"], 16.0, "LBA polygon type")
    use_dither = math_node(nodes, "GREATER_THAN", face_type, 8.99, "Dither shaded polygons")
    ordinary = math_node(nodes, "FLOOR", math_node(nodes, "ADD", palette_value, 0.5, "Nearest index"), 0.0, "Solid palette index")
    chosen = nodes.new("ShaderNodeMix")
    chosen.data_type = "FLOAT"
    links.new(use_dither, chosen.inputs[0])
    links.new(ordinary, chosen.inputs[2])
    links.new(dithered, chosen.inputs[3])
    lookup = math_node(nodes, "DIVIDE", math_node(nodes, "ADD", chosen.outputs[0], 0.5, "Palette texel center"), 256.0, "Palette U")
    palette_uv = nodes.new("ShaderNodeCombineXYZ")
    links.new(lookup, palette_uv.inputs["X"])
    palette_uv.inputs["Y"].default_value = 0.5
    palette = nodes.new("ShaderNodeTexImage")
    palette.image = palette_image
    palette.interpolation = "Closest"
    palette.extension = "CLIP"
    links.new(palette_uv.outputs[0], palette.inputs["Vector"])
    emission = nodes.new("ShaderNodeEmission")
    links.new(palette.outputs["Color"], emission.inputs["Color"])
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
                        cycles.mode_before = "REPEAT"
                        cycles.mode_after = "REPEAT"
                        curves_updated += 1
    return curves_updated


def main():
    source_path, blend_path = input_paths()
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
        reconstruct_palette_material(character, palette_image)
        for texture_material in character.data.materials[1:]:
            if texture_material and texture_material.use_nodes:
                for node in texture_material.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image:
                        node.interpolation = "Closest"
                        node.extension = "REPEAT"
                        if not node.image.packed_file:
                            node.image.pack()

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
    if len(armatures) != 1 or not bpy.data.actions:
        raise RuntimeError("GLB has no usable armature/actions")
    cyclic_curves = make_all_actions_cyclic()
    if cyclic_curves == 0:
        raise RuntimeError("Imported actions have no curves to cycle")
    idle_actions = sorted((action for action in bpy.data.actions if action.name.startswith("Idle_ANIM_")), key=lambda action: action.name)
    if idle_actions:
        armature = armatures[0]
        armature.animation_data_create()
        armature.animation_data.action = idle_actions[0]
        armature.animation_data.action_slot = idle_actions[0].slots[0]
        scene.frame_set(1)
    scene.render.film_transparent = False
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    texture_materials = sum(max(0, len(character.data.materials) - 1) for character in characters)
    print(f"SAVED {blend_path}: {len(bpy.data.actions)} cyclic clips, {cyclic_curves} cyclic channels, {len(armatures[0].data.bones)} bones, {len(characters)} body variants, palette, {texture_materials} texture materials, shadow={shadow is not None}", flush=True)


if __name__ == "__main__":
    main()
