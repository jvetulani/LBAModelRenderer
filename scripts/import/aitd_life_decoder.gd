extends RefCounted

# Read the LIFE references needed by the browser picker. The desktop helper
# uses the same opcode tables and traversal, but can unpack PAKs with Python.
const OPCODES := "res://tools/aitd/life_opcodes.json"


class Reader:
	var data: PackedByteArray
	var pos := 0
	var ok := true
	var version := 1
	var life: Array
	var eval: Array

	func _init(bytes: PackedByteArray, game_version: int, tables: Dictionary) -> void:
		data = bytes
		version = game_version
		life = tables["LifeA" if version == 1 else "LifeB"]
		eval = tables["EvalA" if version == 1 else "EvalB"]

	func word() -> int:
		if pos + 2 > data.size():
			ok = false
			return 0
		var value := int(data.decode_s16(pos))
		pos += 2
		return value

	func words(count: int) -> Array:
		var values := []
		if count < 0 or count > 1024:
			ok = false
			return values
		for i in range(count):
			values.append(word())
		return values

	func evalvar() -> Variant:
		var code := word()
		if code == -1 or code == 0:
			var literal := word()
			return literal if code == -1 else null
		if code & 0x8000:
			word()
		var index := (code & 0x7fff) - 1
		if index < 0 or index >= eval.size():
			ok = false
			return null
		var kind: String = eval[index]
		if kind in ["DIST", "POSREL", "OBJECT", "THROW", "RAND", "C_VAR", "DIV_BY_2"]:
			word()
		elif kind == "ISFOUND":
			evalvar()
		elif kind in ["TEST_ZV_END_ANIM", "MATRIX"]:
			words(2)
		return null

	func evals(count: int) -> Array:
		var values := []
		for i in range(count):
			values.append(evalvar())
		return values

	func instruction() -> Dictionary:
		var code := word() & 0xffff
		var target: Variant = word() if code & 0x8000 else null
		var index := code & 0x7fff
		if index >= life.size():
			ok = false
			return {}
		var name: String = life[index]
		var anims := []
		var bodies := []
		var lifes := []
		if name in ["IF_EGAL", "IF_DIFFERENT", "IF_SUP_EGAL", "IF_SUP", "IF_INF_EGAL", "IF_INF"]:
			evals(2); words(1)
		elif name in ["IF_IN", "IF_OUT"]:
			evals(3); words(1)
		elif name == "SWITCH":
			evals(1)
		elif name in ["CASE", "GOTO"]:
			words(2 if name == "CASE" else 1)
		elif name == "MULTI_CASE":
			words(word() + 1)
		elif name == "BODY":
			bodies.append_array(evals(1))
		elif name == "BODY_RESET":
			var values := evals(3)
			bodies.append(values[0]); anims.append(values[1])
		elif name == "LIFE":
			lifes.append_array(words(1))
		elif name in ["ANIM_ONCE", "ANIM_ALL_ONCE", "ANIM_RESET", "ANIM_HYBRIDE_ONCE", "ANIM_HYBRIDE_REPEAT"]:
			anims.append_array(words(2))
		elif name == "ANIM_REPEAT":
			anims.append_array(words(1))
		elif name == "ANIM_MOVE":
			anims.append_array(words(7))
		elif name == "HIT":
			anims.append(word()); words(3); evals(1); anims.append(word())
		elif name == "FIRE":
			anims.append(evalvar() if version > 1 else word())
			words(4)
			if version > 1:
				words(1); anims.append(evalvar())
			else:
				anims.append(word())
		elif name == "THROW":
			anims.append(word()); words(5); anims.append(word())
		elif name == "ANIM_SOUND":
			evals(1); anims.append(word()); words(1)
		elif name == "FIRE_UP_DOWN":
			evals(1); words(6); evals(1)
		elif name in ["VAR", "ADD", "SUB", "C_VAR"]:
			words(1); evals(1)
		elif name == "DROP":
			evals(1); words(1)
		elif name == "SOUND":
			words(1) if version > 1 else evals(1)
		elif name in ["SOUND_THEN", "SOUND_THEN_REPEAT"]:
			words(2) if version > 1 else evals(2)
		elif name in ["DELETE", "IN_HAND"]:
			evals(1) if version > 1 else words(1)
		elif name == "REP_SOUND":
			words(1) if version > 1 else evals(1)
			words(1)
		elif name == "TRACKMODE":
			words(2)
		elif name == "DEF_SEQUENCE_SOUND":
			pos += word() * 4
		elif name == "UNKNOWN_5":
			evals(word())
		elif name == "PUT":
			words(9)
		elif name == "READ":
			words(3 if version == 1 else 2)
		elif name == "PUT_AT":
			words(2)
		elif name == "PLAY_SEQUENCE":
			words(1 if version == 1 else 3)
		elif name in ["DEF_ZV", "DEF_ABS_ZV"]:
			words(6)
		elif name == "READ_ON_PICTURE":
			words(8)
		elif name == "CHANGEROOM":
			words(5)
		elif name in ["INC", "DEC", "CAMERA_TARGET", "TAKE", "FOUND", "FOUND_NAME", "FOUND_FLAG", "FLAGS", "FOUND_BODY", "FOUND_LIFE", "NEXT_MUSIC", "MUSIC", "SPECIAL", "STAGE_LIFE", "SET_GROUND", "SET_INVENTORY", "COPY_ANGLE", "TEST_COL", "LIFE_MODE", "FOUND_WEIGHT", "ALLOW_INVENTORY", "WATER", "RND_FREQ", "LIGHT", "SHAKING", "FADE_MUSIC", "STOP_BETA", "SPEED", "GET_MATRICE", "MESSAGE", "MESSAGE_VALUE"]:
			words(1)
		elif name in ["SET_BETA", "SET_ALPHA", "HIT_OBJECT", "SET_VOLUME_SOUND", "MUSIC_AND_LOOP", "FADE_OUT_MUSIC_STOP"]:
			words(2)
		elif name in ["ANGLE", "PICTURE", "DO_ROT_CLUT", "MUSIC_B"]:
			words(3)
		elif name in ["START_FADE_IN_MUSIC", "START_FADE_IN_MUSIC_LOOP"]:
			words(5)
		elif not name in ["ENDLIFE", "PLUIE", "DEL_INVENTORY", "CONTINUE_TRACK", "RESET_MOVE_MANUAL", "END_SEQUENCE", "UP_COOR_Y", "GET_HARD_CLIP", "RETURN", "DO_MAX_ZV", "GAME_OVER", "WAIT_GAME_OVER", "STOP_HIT_OBJECT", "START_CHRONO", "DO_MOVE", "MANUAL_ROT", "DO_ROT_ZV", "DO_REAL_ZV", "DO_CARRE_ZV", "DO_NORMAL_ZV", "CALL_INVENTORY", "PROTECT", "STOP_CLUT", "STOP_SOUND", "UNKNOWN_6", "CAMERA"]:
			ok = false
		if pos > data.size():
			ok = false
		return {"target": target, "anims": anims, "bodies": bodies, "lifes": lifes}


static func animation_ids(objets: PackedByteArray, body_index: int, read_entry: Callable) -> Array[int]:
	var result: Array[int] = []
	if objets.size() < 2:
		return result
	var count := int(objets.decode_u16(0))
	if count == 0:
		return result
	var stride := int((objets.size() - 2) / count)
	if stride not in [52, 54] or objets.size() != 2 + count * stride:
		return result
	var tables: Variant = JSON.parse_string(FileAccess.get_file_as_string(OPCODES))
	if not tables is Dictionary:
		return result
	var version := 1 if stride == 52 else 2
	var pending := []
	for object_index in range(count):
		var offset := 2 + object_index * stride
		if int(objets.decode_s16(offset + 2)) != body_index:
			continue
		var initial_animation := int(objets.decode_s16(offset + 38))
		if initial_animation >= 0 and not result.has(initial_animation):
			result.append(initial_animation)
		for life_offset in [34, 36]:
			var script := int(objets.decode_s16(offset + life_offset))
			if script >= 0:
				pending.append(script)
	var seen := {}
	while not pending.is_empty():
		var script_index: int = pending.pop_back()
		if seen.has(script_index):
			continue
		seen[script_index] = true
		var entry: Dictionary = read_entry.call(script_index)
		if not entry.get("ok", false):
			continue
		var reader := Reader.new(entry["data"], version, tables)
		var current_bodies := {body_index: true}
		while reader.ok and reader.pos < reader.data.size():
			var before := reader.pos
			var instruction := reader.instruction()
			if not reader.ok or reader.pos <= before:
				break
			if instruction["target"] != null:
				continue
			for next_body in instruction["bodies"]:
				if next_body != null and int(next_body) >= 0:
					current_bodies[int(next_body)] = true
			for next_life in instruction["lifes"]:
				if int(next_life) >= 0 and not seen.has(int(next_life)):
					pending.append(int(next_life))
			if current_bodies.has(body_index):
				for animation in instruction["anims"]:
					if animation != null and int(animation) >= 0 and not result.has(int(animation)):
						result.append(int(animation))
	result.sort()
	return result
