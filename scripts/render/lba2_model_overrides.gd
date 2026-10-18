class_name LBA2ModelOverrides
extends RefCounted

const PATH := "res://assets/model_overrides/lba2.json"
const DEMO_PATH := "res://assets/model_overrides/demo.json"
static var _retail: Dictionary = {}
static var _demo: Dictionary = {}


static func for_retail_body(body_index: int) -> Dictionary:
	if _retail.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_retail = parsed.get("retail", {})
	return _retail.get(str(body_index), {}).duplicate(true)


static func for_demo_body(body_index: int) -> Dictionary:
	if _demo.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEMO_PATH))
		if parsed is Dictionary:
			_demo = parsed.get("demo", {})
	return _demo.get(str(body_index), {}).duplicate(true)


static func apply_geometry(body: Dictionary) -> void:
	# Source BODY #0 has three shirt faces with UV corners exchanged. Keeping
	# the repair in the data file makes preview and GLB export use one mesh.
	var appearance: Dictionary = body.get("appearance", {})
	var polygons: Array = body.get("polygons", [])
	for swap in appearance.get("uv_corner_swaps", []):
		if swap.size() != 3:
			continue
		var polygon_index := int(swap[0])
		var first := int(swap[1])
		var second := int(swap[2])
		if polygon_index < 0 or polygon_index >= polygons.size():
			continue
		var polygon: Dictionary = polygons[polygon_index]
		var uvs: PackedVector2Array = polygon["texture_uvs"]
		if first < 0 or second < 0 or first >= uvs.size() or second >= uvs.size():
			continue
		var saved := uvs[first]
		uvs[first] = uvs[second]
		uvs[second] = saved
		polygon["texture_uvs"] = uvs
		polygons[polygon_index] = polygon
	body["polygons"] = polygons
