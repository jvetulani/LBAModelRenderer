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
