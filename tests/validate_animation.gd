extends SceneTree


func _init() -> void:
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba1="):
			source = argument.trim_prefix("--lba1=")
	if source.is_empty():
		_fail("Pass --lba1=PATH after --")
		return
	var file3d_entry := HQRReader.read_entry(source.path_join("FILE3D.HQR"), 11)
	if not file3d_entry["ok"]:
		_fail(file3d_entry["error"])
		return
	var file3d := LBA1File3DDecoder.decode(file3d_entry["data"])
	if not file3d["ok"] or file3d["bodies"].size() != 1 or file3d["bodies"][0]["archive_index"] != 17 or file3d["animations"].size() != 17:
		_fail("Grobo FILE3D association differs from source fixture")
		return
	if file3d["animations"][0]["archive_index"] != 108 or file3d["animations"][1]["archive_index"] != 109:
		_fail("Grobo idle/walk associations are wrong")
		return
	var body_entry := HQRReader.read_entry(source.path_join("BODY.HQR"), 17)
	var body := LBA1BodyDecoder.decode(body_entry["data"])
	if not body["ok"] or body["group_count"] != 21:
		_fail("Grobo body groups did not decode")
		return
	var anim_entry := HQRReader.read_entry(source.path_join("ANIM.HQR"), 109)
	var animation := LBA1AnimationDecoder.decode(anim_entry["data"])
	if not animation["ok"] or animation["frame_count"] != 5 or animation["group_count"] != 21 or animation["loop_frame"] != 1:
		_fail("Grobo walk ANIM.HQR entry did not decode")
		return
	if animation["frames"][0]["duration_ticks"] != 13 or animation["frames"][2]["duration_ticks"] != 10:
		_fail("Grobo walk keyframe timing changed")
		return
	var pose_0 := LBA1Pose.sample(body, animation, 0, 0, 1.0)
	var pose_2 := LBA1Pose.sample(body, animation, 2, 2, 1.0)
	var moved_points := 0
	for index in range(body["points"].size()):
		if pose_0["points"][index].distance_to(pose_2["points"][index]) > 1.0:
			moved_points += 1
	if moved_points < 20:
		_fail("Grobo walk pose did not move its articulated points")
		return
	var half_pose := LBA1Pose.sample(body, animation, 0, 2, 0.5)
	var interpolated_points := 0
	for index in range(body["points"].size()):
		var half_point: Vector3 = half_pose["points"][index]
		if half_point.distance_to(pose_0["points"][index]) > 0.5 and half_point.distance_to(pose_2["points"][index]) > 0.5:
			interpolated_points += 1
	if interpolated_points < 20:
		_fail("Grobo walk interpolation did not create an intermediate pose")
		return
	if LBA1AnimationDecoder.decode(anim_entry["data"].slice(0, 50))["ok"]:
		_fail("Truncated animation was accepted")
		return
	var viewer := CharacterViewer.new()
	viewer.stand_position = Vector3(0.0, -0.46, 0.0)
	root.add_child(viewer)
	var loaded := viewer.load_body(source, 17)
	if not loaded["ok"] or loaded["animations"].size() != 12 or not loaded["shadow_loaded"]:
		_fail("Grobo viewer did not load 12 distinct clips and the source shadow")
		return
	if not viewer.select_animation(109)["ok"]:
		_fail("Grobo walk was not selectable")
		return
	viewer._process(0.25)
	viewer._process(0.01)
	if viewer.get("_current_frame") != 1:
		_fail("Walk playback did not advance after the 13-tick destination duration")
		return
	viewer.set_playing(false)
	viewer.scrub_to(2)
	if viewer.get("_current_frame") != 2:
		_fail("Walk frame scrubbing did not reach keyframe 2")
		return
	var one_shot_entry := HQRReader.read_entry(source.path_join("ANIM.HQR"), 178)
	var one_shot := LBA1AnimationDecoder.decode(one_shot_entry["data"])
	if not one_shot["ok"] or one_shot["frame_count"] != 2 or one_shot["loop_frame"] != 2:
		_fail("ANIM #178 one-shot loop marker did not decode")
		return
	if not viewer.load_body(source, 30)["ok"] or not viewer.select_animation(178)["ok"]:
		_fail("BODY #30 could not select its one-shot action")
		return
	for step in range(100):
		viewer._process(0.25)
	if viewer.playing or viewer.get("_current_frame") != 1:
		_fail("One-shot action did not stop on its last frame")
		return
	viewer.set_playing(true)
	if not viewer.playing or viewer.get("_current_frame") != 0:
		_fail("One-shot action did not restart after Play")
		return
	print("PASS: Grobo animation and BODY #30 one-shot playback")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
