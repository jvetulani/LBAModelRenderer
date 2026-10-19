class_name LBA1FaceModes
extends RefCounted

# In LBA1's FillVertic dispatch, 5 replaces the destination palette ramp and
# 6 writes every other pixel. LBA2 uses different render-type meanings.
static func is_transparent(body: Dictionary, polygon: Dictionary) -> bool:
	return body.get("game", "LBA1") == "LBA1" and int(polygon["render_type"]) in [5, 6]


static func has_transparent_faces(body: Dictionary) -> bool:
	if body.get("game", "LBA1") != "LBA1":
		return false
	for polygon in body["polygons"]:
		if int(polygon["render_type"]) in [5, 6]:
			return true
	return false
