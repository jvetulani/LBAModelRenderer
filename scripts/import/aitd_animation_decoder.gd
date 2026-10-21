class_name AITDAnimationDecoder
extends RefCounted

# FITD's createAnimationFromPtr: four-byte header, then an eight-byte frame
# header and eight (AITD1) or sixteen (AITD2/3) bytes per group.
const COORDINATE_SCALE := 0.5


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4:
		return {"ok": false, "error": "AITD animation header is truncated"}
	var frame_count := int(bytes.decode_u16(0))
	var group_count := int(bytes.decode_u16(2))
	if frame_count < 1 or frame_count > 2000 or group_count < 1 or group_count > 500:
		return {"ok": false, "error": "AITD animation counts are invalid"}
	var stride := 8
	if bytes.size() == 4 + frame_count * (8 + group_count * 16):
		stride = 16
	elif bytes.size() != 4 + frame_count * (8 + group_count * 8):
		return {"ok": false, "error": "AITD animation frame table has an invalid size"}
	var frames := []
	for frame_index in range(frame_count):
		var at := 4 + frame_index * (8 + group_count * stride)
		var transforms := []
		for group_index in range(group_count):
			var group_at := at + 8 + group_index * stride
			var kind := int(bytes.decode_s16(group_at))
			if kind not in [0, 1, 2]:
				return {"ok": false, "error": "AITD animation group transform is unsupported"}
			var transform := {"type": kind, "values": Vector3i(bytes.decode_s16(group_at + 2), bytes.decode_s16(group_at + 4), bytes.decode_s16(group_at + 6))}
			if stride == 16:
				transform["rotation"] = Vector3i(bytes.decode_s16(group_at + 8), bytes.decode_s16(group_at + 10), bytes.decode_s16(group_at + 12))
			transforms.append(transform)
		frames.append({
			"duration_ticks": maxi(1, int(bytes.decode_u16(at))),
			"source_duration_ticks": int(bytes.decode_u16(at)),
			"root_step": Vector3(-bytes.decode_s16(at + 2), -bytes.decode_s16(at + 4), -bytes.decode_s16(at + 6)) * COORDINATE_SCALE,
			"transforms": transforms,
		})
	return {"ok": true, "frame_count": frame_count, "group_count": group_count, "loop_frame": 0, "frames": frames}
