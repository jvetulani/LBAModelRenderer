class_name LBA2BodyDecoder
extends RefCounted

# AFF_OBJ.INC (October 1996): header offsets are absolute, polygon block
# lengths are relative, and all point/normal references are table indices.
const HEADER_SIZE := 96
const RECORD_SIZES := {"light": 12, "texture_triangle": 24, "texture_quad": 32, "environment": 16}


static func looks_like_body(bytes: PackedByteArray) -> bool:
	return bytes.size() >= HEADER_SIZE and (bytes.decode_u32(0) & 255) == 0x10 and bytes.decode_u16(4) == HEADER_SIZE


static func decode(bytes: PackedByteArray) -> Dictionary:
	if not looks_like_body(bytes):
		return _error("Not an LBA2 body header")
	var tables := []
	for table_index in range(8):
		var count := int(bytes.decode_u32(32 + table_index * 8))
		var offset := int(bytes.decode_u32(36 + table_index * 8))
		tables.append({"count": count, "offset": offset})
	var groups_table: Dictionary = tables[0]
	var points_table: Dictionary = tables[1]
	var normals_table: Dictionary = tables[2]
	var face_normals_table: Dictionary = tables[3]
	var polygons_table: Dictionary = tables[4]
	var lines_table: Dictionary = tables[5]
	var spheres_table: Dictionary = tables[6]
	var textures_table: Dictionary = tables[7]
	var sizes := [8, 8, 8, 8, 0, 8, 8, 4]
	for table_index in range(8):
		var table: Dictionary = tables[table_index]
		if not _has(bytes, table["offset"], table["count"] * sizes[table_index]):
			return _error("Body table %d exceeds the entry" % table_index)
	if groups_table["count"] == 0 or points_table["count"] == 0 or polygons_table["offset"] > lines_table["offset"]:
		return _error("Body has invalid table counts or offsets")

	var points := PackedVector3Array()
	var point_groups := PackedInt32Array()
	for point_index in range(points_table["count"]):
		var at: int = points_table["offset"] + point_index * 8
		points.append(Vector3(bytes.decode_s16(at), bytes.decode_s16(at + 2), bytes.decode_s16(at + 4)))
		point_groups.append(bytes.decode_u16(at + 6))
	var groups := []
	var pose_points := points.duplicate()
	var first_point := 0
	for group_index in range(groups_table["count"]):
		var at: int = groups_table["offset"] + group_index * 8
		var parent := int(bytes.decode_u16(at))
		var pivot := int(bytes.decode_u16(at + 2))
		var count := int(bytes.decode_u16(at + 4))
		if group_index == 0 and parent == 65535:
			parent = -1
		if count == 0 or first_point + count > points.size() or (parent >= group_index) or (parent >= 0 and (pivot >= first_point or point_groups[pivot] != parent)):
			return _error("Group %d has invalid hierarchy or point range" % group_index)
		var origin := Vector3.ZERO if parent < 0 else pose_points[pivot]
		groups.append({"first": first_point, "count": count, "pivot": pivot, "parent": parent})
		for point_index in range(first_point, first_point + count):
			if point_groups[point_index] != group_index:
				return _error("Point %d disagrees with its group table" % point_index)
			pose_points[point_index] = origin + points[point_index]
		first_point += count
	if first_point != points.size():
		return _error("Some body points have no group")

	var normals := PackedVector3Array()
	var normal_divisors := PackedInt32Array()
	for normal_index in range(normals_table["count"]):
		var at: int = normals_table["offset"] + normal_index * 8
		normals.append(Vector3(bytes.decode_s16(at), bytes.decode_s16(at + 2), bytes.decode_s16(at + 4)))
		normal_divisors.append(bytes.decode_u16(at + 6))
	var face_normals := PackedVector3Array()
	for normal_index in range(face_normals_table["count"]):
		var at: int = face_normals_table["offset"] + normal_index * 8
		face_normals.append(Vector3(bytes.decode_s16(at), bytes.decode_s16(at + 2), bytes.decode_s16(at + 4)))
	# Flat polygon indices address the light list after the vertex normals.
	# AFF_OBJ builds that list by appending the face-normal table.
	for face_normal in face_normals:
		normals.append(face_normal)
		normal_divisors.append(1)

	var polygons := []
	var cursor: int = polygons_table["offset"]
	while cursor < lines_table["offset"]:
		if not _has(bytes, cursor, 8):
			return _error("Polygon block header is truncated")
		var flags := int(bytes.decode_u16(cursor))
		var render_type := flags & 255
		var count := int(bytes.decode_u16(cursor + 2))
		var block_size := int(bytes.decode_u32(cursor + 4))
		var quad := flags & 0x8000 != 0
		var environment := flags & 0x4000 != 0
		if render_type > 23 or count == 0:
			return _error("Invalid polygon block type or count")
		var record_size: int = RECORD_SIZES["environment"] if environment else (RECORD_SIZES["light"] if render_type <= 7 else (RECORD_SIZES["texture_quad"] if quad else RECORD_SIZES["texture_triangle"]))
		if block_size != 8 + count * record_size or cursor + block_size > lines_table["offset"]:
			return _error("Polygon block has an invalid length")
		for polygon_index in range(count):
			var at := cursor + 8 + polygon_index * record_size
			var vertex_count := 4 if quad else 3
			var indices := PackedInt32Array()
			var normal_indices := PackedInt32Array()
			for corner in range(vertex_count):
				var point_index := int(bytes.decode_u16(at + corner * 2))
				if point_index >= points.size():
					return _error("Polygon point index is out of range")
				indices.append(point_index)
				normal_indices.append(point_index if point_index < normals.size() and render_type in [4, 5, 6, 7, 10, 11, 14, 15, 18, 19, 22, 23] else -1)
			var color_word := int(bytes.decode_u16(at + 8))
			var normal_index := int(bytes.decode_u16(at + 10))
			if render_type in [1, 3, 9, 13, 17, 21] and normal_index < normals.size():
				normal_indices.fill(normal_index)
			var texture_handle := int(bytes.decode_u16(at + (28 if quad else 6))) if render_type > 7 and not environment else -1
			var texture_uvs := PackedVector2Array()
			var texture_origin := Vector2.ZERO
			var texture_mask := Vector2(255, 255)
			if texture_handle >= 0:
				if texture_handle >= textures_table["count"]:
					return _error("Polygon texture handle is out of range")
				var texture_at: int = textures_table["offset"] + texture_handle * 4
				var origin_word := int(bytes.decode_u16(texture_at))
				var mask_word := int(bytes.decode_u16(texture_at + 2))
				texture_origin = Vector2(origin_word & 255, origin_word >> 8)
				texture_mask = Vector2(mask_word & 255, mask_word >> 8)
				for corner in range(vertex_count):
					var uv_at := at + 12 + corner * 4
					texture_uvs.append(Vector2(float(bytes.decode_u16(uv_at)) / 256.0, float(bytes.decode_u16(uv_at + 2)) / 256.0))
			polygons.append({
				"render_type": render_type, "color_word": color_word,
				"palette_index": color_word & 255,
				"points": indices, "normals": normal_indices,
				"environment": environment,
				"texture_handle": texture_handle, "texture_uvs": texture_uvs,
				"texture_origin": texture_origin, "texture_mask": texture_mask,
			})
		cursor += block_size
	if polygons.size() != polygons_table["count"]:
		return _error("Polygon block count disagrees with header")
	var lines := []
	for line_index in range(lines_table["count"]):
		var at: int = lines_table["offset"] + line_index * 8
		var first := int(bytes.decode_u16(at + 4))
		var second := int(bytes.decode_u16(at + 6))
		if first >= points.size() or second >= points.size():
			return _error("Line point index is out of range")
		lines.append({"render_type": int(bytes.decode_u16(at)), "palette_index": int(bytes.decode_u16(at + 2)) & 255, "first": first, "second": second})
	var spheres := []
	for sphere_index in range(spheres_table["count"]):
		var at: int = spheres_table["offset"] + sphere_index * 8
		var center := int(bytes.decode_u16(at + 4))
		if center >= points.size():
			return _error("Sphere point index is out of range")
		spheres.append({"render_type": int(bytes.decode_u16(at)), "palette_index": int(bytes.decode_u16(at + 2)) & 255, "center": center, "radius": int(bytes.decode_u16(at + 6))})
	var textures := []
	for texture_index in range(textures_table["count"]):
		var at: int = textures_table["offset"] + texture_index * 4
		textures.append({"origin": int(bytes.decode_u16(at)), "repeat_mask": int(bytes.decode_u16(at + 2))})
	return {"ok": true, "game": "LBA2", "points": points, "pose_points": pose_points, "groups": groups, "group_count": groups.size(), "point_groups": point_groups, "normals": normals, "normal_divisors": normal_divisors, "face_normals": face_normals, "polygons": polygons, "lines": lines, "spheres": spheres, "textures": textures}


static func _has(bytes: PackedByteArray, offset: int, count: int) -> bool:
	return offset >= 0 and count >= 0 and offset <= bytes.size() - count


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
