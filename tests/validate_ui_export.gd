extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			source = argument.trim_prefix("--lba1=")
	if source.is_empty():
		_fail("Pass --lba1=PATH after --")
		return
	var main: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	root.add_child(main)
	main._load_source(source, 0)
	main._load_source(source, 17)
	var platform: DisplayPlatform = main.get_node("DisplayBlock")
	if absf(platform.position.y + 0.525) > 0.0001:
		_fail("Display platform no longer has clearance below the character stand point")
		return
	var platform_material := platform.material_override as ShaderMaterial
	var platform_texture: Texture2D = platform_material.get_shader_parameter("palette_texture")
	if platform_texture == null or platform_texture.get_width() != 256 or platform_material.get_shader_parameter("palette_index_override") != 240 or not platform_material.get_shader_parameter("use_mesh_lighting"):
		_fail("Display platform did not receive the LBA1 palette and selected index")
		return
	var ui: MainUI = main.get_node("MainUI")
	if ui.dither_mode.get_selected_id() != 4:
		_fail("Soft dither is not the default shading choice")
		return
	ui.dither_changed.emit(3)
	var viewer: CharacterViewer = main.get_node("CharacterViewer")
	var character_material: ShaderMaterial = viewer.character.get_node("Polygons").material_override
	if platform_material.get_shader_parameter("dither_mode") != 3 or character_material.get_shader_parameter("dither_mode") != 3:
		_fail("Modern smooth did not reach both the platform and character")
		return
	ui.dither_changed.emit(4)
	if platform_material.get_shader_parameter("dither_mode") != 4 or character_material.get_shader_parameter("dither_mode") != 4:
		_fail("Soft dither did not restore the platform and character shading")
		return
	var exporter: ExportController = main.get_node("ExportController")
	exporter._export("glb", "/tmp/lba1-ui-grobo.glb")
	if not FileAccess.file_exists("/tmp/lba1-ui-grobo.glb"):
		_fail("UI controller did not save GLB: %s" % ui.status_label.text)
		return
	exporter._export("blend", "/tmp/lba1-ui-grobo.blend")
	if not FileAccess.file_exists("/tmp/lba1-ui-grobo.blend") or not ui.status_label.text.begins_with("Saved /tmp/lba1-ui-grobo.blend"):
		_fail("UI controller did not save Blender file: %s" % ui.status_label.text)
		return
	print("PASS: UI exported GLB and Blender file; %s" % ui.status_label.text)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
