class_name LBA2AnimatedTextureAtlas
extends RefCounted

# LBA2 stores fire instructions and palette indices in RESS.HQR #6. The game
# clears those atlas squares and writes new pixels into them every 20 ms.
const ATLAS_SIZE := 256
const FIRE_SIZE := 32
const FIRE_BUFFER_HEIGHT := 36
const TICK_SECONDS := 0.02
const FLIPBOOK_FRAMES := 96

static var _frame_cache: Dictionary = {}

var texture: ImageTexture
var _pixels := PackedByteArray()
var _fires: Array[Dictionary] = []
var _plasmas: Array[Dictionary] = []
var _frames: Array[PackedByteArray] = []
var _frame_index := 0
var _seed := 1876351
var _plasma_seed := 420317
var _elapsed := 0.0


func _init(source: PackedByteArray) -> void:
	var cache_key := source.hex_encode().hash()
	if _frame_cache.has(cache_key):
		_frames = _frame_cache[cache_key]
		_pixels = _frames[0].duplicate()
		texture = ImageTexture.create_from_image(_image())
		return
	_pixels = source.duplicate()
	_scan_effect_markers(source)
	# The original game begins updating its texture before a model is drawn.
	# Bake the animated atlas into a flipbook once per source archive.
	if not _fires.is_empty() or not _plasmas.is_empty():
		for tick in range(48):
			_step_effects()
		for frame in range(FLIPBOOK_FRAMES):
			_step_effects()
			_frames.append(_pixels.duplicate())
		_frame_cache[cache_key] = _frames
		_pixels = _frames[0].duplicate()
	texture = ImageTexture.create_from_image(_image())


func frame_count() -> int:
	return _frames.size()


func pixels() -> PackedByteArray:
	return _pixels.duplicate()


func advance(delta: float) -> void:
	if _frames.is_empty():
		return
	_elapsed += minf(delta, 0.25)
	var steps := mini(int(_elapsed / TICK_SECONDS), 12)
	if steps == 0:
		return
	_elapsed -= float(steps) * TICK_SECONDS
	_frame_index = (_frame_index + steps) % _frames.size()
	_pixels = _frames[_frame_index]
	texture.update(_image())


func _image() -> Image:
	return Image.create_from_data(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_R8, _pixels)


func _scan_effect_markers(source: PackedByteArray) -> void:
	# Scan in atlas order, as ScanTextureAnimation in the original engine does.
	# A marker's next row encodes its square width; row three gives the type.
	var scan := source.duplicate()
	for offset in range(ATLAS_SIZE * ATLAS_SIZE):
		if scan[offset] != 1 or offset + 3 * ATLAS_SIZE + 16 >= scan.size():
			continue
		var x := offset % ATLAS_SIZE
		var y := offset / ATLAS_SIZE
		if x + FIRE_SIZE > ATLAS_SIZE or y + FIRE_SIZE > ATLAS_SIZE:
			continue
		var width := 2
		while x + width - 2 < ATLAS_SIZE and scan[offset + ATLAS_SIZE + width - 1] == 0:
			width += 1
		if width != FIRE_SIZE:
			continue
		var effect_type := scan[offset + 2 * ATLAS_SIZE + 1]
		if effect_type != 0 and effect_type != 1:
			continue
		if effect_type == 1:
			var colors := PackedByteArray()
			colors.resize(FIRE_SIZE)
			for color_index in range(16):
				colors[16 + color_index] = scan[offset + 3 * ATLAS_SIZE + 1 + color_index]
			var state := PackedByteArray()
			state.resize(FIRE_SIZE * FIRE_BUFFER_HEIGHT)
			var next := PackedByteArray()
			next.resize(FIRE_SIZE * FIRE_BUFFER_HEIGHT)
			_fires.append({"x": x, "y": y, "colors": colors, "state": state, "next": next})
		else:
			var colors := PackedByteArray()
			for color_index in range(FIRE_SIZE - 1):
				var color: int = scan[offset + 3 * ATLAS_SIZE + 1 + color_index]
				if color == 1:
					break
				colors.append(color)
			if colors.is_empty():
				continue
			var active := maxi(int(scan[offset + 2 * ATLAS_SIZE + 2]), 4)
			var speed := maxi(int(scan[offset + 2 * ATLAS_SIZE + 3]), 5)
			var values := PackedFloat32Array()
			var velocities := PackedFloat32Array()
			for control_index in range(active * active):
				values.append(_random_unit() * float(colors.size() - 1))
				velocities.append((1.0 if _random_unit() >= 0.5 else -1.0) * float(speed) * (0.012 + _random_unit() * 0.006))
			_plasmas.append({"x": x, "y": y, "colors": colors, "active": active, "values": values, "velocities": velocities})
		for row in range(FIRE_SIZE):
			for column in range(FIRE_SIZE):
				scan[(y + row) * ATLAS_SIZE + x + column] = 0
				_pixels[(y + row) * ATLAS_SIZE + x + column] = 0


func _random_unit() -> float:
	_plasma_seed = (_plasma_seed * 1664525 + 1013904223) & 0xffffffff
	return float(_plasma_seed & 0xffff) / 65535.0


func _step_effects() -> void:
	_step_fire()
	_step_plasma()


func _step_plasma() -> void:
	for plasma_index in range(_plasmas.size()):
		var plasma := _plasmas[plasma_index]
		var colors: PackedByteArray = plasma["colors"]
		var active: int = plasma["active"]
		var values: PackedFloat32Array = plasma["values"]
		var velocities: PackedFloat32Array = plasma["velocities"]
		for control_index in range(values.size()):
			values[control_index] += velocities[control_index]
			if values[control_index] < 0.0 or values[control_index] > float(colors.size() - 1):
				values[control_index] = clampf(values[control_index], 0.0, float(colors.size() - 1))
				velocities[control_index] = -velocities[control_index]
		for row in range(FIRE_SIZE):
			var gy := float(row * active) / float(FIRE_SIZE)
			var y0 := int(gy)
			var y1 := (y0 + 1) % active
			var fy := gy - float(y0)
			for column in range(FIRE_SIZE):
				var gx := float(column * active) / float(FIRE_SIZE)
				var x0 := int(gx)
				var x1 := (x0 + 1) % active
				var fx := gx - float(x0)
				var upper := lerpf(values[y0 * active + x0], values[y0 * active + x1], fx)
				var lower := lerpf(values[y1 * active + x0], values[y1 * active + x1], fx)
				var color_index := clampi(int(lerpf(upper, lower, fy)), 0, colors.size() - 1)
				_pixels[(int(plasma["y"]) + row) * ATLAS_SIZE + int(plasma["x"]) + column] = colors[color_index]
		plasma["values"] = values
		plasma["velocities"] = velocities
		_plasmas[plasma_index] = plasma


func _step_fire() -> void:
	for fire_index in range(_fires.size()):
		var fire := _fires[fire_index]
		var state: PackedByteArray = fire["state"]
		var next: PackedByteArray = fire["next"]
		var colors: PackedByteArray = fire["colors"]
		for random_index in range(FIRE_SIZE * 2):
			var value := _seed
			var rotation := (value >> 8) & 31
			if rotation != 0:
				value = ((value << rotation) | (value >> (32 - rotation))) & 0xffffffff
			value = (value & 0xffff0000) | (((value & 0xffff) * (64 - random_index)) & 0xffff)
			_seed = (_seed + 5137827) & 0xffffffff
			state[FIRE_SIZE * 34 + random_index] = value & 128
		for row in range(34):
			for column in range(FIRE_SIZE):
				var left := (column - 1) & 31
				var right := (column + 1) & 31
				var center := (row + 1) * FIRE_SIZE
				var total := int(state[center - FIRE_SIZE + left]) + int(state[center - FIRE_SIZE + column]) + int(state[center - FIRE_SIZE + right])
				total += int(state[center + left]) + int(state[center + right])
				total += int(state[center + FIRE_SIZE + left]) + int(state[center + FIRE_SIZE + column]) + int(state[center + FIRE_SIZE + right])
				var rotated := ((total >> 3) | ((total & 7) << 13)) & 0xffff
				if (rotated & 0x6000) == 0 and (rotated & 255) != 0:
					rotated -= 1
				next[center + column] = rotated & 255
		for pixel_index in range(FIRE_SIZE * 34):
			state[pixel_index] = next[FIRE_SIZE + pixel_index]
		for row in range(FIRE_SIZE):
			for column in range(FIRE_SIZE):
				var color_index := mini(int(state[row * FIRE_SIZE + column]) >> 1, 31)
				_pixels[(int(fire["y"]) + row) * ATLAS_SIZE + int(fire["x"]) + column] = colors[color_index]
		fire["state"] = state
		fire["next"] = next
		_fires[fire_index] = fire
