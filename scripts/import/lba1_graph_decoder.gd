class_name LBA1GraphDecoder
extends RefCounted

# GRAPH_A.ASM, AffGraph: an offset table followed by RLE sprite records.
# Skipped pixels retain the background, so coverage is separate from colour.


static func decode_sprite(bank: PackedByteArray, sprite_index: int) -> Dictionary:
	if sprite_index < 0 or bank.size() < 8 or sprite_index > bank.size() / 4 - 2:
		return _error("Graphic bank or sprite index is invalid")
	var start := int(bank.decode_u32(sprite_index * 4))
	var end := int(bank.decode_u32((sprite_index + 1) * 4))
	if start < 4 or end <= start or end > bank.size() or end - start < 4:
		return _error("Graphic sprite offset is invalid")
	var width := int(bank[start])
	var height := int(bank[start + 1])
	if width == 0 or height == 0:
		return _error("Graphic sprite has an invalid size")
	var pixels := PackedByteArray()
	var coverage := PackedByteArray()
	pixels.resize(width * height)
	coverage.resize(width * height)
	var cursor := start + 4
	for y in range(height):
		if cursor >= end:
			return _error("Graphic sprite row is truncated")
		var block_count := int(bank[cursor])
		cursor += 1
		var x := 0
		for block_index in range(block_count):
			if cursor >= end:
				return _error("Graphic sprite block is truncated")
			var opcode := int(bank[cursor])
			cursor += 1
			var count := (opcode & 63) + 1
			if x + count > width:
				return _error("Graphic sprite block exceeds its row")
			if opcode & 192 == 0:
				x += count
			elif opcode & 64 != 0:
				if cursor + count > end:
					return _error("Graphic sprite literal is truncated")
				for offset in range(count):
					pixels[y * width + x + offset] = bank[cursor + offset]
					coverage[y * width + x + offset] = 1
				cursor += count
				x += count
			else:
				if cursor >= end:
					return _error("Graphic sprite repeat is truncated")
				var color := bank[cursor]
				cursor += 1
				for offset in range(count):
					pixels[y * width + x + offset] = color
					coverage[y * width + x + offset] = 1
				x += count
		if x != width:
			return _error("Graphic sprite row has an invalid width")
	if cursor != end:
		return _error("Graphic sprite has unused bytes")
	return {
		"ok": true,
		"width": width,
		"height": height,
		"pixels": pixels,
		"coverage": coverage,
	}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
