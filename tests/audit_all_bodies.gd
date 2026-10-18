extends SceneTree

const TILE := 160
const COLUMNS := 8
const PER_SHEET := 64

func _initialize() -> void:
	call_deferred("_audit")

func _audit() -> void:
	var source := ""
	var output_prefix := "/tmp/lba-body-audit"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			source = argument.trim_prefix("--source=")
		elif argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")
	if source.is_empty():
		push_error("Pass --source=GAME_FOLDER")
		quit(1)
		return
	var first := HQRReader.read_entry(source.path_join("BODY.HQR"), 0)
	if not first["ok"]:
		push_error(first["error"])
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(TILE, TILE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	viewport.add_child(scene)
	scene.get_node("MainUI").hide()
	scene.get_node("DisplayBlock").hide()
	var viewer: CharacterViewer = scene.get_node("CharacterViewer")
	var camera: OrbitCamera = scene.get_node("OrbitCamera")
	camera.yaw = deg_to_rad(28.0)
	var failures := []
	var empty_geometry := []
	var sheets := 0
	var sheet := _new_sheet()
	for body_index in range(first["entry_count"]):
		var loaded := viewer.load_body(source, body_index)
		if not loaded["ok"]:
			failures.append("%d: %s" % [body_index, loaded["error"]])
			continue
		var mesh: ArrayMesh = viewer.character.get_node("Polygons").mesh
		var has_glass := viewer.character.has_node("TranslucentPolygons") and viewer.character.get_node("TranslucentPolygons").mesh.get_surface_count() > 0
		if mesh.get_surface_count() == 0 and not has_glass and viewer.body["lines"].is_empty() and viewer.body["spheres"].is_empty():
			empty_geometry.append(body_index)
		camera.frame_points(loaded["points"], Vector3.ZERO)
		await process_frame
		await process_frame
		var tile := viewport.get_texture().get_image()
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)), Vector2i((body_index % COLUMNS) * TILE, ((body_index % PER_SHEET) / COLUMNS) * TILE))
		if body_index % PER_SHEET == PER_SHEET - 1 or body_index == first["entry_count"] - 1:
			var path := "%s-%03d.png" % [output_prefix, sheets]
			var saved := sheet.save_png(path)
			if saved != OK:
				failures.append("sheet %d: %s" % [sheets, error_string(saved)])
			else:
				print("Saved %s (BODY %d..%d)" % [path, sheets * PER_SHEET, body_index])
			sheets += 1
			sheet = _new_sheet()
		if body_index % 100 == 0:
			print("Rendered %d/%d" % [body_index + 1, first["entry_count"]])
	print("Audit %s: %d entries, %d sheets, %d load failures, empty geometry %s" % [source, first["entry_count"], sheets, failures.size(), str(empty_geometry)])
	print("Failures: ", failures)
	quit(1 if not failures.is_empty() or not empty_geometry.is_empty() else 0)

func _new_sheet() -> Image:
	var sheet := Image.create_empty(COLUMNS * TILE, COLUMNS * TILE, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.11, 0.14, 0.2))
	return sheet
