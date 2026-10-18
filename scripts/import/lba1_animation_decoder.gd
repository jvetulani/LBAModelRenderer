class_name LBA1AnimationDecoder
extends RefCounted

# P_ANIM.ASM SetAnimObjet and SetInterAnimObjet: 8-byte header and
# (8-byte frame header + 8 bytes per group) repeated for every keyframe.


static func ticks_per_second(game: String) -> float:
	# The 1996 demo kept the earlier 50 Hz duration units even though its
	# transforms use LBA2 angles. Retail LBA2 stores millisecond durations.
	return 1000.0 if game == "LBA2" else 50.0


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8:
		return _error("Animation header is truncated")
	var frame_count := int(bytes.decode_u16(0))
	var group_count := int(bytes.decode_u16(2))
	var loop_frame := int(bytes.decode_u16(4))
	if frame_count == 0 or group_count == 0 or group_count > 500 or frame_count > 2000:
		return _error("Animation has an invalid frame or group count")
	# A loop index equal to the frame count marks a one-shot action.
	if loop_frame > frame_count:
		return _error("Animation loop frame is outside its keyframes")
	var frame_size := 8 + group_count * 8
	if bytes.size() != 8 + frame_count * frame_size:
		return _error("Animation keyframe table has an invalid size")
	var frames := []
	for frame_index in range(frame_count):
		var at := 8 + frame_index * frame_size
		var source_duration := int(bytes.decode_u16(at))
		# LBA2 uses zero-length keyframes as instantaneous pose changes.
		# Keep the keyframe and give interpolation/export a minimal interval.
		var duration := maxi(source_duration, 1)
		var transforms := []
		for group_index in range(group_count):
			var group_at := at + 8 + group_index * 8
			var transform_type := int(bytes.decode_u16(group_at))
			# LBA2's renderer tests bit 0 of GroupType; 3 is translation too.
			if transform_type > 3:
				return _error("Animation frame %d group %d has unsupported transform %d" % [frame_index, group_index, transform_type])
			transforms.append({
				"type": transform_type & 1,
				"values": Vector3i(bytes.decode_s16(group_at + 2), bytes.decode_s16(group_at + 4), bytes.decode_s16(group_at + 6)),
			})
		frames.append({
			"duration_ticks": duration,
			"source_duration_ticks": source_duration,
			"root_step": Vector3i(bytes.decode_s16(at + 2), bytes.decode_s16(at + 4), bytes.decode_s16(at + 6)),
			"transforms": transforms,
		})
	return {"ok": true, "frame_count": frame_count, "group_count": group_count, "loop_frame": loop_frame, "frames": frames}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
