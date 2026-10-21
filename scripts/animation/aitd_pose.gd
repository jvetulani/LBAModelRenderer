class_name AITDPose
extends RefCounted

const ANGLE_SCALE := TAU / 1024.0
const COORDINATE_SCALE := 0.5


static func sample(body: Dictionary, animation: Dictionary, source_frame: int, target_frame: int, weight: float) -> Dictionary:
	var raw_points: PackedVector3Array = body["points"]
	var points := raw_points.duplicate()
	var bases: Array[Basis] = []
	var from_groups: Array = animation["frames"][source_frame]["transforms"]
	var to_groups: Array = animation["frames"][target_frame]["transforms"]
	for index in range(body["groups"].size()):
		var group: Dictionary = body["groups"][index]
		var parent: int = group["parent"]
		var parent_basis := Basis.IDENTITY if parent < 0 else bases[parent]
		var pivot := Vector3.ZERO if parent < 0 else points[group["pivot"]]
		var from: Dictionary = from_groups[index] if index < from_groups.size() else {"type": 0, "values": Vector3i.ZERO}
		var to: Dictionary = to_groups[index] if index < to_groups.size() else {"type": 0, "values": Vector3i.ZERO}
		var kind: int = to["type"]
		var values := Vector3(to["values"])
		if index == 0:
			values = Vector3.ZERO # FITD overrides the actor's root rotation.
		elif source_frame != target_frame:
			var start := Vector3(from["values"])
			if kind == 0:
				for axis in range(3):
					values[axis] = start[axis] + (fposmod(values[axis] - start[axis] + 512.0, 1024.0) - 512.0) * weight
			else:
				values = start.lerp(values, weight)
		var local_basis := Basis.IDENTITY
		if index > 0 and (kind == 0 or to.has("rotation")):
			var rotation := values if kind == 0 else Vector3(to["rotation"])
			local_basis = Basis(Vector3.BACK, rotation.z * ANGLE_SCALE) * Basis(Vector3.RIGHT, rotation.x * ANGLE_SCALE) * Basis(Vector3.UP, -rotation.y * ANGLE_SCALE)
		var world_basis := parent_basis * local_basis
		bases.append(world_basis)
		for point_index in range(group["first"], group["first"] + group["count"]):
			var local_point: Vector3 = raw_points[point_index]
			if kind == 1:
				local_point += Vector3(-values.x, -values.y, -values.z) * COORDINATE_SCALE
			elif kind == 2:
				local_point *= Vector3.ONE + Vector3(values) / 256.0
			points[point_index] = pivot + world_basis * local_point
	return {"points": points, "bases": bases, "master_rotation": Vector3.ZERO}
