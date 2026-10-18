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
	var dither_mode := 2
	var animation_index := -1
	var animation_frame := -1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			game_path = argument.trim_prefix("--lba1=")
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
		elif argument == "--dither=off":
			dither_mode = 0
		elif argument == "--dither=source":
			dither_mode = 1
		elif argument == "--shading=smooth":
			dither_mode = 3
		elif argument.begins_with("--anim-index="):
			animation_index = int(argument.trim_prefix("--anim-index="))
		elif argument.begins_with("--anim-frame="):
			animation_frame = int(argument.trim_prefix("--anim-frame="))
	if game_path.is_empty() or output_path.is_empty():
		push_error("Pass --lba1=PATH and --output=PATH after --")
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
	scene.call("_load_source", game_path, body_index)
	var viewer: CharacterViewer = scene.get_node("CharacterViewer")
	var ui: MainUI = scene.get_node("MainUI")
	ui.set_source(game_path, body_index)
	viewer.set_dither_mode(dither_mode)
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
