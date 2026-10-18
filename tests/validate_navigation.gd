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
	for source in [LBA1, LBA2, DEMO]:
		var first := HQRReader.read_entry(source.path_join("BODY.HQR"), 0)
		assert(first["ok"])
		var last: int = first["entry_count"] - 1
		scene.call("_load_source", source, last)
		assert(ui.body_index() == 0, "Changing the source must reset to BODY #0")
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
	assert(ui.shadow_toggle.visible and viewer._shadow.visible)
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
	quit()
