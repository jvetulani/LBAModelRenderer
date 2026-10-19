class_name LBA2DetailLayers
extends RefCounted

# LBA2 has small unlit details (buttons, facial marks) embedded just behind
# neighbouring lit polygons. The source rasterizer's polygon order can show
# them, while a depth buffer lets the larger face cover them unpredictably.
const MAX_DETAIL_AREA := 5000.0
const MAX_SEPARATION := 16.0
const CLEARANCE := 1.0


static func apply(body: Dictionary) -> void:
	if body.get("game", "") != "LBA2":
		return
	var polygons: Array = body["polygons"]
	var points: PackedVector3Array = body["pose_points"]
	var faces := []
	for polygon in polygons:
		faces.append(_face(polygon, points))
	var offsets := PackedFloat32Array()
	offsets.resize(polygons.size())
	for index in range(polygons.size()):
		var detail: Dictionary = polygons[index]
		var face: Dictionary = faces[index]
		if int(detail["render_type"]) != 0 or face.is_empty() or float(face["area"]) > MAX_DETAIL_AREA:
			continue
		var required := 0.0
		for other_index in range(polygons.size()):
			if other_index == index or int(polygons[other_index]["render_type"]) == 0:
				continue
			var other: Dictionary = faces[other_index]
			if other.is_empty() or face["normal"].dot(other["normal"]) < 0.98:
				continue
			var separation: float = (other["center"] - face["center"]).dot(face["normal"])
			if separation < 0.0 or separation > MAX_SEPARATION:
				continue
			if not _overlaps(face, other):
				continue
			required = maxf(required, separation + CLEARANCE)
		offsets[index] = required
	# A button or mouth may be several adjoining triangles. Move the whole
	# detail together so its shared edges cannot split after the depth repair.
	var changed := true
	while changed:
		changed = false
		for index in range(polygons.size()):
			if offsets[index] <= 0.0:
				continue
			for other_index in range(polygons.size()):
				if offsets[other_index] >= offsets[index] or not _same_detail(polygons[index], polygons[other_index], faces[index], faces[other_index]):
					continue
				offsets[other_index] = offsets[index]
				changed = true
	for index in range(polygons.size()):
		if offsets[index] > 0.0:
			var polygon: Dictionary = polygons[index]
			polygon["auto_surface_offset"] = offsets[index] / 512.0
			polygons[index] = polygon
	body["polygons"] = polygons


static func _face(polygon: Dictionary, points: PackedVector3Array) -> Dictionary:
	var ids: PackedInt32Array = polygon["points"]
	if ids.size() < 3:
		return {}
	var first: Vector3 = points[ids[0]]
	var cross: Vector3 = (points[ids[1]] - first).cross(points[ids[2]] - first)
	if cross.length_squared() < 0.0001:
		return {}
	var area := 0.0
	var center := Vector3.ZERO
	var dominant_axis := 0
	var normal := cross.normalized()
	if absf(normal.y) > absf(normal.x) and absf(normal.y) > absf(normal.z):
		dominant_axis = 1
	elif absf(normal.z) > absf(normal.x):
		dominant_axis = 2
	var outline := PackedVector2Array()
	for id in ids:
		var point: Vector3 = points[id]
		center += point
		outline.append(_project(point, dominant_axis))
	for corner in range(1, ids.size() - 1):
		area += (points[ids[corner]] - first).cross(points[ids[corner + 1]] - first).length() * 0.5
	return {"center": center / float(ids.size()), "normal": normal, "area": area, "outline": outline, "axis": dominant_axis}


static func _overlaps(first: Dictionary, second: Dictionary) -> bool:
	var axis: int = first["axis"]
	if second["axis"] != axis:
		return false
	return Geometry2D.is_point_in_polygon(_project(second["center"], axis), first["outline"]) or Geometry2D.is_point_in_polygon(_project(first["center"], axis), second["outline"])


static func _same_detail(first: Dictionary, second: Dictionary, face: Dictionary, other: Dictionary) -> bool:
	if face.is_empty() or other.is_empty() or float(other["area"]) > MAX_DETAIL_AREA:
		return false
	if first["render_type"] != 0 or second["render_type"] != 0 or first["palette_index"] != second["palette_index"]:
		return false
	if face["normal"].dot(other["normal"]) < 0.98 or absf((other["center"] - face["center"]).dot(face["normal"])) > 1.0:
		return false
	var shared := 0
	for point_index in first["points"]:
		if second["points"].has(point_index):
			shared += 1
	return shared >= 2


static func _project(point: Vector3, axis: int) -> Vector2:
	if axis == 0:
		return Vector2(point.y, point.z)
	if axis == 1:
		return Vector2(point.x, point.z)
	return Vector2(point.x, point.y)
