class_name CharacterMeshBuilder
extends RefCounted

const UNIT_SCALE := 1.0 / 512.0
const CHARACTER_SHADER := preload("res://shaders/lba_character.gdshader")


static func build_static_pose(body: Dictionary, palette_bytes: PackedByteArray) -> Node3D:
	var character := Node3D.new()
	character.name = "LBA1Body"
	var palette_texture := _make_palette_texture(palette_bytes)
	var points: PackedVector3Array = body["pose_points"]
	var normals: PackedVector3Array = body["normals"]
	var normal_divisors: PackedInt32Array = body["normal_divisors"]
	var vertices := PackedVector3Array()
	var vertex_normals := PackedVector3Array()
	var palette_coordinates := PackedVector2Array()
	var source_normals := PackedFloat32Array()

	for polygon in body["polygons"]:
		var point_indices: PackedInt32Array = polygon["points"]
		var normal_indices: PackedInt32Array = polygon["normals"]
		var first := points[point_indices[0]]
		var second := points[point_indices[1]]
		var third := points[point_indices[2]]
		var face_normal := (second - first).cross(third - first).normalized()
		for triangle_index in range(1, point_indices.size() - 1):
			# LBA's projected winding is opposite Godot's front-face winding.
			for corner in [0, triangle_index + 1, triangle_index]:
				vertices.append(points[point_indices[corner]] * UNIT_SCALE)
				var normal_index := normal_indices[corner]
				var normal := face_normal
				var source_normal := Vector3.ZERO
				var divisor := 1.0
				if normal_index >= 0:
					source_normal = normals[normal_index]
					divisor = float(normal_divisors[normal_index])
					if source_normal.length_squared() > 0.0:
						normal = source_normal.normalized()
				vertex_normals.append(normal)
				palette_coordinates.append(Vector2(float(polygon["palette_index"]), float(polygon["render_type"])))
				source_normals.append_array(PackedFloat32Array([source_normal.x, source_normal.y, source_normal.z, divisor]))

	var mesh_arrays := []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = vertex_normals
	mesh_arrays[Mesh.ARRAY_TEX_UV2] = palette_coordinates
	mesh_arrays[Mesh.ARRAY_CUSTOM0] = source_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var polygons_node := MeshInstance3D.new()
	polygons_node.name = "Polygons"
	polygons_node.mesh = mesh
	polygons_node.material_override = _make_material(palette_texture, -1)
	character.add_child(polygons_node)

	for sphere_data in body["spheres"]:
		var sphere := MeshInstance3D.new()
		sphere.name = "Sphere_%d" % sphere_data["center"]
		var radius := float(sphere_data["radius"]) * UNIT_SCALE
		var shape := SphereMesh.new()
		shape.radius = radius
		shape.height = radius * 2.0
		shape.radial_segments = 12
		shape.rings = 6
		sphere.mesh = shape
		sphere.position = points[sphere_data["center"]] * UNIT_SCALE
		sphere.material_override = _make_material(palette_texture, sphere_data["palette_index"])
		character.add_child(sphere)

	for line_data in body["lines"]:
		var first := points[line_data["first"]] * UNIT_SCALE
		var second := points[line_data["second"]] * UNIT_SCALE
		var direction := second - first
		if direction.length_squared() < 0.000001:
			continue
		var line := MeshInstance3D.new()
		line.name = "Line_%d_%d" % [line_data["first"], line_data["second"]]
		var shape := CylinderMesh.new()
		shape.top_radius = 0.006
		shape.bottom_radius = 0.006
		shape.height = direction.length()
		shape.radial_segments = 4
		line.mesh = shape
		line.position = (first + second) * 0.5
		line.quaternion = Quaternion(Vector3.UP, direction.normalized())
		line.material_override = _make_material(palette_texture, line_data["palette_index"])
		character.add_child(line)

	return character


static func _make_palette_texture(bytes: PackedByteArray) -> ImageTexture:
	var image := Image.create_empty(256, 1, false, Image.FORMAT_RGBA8)
	for index in range(256):
		var start := index * 3
		image.set_pixel(index, 0, Color(
			float(bytes[start] >> 2) / 63.0,
			float(bytes[start + 1] >> 2) / 63.0,
			float(bytes[start + 2] >> 2) / 63.0
		))
	return ImageTexture.create_from_image(image)


static func _make_material(palette: Texture2D, override_index: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CHARACTER_SHADER
	material.set_shader_parameter("palette_texture", palette)
	material.set_shader_parameter("palette_index_override", override_index)
	return material
