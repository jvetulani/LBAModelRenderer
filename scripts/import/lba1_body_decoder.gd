class_name LBA1BodyDecoder
extends RefCounted

# This is the static pose of the LBA1 animated-body format. The layout is
# followed from lba1-classic/LIB386/LIB_3D/P_OB_ISO.ASM, not inferred from a
# matching archive index in ANIM.HQR.


static func decode(bytes: PackedByteArray) -> Dictionary:
	return _decode(bytes, false)


static func decode_compact_groups(bytes: PackedByteArray) -> Dictionary:
	return _decode(bytes, true)


static func _decode(bytes: PackedByteArray, compact_groups: bool) -> Dictionary:
	if bytes.size() < 18:
		return _error("Body header is truncated")
	var flags := int(bytes.decode_u16(0))
	if flags & 2 == 0:
		return _error("This proof of concept supports animated LBA1 bodies only")
	var cursor := 16 + int(bytes.decode_u16(14))
	if not _has(bytes, cursor, 2):
		return _error("Body information section is truncated")

	var point_count := int(bytes.decode_u16(cursor))
	cursor += 2
	if point_count == 0 or not _has(bytes, cursor, point_count * 6):
		return _error("Body point table is invalid")
	var points := PackedVector3Array()
	for point_index in range(point_count):
		points.append(Vector3(
			bytes.decode_s16(cursor),
			bytes.decode_s16(cursor + 2),
			bytes.decode_s16(cursor + 4)
		))
		cursor += 6

	if not _has(bytes, cursor, 2):
		return _error("Body group count is missing")
	var group_count := int(bytes.decode_u16(cursor))
	cursor += 2
	var group_stride := 8 if compact_groups else 38
	if not _has(bytes, cursor, group_count * group_stride):
		return _error("Body group table is truncated")
	var group_bytes := bytes.slice(cursor, cursor + group_count * group_stride)
	var groups := []
	var pose_points := points.duplicate()
	var assigned := PackedByteArray()
	assigned.resize(point_count)
	var point_groups := PackedInt32Array()
	point_groups.resize(point_count)
	var next_point := 0
	for group_index in range(group_count):
		var group_start := cursor + group_index * group_stride
		var first := next_point if compact_groups else _point_index(bytes.decode_u16(group_start), point_count)
		var count := int(bytes.decode_u16(group_start)) if compact_groups else int(bytes.decode_u16(group_start + 2))
		var pivot := _point_index(bytes.decode_u16(group_start + 2), point_count) if compact_groups else _point_index(bytes.decode_u16(group_start + 4), point_count)
		var parent_offset := int(bytes.decode_s16(group_start + 4)) if compact_groups else int(bytes.decode_s16(group_start + 6))
		var group_type := 0 if compact_groups else int(bytes.decode_u16(group_start + 8))
		if first < 0 or count == 0 or first + count > point_count:
			return _error("Group %d has an invalid point range" % group_index)
		if parent_offset == -1:
			if group_index != 0:
				return _error("Group %d has an unexpected root parent" % group_index)
		elif parent_offset < 0 or parent_offset % (36 if compact_groups else 38) != 0 or parent_offset / (36 if compact_groups else 38) >= group_index or pivot < 0 or assigned[pivot] == 0:
			return _error("Group %d has an invalid parent or pivot" % group_index)
		if not compact_groups and (group_type != 0 or bytes.decode_s16(group_start + 10) != 0 or bytes.decode_s16(group_start + 12) != 0 or bytes.decode_s16(group_start + 14) != 0):
			return _error("Group %d has an unsupported nonzero rest transform" % group_index)
		var origin := Vector3.ZERO if parent_offset == -1 else pose_points[pivot]
		groups.append({
			"first": first, "count": count, "pivot": pivot,
			"parent": -1 if parent_offset == -1 else parent_offset / (36 if compact_groups else 38),
		})
		for point_index in range(first, first + count):
			if assigned[point_index] != 0:
				return _error("Point %d belongs to multiple groups" % point_index)
			pose_points[point_index] = origin + points[point_index]
			assigned[point_index] = 1
			point_groups[point_index] = group_index
		next_point += count
	for point_index in range(point_count):
		if assigned[point_index] == 0:
			return _error("Point %d has no group" % point_index)
	cursor += group_count * group_stride

	if not _has(bytes, cursor, 2):
		return _error("Body normal count is missing")
	var normal_count := int(bytes.decode_u16(cursor))
	cursor += 2
	if not _has(bytes, cursor, normal_count * 8):
		return _error("Body normal table is truncated")
	var normals := PackedVector3Array()
	var normal_divisors := PackedInt32Array()
	for normal_index in range(normal_count):
		normals.append(Vector3(
			bytes.decode_s16(cursor),
			bytes.decode_s16(cursor + 2),
			bytes.decode_s16(cursor + 4)
		))
		normal_divisors.append(bytes.decode_u16(cursor + 6))
		cursor += 8

	if not _has(bytes, cursor, 2):
		return _error("Body polygon count is missing")
	var polygon_count := int(bytes.decode_u16(cursor))
	cursor += 2
	var polygons := []
	var textures := []
	var texture_lookup := {}
	for polygon_index in range(polygon_count):
		if not _has(bytes, cursor, 4):
			return _error("Polygon %d header is truncated" % polygon_index)
		var render_type := int(bytes[cursor])
		var vertex_count := int(bytes[cursor + 1])
		var color_word := int(bytes.decode_u16(cursor + 2))
		cursor += 4
		if vertex_count < 3 or vertex_count > point_count:
			return _error("Polygon %d has an invalid vertex count" % polygon_index)
		var point_indices := PackedInt32Array()
		var normal_indices := PackedInt32Array()
		var texture_uvs := PackedVector2Array()
		var texture_origin := Vector2.ZERO
		var texture_mask := Vector2(255, 255)
		var texture_handle := -1
		var face_normal := -1
		var demo_flat_texture := compact_groups and render_type in [12, 16, 20, 24]
		if (render_type >= 7 and render_type < 9) or demo_flat_texture:
			if not _has(bytes, cursor, 2):
				return _error("Polygon %d face normal is truncated" % polygon_index)
			face_normal = int(bytes.decode_u16(cursor))
			cursor += 2
			if face_normal >= normal_count:
				return _error("Polygon %d has an invalid face normal" % polygon_index)
		for vertex_index in range(vertex_count):
			var normal_index := face_normal
			if render_type >= 9:
				if not _has(bytes, cursor, 4):
					return _error("Polygon %d vertex data is truncated" % polygon_index)
				normal_index = int(bytes.decode_u16(cursor))
				cursor += 2
				if not demo_flat_texture and normal_index >= normal_count:
					return _error("Polygon %d has an invalid vertex normal" % polygon_index)
				if demo_flat_texture:
					normal_index = face_normal
			if not _has(bytes, cursor, 2):
				return _error("Polygon %d point reference is truncated" % polygon_index)
			var point_offset := int(bytes.decode_u16(cursor))
			cursor += 2
			if point_offset % 6 != 0 or point_offset / 6 >= point_count:
				return _error("Polygon %d has an invalid point reference" % polygon_index)
			point_indices.append(point_offset / 6)
			normal_indices.append(normal_index)
		if compact_groups and render_type in [12, 13, 14, 16, 20, 24]:
			# 1996 LBA2 demo keeps a texture region and one UV pair per point
			# directly after the old-style polygon's point/normal references.
			if not _has(bytes, cursor, 4 + vertex_count * 4):
				return _error("Polygon %d texture data is truncated" % polygon_index)
			var origin_word := int(bytes.decode_u16(cursor))
			var mask_word := int(bytes.decode_u16(cursor + 2))
			texture_origin = Vector2(origin_word & 255, origin_word >> 8)
			texture_mask = Vector2(mask_word & 255, mask_word >> 8)
			cursor += 4
			for vertex_index in range(vertex_count):
				texture_uvs.append(Vector2(float(bytes.decode_u16(cursor)) / 256.0, float(bytes.decode_u16(cursor + 2)) / 256.0))
				cursor += 4
			var texture_key := "%d/%d" % [origin_word, mask_word]
			if not texture_lookup.has(texture_key):
				texture_lookup[texture_key] = textures.size()
				textures.append({"origin": origin_word, "repeat_mask": mask_word})
			texture_handle = texture_lookup[texture_key]
		polygons.append({
			"render_type": render_type,
			"color_word": color_word,
			"palette_index": color_word & 255,
			"points": point_indices,
			"normals": normal_indices,
			"texture_handle": texture_handle,
			"texture_uvs": texture_uvs,
			"texture_origin": texture_origin,
			"texture_mask": texture_mask,
		})

	if not _has(bytes, cursor, 2):
		return _error("Body line count is missing")
	var line_count := int(bytes.decode_u16(cursor))
	cursor += 2
	if not _has(bytes, cursor, line_count * 8):
		return _error("Body line table is truncated")
	var lines := []
	for line_index in range(line_count):
		var first := _point_index(bytes.decode_u16(cursor + 4), point_count)
		var second := _point_index(bytes.decode_u16(cursor + 6), point_count)
		if first < 0 or second < 0:
			return _error("Line %d has an invalid point reference" % line_index)
		lines.append({
			"render_type": int(bytes[cursor]),
			"palette_index": int(bytes[cursor + 1]),
			"first": first,
			"second": second,
		})
		cursor += 8

	if not _has(bytes, cursor, 2):
		return _error("Body sphere count is missing")
	var sphere_count := int(bytes.decode_u16(cursor))
	cursor += 2
	if not _has(bytes, cursor, sphere_count * 8):
		return _error("Body sphere table is truncated")
	var spheres := []
	for sphere_index in range(sphere_count):
		var center := _point_index(bytes.decode_u16(cursor + 6), point_count)
		var radius := int(bytes.decode_u16(cursor + 4))
		if center < 0 or radius == 0:
			return _error("Sphere %d has invalid geometry" % sphere_index)
		spheres.append({
			"render_type": int(bytes[cursor]),
			"palette_index": int(bytes[cursor + 1]),
			"center": center,
			"radius": radius,
		})
		cursor += 8

	return {
		"ok": true,
		"game": "LBA1",
		"flags": flags,
		"points": points,
		"pose_points": pose_points,
		"groups_raw": group_bytes,
		"groups": groups,
		"point_groups": point_groups,
		"group_count": group_count,
		"normals": normals,
		"normal_divisors": normal_divisors,
		"polygons": polygons,
		"lines": lines,
		"spheres": spheres,
		"textures": textures,
		"trailing_bytes": bytes.size() - cursor,
	}


static func _point_index(offset: int, point_count: int) -> int:
	if offset % 6 != 0 or offset / 6 >= point_count:
		return -1
	return offset / 6


static func _has(bytes: PackedByteArray, offset: int, count: int) -> bool:
	return offset >= 0 and count >= 0 and offset <= bytes.size() - count


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
