extends SceneTree


func _init() -> void:
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			source = argument.trim_prefix("--lba1=")
	if source.is_empty():
		_fail("Pass --lba1=PATH after --")
		return
	var viewer := CharacterViewer.new()
	root.add_child(viewer)
	for body_index in [17, 0, 30]:
		var loaded := viewer.load_body(source, body_index)
		if not loaded["ok"]:
			_fail(loaded["error"])
			return
		if body_index == 0 and viewer.animation_entries.size() < 50:
			_fail("Twinsen BODY #0 lost its shared FILE3D actions")
			return
		var export_result := LBA1GLBExporter.build(viewer.export_input())
		if not export_result["ok"]:
			_fail(export_result["error"])
			return
		var bytes: PackedByteArray = export_result["bytes"]
		var path := "/tmp/lba1-body-%d.glb" % body_index
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_buffer(bytes, "", state)
		if error != OK:
			_fail("Reimport failed: %s" % error_string(error))
			return
		var expected := int(export_result["animations"])
		if state.get_animations().size() != expected or state.get_skins().size() != 1:
			_fail("GLB lacks actions or skin: %d/%d animations, %d skins" % [state.get_animations().size(), expected, state.get_skins().size()])
			return
		print("PASS: BODY #%d: %d actions, %d GLB animations, %d vertices, %d bytes, skin and reimport" % [body_index, export_result["source_actions"], expected, export_result["vertices"], bytes.size()])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
