class_name CharacterViewer
extends Node3D

signal playback_frame_changed(frame_index: int, frame_count: int, duration_ticks: int)
signal palette_texture_ready(texture: Texture2D)

var stand_position := Vector3.ZERO
var character: Node3D
var body: Dictionary = {}
var animation: Dictionary = {}
var animation_entries: Array = []
var playing := false
var speed := 1.0
var _directory := ""
var _archives := {}
var _palette := PackedByteArray()
var _shadow: MeshInstance3D
var _shadow_sprite: Dictionary = {}
var _current_frame := 0
var _phase_ticks := 0.0


func load_body(directory: String, body_index: int) -> Dictionary:
	_directory = directory
	_archives = {}
	return _load_body(body_index)


func load_archives(archives: Dictionary, body_index: int) -> Dictionary:
	_directory = ""
	_archives = archives
	for archive_name in ["BODY.HQR", "ANIM.HQR", "FILE3D.HQR", "RESS.HQR"]:
		if not _archives.has(archive_name):
			return {"ok": false, "error": "Missing %s" % archive_name}
	return _load_body(body_index)


func _read_entry(archive_name: String, index: int) -> Dictionary:
	if _archives.has(archive_name):
		return HQRReader.read_entry_bytes(_archives[archive_name], index)
	return HQRReader.read_entry(_directory.path_join(archive_name), index)


func _load_body(body_index: int) -> Dictionary:
	var body_entry := _read_entry("BODY.HQR", body_index)
	if not body_entry["ok"]:
		return body_entry
	var palette_entry := _read_entry("RESS.HQR", 0)
	if not palette_entry["ok"]:
		return palette_entry
	if palette_entry["data"].size() != 768:
		return {"ok": false, "error": "RESS.HQR entry 0 is not a 768-byte LBA1 palette"}
	var decoded := LBA1BodyDecoder.decode(body_entry["data"])
	if not decoded["ok"]:
		return decoded
	if is_instance_valid(character):
		remove_child(character)
		character.queue_free()
	if is_instance_valid(_shadow):
		remove_child(_shadow)
		_shadow.queue_free()
	_palette = palette_entry["data"]
	body = decoded
	animation = {}
	playing = false
	_current_frame = 0
	_phase_ticks = 0.0
	character = CharacterMeshBuilder.build_static_pose(body, _palette)
	var polygon_material: ShaderMaterial = character.get_node("Polygons").material_override
	palette_texture_ready.emit(polygon_material.get_shader_parameter("palette_texture"))
	var points: PackedVector3Array = body["pose_points"]
	var min_y := points[0].y
	for point in points:
		min_y = minf(min_y, point.y)
	character.position = stand_position - Vector3.UP * min_y * CharacterMeshBuilder.UNIT_SCALE
	add_child(character)
	var shadow_loaded := _load_shadow()
	animation_entries = _find_animations(body_index)
	return {
		"ok": true,
		"points": points,
		"animations": animation_entries,
		"shadow_loaded": shadow_loaded,
		"summary": "BODY.HQR #%d: %d points, %d polygons, %d lines, %d spheres" % [
			body_index, body["points"].size(), body["polygons"].size(), body["lines"].size(), body["spheres"].size()
		],
	}


func _load_shadow() -> bool:
	_shadow_sprite = {}
	var bank := _read_entry("RESS.HQR", 4)
	if not bank["ok"]:
		return false
	var sprite := LBA1GraphDecoder.decode_sprite(bank["data"], 2)
	if not sprite["ok"]:
		return false
	_shadow_sprite = sprite
	_shadow = ShadowSpriteBuilder.build(sprite, _palette)
	_shadow.position = stand_position + Vector3.UP * 0.003
	add_child(_shadow)
	return true


func _find_animations(body_index: int) -> Array:
	var found := []
	var seen := {}
	var first := _read_entry("FILE3D.HQR", 0)
	if not first["ok"]:
		return found
	for file3d_index in range(first["entry_count"]):
		var resource := first if file3d_index == 0 else _read_entry("FILE3D.HQR", file3d_index)
		if not resource["ok"]:
			continue
		var decoded := LBA1File3DDecoder.decode(resource["data"])
		if not decoded["ok"]:
			continue
		var owns_body := false
		for body_record in decoded["bodies"]:
			if body_record["archive_index"] == body_index:
				owns_body = true
				break
		if not owns_body:
			continue
		for anim_record in decoded["animations"]:
			var archive_index: int = anim_record["archive_index"]
			if seen.has(archive_index):
				continue
			seen[archive_index] = true
			found.append({
				"archive_index": archive_index,
				"generic_id": anim_record["generic_id"],
				"file3d_index": file3d_index,
				"name": LBA1File3DDecoder.animation_name(anim_record["generic_id"]),
			})
	return found


func select_animation(archive_index: int) -> Dictionary:
	if body.is_empty():
		return {"ok": false, "error": "Load a character first"}
	var resource := _read_entry("ANIM.HQR", archive_index)
	if not resource["ok"]:
		return resource
	var decoded := LBA1AnimationDecoder.decode(resource["data"])
	if not decoded["ok"]:
		return decoded
	animation = decoded
	_current_frame = 0
	_phase_ticks = 0.0
	playing = true
	_apply_pose(0, 0, 1.0)
	_emit_frame()
	return {"ok": true, "frame_count": animation["frame_count"], "group_count": animation["group_count"]}


func export_input() -> Dictionary:
	if body.is_empty():
		return {"ok": false, "error": "Load a character first"}
	var clips := []
	for entry in animation_entries:
		var resource := _read_entry("ANIM.HQR", entry["archive_index"])
		if not resource["ok"]:
			return {"ok": false, "error": "ANIM #%d: %s" % [entry["archive_index"], resource["error"]]}
		var decoded := LBA1AnimationDecoder.decode(resource["data"])
		if not decoded["ok"]:
			return {"ok": false, "error": "ANIM #%d: %s" % [entry["archive_index"], decoded["error"]]}
		clips.append({"archive_index": entry["archive_index"], "name": entry["name"], "animation": decoded})
	return {"ok": true, "body": body, "palette": _palette, "shadow": _shadow_sprite, "clips": clips}


func set_dither_mode(mode: int) -> void:
	if not is_instance_valid(character):
		return
	var polygon_mesh: MeshInstance3D = character.get_node("Polygons")
	var material: ShaderMaterial = polygon_mesh.material_override
	material.set_shader_parameter("dither_mode", mode)


func set_playing(value: bool) -> void:
	playing = value and not animation.is_empty()


func set_speed(value: float) -> void:
	speed = clampf(value, 0.1, 4.0)


func scrub_to(frame_index: int) -> void:
	if animation.is_empty():
		return
	_current_frame = clampi(frame_index, 0, animation["frame_count"] - 1)
	_phase_ticks = 0.0
	_apply_pose(_current_frame, _current_frame, 1.0)
	_emit_frame()


func _process(delta: float) -> void:
	if not playing or animation.is_empty():
		return
	if animation["frame_count"] == 1:
		return
	var next_frame := _next_frame(_current_frame)
	var duration: int = animation["frames"][next_frame]["duration_ticks"]
	_phase_ticks += minf(delta, 0.25) * 50.0 * speed
	while _phase_ticks >= duration:
		_phase_ticks -= duration
		_current_frame = next_frame
		next_frame = _next_frame(_current_frame)
		duration = animation["frames"][next_frame]["duration_ticks"]
		_emit_frame()
	_apply_pose(_current_frame, next_frame, _phase_ticks / float(duration))


func _next_frame(frame_index: int) -> int:
	return frame_index + 1 if frame_index + 1 < animation["frame_count"] else animation["loop_frame"]


func _apply_pose(source_frame: int, target_frame: int, weight: float) -> void:
	var pose := LBA1Pose.sample(body, animation, source_frame, target_frame, weight)
	CharacterMeshBuilder.update_pose(character, body, pose)


func _emit_frame() -> void:
	playback_frame_changed.emit(_current_frame, animation["frame_count"], animation["frames"][_current_frame]["duration_ticks"])
