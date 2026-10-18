class_name LBA1GLBExporter
extends RefCounted

# glTF has no Godot spatial-shader equivalent. Store the source VGA palette as
# an embedded nearest-filtered texture and animate a one-weight-per-vertex skin.
const SCALE := CharacterMeshBuilder.UNIT_SCALE
const LIGHT_VECTOR := Vector3(-25.8, 37.6, 37.6)
const LBA2_APPEARANCE := preload("res://scripts/render/lba2_appearance.gd")


class MeshCollector:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()

	func add(point: Vector3, normal: Vector3, palette_index: float, group_index: int, render_type: int = 0) -> void:
		vertices.append(point)
		normals.append(normal)
		uvs.append(Vector2((fposmod(palette_index, 256.0) + 0.5) / 256.0, (float(render_type) + 0.5) / 16.0))
		bones.append_array(PackedInt32Array([group_index, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))

	func add_uv(point: Vector3, normal: Vector3, uv: Vector2, group_index: int) -> void:
		vertices.append(point)
		normals.append(normal)
		uvs.append(uv)
		bones.append_array(PackedInt32Array([group_index, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))

	func arrays() -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		return arrays


static func build(input: Dictionary) -> Dictionary:
	if not input.get("ok", false):
		return {"ok": false, "error": "Export input is invalid"}
	var body: Dictionary = input["body"]
	var palette: PackedByteArray = input["palette"]
	var clips: Array = input["clips"]
	if body.is_empty() or palette.size() != 768:
		return {"ok": false, "error": "Character or source palette is missing"}
	var raw_points: PackedVector3Array = body["pose_points"]
	var min_y := raw_points[0].y
	for point in raw_points:
		min_y = minf(min_y, point.y)
	var offset := Vector3.UP * (-min_y * SCALE)
	var scene := Node3D.new()
	scene.name = "%s_Character" % body.get("game", "LBA1")
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	scene.add_child(skeleton)
	skeleton.owner = scene
	var rest_origins: Array[Vector3] = []
	for group_index in range(body["groups"].size()):
		var group: Dictionary = body["groups"][group_index]
		var parent: int = group["parent"]
		var global_origin: Vector3 = offset if parent < 0 else body["pose_points"][group["pivot"]] * SCALE + offset
		var local_origin: Vector3 = global_origin if parent < 0 else global_origin - rest_origins[parent]
		rest_origins.append(global_origin)
		skeleton.add_bone("Group_%02d" % group_index)
		if parent >= 0:
			skeleton.set_bone_parent(group_index, parent)
		skeleton.set_bone_rest(group_index, Transform3D(Basis.IDENTITY, local_origin))
	var collector := MeshCollector.new()
	var glass_collector := MeshCollector.new()
	var textured_collectors := {}
	_add_polygons(collector, textured_collectors, body, offset, glass_collector)
	var translucent_solid: bool = LBA2_APPEARANCE.uses_translucent_solid(body)
	var accents := MeshCollector.new() if translucent_solid else collector
	_add_spheres(accents, body, offset)
	_add_lines(accents, body, offset)
	var mesh := ArrayMesh.new()
	var has_opaque := not collector.vertices.is_empty()
	if has_opaque:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, collector.arrays())
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "CharacterMesh"
	mesh_node.mesh = mesh
	skeleton.add_child(mesh_node)
	mesh_node.owner = scene
	var skin := Skin.new()
	for group_index in range(body["groups"].size()):
		skin.add_bind(group_index, skeleton.get_bone_global_rest(group_index).affine_inverse())
	mesh_node.skin = skin
	mesh_node.skeleton = NodePath("..")
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = ImageTexture.create_from_image(_palette_image(palette, body.get("game", "LBA1") in ["LBA2", "LBA2-96"]))
	material.cull_mode = BaseMaterial3D.CULL_BACK
	if translucent_solid:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = float(body.get("appearance", {}).get("opacity", LBA2_APPEARANCE.SPECTRAL_OPACITY))
	if has_opaque:
		mesh.surface_set_material(0, material)
	if not glass_collector.vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass_collector.arrays())
		var glass_material := StandardMaterial3D.new()
		glass_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glass_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		glass_material.albedo_texture = material.albedo_texture
		glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass_material.albedo_color.a = float(body.get("appearance", {}).get("opacity", LBA2_APPEARANCE.SPECTRAL_OPACITY))
		glass_material.cull_mode = BaseMaterial3D.CULL_BACK
		mesh.surface_set_material(mesh.get_surface_count() - 1, glass_material)
	if translucent_solid and not accents.vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, accents.arrays())
		var accent_material := StandardMaterial3D.new()
		accent_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		accent_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		accent_material.albedo_texture = material.albedo_texture
		accent_material.cull_mode = BaseMaterial3D.CULL_BACK
		mesh.surface_set_material(mesh.get_surface_count() - 1, accent_material)
	var texture_vertex_count := 0
	var spectral_preview: bool = LBA2_APPEARANCE.uses_spectral_preview(body)
	var fireball_preview: bool = LBA2_APPEARANCE.uses_fireball_glow(body)
	var handles: Array = textured_collectors.keys()
	handles.sort()
	for material_key in handles:
		var textured_collector: MeshCollector = textured_collectors[material_key]
		texture_vertex_count += textured_collector.vertices.size()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, textured_collector.arrays())
		var texture_material := StandardMaterial3D.new()
		texture_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		texture_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		texture_material.texture_repeat = true
		var handle: int = int(material_key) >> 1
		var chroma_key: bool = int(material_key) % 2 == 1
		if fireball_preview:
			texture_material.albedo_color = Color(1.0, 0.43, 0.06, float(body.get("appearance", {}).get("opacity", 0.58)))
			texture_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			texture_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		else:
			texture_material.albedo_texture = ImageTexture.create_from_image(_texture_tile_image(body["texture_atlas"], palette, body["textures"][handle], chroma_key, spectral_preview, body.get("appearance", {}).get("opacity", LBA2_APPEARANCE.SPECTRAL_OPACITY)))
		if chroma_key and not fireball_preview:
			texture_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if spectral_preview else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			if not spectral_preview:
				texture_material.alpha_scissor_threshold = 0.5
		texture_material.cull_mode = BaseMaterial3D.CULL_BACK
		mesh.surface_set_material(mesh.get_surface_count() - 1, texture_material)
	var shadow: Dictionary = input.get("shadow", {})
	if not shadow.is_empty():
		_add_shadow(scene, shadow, palette)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	scene.add_child(player)
	player.owner = scene
	var library := AnimationLibrary.new()
	var angle_scale := TAU / (1024.0 if body.get("game", "LBA1") == "LBA1" else 4096.0)
	var tick_rate := LBA1AnimationDecoder.ticks_per_second(body.get("game", "LBA1"))
	var exported_clips := 0
	for clip in clips:
		var name := _safe_name(clip["name"]) + "_ANIM_%03d" % clip["archive_index"]
		var decoded: Dictionary = clip["animation"]
		var all_frames := PackedInt32Array()
		for frame_index in range(decoded["frame_count"]):
			all_frames.append(frame_index)
		library.add_animation(name, _make_animation(skeleton, decoded, all_frames, angle_scale, tick_rate))
		exported_clips += 1
		if decoded["loop_frame"] > 0 and decoded["loop_frame"] < decoded["frame_count"] and decoded["frame_count"] > 1:
			var loop_frames := PackedInt32Array()
			for frame_index in range(decoded["loop_frame"], decoded["frame_count"]):
				loop_frames.append(frame_index)
			loop_frames.append(decoded["loop_frame"])
			library.add_animation(name + "_loop", _make_animation(skeleton, decoded, loop_frames, angle_scale, tick_rate))
			exported_clips += 1
	player.add_animation_library("", library)
	var document := GLTFDocument.new()
	document.image_format = "PNG"
	var state := GLTFState.new()
	var result := document.append_from_scene(scene, state)
	if result != OK:
		scene.free()
		return {"ok": false, "error": "GLB scene conversion failed: %s" % error_string(result)}
	var buffer := document.generate_buffer(state)
	scene.free()
	if buffer.size() < 20 or buffer.slice(0, 4).get_string_from_ascii() != "glTF":
		return {"ok": false, "error": "Godot did not generate a valid GLB buffer"}
	return {"ok": true, "bytes": buffer, "animations": exported_clips, "source_actions": clips.size(), "vertices": collector.vertices.size() + texture_vertex_count}


static func _palette_image(bytes: PackedByteArray, eight_bit: bool = false) -> Image:
	var image := Image.create_empty(256, 1, false, Image.FORMAT_RGBA8)
	for index in range(256):
		var at := index * 3
		var divisor := 255.0 if eight_bit else 63.0
		image.set_pixel(index, 0, Color(float(bytes[at] if eight_bit else bytes[at] >> 2) / divisor, float(bytes[at + 1] if eight_bit else bytes[at + 1] >> 2) / divisor, float(bytes[at + 2] if eight_bit else bytes[at + 2] >> 2) / divisor))
	return image


static func _texture_tile_image(indices: PackedByteArray, palette: PackedByteArray, texture: Dictionary, chroma_key: bool = false, spectral_preview: bool = false, opacity: float = 0.42) -> Image:
	var origin_word: int = texture["origin"]
	var mask_word: int = texture["repeat_mask"]
	var width := (mask_word & 255) + 1
	var height := (mask_word >> 8) + 1
	var colors := PackedByteArray()
	colors.resize(width * height * 4)
	for y in range(height):
		for x in range(width):
			var atlas_x := (origin_word & 255) + x
			var atlas_y := (origin_word >> 8) + y
			var index := int(indices[(atlas_y % 256) * 256 + atlas_x % 256])
			var palette_index := index * 3
			var at := (y * width + x) * 4
			colors[at] = palette[palette_index]
			colors[at + 1] = palette[palette_index + 1]
			colors[at + 2] = palette[palette_index + 2]
			if chroma_key and index == 0:
				colors[at] = 97
				colors[at + 1] = 120
				colors[at + 2] = 140
				colors[at + 3] = int(opacity * 255.0) if spectral_preview else 0
			else:
				colors[at + 3] = 255
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, colors)


static func _add_polygons(collector: MeshCollector, textured: Dictionary, body: Dictionary, offset: Vector3, glass_collector: MeshCollector) -> void:
	var points: PackedVector3Array = body["pose_points"]
	var point_groups: PackedInt32Array = body["point_groups"]
	var is_lba2: bool = body.get("game", "LBA1") == "LBA2"
	for polygon in body["polygons"]:
		var indices: PackedInt32Array = polygon["points"]
		var normals: PackedInt32Array = polygon["normals"]
		var face_normal := (points[indices[1]] - points[indices[0]]).cross(points[indices[2]] - points[indices[0]]).normalized()
		var surface_offset := LBA2_APPEARANCE.surface_offset_for_face(body, polygon)
		for triangle_index in range(1, indices.size() - 1):
			for corner in [0, triangle_index + 1, triangle_index]:
				var point_index: int = indices[corner]
				var normal := face_normal
				var color_index: float = float(polygon["palette_index"])
				var normal_index: int = normals[corner]
				if normal_index >= 0:
						var source_normal: Vector3 = body["normals"][normal_index]
						if source_normal.length_squared() > 0.0:
							normal = source_normal.normalized()
						if is_lba2:
							color_index += 2.0 + maxf(normal.dot(LIGHT_VECTOR.normalized()), 0.0) * 8.0 * minf(source_normal.length() / 16384.0, 1.0)
						else:
							var divisor := maxf(1.0, float(body["normal_divisors"][normal_index]))
							color_index += maxf(source_normal.dot(LIGHT_VECTOR), 0.0) / divisor
				if is_lba2:
					color_index = minf(color_index, floorf(float(polygon["palette_index"]) / 16.0) * 16.0 + 15.0)
				if polygon.get("texture_handle", -1) >= 0:
					var raw_uv: Vector2 = polygon["texture_uvs"][corner]
					var mask: Vector2 = polygon["texture_mask"]
					var handle: int = polygon["texture_handle"]
					var render_type: int = polygon["render_type"]
					var chroma_key := render_type in [12, 13, 14, 15, 20, 21, 22, 23]
					var material_key := handle * 2 + (1 if chroma_key else 0)
					if not textured.has(material_key):
						textured[material_key] = MeshCollector.new()
					var atlas_uv := Vector2(raw_uv.x / (mask.x + 1.0), raw_uv.y / (mask.y + 1.0))
					var texture_collector: MeshCollector = textured[material_key]
					var position: Vector3 = points[point_index] * SCALE + offset + face_normal * surface_offset
					var texture_offset: float = body.get("appearance", {}).get("textured_surface_offset", 0.0)
					if texture_offset > 0.0:
						position += Vector3(position.x, 0.0, position.z).normalized() * texture_offset
					texture_collector.add_uv(position, normal, atlas_uv, point_groups[point_index])
				else:
					var target := glass_collector if LBA2_APPEARANCE.is_translucent_face(body, polygon) else collector
					target.add(points[point_index] * SCALE + offset + face_normal * surface_offset, normal, color_index, point_groups[point_index], polygon["render_type"])


static func _add_spheres(collector: MeshCollector, body: Dictionary, offset: Vector3) -> void:
	var points: PackedVector3Array = body["pose_points"]
	var groups: PackedInt32Array = body["point_groups"]
	for sphere_data in body["spheres"]:
		var shape := SphereMesh.new()
		shape.radius = float(sphere_data["radius"]) * SCALE
		shape.height = shape.radius * 2.0
		shape.radial_segments = 12
		shape.rings = 6
		var arrays := shape.surface_get_arrays(0)
		var local_points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var center_index: int = sphere_data["center"]
		var center := points[center_index] * SCALE + offset
		for vertex_index in triangles:
			collector.add(center + local_points[vertex_index], normals[vertex_index], sphere_data["palette_index"], groups[center_index])


static func _add_lines(collector: MeshCollector, body: Dictionary, offset: Vector3) -> void:
	var points: PackedVector3Array = body["pose_points"]
	var groups: PackedInt32Array = body["point_groups"]
	for line in body["lines"]:
		var first_index: int = line["first"]
		var second_index: int = line["second"]
		var start := points[first_index] * SCALE + offset
		var finish := points[second_index] * SCALE + offset
		var axis := finish - start
		if axis.length_squared() < 0.000001:
			continue
		axis = axis.normalized()
		var side := axis.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = axis.cross(Vector3.RIGHT)
		side = side.normalized() * 0.006
		var up := axis.cross(side).normalized() * 0.006
		var cross_section := [side + up, -side + up, -side - up, side - up]
		var color_index: int = line["palette_index"]
		for side_index in range(4):
			var next := (side_index + 1) % 4
			var outward: Vector3 = (cross_section[side_index] + cross_section[next]).normalized()
			_add_oriented_triangle(collector, start + cross_section[side_index], start + cross_section[next], finish + cross_section[next], groups[first_index], groups[first_index], groups[second_index], outward, color_index)
			_add_oriented_triangle(collector, start + cross_section[side_index], finish + cross_section[next], finish + cross_section[side_index], groups[first_index], groups[second_index], groups[second_index], outward, color_index)
		_add_oriented_triangle(collector, start + cross_section[0], start + cross_section[1], start + cross_section[2], groups[first_index], groups[first_index], groups[first_index], -axis, color_index)
		_add_oriented_triangle(collector, start + cross_section[0], start + cross_section[2], start + cross_section[3], groups[first_index], groups[first_index], groups[first_index], -axis, color_index)
		_add_oriented_triangle(collector, finish + cross_section[0], finish + cross_section[1], finish + cross_section[2], groups[second_index], groups[second_index], groups[second_index], axis, color_index)
		_add_oriented_triangle(collector, finish + cross_section[0], finish + cross_section[2], finish + cross_section[3], groups[second_index], groups[second_index], groups[second_index], axis, color_index)


static func _add_oriented_triangle(collector: MeshCollector, a: Vector3, b: Vector3, c: Vector3, group_a: int, group_b: int, group_c: int, outward: Vector3, color_index: int) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		var swap_group := group_b
		group_b = group_c
		group_c = swap_group
	collector.add(a, outward, color_index, group_a)
	collector.add(b, outward, color_index, group_b)
	collector.add(c, outward, color_index, group_c)


static func _add_shadow(scene: Node3D, sprite: Dictionary, palette: PackedByteArray) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.72, 0.45)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.45
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = ImageTexture.create_from_image(ShadowSpriteBuilder.make_image(sprite, palette))
	var node := MeshInstance3D.new()
	node.name = "LBA1ActorShadow"
	node.mesh = plane
	node.material_override = material
	node.position.y = 0.003
	scene.add_child(node)
	node.owner = scene


static func _make_animation(skeleton: Skeleton3D, decoded: Dictionary, frame_indices: PackedInt32Array, angle_scale: float, tick_rate: float) -> Animation:
	var animation := Animation.new()
	var times := PackedFloat32Array()
	var time := 0.0
	for position in range(frame_indices.size()):
		if position > 0:
			time += float(decoded["frames"][frame_indices[position]]["duration_ticks"]) / tick_rate
		times.append(time)
	animation.length = maxf(time, 0.001)
	for group_index in range(skeleton.get_bone_count()):
		var bone_path := NodePath("Skeleton3D:Group_%02d" % group_index)
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation_track, bone_path)
		var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position_track, bone_path)
		var rest_position := skeleton.get_bone_rest(group_index).origin
		for position in range(frame_indices.size()):
			var transforms: Array = decoded["frames"][frame_indices[position]]["transforms"]
			var transform_data: Dictionary = transforms[group_index] if group_index < transforms.size() else {"type": 0, "values": Vector3i.ZERO}
			var rotation := Quaternion.IDENTITY
			var bone_position := rest_position
			if group_index == 0:
				# Frame group 0 drives actor master rotation; its type-1 Y value
				# is a turn step, not an upward bone translation.
				var master_units := CharacterPose.master_rotation_units(decoded, frame_indices[position], frame_indices[position], 1.0)
				var basis := Basis(Vector3.RIGHT, master_units.x * angle_scale) * Basis(Vector3.BACK, master_units.z * angle_scale) * Basis(Vector3.UP, master_units.y * angle_scale)
				rotation = basis.get_rotation_quaternion()
			elif transform_data["type"] == 0:
				var values: Vector3i = transform_data["values"]
				var basis := Basis(Vector3.RIGHT, float(values.x) * angle_scale) * Basis(Vector3.BACK, float(values.z) * angle_scale) * Basis(Vector3.UP, float(values.y) * angle_scale)
				rotation = basis.get_rotation_quaternion()
			elif transform_data["type"] == 1:
				bone_position += Vector3(transform_data["values"]) * SCALE
			animation.rotation_track_insert_key(rotation_track, times[position], rotation)
			animation.position_track_insert_key(position_track, times[position], bone_position)
	return animation


static func _safe_name(value: String) -> String:
	var result := ""
	for character in value:
		if character.is_valid_identifier() or character == " ":
			result += character
	return result.replace(" ", "_") if not result.is_empty() else "Action"
