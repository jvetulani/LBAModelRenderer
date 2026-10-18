extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sources := {}
	var output_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			sources["LBA1"] = argument.trim_prefix("--lba1=")
		elif argument.begins_with("--lba2="):
			sources["LBA2"] = argument.trim_prefix("--lba2=")
		elif argument.begins_with("--demo="):
			sources["LBA2-96"] = argument.trim_prefix("--demo=")
		elif argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=")
	if sources.size() != 3 or output_dir.is_empty():
		_fail("Pass --lba1, --lba2, --demo and --output-dir")
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_fail("Could not create %s" % output_dir)
		return
	var results := []
	for game_name in ["LBA1", "LBA2", "LBA2-96"]:
		# Demo BODY #0 is palette-only; #1 also exercises texture export.
		var body_index := 17 if game_name == "LBA1" else (1 if game_name == "LBA2-96" else 0)
		var source: String = sources[game_name]
		var main: Node3D = load("res://assets/scenes/main.tscn").instantiate()
		root.add_child(main)
		main._load_source(source, 0)
		if body_index != 0:
			main._load_source(source, body_index)
		var viewer: CharacterViewer = main.get_node("CharacterViewer")
		var ui: MainUI = main.get_node("MainUI")
		var exporter: ExportController = main.get_node("ExportController")
		if viewer.game != game_name or viewer.body.is_empty() or viewer.animation_entries.is_empty():
			_fail("%s did not load a body with actions: %s" % [game_name, ui.status_label.text])
			return
		var prefix: String = game_name.to_lower().replace("-", "")
		var glb_path := output_dir.path_join("%s-body-%d.glb" % [prefix, body_index])
		var blend_path := output_dir.path_join("%s-body-%d.blend" % [prefix, body_index])
		exporter._export("glb", glb_path)
		if not ui.status_label.text.begins_with("Saved ") or not FileAccess.file_exists(glb_path):
			_fail("%s GLB export failed: %s" % [game_name, ui.status_label.text])
			return
		var bytes := FileAccess.get_file_as_bytes(glb_path)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_buffer(bytes, "", state) != OK:
			_fail("%s GLB failed to reimport" % game_name)
			return
		if state.get_skins().size() != 1 or state.get_animations().size() < viewer.animation_entries.size():
			_fail("%s GLB lost its skin or actions" % game_name)
			return
		var imported := document.generate_scene(state)
		if imported == null or imported.find_child("CharacterMesh", true, false) == null:
			_fail("%s GLB has no reimported character mesh" % game_name)
			return
		imported.free()
		exporter._export("blend", blend_path)
		if not ui.status_label.text.begins_with("Saved ") or not FileAccess.file_exists(blend_path):
			_fail("%s Blender export failed: %s" % [game_name, ui.status_label.text])
			return
		var result := {
			"game": game_name,
			"body_index": body_index,
			"source_actions": viewer.animation_entries.size(),
			"glb_animations": state.get_animations().size(),
			"glb_bytes": bytes.size(),
			"blend_path": blend_path,
			"blend_bytes": FileAccess.get_file_as_bytes(blend_path).size(),
		}
		results.append(result)
		print("PASS: ", result)
		root.remove_child(main)
		main.free()
	var manifest := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
	if manifest == null:
		_fail("Could not write export manifest")
		return
	manifest.store_string(JSON.stringify(results, "\t"))
	manifest.close()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
