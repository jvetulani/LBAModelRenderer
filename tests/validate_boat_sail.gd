extends SceneTree


func _initialize() -> void:
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			source = argument.trim_prefix("--lba1=")
	assert(not source.is_empty(), "Pass --lba1=PATH")
	var viewer := CharacterViewer.new()
	root.add_child(viewer)
	assert(viewer.load_body(source, 49)["ok"])
	var names := {}
	for entry in viewer.animation_entries:
		names[entry["archive_index"]] = entry["name"]
	assert(names[233] == "Move left" and names[234] == "Move right")
	assert(viewer.select_animation(231)["ok"])
	var sailing := viewer.animation.duplicate(true)
	for archive_index in [230, 232, 233, 234]:
		var source_data := HQRReader.read_entry(source.path_join("ANIM.HQR"), archive_index)
		var original := LBA1AnimationDecoder.decode(source_data["data"])
		assert(viewer.select_animation(archive_index)["ok"])
		for frame_index in range(4):
			assert(viewer.animation["frames"][frame_index]["transforms"][2] == original["frames"][frame_index]["transforms"][2])
			assert(viewer.animation["frames"][frame_index]["root_step"] == original["frames"][frame_index]["root_step"])
			for group_index in [3, 4]:
				assert(viewer.animation["frames"][frame_index]["transforms"][group_index] == sailing["frames"][frame_index]["transforms"][group_index])
		viewer.scrub_to(2)
		assert(viewer._motion_grid.visible == (archive_index != 230))
		var travel: Vector2 = (viewer._motion_grid.material_override as ShaderMaterial).get_shader_parameter("travel")
		if archive_index == 233:
			assert(travel.x < -0.4 and absf(travel.y) < 0.01)
		elif archive_index == 234:
			assert(travel.x > 0.4 and absf(travel.y) < 0.01)
	viewer.set_motion_grid_visible(false)
	assert(not viewer._motion_grid.visible)
	viewer.set_motion_grid_visible(true)
	assert(viewer._motion_grid.visible)
	var export_data := viewer.export_input()
	assert(export_data["ok"])
	for clip in export_data["clips"]:
		if clip["archive_index"] == 234:
			assert(clip["animation"]["frames"][1]["transforms"][3] == sailing["frames"][1]["transforms"][3])
	var exported := LBA1GLBExporter.build(export_data)
	assert(exported["ok"])
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_buffer(exported["bytes"], "", state) == OK)
	assert(state.get_animations().size() >= 5)
	print("PASS: catamaran sail, action labels, motion grid, and exported clips")
	quit(0)
