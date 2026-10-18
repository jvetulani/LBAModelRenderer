class_name LBA2File3DDecoder
extends RefCounted

# LBA2 keeps its FILE3D table in RESS.HQR entry 44. Each offset selects a
# terminated command stream. F_BODY uses an 8-bit generic ID; F_ANIM uses 16.


static func animations_for_body(bytes: PackedByteArray, body_index: int) -> Dictionary:
	if bytes.size() < 4:
		return _error("LBA2 FILE3D table is truncated")
	var table_size := int(bytes.decode_u32(0))
	if table_size < 4 or table_size % 4 != 0 or table_size > bytes.size():
		return _error("LBA2 FILE3D offsets are invalid")
	var file_count := table_size / 4
	# Retail archives may end the offset table with an EOF sentinel.
	if int(bytes.decode_u32((file_count - 1) * 4)) == bytes.size():
		file_count -= 1
	var found := []
	var seen := {}
	for file_index in range(file_count):
		var begin := int(bytes.decode_u32(file_index * 4))
		var end := bytes.size() if file_index + 1 == file_count else int(bytes.decode_u32((file_index + 1) * 4))
		if begin < table_size or end < begin or end > bytes.size():
			return _error("LBA2 FILE3D entry %d has invalid bounds" % file_index)
		var decoded := _decode_stream(bytes, begin, end)
		if not decoded["ok"]:
			return _error("LBA2 FILE3D entry %d: %s" % [file_index, decoded["error"]])
		var owns_body := false
		for body in decoded["bodies"]:
			if body["archive_index"] == body_index:
				owns_body = true
				break
		if not owns_body:
			continue
		for animation in decoded["animations"]:
			var archive_index: int = animation["archive_index"]
			if seen.has(archive_index):
				continue
			seen[archive_index] = true
			found.append({"archive_index": archive_index, "generic_id": animation["generic_id"], "file3d_index": file_index, "name": LBA1File3DDecoder.animation_name(animation["generic_id"])})
	return {"ok": true, "animations": found, "file_count": file_count}


static func decode_entry(bytes: PackedByteArray) -> Dictionary:
	# The 1996 demo stores one command stream per FILE3D.HQR entry, instead
	# of the offset table embedded in retail RESS.HQR entry 44.
	return _decode_stream(bytes, 0, bytes.size())


static func _decode_stream(bytes: PackedByteArray, begin: int, end: int) -> Dictionary:
	var at := begin
	var bodies := []
	var animations := []
	while at < end:
		var command := int(bytes[at])
		if command == 255:
			return {"ok": true, "bodies": bodies, "animations": animations}
		var generic_size := 2 if command == 3 else 1
		if at + generic_size + 2 > end:
			return _error("Command header is truncated")
		var generic_id := int(bytes.decode_u16(at + 1)) if generic_size == 2 else int(bytes[at + 1])
		var payload_size := int(bytes[at + 1 + generic_size])
		var next := at + 1 + generic_size + payload_size
		if payload_size < 3 or next > end:
			return _error("Command size is invalid")
		if command == 1 or command == 3:
			var archive_index := int(bytes.decode_u16(at + 2 + generic_size)) & 0x7fff
			var record := {"generic_id": generic_id, "archive_index": archive_index}
			if command == 1:
				bodies.append(record)
			else:
				animations.append(record)
		at = next
	return _error("Command terminator is missing")


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
