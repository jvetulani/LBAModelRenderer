class_name LBA2Appearance
extends RefCounted

const SPECTRAL_OPACITY := 0.42


static func uses_spectral_preview(body: Dictionary) -> bool:
	return body.get("appearance", {}).get("effect", "") == "chroma_spectral"


static func uses_fireball_glow(body: Dictionary) -> bool:
	return body.get("appearance", {}).get("effect", "") == "fireball_glow"


static func uses_translucent_solid(body: Dictionary) -> bool:
	return body.get("appearance", {}).get("effect", "") == "translucent_solid"


static func is_translucent_face(body: Dictionary, polygon: Dictionary) -> bool:
	# AFF_OBJ mode 2 is transparent; mode 3 is a screen-door fill.
	# Both are authored per polygon, so use the source mode across every body.
	if body.get("game", "") == "LBA2" and int(polygon["render_type"]) in [2, 3]:
		return true
	for rule in body.get("appearance", {}).get("translucent_faces", []):
		if int(rule.get("palette_index", -1)) == int(polygon["palette_index"]) and int(rule.get("render_type", -1)) == int(polygon["render_type"]):
			return true
	return false


static func has_translucent_faces(body: Dictionary) -> bool:
	if not body.get("appearance", {}).get("translucent_faces", []).is_empty():
		return true
	if body.get("game", "") != "LBA2":
		return false
	for polygon in body["polygons"]:
		if int(polygon["render_type"]) in [2, 3]:
			return true
	return false


static func surface_offset_for_face(body: Dictionary, polygon: Dictionary) -> float:
	for rule in body.get("appearance", {}).get("surface_offsets", []):
		if int(rule.get("palette_index", -1)) == int(polygon["palette_index"]) and int(rule.get("render_type", -1)) == int(polygon["render_type"]):
			return float(rule.get("offset", 0.0))
	return 0.0
