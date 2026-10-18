class_name CharacterViewer
extends Node3D

const LBA2_BODY = preload("res://scripts/import/lba2_body_decoder.gd")
const LBA2_FILE3D = preload("res://scripts/import/lba2_file3d_decoder.gd")
const LBA2_PALETTE = preload("res://scripts/import/lba2_palette_decoder.gd")
const LBA2_POSE = preload("res://scripts/animation/lba2_pose.gd")
const LBA1_SAIL_REPAIR = preload("res://scripts/animation/lba1_sail_repair.gd")
const MOTION_GRID_SHADER = preload("res://shaders/motion_grid.gdshader")
const LBA2_OVERRIDES = preload("res://scripts/render/lba2_model_overrides.gd")

signal playback_frame_changed(frame_index: int, frame_count: int, duration_ticks: int)
signal playback_ended
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
var _lba2_palette_index := 42
var game := ""
var _body_index := 0
var _motion_grid: MeshInstance3D
var _motion_grid_enabled := true
var _root_motion_accumulated := Vector3.ZERO
var _shadow: MeshInstance3D
var _shadow_sprite: Dictionary = {}
var _shadow_enabled := true
var _wireframe_enabled := false
var _current_frame := 0
var _phase_ticks := 0.0
var _finished_one_shot := false
var _master_rotation_offset := Vector3.ZERO


func load_body(directory: String, body_index: int) -> Dictionary:
	_directory = directory
	_archives = {}
	return _load_body(body_index)


func load_archives(archives: Dictionary, body_index: int) -> Dictionary:
	_directory = ""
	_archives = archives
	for archive_name in ["BODY.HQR", "ANIM.HQR", "RESS.HQR"]:
		if not _archives.has(archive_name):
			return {"ok": false, "error": "Missing %s" % archive_name}
	return _load_body(body_index)


func _read_entry(archive_name: String, index: int) -> Dictionary:
	if _archives.has(archive_name):
		return HQRReader.read_entry_bytes(_archives[archive_name], index)
	return HQRReader.read_entry(_directory.path_join(archive_name), index)


func _load_body(body_index: int) -> Dictionary:
	var first_body := _read_entry("BODY.HQR", 0)
	if not first_body["ok"]:
		return first_body
	var is_lba2: bool = LBA2_BODY.looks_like_body(first_body["data"])
	var is_demo := false
	if not is_lba2:
		var first_lba1 := LBA1BodyDecoder.decode(first_body["data"])
		if not first_lba1["ok"]:
			var first_compact := LBA1BodyDecoder.decode_compact_groups(first_body["data"])
			if not first_compact["ok"]:
				return {"ok": false, "error": "BODY.HQR is neither a supported LBA1, LBA2, nor 1996 demo body archive"}
			is_demo = true
		if _archives.size() > 0 and not _archives.has("FILE3D.HQR"):
			return {"ok": false, "error": "This source needs FILE3D.HQR"}
	var body_entry := _read_entry("BODY.HQR", body_index)
	if not body_entry["ok"]:
		return body_entry
	# ChoicePalette in AMBIANCE.CPP uses XPL 42 indoors/after the storm and
		# XPL 27 for Citadel during rain. A BODY can appear in several scenes.
	# The 1996 demo stores its active RGB palette at the start of RESS #0.
	# RESS #10 is a separate 768-byte palette with pale greys in the model
	# ranges; using it made characters look blown out.
	var palette_entry := _read_entry("RESS.HQR", _lba2_palette_index if is_lba2 else 0)
	if not palette_entry["ok"]:
		return palette_entry
	if is_demo and palette_entry["data"].size() < 768 + 65536:
		return {"ok": false, "error": "Demo RESS.HQR entry 0 has no complete palette and shade table"}
	if not is_lba2 and not is_demo and palette_entry["data"].size() != 768:
		return {"ok": false, "error": "RESS.HQR entry 0 is not a 768-byte palette"}
	var palette_data: Dictionary = LBA2_PALETTE.decode(palette_entry["data"]) if is_lba2 else {"ok": true, "palette": palette_entry["data"].slice(0, 768) if is_demo else palette_entry["data"]}
	if not palette_data["ok"]:
		return palette_data
	var decoded: Dictionary = LBA2_BODY.decode(body_entry["data"]) if is_lba2 else (LBA1BodyDecoder.decode_compact_groups(body_entry["data"]) if is_demo else LBA1BodyDecoder.decode(body_entry["data"]))
	if not decoded["ok"]:
		return decoded
	if is_lba2:
		decoded["appearance"] = LBA2_OVERRIDES.for_retail_body(body_index)
		decoded["shade_table"] = palette_data["shade_table"]
		decoded["normal_light_level"] = palette_data["normal_level"]
		var atlas := _read_entry("RESS.HQR", 6)
		if not atlas["ok"] or atlas["data"].size() != 65536:
			return {"ok": false, "error": "LBA2 RESS.HQR entry 6 is not a 256x256 texture atlas"}
		decoded["texture_atlas"] = atlas["data"]
	elif is_demo:
		decoded["game"] = "LBA2-96"
		decoded["appearance"] = LBA2_OVERRIDES.for_demo_body(body_index)
		# The 1996 XPL stores the RGB palette first, then its 256x256 shade CLUT.
		decoded["shade_table"] = palette_entry["data"].slice(768, 768 + 65536)
		decoded["normal_light_level"] = 12
		var demo_atlas := _read_entry("RESS.HQR", 6)
		if not demo_atlas["ok"] or demo_atlas["data"].size() != 65536:
			return {"ok": false, "error": "LBA2-96 RESS.HQR entry 6 is not a 256x256 texture atlas"}
		decoded["texture_atlas"] = demo_atlas["data"]
	if is_instance_valid(character):
		if character.get_parent() == self:
			remove_child(character)
		character.queue_free()
	if is_instance_valid(_shadow):
		if _shadow.get_parent() == self:
			remove_child(_shadow)
		_shadow.queue_free()
	_shadow = null
	_root_motion_accumulated = Vector3.ZERO
	_ensure_motion_grid()
	_motion_grid.position = stand_position - Vector3.UP * 0.01
	_motion_grid.visible = false
	_palette = palette_data["palette"]
	game = "LBA2" if is_lba2 else ("LBA2-96" if is_demo else "LBA1")
	_body_index = body_index
	_shadow_sprite = {}
	body = decoded
	animation = {}
	playing = false
	_current_frame = 0
	_phase_ticks = 0.0
	_finished_one_shot = false
	_master_rotation_offset = Vector3.ZERO
	character = CharacterMeshBuilder.build_static_pose(body, _palette)
	character.get_node("Wireframe").visible = _wireframe_enabled
	var polygon_material: ShaderMaterial = character.get_node("Polygons").material_override
	palette_texture_ready.emit(polygon_material.get_shader_parameter("palette_texture"))
	var points: PackedVector3Array = body["pose_points"]
	var min_y := points[0].y
	for point in points:
		min_y = minf(min_y, point.y)
	character.position = stand_position - Vector3.UP * min_y * CharacterMeshBuilder.UNIT_SCALE
	add_child(character)
	var shadow_loaded := _load_shadow() if game == "LBA1" else false
	animation_entries = _find_animations(body_index)
	return {
		"ok": true,
		"points": points,
		"animations": animation_entries,
		"entry_count": first_body["entry_count"],
		"shadow_loaded": shadow_loaded,
		"summary": "%s BODY.HQR #%d: %d points, %d polygons, %d lines, %d spheres" % [
			game, body_index, body["points"].size(), body["polygons"].size(), body["lines"].size(), body["spheres"].size()
		],
	}


func select_lba2_palette(index: int) -> Dictionary:
	if game != "LBA2" or body.is_empty():
		return {"ok": false, "error": "Load an LBA2 body first"}
	var entry := _read_entry("RESS.HQR", index)
	if not entry["ok"]:
		return entry
	var decoded := LBA2_PALETTE.decode(entry["data"])
	if not decoded["ok"]:
		return decoded
	_lba2_palette_index = index
	_palette = decoded["palette"]
	body["shade_table"] = decoded["shade_table"]
	body["normal_light_level"] = decoded["normal_level"]
	var previous_position := character.position
	remove_child(character)
	character.queue_free()
	character = CharacterMeshBuilder.build_static_pose(body, _palette)
	character.get_node("Wireframe").visible = _wireframe_enabled
	character.position = previous_position
	add_child(character)
	if not animation.is_empty():
		var next_frame := _next_frame(_current_frame)
		var duration: int = animation["frames"][next_frame]["duration_ticks"]
		_apply_pose(_current_frame, next_frame, _phase_ticks / float(duration))
	var polygon_material: ShaderMaterial = character.get_node("Polygons").material_override
	palette_texture_ready.emit(polygon_material.get_shader_parameter("palette_texture"))
	return {"ok": true}


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
	_shadow.visible = _shadow_enabled
	_shadow.position = stand_position + Vector3.UP * 0.003
	add_child(_shadow)
	return true


func set_shadow_visible(visible: bool) -> void:
	_shadow_enabled = visible
	if is_instance_valid(_shadow):
		_shadow.visible = visible


func set_wireframe_visible(visible: bool) -> void:
	_wireframe_enabled = visible
	if not is_instance_valid(character):
		return
	character.get_node("Wireframe").visible = visible
	if visible and not animation.is_empty():
		var next_frame := _next_frame(_current_frame)
		var duration: int = animation["frames"][next_frame]["duration_ticks"]
		_apply_pose(_current_frame, next_frame, _phase_ticks / float(duration))


func set_motion_grid_visible(visible: bool) -> void:
	_motion_grid_enabled = visible
	if animation.is_empty():
		_update_motion_grid(0, 0, 0.0)
	else:
		var next_frame := _next_frame(_current_frame)
		var duration: int = animation["frames"][next_frame]["duration_ticks"]
		_update_motion_grid(_current_frame, next_frame, _phase_ticks / float(duration))


func _ensure_motion_grid() -> void:
	if is_instance_valid(_motion_grid):
		return
	_motion_grid = MeshInstance3D.new()
	_motion_grid.name = "MotionGrid"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	_motion_grid.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = MOTION_GRID_SHADER
	_motion_grid.material_override = material
	add_child(_motion_grid)


func _update_motion_grid(source_frame: int, target_frame: int, weight: float) -> void:
	if not is_instance_valid(_motion_grid):
		return
	var has_motion := false
	if not animation.is_empty():
		for frame in animation["frames"]:
			var step: Vector3i = frame["root_step"]
			if step.x != 0 or step.z != 0:
				has_motion = true
				break
	_motion_grid.visible = _motion_grid_enabled and has_motion
	if not _motion_grid.visible:
		return
	var travel := _root_motion_accumulated
	if target_frame != source_frame:
		travel += Vector3(animation["frames"][target_frame]["root_step"]) * weight
	(_motion_grid.material_override as ShaderMaterial).set_shader_parameter("travel", Vector2(travel.x, travel.z) * CharacterMeshBuilder.UNIT_SCALE)


func _find_animations(body_index: int) -> Array:
	if game == "LBA2":
		var file3d := _read_entry("RESS.HQR", 44)
		if not file3d["ok"]:
			return []
		var matches: Dictionary = LBA2_FILE3D.animations_for_body(file3d["data"], body_index)
		return matches["animations"] if matches["ok"] else []
	if game == "LBA2-96":
		var demo_found := []
		var demo_by_archive := {}
		var first_demo := _read_entry("FILE3D.HQR", 0)
		if not first_demo["ok"]:
			return demo_found
		for file_index in range(first_demo["entry_count"]):
			var entry := first_demo if file_index == 0 else _read_entry("FILE3D.HQR", file_index)
			if not entry["ok"]:
				continue
			var decoded := LBA2_FILE3D.decode_entry(entry["data"])
			if not decoded["ok"]:
				continue
			if not decoded["bodies"].any(func(record: Dictionary) -> bool: return record["archive_index"] == body_index):
				continue
			for animation_record in decoded["animations"]:
				var archive_index: int = animation_record["archive_index"]
				var generic_id: int = animation_record["generic_id"]
				if demo_by_archive.has(archive_index):
					var existing: Dictionary = demo_found[demo_by_archive[archive_index]]
					if not existing["generic_ids"].has(generic_id):
						existing["generic_ids"].append(generic_id)
					continue
				var animation_entry := _read_entry("ANIM.HQR", archive_index)
				if not animation_entry["ok"]:
					continue
				var animation_data := LBA1AnimationDecoder.decode(animation_entry["data"])
				# FILE3D owns the association. The original engine applies only
				# the groups present in a shorter action to a body variant.
				if not animation_data["ok"]:
					continue
				demo_by_archive[archive_index] = demo_found.size()
				demo_found.append({"archive_index": archive_index, "generic_id": generic_id, "generic_ids": [generic_id], "file3d_index": file_index, "name": LBA1File3DDecoder.animation_name(generic_id)})
		for item in demo_found:
			if item["generic_ids"].size() > 1:
				item["name"] = "Shared action (%d IDs)" % item["generic_ids"].size()
		return demo_found
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
			var animation_entry := _read_entry("ANIM.HQR", archive_index)
			if not animation_entry["ok"]:
				continue
			var animation_data := LBA1AnimationDecoder.decode(animation_entry["data"])
			if not animation_data["ok"]:
				continue
			seen[archive_index] = true
			var action_name := LBA1File3DDecoder.animation_name(anim_record["generic_id"])
			# The catamaran's side-movement actions share all joint poses with
			# Back up. Their distinct X root steps are the only authored change.
			if LBA1_SAIL_REPAIR.BODY_INDICES.has(body_index) and anim_record["generic_id"] in [124, 125]:
				action_name = "Move left" if anim_record["generic_id"] == 124 else "Move right"
			found.append({
				"archive_index": archive_index,
				"generic_id": anim_record["generic_id"],
				"file3d_index": file3d_index,
				"name": action_name,
			})
	return found


func select_animation(archive_index: int) -> Dictionary:
	if body.is_empty():
		return {"ok": false, "error": "Load a character first"}
	var resource := _read_entry("ANIM.HQR", archive_index)
	if not resource["ok"]:
		return resource
	var decoded := _decode_animation(archive_index, resource["data"])
	if not decoded["ok"]:
		return decoded
	animation = decoded
	_current_frame = 0
	_phase_ticks = 0.0
	_root_motion_accumulated = Vector3.ZERO
	_master_rotation_offset = Vector3.ZERO
	_finished_one_shot = false
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
		var decoded := _decode_animation(entry["archive_index"], resource["data"])
		if not decoded["ok"]:
			return {"ok": false, "error": "ANIM #%d: %s" % [entry["archive_index"], decoded["error"]]}
		clips.append({"archive_index": entry["archive_index"], "name": entry["name"], "animation": decoded})
	return {"ok": true, "body": body, "palette": _palette, "shadow": _shadow_sprite if _shadow_enabled else {}, "clips": clips, "game": game}


func _decode_animation(archive_index: int, bytes: PackedByteArray) -> Dictionary:
	var decoded := LBA1AnimationDecoder.decode(bytes)
	if not decoded["ok"] or not LBA1_SAIL_REPAIR.needs_repair(_body_index, body, archive_index):
		return decoded
	var sailing_entry := _read_entry("ANIM.HQR", LBA1_SAIL_REPAIR.SAILING_ANIMATION)
	if not sailing_entry["ok"]:
		return decoded
	return LBA1_SAIL_REPAIR.repair(decoded, LBA1AnimationDecoder.decode(sailing_entry["data"]))


func set_dither_mode(mode: int) -> void:
	if not is_instance_valid(character):
		return
	var polygon_mesh: MeshInstance3D = character.get_node("Polygons")
	var material: ShaderMaterial = polygon_mesh.material_override
	material.set_shader_parameter("dither_mode", mode)


func set_playing(value: bool) -> void:
	if value and _finished_one_shot:
		_current_frame = 0
		_phase_ticks = 0.0
		_root_motion_accumulated = Vector3.ZERO
		_master_rotation_offset = Vector3.ZERO
		_finished_one_shot = false
		_apply_pose(0, 0, 1.0)
		_emit_frame()
	playing = value and not animation.is_empty()


func set_speed(value: float) -> void:
	speed = clampf(value, 0.1, 4.0)


func scrub_to(frame_index: int) -> void:
	if animation.is_empty():
		return
	_current_frame = clampi(frame_index, 0, animation["frame_count"] - 1)
	_root_motion_accumulated = Vector3.ZERO
	for step_index in range(1, _current_frame + 1):
		_root_motion_accumulated += Vector3(animation["frames"][step_index]["root_step"])
	_phase_ticks = 0.0
	_master_rotation_offset = Vector3.ZERO
	_finished_one_shot = false
	_apply_pose(_current_frame, _current_frame, 1.0)
	_emit_frame()


func _process(delta: float) -> void:
	if not playing or animation.is_empty():
		return
	if animation["frame_count"] == 1:
		return
	var next_frame := _next_frame(_current_frame)
	var duration: int = animation["frames"][next_frame]["duration_ticks"]
	_phase_ticks += minf(delta, 0.25) * LBA1AnimationDecoder.ticks_per_second(game) * speed
	while _phase_ticks >= duration:
		if _current_frame + 1 == animation["frame_count"] and animation["loop_frame"] == animation["frame_count"]:
			playing = false
			_finished_one_shot = true
			_phase_ticks = 0.0
			playback_ended.emit()
			return
		_phase_ticks -= duration
		if next_frame <= _current_frame:
			var angle_scale := TAU / (1024.0 if game == "LBA1" else 4096.0)
			var last_rotation := CharacterPose.master_rotation_units(animation, _current_frame, _current_frame, 1.0)
			var loop_rotation := CharacterPose.master_rotation_units(animation, next_frame, next_frame, 1.0)
			_master_rotation_offset += (last_rotation - loop_rotation) * angle_scale
		_current_frame = next_frame
		_root_motion_accumulated += Vector3(animation["frames"][next_frame]["root_step"])
		next_frame = _next_frame(_current_frame)
		duration = animation["frames"][next_frame]["duration_ticks"]
		_emit_frame()
	_apply_pose(_current_frame, next_frame, _phase_ticks / float(duration))


func _next_frame(frame_index: int) -> int:
	return frame_index + 1 if frame_index + 1 < animation["frame_count"] else mini(animation["loop_frame"], frame_index)


func _apply_pose(source_frame: int, target_frame: int, weight: float) -> void:
	var pose: Dictionary = LBA1Pose.sample(body, animation, source_frame, target_frame, weight) if game == "LBA1" else LBA2_POSE.sample(body, animation, source_frame, target_frame, weight)
	CharacterMeshBuilder.update_pose(character, body, pose)
	var rotation: Vector3 = pose["master_rotation"] + _master_rotation_offset
	character.basis = Basis(Vector3.RIGHT, rotation.x) * Basis(Vector3.BACK, rotation.z) * Basis(Vector3.UP, rotation.y)
	_update_motion_grid(source_frame, target_frame, weight)


func _emit_frame() -> void:
	playback_frame_changed.emit(_current_frame, animation["frame_count"], animation["frames"][_current_frame]["duration_ticks"])
