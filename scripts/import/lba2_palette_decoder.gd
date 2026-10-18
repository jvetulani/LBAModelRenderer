class_name LBA2PaletteDecoder
extends RefCounted

# COMMON.H XPL_HEADER: the palette and fog/shade CLUT live in RESS.HQR.
const HEADER_SIZE := 44
const PALETTE_SIZE := 256 * 3
const SHADE_TABLE_SIZE := 256 * 256


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE or bytes.decode_u32(0) != 0:
		return {"ok": false, "error": "Invalid LBA2 XPL header"}
	var palette_offset := int(bytes.decode_u32(4))
	var shade_offset := int(bytes.decode_u32(12))
	var normal_level := int(bytes.decode_u32(24))
	if palette_offset < HEADER_SIZE or palette_offset + PALETTE_SIZE > bytes.size():
		return {"ok": false, "error": "LBA2 XPL palette is truncated"}
	if shade_offset < palette_offset + PALETTE_SIZE or shade_offset + SHADE_TABLE_SIZE > bytes.size():
		return {"ok": false, "error": "LBA2 XPL shade table is truncated"}
	if normal_level < 0 or normal_level > 255:
		return {"ok": false, "error": "LBA2 XPL shade level is invalid"}
	return {
		"ok": true,
		"palette": bytes.slice(palette_offset, palette_offset + PALETTE_SIZE),
		"shade_table": bytes.slice(shade_offset, shade_offset + SHADE_TABLE_SIZE),
		"normal_level": normal_level,
	}
