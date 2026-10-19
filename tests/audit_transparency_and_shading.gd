extends SceneTree

const LBA1_MODES := preload("res://scripts/render/lba1_face_modes.gd")
const LBA2_APPEARANCE := preload("res://scripts/render/lba2_appearance.gd")


func _init() -> void:
	for source in [
		{"game": "LBA1", "path": "/home/asia/Games/LBAgog/BODY.HQR"},
		{"game": "LBA2-96", "path": "/home/asia/Projekty/LBA/LBAModelVIewer/LBA2-96/BODY.HQR"},
		{"game": "LBA2", "path": "/home/asia/Games/LBA2gog/BODY.HQR"},
	]:
		var first := HQRReader.read_entry(source.path, 0)
		assert(first["ok"], "Cannot read %s" % source.path)
		var decoded := 0
		var transparent_bodies := 0
		var ramp_crossing_bodies := []
		for body_index in range(first["entry_count"]):
			var entry := HQRReader.read_entry(source.path, body_index)
			if not entry["ok"] or entry["data"].is_empty():
				continue
			var body: Dictionary
			match source.game:
				"LBA2": body = LBA2BodyDecoder.decode(entry["data"])
				"LBA2-96": body = LBA1BodyDecoder.decode_compact_groups(entry["data"])
				_: body = LBA1BodyDecoder.decode(entry["data"])
			assert(body["ok"], "%s BODY #%d failed to decode" % [source.game, body_index])
			body["game"] = source.game
			decoded += 1
			var transparent_faces := 0
			var ramp_crossing_faces := 0
			for polygon in body["polygons"]:
				var kind: int = polygon["render_type"]
				var source_transparent: bool = kind in [2, 3] if source.game == "LBA2" else kind in [5, 6]
				if source_transparent:
					transparent_faces += 1
					var covered: bool = LBA1_MODES.is_transparent(body, polygon) if source.game == "LBA1" else LBA2_APPEARANCE.is_translucent_face(body, polygon)
					assert(covered, "%s BODY #%d has opaque source-transparent mode %d" % [source.game, body_index, kind])
				if source.game != "LBA2" or kind not in [1, 4, 5] or int(polygon.get("texture_handle", -1)) >= 0 or int(polygon["palette_index"]) % 16 < 14:
					continue
				for normal_index in polygon["normals"]:
					if normal_index >= 0:
						ramp_crossing_faces += 1
						break
			if transparent_faces > 0:
				transparent_bodies += 1
				assert(LBA1_MODES.has_transparent_faces(body) if source.game == "LBA1" else LBA2_APPEARANCE.has_translucent_faces(body))
			if ramp_crossing_faces > 0:
				ramp_crossing_bodies.append({"body": body_index, "faces": ramp_crossing_faces})
		ramp_crossing_bodies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.faces > b.faces)
		print("%s: %d decoded; %d source-transparent bodies covered; %d direct-shade ramp-crossing bodies" % [source.game, decoded, transparent_bodies, ramp_crossing_bodies.size()])
		if not ramp_crossing_bodies.is_empty():
			print("Largest direct-shade ramp crossings: ", ramp_crossing_bodies.slice(0, mini(15, ramp_crossing_bodies.size())))
	quit()
