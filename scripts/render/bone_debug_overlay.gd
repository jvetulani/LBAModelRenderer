class_name BoneDebugOverlay
extends RefCounted

const SCALE := 1.0 / 512.0


static func create(body: Dictionary) -> Node3D:
	var overlay := Node3D.new()
	overlay.name = "Bones"
	overlay.visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(1.0, 0.69, 0.08)
	var lines := MeshInstance3D.new()
	lines.name = "Links"
	lines.material_override = material
	overlay.add_child(lines)
	var joint_mesh := SphereMesh.new()
	joint_mesh.radius = 0.026
	joint_mesh.height = 0.052
	joint_mesh.radial_segments = 8
	joint_mesh.rings = 4
	for group_index in range(body["groups"].size()):
		var joint := MeshInstance3D.new()
		joint.name = "Joint_%02d" % group_index
		joint.mesh = joint_mesh
		joint.material_override = material
		overlay.add_child(joint)
	update(overlay, body, body["pose_points"])
	return overlay


static func update(overlay: Node3D, body: Dictionary, points: PackedVector3Array) -> void:
	var groups: Array = body["groups"]
	var origins: Array[Vector3] = []
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var parent: int = group["parent"]
		var pivot: int = group["pivot"]
		var origin := Vector3.ZERO if parent < 0 or pivot < 0 or pivot >= points.size() else points[pivot]
		origins.append(origin * SCALE)
		overlay.get_node("Joint_%02d" % group_index).position = origins[-1]
	var mesh := ImmediateMesh.new()
	if groups.size() > 1:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for group_index in range(groups.size()):
			var parent: int = groups[group_index]["parent"]
			if parent < 0 or parent >= origins.size():
				continue
			mesh.surface_add_vertex(origins[parent])
			mesh.surface_add_vertex(origins[group_index])
		mesh.surface_end()
	overlay.get_node("Links").mesh = mesh
