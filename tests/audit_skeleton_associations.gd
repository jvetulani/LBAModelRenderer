extends SceneTree

# Lists every FILE3D BODY/ANIM pairing. A shorter action can legitimately
# leave some bones at rest; group-count differences are audit signals only.
const LBA2_BODY = preload("res://scripts/import/lba2_body_decoder.gd")
const LBA2_FILE3D = preload("res://scripts/import/lba2_file3d_decoder.gd")


func _initialize() -> void:
	var sources := {}
	var report_path := ""
	for argument in OS.get_cmdline_user_args():
		for key in ["lba1", "lba2", "demo"]:
			if argument.begins_with("--%s=" % key):
				sources[key] = argument.trim_prefix("--%s=" % key)
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if sources.is_empty():
		push_error("Pass --lba1, --lba2, or --demo")
		quit(1)
		return
	var lines := PackedStringArray(["game\tfile3d\tbody\tbody_groups\tanim\tanim_groups\tdelta\tclassification\treview\tcompatible_variants"])
	var failed := false
	for game in ["lba1", "lba2", "demo"]:
		if not sources.has(game):
			continue
		var summary := _audit_game(game, sources[game], lines)
		if not summary["ok"]:
			push_error(summary["error"])
			failed = true
			continue
		print("%s: %d unique pairings, %d exact, %d short, %d long, %d review (%d with alternate, %d unresolved), %d shared ANIMs, max missing %d, max extra %d" % [game, summary["pairs"], summary["exact"], summary["short"], summary["long"], summary["review"], summary["review_alternate"], summary["review_unresolved"], summary["shared"], summary["max_missing"], summary["max_extra"]])
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write %s" % report_path)
			failed = true
		else:
			file.store_string("\n".join(lines) + "\n")
			file.close()
			print("Wrote %s" % report_path)
	quit(1 if failed else 0)


func _audit_game(game: String, source: String, lines: PackedStringArray) -> Dictionary:
	var streams := []
	if game == "lba2":
		var file3d := HQRReader.read_entry(source.path_join("RESS.HQR"), 44)
		if not file3d["ok"]:
			return file3d
		var data: PackedByteArray = file3d["data"]
		var file_count := int(data.decode_u32(0)) / 4
		if int(data.decode_u32((file_count - 1) * 4)) == data.size():
			file_count -= 1
		for file_index in range(file_count):
			var begin := int(data.decode_u32(file_index * 4))
			var end := data.size() if file_index + 1 == file_count else int(data.decode_u32((file_index + 1) * 4))
			var stream := LBA2_FILE3D.decode_entry(data.slice(begin, end))
			if not stream["ok"]:
				return {"ok": false, "error": "LBA2 FILE3D #%d: %s" % [file_index, stream["error"]]}
			streams.append(stream)
	else:
		var first := HQRReader.read_entry(source.path_join("FILE3D.HQR"), 0)
		if not first["ok"]:
			return first
		for file_index in range(first["entry_count"]):
			var entry := first if file_index == 0 else HQRReader.read_entry(source.path_join("FILE3D.HQR"), file_index)
			if not entry["ok"]:
				continue
			var stream: Dictionary = LBA1File3DDecoder.decode(entry["data"]) if game == "lba1" else LBA2_FILE3D.decode_entry(entry["data"])
			if not stream["ok"]:
				return {"ok": false, "error": "%s FILE3D #%d: %s" % [game, file_index, stream["error"]]}
			streams.append(stream)
	var body_counts := {}
	var anim_counts := {}
	var pair_seen := {}
	var anim_owners := {}
	var stats := {"ok": true, "pairs": 0, "exact": 0, "short": 0, "long": 0, "review": 0, "review_alternate": 0, "review_unresolved": 0, "shared": 0, "max_missing": 0, "max_extra": 0}
	for file_index in range(streams.size()):
		var stream: Dictionary = streams[file_index]
		var stream_body_counts := {}
		for body_record in stream["bodies"]:
			var body_index: int = body_record["archive_index"]
			if not body_counts.has(body_index):
				var body_entry := HQRReader.read_entry(source.path_join("BODY.HQR"), body_index)
				if not body_entry["ok"]:
					continue
				var body: Dictionary = LBA1BodyDecoder.decode(body_entry["data"]) if game == "lba1" else (LBA2_BODY.decode(body_entry["data"]) if game == "lba2" else LBA1BodyDecoder.decode_compact_groups(body_entry["data"]))
				if not body["ok"]:
					continue
				body_counts[body_index] = body["groups"].size()
			stream_body_counts[body_index] = body_counts[body_index]
		for body_index in stream_body_counts:
			for anim_record in stream["animations"]:
				var anim_index: int = anim_record["archive_index"]
				var pair_key := "%d/%d" % [body_index, anim_index]
				if pair_seen.has(pair_key):
					continue
				pair_seen[pair_key] = true
				if not anim_counts.has(anim_index):
					var anim_entry := HQRReader.read_entry(source.path_join("ANIM.HQR"), anim_index)
					if not anim_entry["ok"]:
						continue
					var anim := LBA1AnimationDecoder.decode(anim_entry["data"])
					if not anim["ok"]:
						continue
					anim_counts[anim_index] = anim["group_count"]
				if not anim_owners.has(anim_index):
					anim_owners[anim_index] = {}
				anim_owners[anim_index][body_index] = true
				var delta: int = body_counts[body_index] - anim_counts[anim_index]
				var classification := "exact" if delta == 0 else ("short" if delta > 0 else "long")
				stats[classification] += 1
				stats["pairs"] += 1
				stats["max_missing"] = maxi(stats["max_missing"], delta)
				stats["max_extra"] = maxi(stats["max_extra"], -delta)
				var review: bool = absi(delta) > maxi(4, ceili(float(body_counts[body_index]) * 0.25))
				if review:
					stats["review"] += 1
					var compatible := PackedStringArray()
					for variant_index in stream_body_counts:
						if variant_index != body_index and stream_body_counts[variant_index] == anim_counts[anim_index]:
							compatible.append(str(variant_index))
					stats["review_alternate" if not compatible.is_empty() else "review_unresolved"] += 1
					lines.append("%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%s" % [game, file_index, body_index, body_counts[body_index], anim_index, anim_counts[anim_index], delta, classification, int(review), ",".join(compatible)])
	for owners in anim_owners.values():
		if owners.size() > 1:
			stats["shared"] += 1
	return stats
