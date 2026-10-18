class_name LBA2ModelOverrides
extends RefCounted

const PATH := "res://assets/model_overrides/lba2.json"
const DEMO_PATH := "res://assets/model_overrides/demo.json"
static var _retail: Dictionary = {}
static var _demo: Dictionary = {}


static func for_retail_body(body_index: int) -> Dictionary:
	if _retail.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_retail = parsed.get("retail", {})
	return _retail.get(str(body_index), {}).duplicate(true)


static func for_demo_body(body_index: int) -> Dictionary:
	if _demo.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEMO_PATH))
		if parsed is Dictionary:
			_demo = parsed.get("demo", {})
	return _demo.get(str(body_index), {}).duplicate(true)


static func apply_geometry(body: Dictionary) -> void:
	# Source BODY #0 has three shirt faces with UV corners exchanged. Keeping
	# the repair in the data file makes preview and GLB export use one mesh.
	var appearance: Dictionary = body.get("appearance", {})
	var polygons: Array = body.get("polygons", [])
	for swap in appearance.get("uv_corner_swaps", []):
		if swap.size() != 3:
			continue
		var polygon_index := int(swap[0])
		var first := int(swap[1])
		var second := int(swap[2])
		if polygon_index < 0 or polygon_index >= polygons.size():
			continue
		var polygon: Dictionary = polygons[polygon_index]
		var uvs: PackedVector2Array = polygon["texture_uvs"]
		if first < 0 or second < 0 or first >= uvs.size() or second >= uvs.size():
			continue
		var saved := uvs[first]
		uvs[first] = uvs[second]
		uvs[second] = saved
		polygon["texture_uvs"] = uvs
		polygons[polygon_index] = polygon
	var arm_uv_min_density := float(appearance.get("arm_uv_min_density", 0.0))
	if arm_uv_min_density > 0.0:
		# All four monkey limb chains have faces with a collapsed texture axis.
		# Restore that axis to a consistent texel density in the face plane.
		var point_groups: PackedInt32Array = body["point_groups"]
		var pose_points: PackedVector3Array = body["pose_points"]
		for polygon_index in range(polygons.size()):
			var polygon: Dictionary = polygons[polygon_index]
			if int(polygon.get("texture_handle", -1)) != 1:
				continue
			var points: PackedInt32Array = polygon["points"]
			var arm_face := false
			var arm_region := true
			for point_index in points:
				var group_index := point_groups[point_index]
				arm_face = arm_face or (group_index >= 13 and group_index <= 24)
				arm_region = arm_region and (group_index == 4 or group_index == 5 or (group_index >= 13 and group_index <= 24))
			if not arm_face or not arm_region:
				continue
			var uvs: PackedVector2Array = polygon["texture_uvs"]
			var repaired := _restore_uv_density(points, pose_points, uvs, arm_uv_min_density)
			if repaired != uvs:
				polygon["texture_uvs"] = repaired
				polygons[polygon_index] = polygon
	body["polygons"] = polygons


static func _restore_uv_density(points: PackedInt32Array, positions: PackedVector3Array, uvs: PackedVector2Array, minimum: float) -> PackedVector2Array:
	if points.size() < 3 or uvs.size() != points.size():
		return uvs
	var origin: Vector3 = positions[points[0]]
	var tangent: Vector3 = positions[points[1]] - origin
	if tangent.length_squared() < 0.0001:
		return uvs
	tangent = tangent.normalized()
	var normal: Vector3 = tangent.cross(positions[points[2]] - origin)
	if normal.length_squared() < 0.0001:
		return uvs
	var bitangent := normal.normalized().cross(tangent)
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	var ux := 0.0
	var uy := 0.0
	var vx := 0.0
	var vy := 0.0
	var local := PackedVector2Array()
	for corner in range(points.size()):
		var delta: Vector3 = positions[points[corner]] - origin
		var p := Vector2(delta.dot(tangent), delta.dot(bitangent))
		local.append(p)
		var uv_delta := uvs[corner] - uvs[0]
		xx += p.x * p.x
		xy += p.x * p.y
		yy += p.y * p.y
		ux += uv_delta.x * p.x
		uy += uv_delta.x * p.y
		vx += uv_delta.y * p.x
		vy += uv_delta.y * p.y
	var determinant := xx * yy - xy * xy
	if determinant < 0.0001:
		return uvs
	var gradient_u := Vector2((ux * yy - uy * xy) / determinant, (uy * xx - ux * xy) / determinant)
	var gradient_v := Vector2((vx * yy - vy * xy) / determinant, (vy * xx - vx * xy) / determinant)
	var a := gradient_u.x * gradient_u.x + gradient_v.x * gradient_v.x
	var b := gradient_u.x * gradient_u.y + gradient_v.x * gradient_v.y
	var c := gradient_u.y * gradient_u.y + gradient_v.y * gradient_v.y
	var spread := sqrt((a - c) * (a - c) + 4.0 * b * b)
	var major_value := maxf((a + c + spread) * 0.5, 0.0)
	var minor_value := maxf((a + c - spread) * 0.5, 0.0)
	var major := sqrt(major_value)
	if major < minimum or sqrt(minor_value) >= minimum:
		return uvs
	var right_major := Vector2(b, major_value - a)
	if right_major.length_squared() < 0.00000001:
		right_major = Vector2.RIGHT if a >= c else Vector2.DOWN
	right_major = right_major.normalized()
	var right_minor := Vector2(-right_major.y, right_major.x)
	var left_major := Vector2(gradient_u.dot(right_major), gradient_v.dot(right_major)) / major
	var left_minor := Vector2(-left_major.y, left_major.x)
	if gradient_u.cross(gradient_v) < 0.0:
		left_minor = -left_minor
	var repaired := PackedVector2Array()
	for p in local:
		repaired.append(uvs[0] + left_major * major * p.dot(right_major) + left_minor * minimum * p.dot(right_minor))
	return repaired
