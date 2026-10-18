class_name HQRReader
extends RefCounted

# The on-disk layout follows lba1-classic/LIB386/LIB_SYS/HQ_RESS.C.
# Modes 1 and 2 use the same token layout; mode changes the match length.
const MAX_ENTRY_BYTES := 32 * 1024 * 1024


static func read_entry(path: String, index: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("Cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])

	var archive_size := file.get_length()
	if archive_size < 4:
		return _error("HQR offset table is missing")
	var first := file.get_buffer(4)
	var table_size := int(first.decode_u32(0))
	if table_size < 4 or table_size % 4 != 0 or table_size > archive_size:
		return _error("Invalid HQR offset table size")
	var entry_count := table_size / 4
	if index < 0 or index >= entry_count:
		return _error("HQR entry %d is outside 0..%d" % [index, entry_count - 1])

	file.seek(index * 4)
	var offset_bytes := file.get_buffer(4)
	if offset_bytes.size() != 4:
		return _error("Truncated HQR offset table")
	var offset := int(offset_bytes.decode_u32(0))
	if offset == 0:
		return _error("HQR entry %d is empty" % index)
	if offset < table_size or offset > archive_size - 10:
		return _error("HQR entry %d has an invalid offset" % index)

	file.seek(offset)
	var header := file.get_buffer(10)
	if header.size() != 10:
		return _error("Truncated HQR entry header")
	var unpacked_size := int(header.decode_u32(0))
	var packed_size := int(header.decode_u32(4))
	var mode := int(header.decode_u16(8))
	if unpacked_size <= 0 or unpacked_size > MAX_ENTRY_BYTES:
		return _error("HQR entry size is invalid or exceeds the safety limit")
	if packed_size <= 0 or offset + 10 + packed_size > archive_size:
		return _error("HQR entry payload is truncated")
	if mode != 0 and mode != 1 and mode != 2:
		return _error("Unsupported HQR compression mode %d" % mode)
	if mode == 0 and packed_size != unpacked_size:
		return _error("Stored HQR entry has inconsistent sizes")

	var payload := file.get_buffer(packed_size)
	if payload.size() != packed_size:
		return _error("Truncated HQR entry payload")
	var decoded := payload if mode == 0 else _decompress(payload, unpacked_size, mode)
	if decoded.size() != unpacked_size:
		return _error("Invalid HQR compressed stream in entry %d" % index)
	return {
		"ok": true,
		"data": decoded,
		"index": index,
		"entry_count": entry_count,
		"mode": mode,
		"packed_size": packed_size,
		"unpacked_size": unpacked_size,
	}


static func _decompress(source: PackedByteArray, output_size: int, mode: int) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(output_size)
	var read_at := 0
	var write_at := 0
	while write_at < output_size:
		if read_at >= source.size():
			return PackedByteArray()
		var flags := source[read_at]
		read_at += 1
		for bit in range(8):
			if flags & (1 << bit):
				if read_at >= source.size():
					return PackedByteArray()
				output[write_at] = source[read_at]
				read_at += 1
				write_at += 1
			else:
				if read_at + 2 > source.size():
					return PackedByteArray()
				var token := int(source.decode_u16(read_at))
				read_at += 2
				var length := (token & 15) + mode + 1
				var distance := (token >> 4) + 1
				if distance > write_at or write_at + length > output_size:
					return PackedByteArray()
				for byte_index in range(length):
					output[write_at] = output[write_at - distance]
					write_at += 1
			if write_at == output_size:
				break
	if read_at != source.size():
		return PackedByteArray()
	return output


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
