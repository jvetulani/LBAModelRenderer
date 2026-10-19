extends SceneTree

# Measures every textured triangle in all supported BODY archives. A high
# anisotropy score is a review signal; some original assets use narrow strips.

func _initialize() -> void:
	var sources := [
		["LBA1", "/home/asia/Games/LBAgog/BODY.HQR"],
		["LBA2", "/home/asia/Games/LBA2gog/BODY.HQR"],
		["LBA2-96", "/home/asia/Projekty/LBA/LBAModelVIewer/LBA2-96/BODY.HQR"]
	]
	var output := "/tmp/lba-uv-audit.tsv"
	var effective := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			output = argument.trim_prefix("--report=")
		elif argument == "--effective":
			effective = true
	var out := FileAccess.open(output, FileAccess.WRITE)
	if out == null:
		push_error("Cannot write %s" % output)
		quit(1)
		return
	out.store_line("game\tbody\tface\ttriangle\ttexture\tanisotropy\tdensity\tarea3d\tareauv\tminuv\tmaxuv\tflagged\tuvs")
	for source in sources:
		var first := HQRReader.read_entry(source[1], 0)
		if not first.get("ok", false):
			print(source[0], " unavailable: ", first.get("error")); continue
		var bodies := 0; var triangles := 0; var flagged := 0; var texture_faces := 0; var decode_fail := 0
		var body_flags := {}
		for body_id in range(first["entry_count"]):
			var entry := first if body_id == 0 else HQRReader.read_entry(source[1], body_id)
			if not entry.get("ok", false):
				continue
			var body: Dictionary = LBA2BodyDecoder.decode(entry["data"]) if source[0] == "LBA2" else (LBA1BodyDecoder.decode_compact_groups(entry["data"]) if source[0] == "LBA2-96" else LBA1BodyDecoder.decode(entry["data"]))
			if not body.get("ok", false):
				decode_fail += 1; continue
			bodies += 1
			if effective and source[0] == "LBA2":
				body["appearance"] = LBA2ModelOverrides.for_retail_body(body_id)
				LBA2ModelOverrides.apply_geometry(body)
			var pts: PackedVector3Array = body["pose_points"]
			for face_id in range(body["polygons"].size()):
				var face: Dictionary = body["polygons"][face_id]
				if int(face.get("texture_handle", -1)) < 0:
					continue
				texture_faces += 1
				var ids: PackedInt32Array = face["points"]
				var uv: PackedVector2Array = face["texture_uvs"]
				for tri_id in range(1, ids.size() - 1):
					triangles += 1
					var v0: Vector3 = pts[ids[0]]; var v1: Vector3 = pts[ids[tri_id]]; var v2: Vector3 = pts[ids[tri_id + 1]]
					var e1 := v1 - v0; var e2 := v2 - v0
					var base: float = e1.length(); var area3d: float = e1.cross(e2).length() * 0.5
					if base < 1.0 or area3d < 1.0:
						continue
					var du1: Vector2 = uv[tri_id] - uv[0]; var du2: Vector2 = uv[tri_id + 1] - uv[0]
					var area_uv: float = absf(du1.cross(du2)) * 0.5
					var x2 := e2.dot(e1) / base
					var y2 := area3d * 2.0 / base
					var gu := Vector2(du1.x / base, (du2.x - du1.x * x2 / base) / y2)
					var gv := Vector2(du1.y / base, (du2.y - du1.y * x2 / base) / y2)
					var aa := gu.x * gu.x + gv.x * gv.x; var bb := gu.x * gu.y + gv.x * gv.y; var cc := gu.y * gu.y + gv.y * gv.y
					var spread := sqrt((aa - cc) * (aa - cc) + 4.0 * bb * bb)
					var major := sqrt(maxf((aa + cc + spread) * 0.5, 0.0))
					var minor := sqrt(maxf((aa + cc - spread) * 0.5, 0.0))
					var ratio := major / maxf(minor, 0.000001)
					var density := sqrt(area_uv / area3d)
					var minuv := minf(uv[0].x, minf(uv[tri_id].x, uv[tri_id + 1].x))
					var maxuv := maxf(uv[0].x, maxf(uv[tri_id].x, uv[tri_id + 1].x))
					var is_flagged := ratio >= 12.0 or density < 0.002
					if is_flagged:
						flagged += 1
						body_flags[body_id] = int(body_flags.get(body_id, 0)) + 1
					out.store_line("%s\t%d\t%d\t%d\t%d\t%.2f\t%.5f\t%.1f\t%.2f\t%.2f\t%.2f\t%d\t%s" % [source[0], body_id, face_id, tri_id-1, face["texture_handle"], ratio, density, area3d, area_uv, minuv, maxuv, int(is_flagged), str(uv)])
		if source[0] == "LBA2":
			print("LBA2 #381 flags: ", body_flags.get(381, 0))
		print("AUDIT ", source[0], " entries=", first["entry_count"], " decoded=", bodies, " textured_faces=", texture_faces, " triangles=", triangles, " flagged=", flagged, " affected_bodies=", body_flags.size(), " decode_fail=", decode_fail)
	out.close()
	print("Wrote ", output)
	quit()
