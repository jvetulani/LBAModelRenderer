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
	scene.set("_orbit_yaw", deg_to_rad(yaw_degrees))
	scene.call("_update_camera")
	var source_field: LineEdit = scene.get("_source_field")
	source_field.text = game_path
	var entry_number: SpinBox = scene.get("_entry_number")
	entry_number.value = body_index
	scene.call("_load_source")
	scene.call("_set_dither_mode", dither_mode)
	if hide_ui:
		for child in scene.get_children():
			if child is CanvasLayer:
				child.hide()
	var character: Node3D = scene.get("_character")
	if character == null:
		push_error("Scene did not create the character: %s" % scene.get("_status").text)
		quit(1)
		return
	var polygon_mesh: MeshInstance3D = character.get_node("Polygons")
	print("Viewer mesh vertices: ", polygon_mesh.mesh.surface_get_array_len(0))
	print("Character child meshes: ", character.get_child_count())
	print("Status: ", scene.get("_status").text)
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
