class_name LBA1File3DDecoder
extends RefCounted

# FICHE.C SearchBody/SearchAnim: command, generic ID, then a size-prefixed
# payload whose size includes the size byte itself.
const GENERIC_NAMES := {
	0: "Idle", 1: "Walk", 2: "Back up", 3: "Turn left", 4: "Turn right",
	5: "Hit", 6: "Impact", 7: "Fall", 8: "Land", 9: "Land 2",
	10: "Death", 11: "Action", 12: "Climb", 13: "Ladder", 14: "Jump",
	15: "Throw", 16: "Hide", 17: "Punch 1", 18: "Punch 2", 19: "Punch 3",
	20: "Find", 21: "Drown", 22: "Impact 2", 23: "Sword", 24: "Draw sword",
}


static func decode(bytes: PackedByteArray) -> Dictionary:
	var bodies := []
	var animations := []
	var at := 0
	while at < bytes.size():
		var command := int(bytes[at])
		at += 1
		if command == 255:
			if at != bytes.size():
				return _error("FILE3D has bytes after its terminator")
			return {"ok": true, "bodies": bodies, "animations": animations}
		if at + 2 > bytes.size():
			return _error("FILE3D record header is truncated")
		var generic_id := int(bytes[at])
		var record_size := int(bytes[at + 1])
		if record_size < 3 or at + 1 + record_size > bytes.size():
			return _error("FILE3D record size is invalid")
		if command == 1 or command == 3:
			var record := {"generic_id": generic_id, "archive_index": int(bytes.decode_u16(at + 2)) & 0x7fff}
			if command == 1:
				bodies.append(record)
			else:
				animations.append(record)
		at += 1 + record_size
	return _error("FILE3D terminator is missing")


static func animation_name(generic_id: int) -> String:
	return GENERIC_NAMES.get(generic_id, "Action %d" % generic_id)


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
