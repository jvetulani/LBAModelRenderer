extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var path := "/tmp/lba2-body0.glb"
	var output := "/tmp/lba2-glb.png"
	var time := 0.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--glb="):
			path = argument.trim_prefix("--glb=")
		elif argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--time="):
			time = float(argument.trim_prefix("--time="))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_buffer(FileAccess.get_file_as_bytes(path), "", state)
	if result != OK:
		push_error("Could not load GLB: %s" % error_string(result))
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	viewport.add_child(stage)
	stage.get_node("MainUI").hide()
	var imported := document.generate_scene(state)
	stage.add_child(imported)
	imported.position = stage.get_node("CharacterStandPoint").position
	var camera: OrbitCamera = stage.get_node("OrbitCamera")
	camera.yaw = deg_to_rad(28.0)
	camera._update_pose()
	var player := imported.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		push_error("GLB has no AnimationPlayer")
		quit(1)
		return
	var names := player.get_animation_list()
	print("GLB animation count: ", names.size())
	var idle := ""
	for name in names:
		if name.begins_with("Idle_ANIM_") and not name.ends_with("_loop"):
			idle = name
			break
	if not idle.is_empty():
		player.play(idle)
		player.seek(time, true)
	for frame in range(10):
		await process_frame
	var image := viewport.get_texture().get_image()
	assert(image.save_png(output) == OK)
	print("Saved imported GLB capture: ", output)
	quit(0)
