class_name LBA1Pose
extends RefCounted

# P_TRIGO.ASM RotMatIndex2 applies Alpha(X), Gamma(Z), Beta(Y) to the parent
# matrix. The source rotates each group's local points about a parent pivot.
const ANGLE_SCALE := TAU / 1024.0


static func sample(body: Dictionary, animation: Dictionary, source_frame: int, target_frame: int, weight: float) -> Dictionary:
	var source_transforms: Array = animation["frames"][source_frame]["transforms"]
	var target_transforms: Array = animation["frames"][target_frame]["transforms"]
	var groups: Array = body["groups"]
	var raw_points: PackedVector3Array = body["points"]
	var points := raw_points.duplicate()
	var bases: Array[Basis] = []
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var parent: int = group["parent"]
		var parent_basis := Basis.IDENTITY if parent < 0 else bases[parent]
		var pivot := Vector3.ZERO if parent < 0 else points[group["pivot"]]
		var from: Dictionary = source_transforms[min(group_index, source_transforms.size() - 1)]
		var to: Dictionary = target_transforms[min(group_index, target_transforms.size() - 1)]
		var transform_type: int = to["type"]
		var values := Vector3.ZERO
		for axis in range(3):
			var start := float(from["values"][axis])
			var end := float(to["values"][axis])
			if transform_type == 0:
				var difference := fposmod(end - start + 512.0, 1024.0) - 512.0
				values[axis] = start + difference * weight
			else:
				values[axis] = lerpf(start, end, weight)
		var local_basis := Basis.IDENTITY
		if transform_type == 0:
			local_basis = Basis(Vector3.RIGHT, values.x * ANGLE_SCALE) * Basis(Vector3.BACK, values.z * ANGLE_SCALE) * Basis(Vector3.UP, values.y * ANGLE_SCALE)
		var world_basis := parent_basis * local_basis
		bases.append(world_basis)
		for point_index in range(group["first"], group["first"] + group["count"]):
			var local_point: Vector3 = raw_points[point_index]
			if transform_type == 1:
				local_point += values
			points[point_index] = pivot + world_basis * local_point
	return {"points": points, "bases": bases}
