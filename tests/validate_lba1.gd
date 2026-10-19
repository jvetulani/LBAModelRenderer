extends SceneTree

const LBA1_FACE_MODES := preload("res://scripts/render/lba1_face_modes.gd")


func _init() -> void:
	var lba1_dir := ""
	var lba2_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			lba1_dir = argument.trim_prefix("--lba1=")
		elif argument.begins_with("--lba2="):
			lba2_dir = argument.trim_prefix("--lba2=")
	if lba1_dir.is_empty() or lba2_dir.is_empty():
		_fail("Pass --lba1=PATH and --lba2=PATH after --")
		return

	var body_entry := HQRReader.read_entry(lba1_dir.path_join("BODY.HQR"), 0)
	if not body_entry["ok"]:
		_fail(body_entry["error"])
		return
	if body_entry["mode"] != 1 or body_entry["unpacked_size"] != 6660:
		_fail("Unexpected LBA1 BODY.HQR #0 metadata")
		return
	var body: Dictionary = LBA1BodyDecoder.decode(body_entry["data"])
	if not body["ok"]:
		_fail(body["error"])
		return
	if body["points"].size() != 161 or body["polygons"].size() != 224 or body["lines"].size() != 19 or body["spheres"].size() != 5:
		_fail("LBA1 BODY.HQR #0 geometry counts differ from the verified fixture")
		return
	if body["points"][2] != Vector3(0, 533, 33) or body["pose_points"][2] != Vector3(0, 566, 33) or body["pose_points"][3] != Vector3(0, 599, 33):
		_fail("LBA1 group pivots did not produce the expected static pose")
		return
	if body["normals"][0] != Vector3(0, 4, 63) or body["normal_divisors"][0] != 315:
		_fail("LBA1 source normal and divisor were decoded incorrectly")
		return
	var dither_polygon_count := 0
	for polygon in body["polygons"]:
		if polygon["render_type"] == 10:
			dither_polygon_count += 1
	if dither_polygon_count != 2:
		_fail("LBA1 BODY.HQR #0 dither material count differs from the source fixture")
		return
	var transparent_bodies := {}
	var mode_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0}
	for body_index in range(132):
		var candidate_entry := HQRReader.read_entry(lba1_dir.path_join("BODY.HQR"), body_index)
		if not candidate_entry["ok"]:
			continue
		var candidate: Dictionary = LBA1BodyDecoder.decode(candidate_entry["data"])
		if not candidate["ok"]:
			_fail("Could not inspect LBA1 BODY.HQR #%d" % body_index)
			return
		for polygon in candidate["polygons"]:
			var kind: int = polygon["render_type"]
			if kind in [1, 2, 3, 4]:
				mode_counts[kind] += 1
			if kind in [5, 6]:
				mode_counts[kind] += 1
				transparent_bodies[body_index] = true
				if not LBA1_FACE_MODES.is_transparent(candidate, polygon):
					_fail("Source transparent face was not classified")
					return
	if mode_counts[5] != 15 or mode_counts[6] != 14 or transparent_bodies.size() != 9 or not transparent_bodies.has(130) or transparent_bodies.has(54):
		_fail("LBA1 transparency face audit differs from the archive")
		return
	var digger_entry := HQRReader.read_entry(lba1_dir.path_join("BODY.HQR"), 130)
	var digger: Dictionary = LBA1BodyDecoder.decode(digger_entry["data"])
	var digger_node := CharacterMeshBuilder.build_static_pose(digger, HQRReader.read_entry(lba1_dir.path_join("RESS.HQR"), 0)["data"])
	if not digger_node.has_node("LBA1TransparentPolygons") or digger_node.get_node("LBA1TransparentPolygons").mesh.surface_get_array_len(0) == 0:
		digger_node.free()
		_fail("Digger glass faces were not split into a transparent mesh")
		return
	digger_node.free()
	var boat_entry := HQRReader.read_entry(lba1_dir.path_join("BODY.HQR"), 54)
	var boat: Dictionary = LBA1BodyDecoder.decode(boat_entry["data"])
	var boat_copper_faces: int = boat["polygons"].filter(func(polygon: Dictionary) -> bool: return int(polygon["render_type"]) == 2).size()
	if boat_copper_faces != 3 or mode_counts[2] != 43:
		_fail("LBA1 copper window face audit differs from the archive")
		return
	var ferry_entry := HQRReader.read_entry(lba1_dir.path_join("BODY.HQR"), 51)
	var ferry: Dictionary = LBA1BodyDecoder.decode(ferry_entry["data"])
	var ferry_bopper_faces: int = ferry["polygons"].filter(func(polygon: Dictionary) -> bool: return int(polygon["render_type"]) == 3).size()
	if ferry_bopper_faces != 5 or mode_counts[3] != 5:
		_fail("LBA1 ferry Bopper face audit differs from the archive")
		return
	if mode_counts[1] != 6 or mode_counts[4] != 8:
		_fail("LBA1 Tele or Marble face audit differs from the archive")
		return

	var palette_entry := HQRReader.read_entry(lba1_dir.path_join("RESS.HQR"), 0)
	if not palette_entry["ok"] or palette_entry["data"].size() != 768:
		_fail("LBA1 palette entry is missing or invalid")
		return
	var shadow_entry := HQRReader.read_entry(lba1_dir.path_join("RESS.HQR"), 4)
	if not shadow_entry["ok"]:
		_fail("LBA1 shadow graphic bank is missing")
		return
	var shadow := LBA1GraphDecoder.decode_sprite(shadow_entry["data"], 2)
	if not shadow["ok"] or shadow["width"] != 27 or shadow["height"] != 17:
		_fail("LBA1 actor shadow sprite did not decode")
		return
	var covered := 0
	for index in range(shadow["coverage"].size()):
		if shadow["coverage"][index] != 0:
			covered += 1
			if shadow["pixels"][index] != 16:
				_fail("LBA1 shadow sprite has an unexpected palette index")
				return
	if covered != 182:
		_fail("LBA1 shadow checker pattern changed")
		return
	var second_game := HQRReader.read_entry(lba2_dir.path_join("BODY.HQR"), 0)
	if not second_game["ok"] or second_game["mode"] != 2 or second_game["data"].size() != 7804:
		_fail("LBA2 compressed HQR entry did not decode")
		return
	var second_body: PackedByteArray = second_game["data"]
	if second_body.decode_u16(4) != 96 or second_body.decode_u32(32) != 19 or second_body.decode_u32(40) != 193 or second_body.decode_u32(64) != 281:
		_fail("LBA2 body header does not match its offset-based source layout")
		return
	var cut_short: PackedByteArray = body_entry["data"].slice(0, 100)
	if LBA1BodyDecoder.decode(cut_short)["ok"]:
		_fail("Truncated body was accepted")
		return
	if HQRReader.read_entry(lba1_dir.path_join("BODY.HQR"), 9999)["ok"]:
		_fail("Out-of-range HQR entry was accepted")
		return
	if HQRReader.read_entry(lba1_dir.path_join("BODY.HQR"), 132)["ok"]:
		_fail("The BODY.HQR end-of-file sentinel was accepted as an entry")
		return
	var corrupt_path := OS.get_user_data_dir().path_join("invalid_backref.hqr")
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	if corrupt_file == null:
		_fail("Could not create the malformed HQR fixture")
		return
	corrupt_file.store_buffer(PackedByteArray([
		4, 0, 0, 0,  # Offset table size.
		4, 0, 0, 0,  # Entry 0 offset.
		3, 0, 0, 0,  # Unpacked size.
		1, 0, 0, 0,  # Packed size.
		1, 0,        # Compression mode 1.
		0,           # Back-reference flag without a token.
	]))
	corrupt_file.close()
	var accepted_corrupt: bool = HQRReader.read_entry(corrupt_path, 0)["ok"]
	DirAccess.remove_absolute(corrupt_path)
	if accepted_corrupt:
		_fail("Malformed compressed HQR stream was accepted")
		return

	print("PASS: LBA1 body 0, LBA1 palette, LBA2 HQR/body header, malformed inputs")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
