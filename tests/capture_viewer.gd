extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game_path := ""
	var output_path := ""
	var yaw_degrees := 28.0
	var body_index := 0
	var capture_size := Vector2i(1280, 720)
	var hide_ui := false
	var hide_glass := false
	var hide_opaque := false
	var hide_platform := false
	var dither_mode := 4
	var animation_index := -1
	var animation_frame := -1
	var palette_index := -1
	var static_pose := false
	var wireframe := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			game_path = argument.trim_prefix("--lba1=")
		elif argument.begins_with("--lba2="):
			game_path = argument.trim_prefix("--lba2=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--yaw="):
			yaw_degrees = float(argument.trim_prefix("--yaw="))
		elif argument.begins_with("--body-index="):
			body_index = int(argument.trim_prefix("--body-index="))
		elif argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size() == 2:
				capture_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument == "--hide-ui":
			hide_ui = true
		elif argument == "--hide-glass":
			hide_glass = true
		elif argument == "--hide-opaque":
			hide_opaque = true
		elif argument == "--hide-platform":
			hide_platform = true
		elif argument == "--dither=off":
			dither_mode = 0
		elif argument == "--dither=source":
			dither_mode = 1
		elif argument == "--dither=strong":
			dither_mode = 2
		elif argument == "--dither=soft":
			dither_mode = 4
		elif argument == "--shading=smooth":
			dither_mode = 3
		elif argument.begins_with("--anim-index="):
			animation_index = int(argument.trim_prefix("--anim-index="))
		elif argument.begins_with("--anim-frame="):
			animation_frame = int(argument.trim_prefix("--anim-frame="))
		elif argument.begins_with("--palette-index="):
			palette_index = int(argument.trim_prefix("--palette-index="))
		elif argument == "--static":
			static_pose = true
		elif argument == "--wireframe":
			wireframe = true
	if game_path.is_empty() or output_path.is_empty():
		push_error("Pass --lba1=PATH or --lba2=PATH and --output=PATH after --")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = capture_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	viewport.add_child(scene)
	var orbit_camera: OrbitCamera = scene.get_node("OrbitCamera")
	orbit_camera.yaw = deg_to_rad(yaw_degrees)
	orbit_camera._update_pose()
	scene.call("_load_source", game_path, 0)
	if body_index != 0:
		scene.call("_load_source", game_path, body_index)
	if hide_platform:
		scene.get_node("DisplayBlock").hide()
	var viewer: CharacterViewer = scene.get_node("CharacterViewer")
	var ui: MainUI = scene.get_node("MainUI")
	if static_pose:
		var static_result := viewer.load_body(game_path, body_index)
		if not static_result["ok"]:
			push_error(static_result["error"])
			quit(1)
			return
		orbit_camera.frame_points(static_result["points"], scene.get_node("CharacterStandPoint").position)
	if palette_index >= 0:
		var palette_result := viewer.select_lba2_palette(palette_index)
		if not palette_result["ok"]:
			push_error(palette_result["error"])
			quit(1)
			return
	ui.set_source(game_path, body_index)
	viewer.set_dither_mode(dither_mode)
	viewer.set_wireframe_visible(wireframe)
	if animation_index >= 0:
		var selected := viewer.select_animation(animation_index)
		if not selected["ok"]:
			push_error(selected["error"])
			quit(1)
			return
		for item in range(ui.animation_list.item_count):
			if ui.animation_list.get_item_id(item) == animation_index:
				ui.animation_list.select(item)
				break
	if animation_frame >= 0:
		viewer.scrub_to(animation_frame)
		viewer.set_playing(false)
	if hide_ui:
		for child in scene.get_children():
			if child is CanvasLayer:
				child.hide()
	var character: Node3D = viewer.character
	if character == null:
		push_error("Scene did not create the character")
		quit(1)
		return
	var polygon_mesh: MeshInstance3D = character.get_node("Polygons")
	if hide_opaque:
		polygon_mesh.hide()
	if hide_glass and character.has_node("TranslucentPolygons"):
		character.get_node("TranslucentPolygons").hide()
	print("Viewer mesh vertices: ", polygon_mesh.mesh.surface_get_array_len(0))
	print("Character child meshes: ", character.get_child_count())
	print("Status: ", ui.status_label.text)
	print("Associated animations: ", viewer.animation_entries.size())
	print("Shadow: ", viewer.get_node_or_null("LBA1ActorShadow") != null)
	for frame in range(10):
		await process_frame
	var image := viewport.get_texture().get_image()
	var result := image.save_png(output_path)
	if result != OK:
		push_error("Could not save viewer capture: %s" % error_string(result))
		quit(1)
		return
	print("Saved capture: ", output_path)
	quit(0)
