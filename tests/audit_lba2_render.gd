extends SceneTree


func _initialize() -> void:
	call_deferred("_audit")


func _audit() -> void:
	var source := "/home/asia/Games/LBA2gog"
	var output := "/tmp/lba2-render-sheet.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba2="):
			source = argument.trim_prefix("--lba2=")
		elif argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	var archive := HQRReader.read_entry(source.path_join("BODY.HQR"), 0)
	if not archive["ok"]:
		push_error(archive["error"])
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	viewport.add_child(scene)
	for child in scene.get_children():
		if child is CanvasLayer:
			child.hide()
	var camera: OrbitCamera = scene.get_node("OrbitCamera")
	camera.yaw = deg_to_rad(28.0)
	scene.get_node("DisplayBlock").set_game("LBA2")
	var sheet := Image.create_empty(8 * 192, 8 * 192, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.11, 0.14, 0.2))
	var failures := []
	var sampled := 0
	var textured := 0
	var with_source_stretch := 0
	for body_index in range(archive["entry_count"]):
		var viewer: CharacterViewer = scene.get_node("CharacterViewer")
		var result := viewer.load_body(source, body_index)
		if not result["ok"]:
			failures.append("%d: %s" % [body_index, result["error"]])
			continue
		camera.frame_points(result["points"], Vector3.ZERO)
		var polygon_mesh: ArrayMesh = viewer.character.get_node("Polygons").mesh
		if polygon_mesh.get_surface_count() == 0:
			if viewer.body["polygons"].is_empty() and (not viewer.body["lines"].is_empty() or not viewer.body["spheres"].is_empty()):
				print("Geometry-only BODY %d: %d lines, %d spheres" % [body_index, viewer.body["lines"].size(), viewer.body["spheres"].size()])
			else:
				failures.append("%d: empty polygon mesh (%d source polygons, %d lines, %d spheres)" % [body_index, viewer.body["polygons"].size(), viewer.body["lines"].size(), viewer.body["spheres"].size()])
		var has_texture := false
		var stretches := false
		for polygon in viewer.body["polygons"]:
			if polygon.get("texture_handle", -1) < 0:
				continue
			has_texture = true
			var edge_ratios := []
			var point_ids: PackedInt32Array = polygon["points"]
			var uvs: PackedVector2Array = polygon["texture_uvs"]
			for edge in range(point_ids.size()):
				var next := (edge + 1) % point_ids.size()
				var world_length: float = viewer.body["pose_points"][point_ids[edge]].distance_to(viewer.body["pose_points"][point_ids[next]])
				if world_length > 0.01:
					edge_ratios.append(uvs[edge].distance_to(uvs[next]) / world_length)
			if edge_ratios.size() >= 3 and edge_ratios.min() > 0.0 and edge_ratios.max() / edge_ratios.min() > 8.0:
				stretches = true
		if has_texture:
			textured += 1
		if stretches:
			with_source_stretch += 1
		if body_index < 8 or (body_index % 8 == 0 and sampled < 64):
			await process_frame
			await process_frame
			var tile := viewport.get_texture().get_image()
			tile.resize(192, 192, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i((sampled % 8) * 192, (sampled / 8) * 192))
			sampled += 1
		elif body_index % 32 == 0:
			await process_frame
		if body_index % 100 == 0:
			print("Audited %d/%d bodies" % [body_index + 1, archive["entry_count"]])
	var save_error := sheet.save_png(output)
	if save_error != OK:
		failures.append("contact sheet: %s" % error_string(save_error))
	print("Render audit: %d bodies, %d textured, %d with strongly anisotropic source UVs, %d sampled, %d failures" % [archive["entry_count"], textured, with_source_stretch, sampled, failures.size()])
	print("Failures: ", failures.slice(0, 30))
	print("Contact sheet: ", output)
	quit(1 if not failures.is_empty() else 0)
