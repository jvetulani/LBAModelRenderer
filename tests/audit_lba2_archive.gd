extends SceneTree

func _init() -> void:
	var archive := "/home/asia/Games/LBA2gog/BODY.HQR"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--archive="):
			archive = argument.trim_prefix("--archive=")
	var first := HQRReader.read_entry(archive, 0)
	if not first["ok"]:
		push_error(first["error"])
		quit(1)
		return
	var totals := {"decoded": 0, "empty": 0, "transparent": 0, "trame": 0, "flagged": 0}
	for body_index in range(first["entry_count"]):
		var entry := first if body_index == 0 else HQRReader.read_entry(archive, body_index)
		if not entry["ok"] or entry["data"].is_empty():
			totals["empty"] += 1
			continue
		var body := LBA2BodyDecoder.decode(entry["data"])
		if not body["ok"]:
			push_error("BODY #%d: %s" % [body_index, body["error"]])
			continue
		totals["decoded"] += 1
		var flags: int = entry["data"].decode_u32(0)
		if (flags & (1 << 10)) != 0:
			totals["flagged"] += 1
		var transparent := 0
		var trame := 0
		var colors := {}
		for polygon in body["polygons"]:
			var kind: int = polygon["render_type"]
			if kind == 2 or kind == 3:
				if kind == 2:
					transparent += 1
				else:
					trame += 1
				var color: int = polygon["palette_index"]
				colors[color] = colors.get(color, 0) + 1
		if transparent > 0 or trame > 0:
			totals["transparent"] += transparent
			totals["trame"] += trame
			print("BODY ", body_index, " mode2=", transparent, " mode3=", trame, " colors=", colors, " flags=", flags)
	print("TOTALS ", totals)
	quit()
