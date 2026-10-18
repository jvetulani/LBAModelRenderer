extends SceneTree

const LBA1 := "/home/asia/Games/LBAgog"
const LBA2 := "/home/asia/Games/LBA2gog"
const DEMO := "/home/asia/Projekty/LBA/LBAModelVIewer/LBA2-96"

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	root.add_child(scene)
	var ui: MainUI = scene.get_node("MainUI")
	assert(ui.dither_mode.get_selected_id() == 4, "Soft model-anchored dither must be the default")
	var next_button: Button = ui.get_node("Screen/BodyNavigation/NextBody")
	var platform_switch: CheckButton = ui.get_node("Screen/PlatformToggle")
	assert(is_equal_approx(next_button.size.x, platform_switch.size.x), "The switch and navigation button widths must match")
	assert(ui.play_button.text.is_empty() and ui.play_button.icon != null, "Playback uses an icon-only button")
	var play_icon := ui.play_button.icon
	ui.set_play_state(true)
	assert(ui.play_button.icon != play_icon and ui.play_button.tooltip_text == "Pause animation")
	ui.set_play_state(false)
	assert(ui.play_button.icon == play_icon and ui.play_button.tooltip_text == "Play animation")
	for source in [LBA1, LBA2, DEMO]:
		var first := HQRReader.read_entry(source.path_join("BODY.HQR"), 0)
		assert(first["ok"])
		var last: int = first["entry_count"] - 1
		scene.call("_load_source", source, last)
		assert(ui.body_index() == 0, "Changing the source must reset to BODY #0")
		if source != LBA2:
			var material: ShaderMaterial = scene.get_node("CharacterViewer").character.get_node("Polygons").material_override
			assert(is_equal_approx(float(material.get_shader_parameter("palette_ramp_size")), 16.0), "Soft shading must not cross palette ramps")
		ui._step_body(-1)
		assert(ui.body_index() == last, "Previous from BODY #0 must wrap to last")
		ui._step_body(1)
		assert(ui.body_index() == 0, "Next from last must wrap to BODY #0")
		ui.body_number.text = str(last)
		ui.request_load()
		assert(ui.body_index() == last)
		ui._step_body(1)
		assert(ui.body_index() == 0)
		print("Navigation ", source, ": 0 <-> ", last)
	scene.call("_load_source", LBA1, 0)
	var viewer: CharacterViewer = scene.get_node("CharacterViewer")
	var polygon_mesh: MeshInstance3D = viewer.character.get_node("Polygons")
	var anchors: PackedFloat32Array = polygon_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM2]
	assert(anchors.size() == polygon_mesh.mesh.surface_get_array_len(0) * 4)
	assert(anchors[0] != 0.0 or anchors[1] != 0.0 or anchors[2] != 0.0)
	viewer.scrub_to(1)
	var moved_mesh: MeshInstance3D = viewer.character.get_node("Polygons")
	assert(moved_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM2] == anchors, "Dither anchors must remain stable across poses")
	assert(ui.shadow_toggle.visible and ui.shadow_label.visible and viewer._shadow.visible)
	ui.shadow_toggle.button_pressed = false
	assert(not viewer._shadow.visible and viewer.export_input()["shadow"].is_empty())
	ui._step_body(1)
	assert(not viewer._shadow.visible, "Shadow setting must survive entry changes")
	var wire_toggle: CheckButton = ui.get_node("Screen/WireframeToggle")
	wire_toggle.button_pressed = true
	var wire: MeshInstance3D = viewer.character.get_node("Wireframe")
	assert(wire.visible and wire.mesh.get_surface_count() == 1)
	assert(wire.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES)
	ui._step_body(1)
	assert(viewer.character.get_node("Wireframe").visible, "Wireframe setting must survive entry changes")
	scene.call("_load_source", LBA2, 14)
	var animated_mesh: MeshInstance3D = viewer.character.get_node("Polygons")
	var frame_zero: Array = animated_mesh.mesh.surface_get_arrays(0)
	viewer.scrub_to(1)
	var frame_one: Array = viewer.character.get_node("Polygons").mesh.surface_get_arrays(0)
	assert(frame_one[Mesh.ARRAY_VERTEX] != frame_zero[Mesh.ARRAY_VERTEX], "Animation fixture must move")
	assert(frame_one[Mesh.ARRAY_CUSTOM2] == frame_zero[Mesh.ARRAY_CUSTOM2], "Dither anchors must stay fixed during animation")
	quit()
