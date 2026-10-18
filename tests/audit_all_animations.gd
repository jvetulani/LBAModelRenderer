extends SceneTree

func _initialize() -> void:
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			source = argument.trim_prefix("--source=")
	if source.is_empty():
		push_error("Pass --source=GAME_FOLDER")
		quit(1)
		return
	var first := HQRReader.read_entry(source.path_join("BODY.HQR"), 0)
	if not first["ok"]:
		push_error(first["error"])
		quit(1)
		return
	var viewer := CharacterViewer.new()
	root.add_child(viewer)
	var action_count := 0
	var short_actions := 0
	var sampled_frames := 0
	var failures := []
	for body_index in range(first["entry_count"]):
		var loaded := viewer.load_body(source, body_index)
		if not loaded["ok"]:
			failures.append("BODY #%d: %s" % [body_index, loaded["error"]])
			continue
		var angle_units := 1024.0 if viewer.game == "LBA1" else 4096.0
		for item in viewer.animation_entries:
			var entry := HQRReader.read_entry(source.path_join("ANIM.HQR"), item["archive_index"])
			if not entry["ok"]:
				failures.append("BODY #%d ANIM #%d: %s" % [body_index, item["archive_index"], entry["error"]])
				continue
			var animation := LBA1AnimationDecoder.decode(entry["data"])
			if not animation["ok"]:
				failures.append("BODY #%d ANIM #%d: %s" % [body_index, item["archive_index"], animation["error"]])
				continue
			action_count += 1
			if animation["group_count"] < viewer.body["groups"].size():
				short_actions += 1
			for frame_index in [0, int(animation["frame_count"] / 2), animation["frame_count"] - 1]:
				var pose := CharacterPose.sample(viewer.body, animation, frame_index, frame_index, 1.0, angle_units)
				var points: PackedVector3Array = pose["points"]
				if points.size() != viewer.body["points"].size():
					failures.append("BODY #%d ANIM #%d frame %d: point count changed" % [body_index, item["archive_index"], frame_index])
					continue
				for point in points:
					if not point.is_finite():
						failures.append("BODY #%d ANIM #%d frame %d: non-finite point" % [body_index, item["archive_index"], frame_index])
						break
				if not (pose["master_rotation"] as Vector3).is_finite():
					failures.append("BODY #%d ANIM #%d frame %d: non-finite master rotation" % [body_index, item["archive_index"], frame_index])
				sampled_frames += 1
		if body_index % 100 == 0:
			print("Sampled BODY %d/%d: %d actions" % [body_index + 1, first["entry_count"], action_count])
	print("Animation audit %s: %d bodies, %d associated actions (%d with fewer groups), %d poses, %d failures" % [viewer.game, first["entry_count"], action_count, short_actions, sampled_frames, failures.size()])
	if not failures.is_empty():
		print("Failures: ", failures.slice(0, 20))
	quit(1 if not failures.is_empty() else 0)
