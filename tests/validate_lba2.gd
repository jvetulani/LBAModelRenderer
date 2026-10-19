extends SceneTree

const BODY_DECODER = preload("res://scripts/import/lba2_body_decoder.gd")
const FILE3D_DECODER = preload("res://scripts/import/lba2_file3d_decoder.gd")
const PALETTE_DECODER = preload("res://scripts/import/lba2_palette_decoder.gd")
const LBA2_APPEARANCE = preload("res://scripts/render/lba2_appearance.gd")
const LBA2_OVERRIDES = preload("res://scripts/render/lba2_model_overrides.gd")
const ANIMATED_ATLAS = preload("res://scripts/render/lba2_animated_texture_atlas.gd")
const LBA2_POSE = preload("res://scripts/animation/lba2_pose.gd")

func _init() -> void:
	var path := "/home/asia/Games/LBA2gog"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba2="):
			path = argument.trim_prefix("--lba2=")
	var first := HQRReader.read_entry(path.path_join("BODY.HQR"), 0)
	assert(first["ok"], str(first.get("error", "BODY.HQR entry 0 failed")))
	var decoded: Dictionary = BODY_DECODER.decode(first["data"])
	assert(decoded["ok"], str(decoded.get("error", "BODY.HQR entry 0 decode failed")))
	assert(decoded["points"].size() == 193)
	assert(decoded["polygons"].size() == 281)
	decoded["appearance"] = LBA2_OVERRIDES.for_retail_body(0)
	LBA2_OVERRIDES.apply_geometry(decoded)
	var shirt_faces: Array = decoded["polygons"]
	assert(shirt_faces[233]["texture_uvs"][1].is_equal_approx(shirt_faces[232]["texture_uvs"][2]))
	assert(shirt_faces[237]["texture_uvs"][1].is_equal_approx(shirt_faces[233]["texture_uvs"][2]))
	assert(shirt_faces[279]["texture_uvs"][3].is_equal_approx(shirt_faces[232]["texture_uvs"][1]))
	var xpl_entry := HQRReader.read_entry(path.path_join("RESS.HQR"), 27)
	assert(xpl_entry["ok"])
	var xpl := PALETTE_DECODER.decode(xpl_entry["data"])
	assert(xpl["ok"] and xpl["palette"].size() == 768 and xpl["shade_table"].size() == 65536)
	assert(xpl["normal_level"] == 12)
	var clear_entry := HQRReader.read_entry(path.path_join("RESS.HQR"), 42)
	assert(clear_entry["ok"])
	var clear_xpl := PALETTE_DECODER.decode(clear_entry["data"])
	assert(clear_xpl["ok"] and clear_xpl["palette"] != xpl["palette"])
	for palette_index in [28, 29, 30, 31, 32, 33, 34, 35, 36, 37]:
		var scene_entry := HQRReader.read_entry(path.path_join("RESS.HQR"), palette_index)
		assert(scene_entry["ok"] and PALETTE_DECODER.decode(scene_entry["data"])["ok"])
	var file3d := HQRReader.read_entry(path.path_join("RESS.HQR"), 44)
	assert(file3d["ok"], str(file3d.get("error", "RESS.HQR entry 44 failed")))
	var associations: Dictionary = FILE3D_DECODER.animations_for_body(file3d["data"], 0)
	assert(associations["ok"], str(associations.get("error", "LBA2 FILE3D failed")))
	assert(associations["animations"].size() > 0)
	var viewer := CharacterViewer.new()
	root.add_child(viewer)
	var loaded := viewer.load_body(path, 0)
	assert(loaded["ok"], str(loaded.get("error", "Viewer load failed")))
	assert(viewer.game == "LBA2")
	var selected := viewer.select_animation(associations["animations"][0]["archive_index"])
	assert(selected["ok"], str(selected.get("error", "Animation load failed")))
	viewer.scrub_to(2)
	var rainy := viewer.select_lba2_palette(27)
	assert(rainy["ok"] and viewer.export_input()["palette"] == xpl["palette"])
	var clear := viewer.select_lba2_palette(42)
	assert(clear["ok"] and viewer.export_input()["palette"] == clear_xpl["palette"])
	assert(viewer.animation["frame_count"] == selected["frame_count"])
	print("LBA2 animation 0: %d frames, %d groups, loop %d" % [viewer.animation["frame_count"], viewer.animation["group_count"], viewer.animation["loop_frame"]])
	for frame_index in [0, 1, mini(5, viewer.animation["frame_count"] - 1)]:
		print("Frame %d root %s, group1 %s, group2 %s" % [frame_index, str(viewer.animation["frames"][frame_index]["transforms"][0]), str(viewer.animation["frames"][frame_index]["transforms"][1]), str(viewer.animation["frames"][frame_index]["transforms"][2])])
	var export_input := viewer.export_input()
	assert(export_input["ok"], str(export_input.get("error", "LBA2 animation export input failed")))
	var exported := LBA1GLBExporter.build(export_input)
	assert(exported["ok"], str(exported.get("error", "LBA2 GLB conversion failed")))
	assert(viewer.select_lba2_palette(27)["ok"])
	var rainy_export := LBA1GLBExporter.build(viewer.export_input())
	assert(rainy_export["ok"] and rainy_export["bytes"] != exported["bytes"], "GLB did not reflect the selected palette")
	assert(viewer.select_lba2_palette(42)["ok"])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--export="):
			var file := FileAccess.open(argument.trim_prefix("--export="), FileAccess.WRITE)
			assert(file != null)
			file.store_buffer(exported["bytes"])
			file.close()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_buffer(exported["bytes"], "", state) == OK)
	assert(state.get_animations().size() == exported["animations"])
	assert(state.get_skins().size() == 1)
	assert(state.get_meshes().size() > 0)
	var spectral_body: Dictionary = BODY_DECODER.decode(HQRReader.read_entry(path.path_join("BODY.HQR"), 112)["data"])
	spectral_body["appearance"] = LBA2_OVERRIDES.for_retail_body(112)
	assert(spectral_body["ok"])
	assert(spectral_body["polygons"].any(func(polygon: Dictionary) -> bool: return polygon["render_type"] == 14))
	assert(LBA2_APPEARANCE.uses_spectral_preview(spectral_body))
	var grid_body: Dictionary = BODY_DECODER.decode(HQRReader.read_entry(path.path_join("BODY.HQR"), 156)["data"])
	grid_body["appearance"] = LBA2_OVERRIDES.for_retail_body(156)
	assert(grid_body["ok"] and not LBA2_APPEARANCE.uses_spectral_preview(grid_body))
	for effect_index in [24, 88, 125]:
		var effect_body: Dictionary = BODY_DECODER.decode(HQRReader.read_entry(path.path_join("BODY.HQR"), effect_index)["data"])
		effect_body["appearance"] = LBA2_OVERRIDES.for_retail_body(effect_index)
		assert(effect_body["ok"] and LBA2_APPEARANCE.has_translucent_faces(effect_body))
		assert(effect_body["polygons"].any(func(polygon: Dictionary) -> bool: return LBA2_APPEARANCE.is_translucent_face(effect_body, polygon)))
	assert(not LBA2_APPEARANCE.has_translucent_faces(decoded))
	var chest_body: Dictionary = BODY_DECODER.decode(HQRReader.read_entry(path.path_join("BODY.HQR"), 329)["data"])
	var chest_animation: Dictionary = LBA1AnimationDecoder.decode(HQRReader.read_entry(path.path_join("ANIM.HQR"), 1489)["data"])
	assert(chest_body["ok"] and chest_animation["ok"])
	var original_chest: Dictionary = LBA2_POSE.sample(chest_body, chest_animation, 4, 4, 0.0)
	chest_body["appearance"] = LBA2_OVERRIDES.for_retail_body(329)
	var repaired_chest: Dictionary = LBA2_POSE.sample(chest_body, chest_animation, 4, 4, 0.0)
	assert(original_chest["points"][199].distance_to(repaired_chest["points"][199]) > 100.0)
	assert(original_chest["points"][200].is_equal_approx(repaired_chest["points"][200]), "BODY #329 repair must only affect the stray point")
	var glass_loaded := viewer.load_body(path, 106)
	assert(glass_loaded["ok"] and viewer.character.has_node("TranslucentPolygons"))
	var glass_export := LBA1GLBExporter.build(viewer.export_input())
	assert(glass_export["ok"])
	var spectral_loaded := viewer.load_body(path, 112)
	assert(spectral_loaded["ok"])
	var funfrock_loaded := viewer.load_body(path, 315)
	assert(funfrock_loaded["ok"] and LBA2_APPEARANCE.uses_spectral_preview(viewer.body))
	var funfrock_material: ShaderMaterial = viewer.character.get_node("Polygons").material_override
	assert(funfrock_material.next_pass != null, "Teleporting FunFrock must fill chroma holes")
	var atlas_entry := HQRReader.read_entry(path.path_join("RESS.HQR"), 6)
	assert(atlas_entry["ok"])
	var animated_atlas := ANIMATED_ATLAS.new(atlas_entry["data"])
	assert(animated_atlas.frame_count() == 96)
	var first_atlas: PackedByteArray = animated_atlas.pixels()
	animated_atlas.advance(0.08)
	var next_atlas: PackedByteArray = animated_atlas.pixels()
	var fire_coverage := 0
	var plasma_coverage := 0
	var animated_pixels := 0
	for y in range(32, 64):
		for x in range(32, 64):
			fire_coverage += int(first_atlas[y * 256 + x] != 0)
			animated_pixels += int(first_atlas[y * 256 + x] != next_atlas[y * 256 + x])
		for x in range(32):
			plasma_coverage += int(first_atlas[y * 256 + x] != 0)
	assert(fire_coverage > 100 and plasma_coverage > 100 and animated_pixels > 0, "Atlas fire and plasma must render and animate")
	assert(first_atlas[200 * 256 + 200] == next_atlas[200 * 256 + 200], "Static atlas pixels must remain unchanged")
	for y in range(101, 128):
		for x in range(193, 224):
			var shirt_pixel := y * 256 + x
			assert(first_atlas[shirt_pixel] == atlas_entry["data"][shirt_pixel] and next_atlas[shirt_pixel] == atlas_entry["data"][shirt_pixel], "Animated effects must not alter Twinsen's shirt texture")
	for monkey_index in [388, 389]:
		var monkey: Dictionary = BODY_DECODER.decode(HQRReader.read_entry(path.path_join("BODY.HQR"), monkey_index)["data"])
		assert(monkey["ok"])
		var side_face: int = 281 + monkey_index - 388
		var original_uvs: PackedVector2Array = monkey["polygons"][side_face]["texture_uvs"].duplicate()
		var opposite_side: int = 252 + monkey_index - 388
		var opposite_uvs: PackedVector2Array = monkey["polygons"][opposite_side]["texture_uvs"].duplicate()
		var stretched_faces := [177, 181, 182, 202, 203, 209, 212, 215, 216, 236, 252, 253, 255, 256, 280, 281, 282, 284, 285, 309, 195, 199, 204, 205, 207, 229, 233, 238, 239, 240, 257, 258, 259, 260, 278, 279, 286, 287, 288, 289, 307, 308]
		var stretched_uvs := {}
		for face_index in stretched_faces:
			var variant_face: int = face_index + monkey_index - 388
			stretched_uvs[variant_face] = monkey["polygons"][variant_face]["texture_uvs"].duplicate()
		var unchanged_face: int = 310 + monkey_index - 388
		var original_face_uvs: PackedVector2Array = monkey["polygons"][unchanged_face]["texture_uvs"].duplicate()
		monkey["appearance"] = LBA2_OVERRIDES.for_retail_body(monkey_index)
		LBA2_OVERRIDES.apply_geometry(monkey)
		var repaired_uvs: PackedVector2Array = monkey["polygons"][side_face]["texture_uvs"]
		assert(absf(repaired_uvs[0].x - repaired_uvs[1].x) > absf(original_uvs[0].x - original_uvs[1].x) * 4.0, "Monkey arm side UVs must cover more texture columns")
		assert(monkey["polygons"][opposite_side]["texture_uvs"] != opposite_uvs, "Both monkey arm side faces must be repaired")
		for face_index in stretched_uvs:
			assert(monkey["polygons"][face_index]["texture_uvs"] != stretched_uvs[face_index], "Monkey BODY #%d arm face %d remains stretched" % [monkey_index, face_index])
		assert(monkey["polygons"][unchanged_face]["texture_uvs"] == original_face_uvs, "Monkey face texture must stay unchanged")
		assert(viewer.load_body(path, monkey_index)["ok"])
		assert(LBA1GLBExporter.build(viewer.export_input())["ok"], "Monkey BODY #%d GLB export failed" % monkey_index)
	var skirt_source := BODY_DECODER.decode(HQRReader.read_entry(path.path_join("BODY.HQR"), 381)["data"])
	var skirt_repaired: Dictionary = skirt_source.duplicate(true)
	skirt_repaired["appearance"] = LBA2_OVERRIDES.for_retail_body(381)
	LBA2_OVERRIDES.apply_geometry(skirt_repaired)
	var thin_uvs: PackedVector2Array = skirt_source["polygons"][294]["texture_uvs"]
	var full_uvs: PackedVector2Array = skirt_repaired["polygons"][294]["texture_uvs"]
	var thin_area := absf((thin_uvs[1] - thin_uvs[0]).cross(thin_uvs[2] - thin_uvs[0]))
	var full_area := absf((full_uvs[1] - full_uvs[0]).cross(full_uvs[2] - full_uvs[0]))
	assert(full_area > thin_area * 5.0, "BODY #381 skirt UV strip remains collapsed")
	assert(skirt_repaired["polygons"][306]["texture_uvs"] == skirt_source["polygons"][306]["texture_uvs"], "BODY #381 non-stretched texture face changed")
	for undergass_index in [320, 321, 322, 376, 426, 427]:
		var undergass_loaded := viewer.load_body(path, undergass_index)
		assert(undergass_loaded["ok"])
		assert(not viewer.animation_entries.is_empty(), "Undergass BODY #%d needs its authored actions" % undergass_index)
		var actions: Array = viewer.animation_entries.duplicate(true)
		for action in actions:
			var action_data: Dictionary = LBA1AnimationDecoder.decode(HQRReader.read_entry(path.path_join("ANIM.HQR"), action["archive_index"])["data"])
			assert(action_data["ok"])
			assert(viewer.select_animation(action["archive_index"])["ok"], "Undergass BODY #%d action %d did not select" % [undergass_index, action["archive_index"]])
			assert(action_data["group_count"] == viewer.body["groups"].size(), "Undergass BODY #%d action %d uses the wrong skeleton" % [undergass_index, action["archive_index"]])
		assert(viewer.export_input()["clips"].size() == actions.size())
	assert(viewer.load_body(path, 320)["ok"])
	assert(viewer.animation_entries.any(func(action: Dictionary) -> bool: return action["archive_index"] == 1480))
	assert(viewer.load_body(path, 322)["ok"])
	assert(viewer.animation_entries.any(func(action: Dictionary) -> bool: return action["archive_index"] == 1481))
	assert(viewer.load_body(path, 426)["ok"])
	assert(viewer.animation_entries.any(func(action: Dictionary) -> bool: return action["archive_index"] == 1889))
	assert(viewer.load_body(path, 427)["ok"])
	assert(viewer.animation_entries.any(func(action: Dictionary) -> bool: return action["archive_index"] == 1892))
	assert(viewer.select_animation(1892)["ok"] and viewer.body["groups"].size() == 30)
	var undergass_export := LBA1GLBExporter.build(viewer.export_input())
	assert(undergass_export["ok"] and undergass_export["variants"] == 3 and undergass_export["source_actions"] >= 10, "Undergass BODY #427 GLB must include all three forms")
	var undergass_state := GLTFState.new()
	assert(GLTFDocument.new().append_from_buffer(undergass_export["bytes"], "", undergass_state) == OK)
	assert(undergass_state.get_skins().size() == 3, "Undergass GLB must have three separate skins")
	assert(undergass_state.get_animations().size() >= undergass_export["source_actions"], "Undergass GLB is missing actions")
	var glb_bytes: PackedByteArray = undergass_export["bytes"]
	var gltf_json: Dictionary = JSON.parse_string(glb_bytes.slice(20, 20 + int(glb_bytes.decode_u32(12))).get_string_from_utf8())
	for clip_json in gltf_json["animations"]:
		var scale_targets := 0
		for channel in clip_json["channels"]:
			if channel["target"]["path"] == "scale":
				scale_targets += 1
		assert(scale_targets == 3, "Every undergass action must select exactly one of its three forms")
	assert(viewer.load_body(path, 399)["ok"])
	var fire_export := viewer.export_input()
	var exported_fire_atlas: PackedByteArray = fire_export["body"]["texture_atlas"]
	var visible_fire_pixels := 0
	for y in range(32, 64):
		for x in range(32, 64):
			visible_fire_pixels += int(exported_fire_atlas[y * 256 + x] != 0)
	assert(visible_fire_pixels > 100, "BODY #399 GLB must receive a visible fire frame")
	assert(LBA1GLBExporter.build(fire_export)["ok"])
	for spell_index in [457, 458]:
		var spell_loaded := viewer.load_body(path, spell_index)
		assert(spell_loaded["ok"] and LBA2_APPEARANCE.uses_spectral_preview(viewer.body))
		assert(viewer.character.get_node("Polygons").material_override.next_pass != null, "Spell %d must fill chroma holes" % spell_index)
		var spell_export := LBA1GLBExporter.build(viewer.export_input())
		assert(spell_export["ok"], "Spell %d GLB export failed" % spell_index)
	assert(viewer.load_body(path, 112)["ok"])
	var spectral_export := LBA1GLBExporter.build(viewer.export_input())
	assert(spectral_export["ok"])
	var spectral_state := GLTFState.new()
	assert(document.append_from_buffer(spectral_export["bytes"], "", spectral_state) == OK)
	var spectral_material_modes := []
	for surface in spectral_state.get_materials():
		if surface is BaseMaterial3D:
			spectral_material_modes.append(surface.transparency)
	assert(spectral_material_modes.any(func(mode: int) -> bool: return mode != BaseMaterial3D.TRANSPARENCY_DISABLED and mode != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR), "Spectral alpha was lost from GLB")
	var fireball_loaded := viewer.load_body(path, 306)
	assert(fireball_loaded["ok"] and LBA2_APPEARANCE.uses_fireball_glow(viewer.body))
	assert(viewer.character.get_node("Polygons").material_override.shader.resource_path.ends_with("lba2_fireball.gdshader"))
	var fireball_export := LBA1GLBExporter.build(viewer.export_input())
	assert(fireball_export["ok"])
	var fireball_state := GLTFState.new()
	assert(document.append_from_buffer(fireball_export["bytes"], "", fireball_state) == OK)
	print("Fireball GLB material modes: ", fireball_state.get_materials().map(func(surface: Material) -> String: return "%s/%s" % [surface.transparency, surface.albedo_color] if surface is BaseMaterial3D else str(surface)))
	assert(fireball_state.get_materials().any(func(surface: Material) -> bool: return surface is BaseMaterial3D and surface.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and surface.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR))
	var zero_duration_loaded := viewer.load_body(path, 394)
	assert(zero_duration_loaded["ok"])
	var zero_duration_selected := viewer.select_animation(1738)
	assert(zero_duration_selected["ok"], str(zero_duration_selected.get("error", "")))
	assert(viewer.animation["frames"].any(func(frame: Dictionary) -> bool: return frame["source_duration_ticks"] == 0 and frame["duration_ticks"] == 1))
	var valid_bodies := 0
	var failures := []
	var mostly_chroma_bodies := []
	for body_index in range(first["entry_count"]):
		var entry := HQRReader.read_entry(path.path_join("BODY.HQR"), body_index)
		if not entry["ok"]:
			failures.append("%d archive: %s" % [body_index, entry["error"]])
			continue
		var model: Dictionary = BODY_DECODER.decode(entry["data"])
		if model["ok"]:
			valid_bodies += 1
			var chroma_faces: int = model["polygons"].filter(func(polygon: Dictionary) -> bool: return polygon["render_type"] in [12, 13, 14, 15, 20, 21, 22, 23]).size()
			if chroma_faces > 0 and float(chroma_faces) / float(model["polygons"].size()) > 0.8:
				mostly_chroma_bodies.append("%d:%x:%d/%d" % [body_index, int(entry["data"].decode_u32(0)), model["lines"].size(), model["spheres"].size()])
		else:
			failures.append("%d body: %s" % [body_index, model["error"]])
	print("LBA2 BODY #0: %d points, %d polygons, %d groups" % [decoded["points"].size(), decoded["polygons"].size(), decoded["groups"].size()])
	print("LBA2 FILE3D: %d files, %d BODY #0 animations" % [associations["file_count"], associations["animations"].size()])
	print("LBA2 viewer loaded and selected animation")
	print("LBA2 GLB: %d bytes, %d actions" % [exported["bytes"].size(), exported["source_actions"]])
	print("LBA2 body sweep: %d/%d decoded; failures: %s" % [valid_bodies, first["entry_count"], str(failures.slice(0, 20))])
	print("Mostly chroma-key bodies: ", mostly_chroma_bodies)
	quit()
