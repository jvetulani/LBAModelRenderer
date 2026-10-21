extends SceneTree

const CASES := [
	["LBA1", "/home/asia/Games/LBAgog", 0],
	["LBA2", "/home/asia/Games/LBA2gog", 0],
	["LBA2-96", "/home/asia/Projekty/LBA/LBAModelVIewer/LBA2-96", 1],
	["AITD1", "/home/asia/Projekty/LBA/LBAModelVIewer/AITD_GOG", 12],
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for test_case in CASES:
		var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
		root.add_child(scene)
		scene._active_source = test_case[1]
		scene._load_source(test_case[1], test_case[2])
		var viewer: CharacterViewer = scene.get_node("CharacterViewer")
		var ui: MainUI = scene.get_node("MainUI")
		if viewer.game != test_case[0]:
			push_error("%s failed to load: %s" % [test_case[0], ui.status_label.text])
			quit(1)
			return
		if test_case[0] == "AITD1" and ui._asset_picker.visible:
			push_error("AITD category picker should be hidden")
			quit(1)
			return
		if test_case[0] == "AITD1" and not viewer.select_animation(2).get("ok", false):
			push_error("AITD compatible moving clip could not be selected")
			quit(1)
			return
		var input := viewer.export_input()
		var built := LBA1GLBExporter.build(input)
		if not built.get("ok", false):
			push_error("%s GLB failed: %s" % [test_case[0], built.get("error", "")])
			quit(1)
			return
		var bytes: PackedByteArray = built["bytes"]
		var json_length := int(bytes.decode_u32(12))
		var document: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
		var root_tracks := 0
		for clip in document.get("animations", []):
			for channel in clip.get("channels", []):
				var target: Dictionary = channel["target"]
				if target["path"] != "translation":
					continue
				var node: Dictionary = document["nodes"][int(target["node"])]
				if str(node.get("name", "")) == "Group_00":
					root_tracks += 1
		if root_tracks == 0:
			push_error("%s GLB has no root-bone translation channel" % test_case[0])
			quit(1)
			return
		var moving_clip := {}
		for clip in input["clips"]:
			for frame in clip["animation"]["frames"]:
				if Vector3(frame["root_step"]).length_squared() > 0.0:
					moving_clip = clip
					break
			if not moving_clip.is_empty():
				break
		if moving_clip.is_empty():
			push_error("No moving source clip found for " + str(test_case[0]))
			quit(1)
			return
		var moving_input: Dictionary = input.duplicate(true)
		moving_input["clips"] = [moving_clip]
		moving_input.erase("variants")
		var still_input: Dictionary = moving_input.duplicate(true)
		for frame in still_input["clips"][0]["animation"]["frames"]:
			frame["root_step"] = Vector3i.ZERO
		var moving := LBA1GLBExporter.build(moving_input)
		var still := LBA1GLBExporter.build(still_input)
		if not moving["ok"] or not still["ok"] or _root_samples(moving["bytes"]) == _root_samples(still["bytes"]):
			push_error("Source root steps did not change exported root positions")
			quit(1)
			return
		print("PASS %s moving clip #%d changes exported root positions" % [test_case[0], moving_clip["archive_index"]])
		print("PASS %s: %d source actions, %d root-motion channels" % [test_case[0], built["source_actions"], root_tracks])
		root.remove_child(scene)
		scene.free()
	quit()


func _root_samples(bytes: PackedByteArray) -> PackedVector3Array:
	var json_length := int(bytes.decode_u32(12))
	var document: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	var binary_start := 20 + json_length + 8
	for channel in document["animations"][0]["channels"]:
		if channel["target"]["path"] != "translation":
			continue
		if document["nodes"][int(channel["target"]["node"])].get("name", "") != "Group_00":
			continue
		var sampler: Dictionary = document["animations"][0]["samplers"][int(channel["sampler"])]
		var accessor: Dictionary = document["accessors"][int(sampler["output"])]
		var view: Dictionary = document["bufferViews"][int(accessor["bufferView"])]
		var at := binary_start + int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
		var result := PackedVector3Array()
		for key in range(int(accessor["count"])):
			result.append(Vector3(bytes.decode_float(at + key * 12), bytes.decode_float(at + key * 12 + 4), bytes.decode_float(at + key * 12 + 8)))
		return result
	return PackedVector3Array()
