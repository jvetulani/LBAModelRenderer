extends SceneTree

const DEMO_PATH := "/home/asia/Projekty/LBA/LBAModelVIewer/LBA2-96"


func _init() -> void:
	var first := HQRReader.read_entry(DEMO_PATH.path_join("BODY.HQR"), 0)
	assert(first["ok"])
	var valid := 0
	var failures := []
	for body_index in range(first["entry_count"]):
		var entry := HQRReader.read_entry(DEMO_PATH.path_join("BODY.HQR"), body_index)
		if not entry["ok"]:
			failures.append("%d: archive %s" % [body_index, entry["error"]])
			continue
		var body := LBA1BodyDecoder.decode_compact_groups(entry["data"])
		if body["ok"]:
			valid += 1
		else:
			var regular := LBA1BodyDecoder.decode(entry["data"])
			failures.append("%d: compact %s; regular %s" % [body_index, body["error"], "valid" if regular["ok"] else regular["error"]])
	assert(valid == first["entry_count"], "1996 demo body decode failures: %s" % str(failures))
	var viewer := CharacterViewer.new()
	root.add_child(viewer)
	var empty_animation := HQRReader.read_entry(DEMO_PATH.path_join("ANIM.HQR"), 480)
	assert(empty_animation["ok"] and empty_animation["data"].decode_u16(0) == 0)
	assert(not LBA1AnimationDecoder.decode(empty_animation["data"])["ok"], "Zero-keyframe demo action must be rejected")
	var shared_actions := 0
	for body_index in range(first["entry_count"]):
		var loaded_body := viewer.load_body(DEMO_PATH, body_index)
		assert(loaded_body["ok"])
		assert(viewer.animation_entries.all(func(item: Dictionary) -> bool: return item["archive_index"] != 480), "Zero-keyframe action leaked into the selector")
		for item in viewer.animation_entries:
			if item["generic_ids"].size() > 1:
				assert(item["name"].begins_with("Shared action"))
				shared_actions += 1
	assert(shared_actions > 0, "Aliased demo actions must not get a misleading single name")
	var loaded := viewer.load_body(DEMO_PATH, 0)
	assert(loaded["ok"] and viewer.game == "LBA2-96")
	assert(viewer.body["shade_table"].size() == 65536, "Demo XPL shade table was not loaded")
	assert(viewer.animation_entries.size() > 0)
	assert(LBA1AnimationDecoder.ticks_per_second("LBA2-96") == 50.0)
	assert(LBA1AnimationDecoder.ticks_per_second("LBA2") == 1000.0)
	var decoded_actions := 0
	var short_actions := 0
	for animation_entry in viewer.animation_entries:
		var anim := HQRReader.read_entry(DEMO_PATH.path_join("ANIM.HQR"), animation_entry["archive_index"])
		if not anim["ok"]:
			continue
		var decoded := LBA1AnimationDecoder.decode(anim["data"])
		if decoded["ok"]:
			decoded_actions += 1
			if decoded["group_count"] < viewer.body["groups"].size():
				short_actions += 1
	assert(decoded_actions > 0 and decoded_actions == viewer.animation_entries.size())
	var associated_count: int = viewer.animation_entries.size()
	var selected := viewer.select_animation(viewer.animation_entries[0]["archive_index"])
	assert(selected["ok"])
	assert(viewer.animation["frame_count"] > 1)
	viewer.scrub_to(0)
	viewer.set_playing(true)
	viewer._process(0.02)
	assert(viewer._current_frame == 0, "Demo frame must not finish after 20 ms")
	viewer._process(0.25)
	assert(viewer._current_frame == 0, "Demo frame duration is in 50 Hz ticks")
	viewer._process(0.03)
	assert(viewer._current_frame == 1, "Demo frame must advance after 300 ms")
	var exported := LBA1GLBExporter.build(viewer.export_input())
	assert(exported["ok"], str(exported.get("error", "Demo GLB failed")))
	var state := GLTFState.new()
	assert(GLTFDocument.new().append_from_buffer(exported["bytes"], "", state) == OK)
	var textured_loaded := viewer.load_body(DEMO_PATH, 1)
	assert(textured_loaded["ok"] and viewer.body["textures"].size() > 0)
	var textured_material: ShaderMaterial = viewer.character.get_node("Polygons").material_override
	assert(textured_material.get_shader_parameter("has_shade_table"), "Demo textured faces must use the source shade table")
	var textured_export := LBA1GLBExporter.build(viewer.export_input())
	assert(textured_export["ok"], str(textured_export.get("error", "Demo textured GLB failed")))
	var textured_state := GLTFState.new()
	assert(GLTFDocument.new().append_from_buffer(textured_export["bytes"], "", textured_state) == OK)
	for case_index in [47, 48]:
		var case_loaded := viewer.load_body(DEMO_PATH, case_index)
		assert(case_loaded["ok"] and viewer.character.has_node("TranslucentPolygons"))
		var pane_count: int = viewer.body["polygons"].filter(func(polygon: Dictionary) -> bool: return LBA2Appearance.is_translucent_face(viewer.body, polygon)).size()
		assert(pane_count == 24, "Demo case pane faces must stay separate from the frame")
		var case_export := LBA1GLBExporter.build(viewer.export_input())
		assert(case_export["ok"])
		var case_state := GLTFState.new()
		assert(GLTFDocument.new().append_from_buffer(case_export["bytes"], "", case_state) == OK)
		var blend_found := false
		for material in case_state.get_materials():
			if material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				blend_found = true
		assert(blend_found, "Demo case GLB lost translucent panes")
	print("LBA2-96: %d/%d bodies, %d associated animations (%d with fewer groups), GLB %d bytes" % [valid, first["entry_count"], associated_count, short_actions, exported["bytes"].size()])
	print("Decode failures: ", failures)
	quit()
