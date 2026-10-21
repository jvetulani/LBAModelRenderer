extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var source := "/home/asia/Projekty/LBA/LBAModelVIewer/AITD_GOG"
	var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	root.add_child(scene)
	var viewer: CharacterViewer = scene.get_node("CharacterViewer")
	var aitd_directory := source.path_join("INDARK")
	var objects_bytes := FileAccess.get_file_as_bytes(aitd_directory.path_join("OBJETS.ITD"))
	var source_links := AITDPakReader.life_animation_map(aitd_directory)
	var browser_decoder = load("res://scripts/import/aitd_life_decoder.gd")
	for body_index in [4, 12]:
		var browser_links: Array[int] = browser_decoder.animation_ids(objects_bytes, body_index, func(index: int) -> Dictionary:
			return AITDPakReader.read_entry(aitd_directory.path_join("LISTLIFE.PAK"), index)
		)
		if browser_links != source_links.get(str(body_index), []):
			push_error("Browser LIFE references disagree for body %d: %s vs %s" % [body_index, browser_links, source_links.get(str(body_index), [])])
			quit(1)
			return
		var result := viewer.load_body(source, body_index)
		if not result.get("ok", false):
			push_error("AITD body %d failed: %s" % [body_index, result.get("error", "")])
			quit(1)
			return
		var associated := []
		for clip in viewer.animation_entries:
			if clip["associated"]:
				associated.append(clip["archive_index"])
		if body_index == 4 and not associated.has(9):
			push_error("Rocking horse lost game clip #9")
			quit(1)
			return
		if body_index == 12 and not (associated.has(5) and associated.has(11) and associated.has(254)):
			push_error("Twinsen is missing LIFE linked animations")
			quit(1)
			return
		for clip in viewer.animation_entries:
			var entry: Dictionary = AITDPakReader.read_entry(source.path_join("INDARK").path_join("LISTANIM.PAK"), clip["archive_index"])
			var decoded: Dictionary = AITDAnimationDecoder.decode(entry["data"])
			if not decoded.get("ok", false) or decoded["group_count"] != viewer.body["groups"].size():
				push_error("Animation %d is incompatible with body %d" % [clip["archive_index"], body_index])
				quit(1)
				return
		print("PASS AITD body %d: %d linked, %d compatible" % [body_index, associated.size(), viewer.animation_entries.size()])
	quit()
