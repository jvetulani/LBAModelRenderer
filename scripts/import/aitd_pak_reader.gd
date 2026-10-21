class_name AITDPakReader
extends RefCounted

const HELPER := "res://tools/aitd/pak_entry.py"
const LIFE_DECODER = preload("res://scripts/import/aitd_life_decoder.gd")
static var _life_cache: Dictionary = {}
static var _web_unpacker_ready := false


static func _helper_path() -> String:
	# Python cannot execute a script inside a packaged .pck. Materialize the
	# bundled helper beside its C source in the app's writable user directory.
	var directory := ProjectSettings.globalize_path("user://aitd_tools")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return ""
	for name in ["pak_entry.py", "unpak.c", "life_links.py", "life_opcodes.json"]:
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


static func _ensure_web_unpacker() -> bool:
	if _web_unpacker_ready:
		return true
	var wasm := FileAccess.get_file_as_bytes("res://tools/aitd/unpak.wasm")
	if wasm.is_empty():
		return false
	var setup := """
		(() => {
			const binary = Uint8Array.from(atob('%s'), ch => ch.charCodeAt(0));
			const module = new WebAssembly.Module(binary);
			const api = new WebAssembly.Instance(module).exports;
			window.lbaAitdExplode = (encoded, unpacked, flags) => {
				const packed = Uint8Array.from(atob(encoded), ch => ch.charCodeAt(0));
				const needed = packed.length + unpacked + 8 * 1024 * 1024;
				const pages = Math.ceil(needed / 65536);
				if (api.memory.buffer.byteLength < pages * 65536)
					api.memory.grow(pages - api.memory.buffer.byteLength / 65536);
				api.reset_heap();
				const input = api.malloc(packed.length);
				const output = api.malloc(unpacked);
				new Uint8Array(api.memory.buffer, input, packed.length).set(packed);
				api.PAK_explode(input, output, packed.length, unpacked, flags);
				const bytes = new Uint8Array(api.memory.buffer, output, unpacked);
				const chunks = [];
				for (let i = 0; i < bytes.length; i += 32768)
					chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, i + 32768)));
				return btoa(chunks.join(''));
			};
			return true;
		})()
	""" % Marshalls.raw_to_base64(wasm)
	_web_unpacker_ready = bool(JavaScriptBridge.eval(setup))
	return _web_unpacker_ready


static func read_entry_bytes(archive: PackedByteArray, index: int) -> Dictionary:
	if archive.size() < 8:
		return {"ok": false, "error": "PAK header is truncated"}
	var first_offset := int(archive.decode_u32(4))
	var count := int(first_offset / 4) - 2
	if first_offset > archive.size() or index < 0 or index >= count:
		return {"ok": false, "error": "PAK entry %d is out of range" % index}
	var offset := int(archive.decode_u32((index + 1) * 4))
	if offset + 16 > archive.size():
		return {"ok": false, "error": "PAK entry is truncated"}
	var info := offset + maxi(int(archive.decode_u32(offset)), 4)
	if info + 12 > archive.size():
		return {"ok": false, "error": "PAK entry descriptor is truncated"}
	var packed := int(archive.decode_u32(info))
	var unpacked := int(archive.decode_u32(info + 4))
	var mode := int(archive[info + 8])
	var flags := int(archive[info + 9])
	var start := info + 12 + int(archive.decode_u16(info + 10))
	if packed < 0 or unpacked > 64_000_000 or start + packed > archive.size():
		return {"ok": false, "error": "PAK entry payload is invalid"}
	var payload := archive.slice(start, start + packed)
	if mode == 0:
		return {"ok": true, "data": payload, "entry_count": count}
	if mode == 1 and OS.has_feature("web") and _ensure_web_unpacker():
		var expression := "window.lbaAitdExplode(%s, %d, %d)" % [JSON.stringify(Marshalls.raw_to_base64(payload)), unpacked, flags]
		var encoded: Variant = JavaScriptBridge.eval(expression)
		if encoded is String:
			var bytes := Marshalls.base64_to_raw(encoded)
			if bytes.size() == unpacked:
				return {"ok": true, "data": bytes, "entry_count": count}
	return {"ok": false, "error": "PAK compression mode %d could not be decoded in this browser" % mode}


static func animation_catalog_bytes(archive: PackedByteArray) -> Array:
	var first := read_entry_bytes(archive, 0)
	if not first.get("ok", false):
		return []
	var catalog := []
	for index in range(int(first["entry_count"])):
		var entry := first if index == 0 else read_entry_bytes(archive, index)
		if not entry.get("ok", false):
			continue
		var data: PackedByteArray = entry["data"]
		if data.size() < 4:
			continue
		var frames := int(data.decode_u16(0))
		var groups := int(data.decode_u16(2))
		if frames > 0 and groups > 0 and data.size() in [4 + frames * (8 + groups * 8), 4 + frames * (8 + groups * 16)]:
			catalog.append([index, frames, groups])
	return catalog


static func animation_catalog(archive_path: String) -> Array:
	if not FileAccess.file_exists(archive_path) or OS.has_feature("web"):
		return []
	var output := []
	var helper := _helper_path()
	if helper.is_empty() or OS.execute("python3", [helper, archive_path, "--animation-catalog"], output, true) != 0 or output.is_empty():
		return []
	var catalog: Variant = JSON.parse_string(str(output[0]))
	return catalog if catalog is Array else []


static func life_animation_map(directory: String) -> Dictionary:
	if _life_cache.has(directory):
		return _life_cache[directory]
	if OS.has_feature("web") or not FileAccess.file_exists(directory.path_join("OBJETS.ITD")) or not FileAccess.file_exists(directory.path_join("LISTLIFE.PAK")):
		return {}
	var helper := _helper_path()
	var output := []
	if helper.is_empty() or OS.execute("python3", [helper, directory, "--life-animation-map"], output, true) != 0 or output.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(str(output[0]))
	var links: Dictionary = parsed.get("links", {}) if parsed is Dictionary else {}
	for key in links:
		var ids: Array[int] = []
		for value in links[key]:
			ids.append(int(value))
		links[key] = ids
	_life_cache[directory] = links
	return links


static func life_animation_ids_bytes(archives: Dictionary, body_index: int) -> Array[int]:
	if not archives.has("OBJETS.ITD") or not archives.has("LISTLIFE.PAK"):
		return []
	var archive: PackedByteArray = archives["LISTLIFE.PAK"]
	return LIFE_DECODER.animation_ids(archives["OBJETS.ITD"], body_index, func(index: int) -> Dictionary:
		return read_entry_bytes(archive, index)
	)


static func scene_animation_ids(directory: String, body_index: int) -> Array[int]:
	# OBJETS.ITD records the game's initial BODY/ANIM pairing for each object.
	var path := directory.path_join("OBJETS.ITD")
	if not FileAccess.file_exists(path):
		return []
	return scene_animation_ids_bytes(FileAccess.get_file_as_bytes(path), body_index)


static func scene_animation_ids_bytes(bytes: PackedByteArray, body_index: int) -> Array[int]:
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
