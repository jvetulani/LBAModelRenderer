class_name AITDBodyDecoder
extends RefCounted

# LISTBODY.PAK body layout follows the original AITD body tables documented by
# FITD's createBodyFromPtr. The output matches the viewer's LBA body contract.
# AITD's source axes face opposite LBA and its Y points down. A half turn
# around upright Y after the Y flip converts source (x, y, z) to (-x, -y, -z).
# The half-size conversion keeps character heights near the viewer's LBA scale.
const COORDINATE_SCALE := 0.5

static func decode(bytes: PackedByteArray, game_name: String = "AITD1") -> Dictionary:
	if bytes.size() < 18:
		return _error("AITD body header is truncated")
	var flags := int(bytes.decode_u16(0))
	var cursor := 16 + int(bytes.decode_u16(14))
	if not _has(bytes, cursor, 2):
		return _error("AITD point count is missing")
	var point_count := int(bytes.decode_u16(cursor))
	cursor += 2
	if point_count == 0 or not _has(bytes, cursor, point_count * 6):
		return _error("AITD point table is invalid")
	var points := PackedVector3Array()
	for index in range(point_count):
		points.append(Vector3(-bytes.decode_s16(cursor), -bytes.decode_s16(cursor + 2), -bytes.decode_s16(cursor + 4)) * COORDINATE_SCALE)
		cursor += 6
	var groups := []
	var point_groups := PackedInt32Array()
	point_groups.resize(point_count)
	if flags & 2:
		if not _has(bytes, cursor, 2):
			return _error("AITD group count is missing")
		var group_count := int(bytes.decode_u16(cursor))
		cursor += 2
		var stride := 24 if flags & 8 else 16
		if group_count == 0 or not _has(bytes, cursor, group_count * (stride + 2)):
			return _error("AITD group table is truncated")
		cursor += group_count * 2 # Transform order; rest hierarchy is in each group.
		for index in range(group_count):
			var first := int(bytes.decode_u16(cursor)) / 6
			var count := int(bytes.decode_u16(cursor + 2))
			var pivot := int(bytes.decode_u16(cursor + 4)) / 6
			var parent := int(bytes.decode_s8(cursor + 6))
			if first < 0 or first + count > point_count or pivot >= point_count or parent >= index:
				return _error("AITD group %d has invalid geometry" % index)
			groups.append({"first": first, "count": count, "pivot": pivot, "parent": parent})
			for point_index in range(first, first + count):
				point_groups[point_index] = index
			cursor += stride
	else:
		groups.append({"first": 0, "count": point_count, "pivot": 0, "parent": -1})
	var pose_points := points.duplicate()
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		if group["parent"] < 0:
			continue
		var origin: Vector3 = pose_points[group["pivot"]]
		for point_index in range(group["first"], group["first"] + group["count"]):
			pose_points[point_index] += origin
	if not _has(bytes, cursor, 2):
		return _error("AITD primitive count is missing")
	var primitive_count := int(bytes.decode_u16(cursor))
	cursor += 2
	var polygons := []
	var lines := []
	var spheres := []
	for primitive_index in range(primitive_count):
		if not _has(bytes, cursor, 4):
			return _error("AITD primitive %d is truncated" % primitive_index)
		var kind := int(bytes[cursor])
		if kind in [1, 8, 9, 10]:
			var vertex_count := int(bytes[cursor + 1])
			var color := int(bytes[cursor + 3])
			cursor += 4
			if vertex_count < 3 or not _has(bytes, cursor, vertex_count * (4 if kind in [9, 10] else 2)):
				return _error("AITD polygon %d is invalid" % primitive_index)
			var indices := PackedInt32Array()
			var normals := PackedInt32Array()
			for vertex_index in range(vertex_count):
				var point_offset := int(bytes.decode_u16(cursor))
				if point_offset % 6 != 0 or point_offset / 6 >= point_count:
					return _error("AITD polygon %d has an invalid point" % primitive_index)
				indices.append(point_offset / 6)
				normals.append(-1)
				cursor += 2
			if kind in [9, 10]:
				cursor += vertex_count * 2 # UV pairs; textured AITD2/3 faces need atlas mapping.
			polygons.append({"render_type": 0, "palette_index": color, "color_word": color, "points": indices, "normals": normals, "texture_handle": -1, "texture_uvs": PackedVector2Array(), "texture_origin": Vector2.ZERO, "texture_mask": Vector2(255, 255)})
		elif kind == 0:
			if not _has(bytes, cursor, 8):
				return _error("AITD line %d is truncated" % primitive_index)
			var a := _point_index(bytes.decode_u16(cursor + 4), point_count)
			var b := _point_index(bytes.decode_u16(cursor + 6), point_count)
			if a < 0 or b < 0:
				return _error("AITD line %d has an invalid point" % primitive_index)
			lines.append({"render_type": 0, "palette_index": int(bytes[cursor + 2]), "first": a, "second": b})
			cursor += 8
		elif kind == 3:
			if not _has(bytes, cursor, 8):
				return _error("AITD sphere %d is truncated" % primitive_index)
			var center := _point_index(bytes.decode_u16(cursor + 6), point_count)
			if center < 0:
				return _error("AITD sphere %d has an invalid point" % primitive_index)
			spheres.append({"render_type": 0, "palette_index": int(bytes[cursor + 2]), "center": center, "radius": float(bytes.decode_u16(cursor + 4)) * COORDINATE_SCALE})
			cursor += 8
		elif kind in [2, 6, 7]:
			if not _has(bytes, cursor, 6):
				return _error("AITD point primitive %d is truncated" % primitive_index)
			cursor += 6
		else:
			return _error("AITD primitive type %d is unsupported" % kind)
	return {"ok": true, "game": game_name, "flags": flags, "points": points, "pose_points": pose_points, "groups": groups, "point_groups": point_groups, "group_count": groups.size(), "normals": PackedVector3Array(), "normal_divisors": PackedInt32Array(), "polygons": polygons, "lines": lines, "spheres": spheres, "textures": [], "appearance": {}, "trailing_bytes": bytes.size() - cursor}


static func _point_index(offset: int, point_count: int) -> int:
	return offset / 6 if offset % 6 == 0 and offset / 6 < point_count else -1


static func _has(bytes: PackedByteArray, offset: int, count: int) -> bool:
	return offset >= 0 and count >= 0 and offset <= bytes.size() - count


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
