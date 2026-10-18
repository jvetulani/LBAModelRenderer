extends SceneTree

const SOURCES := [
	["LBA1", "/home/asia/Games/LBAgog", 1024.0],
	["LBA2", "/home/asia/Games/LBA2gog", 4096.0],
	["LBA2-96", "/home/asia/Projekty/LBA/LBAModelVIewer/LBA2-96", 4096.0],
]

func _initialize() -> void:
	var viewer := CharacterViewer.new()
	root.add_child(viewer)
	for source in SOURCES:
		var loaded := viewer.load_body(source[1], 0)
		assert(loaded["ok"], "%s BODY #0 failed" % source[0])
		for action_index in [3, 4]:
			var action := viewer.animation_entries.filter(func(item: Dictionary) -> bool: return item["archive_index"] == action_index)
			assert(action.size() == 1, "%s turn action #%d is missing" % [source[0], action_index])
			assert(viewer.select_animation(action_index)["ok"])
			var rest_pose := CharacterPose.sample(viewer.body, viewer.animation, 0, 0, 1.0, source[2])
			var turned_pose := CharacterPose.sample(viewer.body, viewer.animation, 2, 2, 1.0, source[2])
			var root: Dictionary = viewer.body["groups"][0]
			for point_index in range(root["first"], root["first"] + root["count"]):
				assert(rest_pose["points"][point_index].is_equal_approx(turned_pose["points"][point_index]), "%s turn action translated the root group" % source[0])
			assert(absf(turned_pose["master_rotation"].y) > 0.1, "%s turn action lost master yaw" % source[0])
			viewer.scrub_to(2)
			assert(absf(viewer.character.rotation.y) > 0.1, "%s viewer did not rotate the actor" % source[0])
			assert(signf(viewer.character.rotation.y) == (1.0 if action_index == 3 else -1.0), "%s turn action has the wrong yaw direction" % source[0])
			var skeleton := Skeleton3D.new()
			skeleton.add_bone("Group_00")
			var frames := PackedInt32Array([0, 1, 2, 3])
			var exported := LBA1GLBExporter._make_animation(skeleton, viewer.animation, frames, TAU / source[2], LBA1AnimationDecoder.ticks_per_second(source[0]))
			var position_track := 1
			assert(exported.track_get_key_value(position_track, 0).is_equal_approx(exported.track_get_key_value(position_track, 2)), "%s GLB root rose during turn" % source[0])
			assert(exported.track_get_key_value(0, 0).angle_to(exported.track_get_key_value(0, 2)) > 0.1, "%s GLB root did not rotate" % source[0])
			print("%s %s: %.1f degrees; root height fixed in viewer and GLB" % [source[0], action[0]["name"], rad_to_deg(viewer.character.rotation.y)])
			skeleton.free()
	quit()
