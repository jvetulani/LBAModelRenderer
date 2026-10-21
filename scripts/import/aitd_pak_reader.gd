class_name AITDPakReader
extends RefCounted

const HELPER := "res://tools/aitd/pak_entry.py"


static func _helper_path() -> String:
	# Python cannot execute a script inside a packaged .pck. Materialize the
	# bundled helper beside its C source in the app's writable user directory.
	var directory := ProjectSettings.globalize_path("user://aitd_tools")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return ""
	for name in ["pak_entry.py", "unpak.c"]:
		var source := FileAccess.open("res://tools/aitd/" + name, FileAccess.READ)
		if source == null:
			return ""
		var destination := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
		if destination == null:
			return ""
		destination.store_buffer(source.get_buffer(source.get_length()))
		destination.close()
	return directory.path_join("pak_entry.py")


static func resolve_directory(source: String, requested: String = "") -> Dictionary:
	var candidates := [source]
	if requested == "AITD2":
		candidates = [source.path_join("AITD2"), source.path_join("ALONE2"), source]
	elif requested == "AITD3":
		candidates = [source.path_join("AITD3"), source.path_join("ALONE3"), source]
	else:
		candidates = [source, source.path_join("INDARK"), source.path_join("AITD1"), source.path_join("AITD2"), source.path_join("ALONE2"), source.path_join("AITD3"), source.path_join("ALONE3")]
	for directory in candidates:
		if FileAccess.file_exists(directory.path_join("LISTBODY.PAK")):
			var title := requested if not requested.is_empty() else ("AITD3" if directory.get_file().to_upper().contains("3") else ("AITD2" if directory.get_file().to_upper().contains("2") else "AITD1"))
			return {"ok": true, "directory": directory, "game": title}
	return {"ok": false, "error": "No %s LISTBODY.PAK found in %s" % [requested if not requested.is_empty() else "AITD", source]}


static func read_entry(archive_path: String, index: int) -> Dictionary:
	if OS.has_feature("web"):
		return {"ok": false, "error": "AITD PAK support currently requires the desktop viewer"}
	if not FileAccess.file_exists(archive_path):
		return {"ok": false, "error": "Missing %s" % archive_path.get_file()}
	var temp_directory := OS.get_environment("TMPDIR") if not OS.get_environment("TMPDIR").is_empty() else "/tmp"
	var temp_path := temp_directory.path_join("aitd_%d_%d_%s.bin" % [OS.get_process_id(), index, archive_path.get_file().get_basename()])
	var output := []
	var helper := _helper_path()
	if helper.is_empty():
		return {"ok": false, "error": "AITD unpacker is missing from this build"}
	var status := OS.execute("python3", [helper, archive_path, str(index), temp_path], output, true)
	if status != 0 or not FileAccess.file_exists(temp_path):
		return {"ok": false, "error": "PAK extraction failed: %s" % (str(output[0]).strip_edges() if not output.is_empty() else "python3 or a C compiler may be missing")}
	var bytes := FileAccess.get_file_as_bytes(temp_path)
	DirAccess.remove_absolute(temp_path)
	return {"ok": true, "data": bytes, "entry_count": int(str(output[0]).strip_edges())}


static func animation_catalog(archive_path: String) -> Array:
	if not FileAccess.file_exists(archive_path) or OS.has_feature("web"):
		return []
	var output := []
	var helper := _helper_path()
	if helper.is_empty() or OS.execute("python3", [helper, archive_path, "--animation-catalog"], output, true) != 0 or output.is_empty():
		return []
	var catalog: Variant = JSON.parse_string(str(output[0]))
	return catalog if catalog is Array else []


static func scene_animation_ids(directory: String, body_index: int) -> Array[int]:
	# OBJETS.ITD records the game's initial BODY/ANIM pairing for each object.
	var path := directory.path_join("OBJETS.ITD")
	if not FileAccess.file_exists(path):
		return []
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 2:
		return []
	var count := int(bytes.decode_u16(0))
	if count == 0:
		return []
	var stride := int((bytes.size() - 2) / count)
	if stride not in [52, 54] or bytes.size() != 2 + count * stride:
		return []
	var matched: Array[int] = []
	for index in range(count):
		var offset := 2 + index * stride
		if int(bytes.decode_s16(offset + 2)) != body_index:
			continue
		var animation_index := int(bytes.decode_s16(offset + 38))
		if animation_index >= 0 and not matched.has(animation_index):
			matched.append(animation_index)
	return matched


static func confirmed_animation_ids(game: String, body_index: int) -> Array[int]:
	# Some scene props have no initial OBJETS.ITD pairing. Body 4 is the
	# rocking horse; its five-frame rock is LISTANIM #9 (confirmed in viewer).
	if game == "AITD1" and body_index == 4:
		return [9]
	return []
