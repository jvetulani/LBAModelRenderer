class_name OrbitCamera
extends Camera3D

var yaw := deg_to_rad(20.0)
var pitch := deg_to_rad(12.0)
var distance := 4.4
var focus := Vector3(0.0, 0.75, 0.0)
var maximum_size := 12.0
var _touches: Dictionary = {}


func _ready() -> void:
	_update_pose()


func frame_points(points: PackedVector3Array, stand_position: Vector3, padding: float = 1.45) -> void:
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var extent := (maximum - minimum) * CharacterMeshBuilder.UNIT_SCALE
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var horizontal_span := Vector2(extent.x, extent.z).length()
	focus = stand_position + Vector3((minimum.x + maximum.x) * 0.5 * CharacterMeshBuilder.UNIT_SCALE, extent.y * 0.5, (minimum.z + maximum.z) * 0.5 * CharacterMeshBuilder.UNIT_SCALE)
	size = maxf(1.8 * padding / 1.45, maxf(extent.y, horizontal_span / aspect) * padding)
	maximum_size = maxf(12.0, size * 2.0)
	distance = maxf(3.0, size * 1.8)
	_update_pose()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed:
		_touches.erase(event.index)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		var previous: Vector2 = _touches[event.index]
		_touches[event.index] = event.position
		if _touches.size() == 1:
			var movement: Vector2 = event.position - previous
			yaw -= movement.x * 0.008
			pitch = clampf(pitch + movement.y * 0.008, -1.2, 1.2)
			_update_pose()
		elif _touches.size() == 2:
			var indices: Array = _touches.keys()
			var other: Vector2 = _touches[indices[0] if indices[1] == event.index else indices[1]]
			var old_span: float = previous.distance_to(other)
			var new_span: float = event.position.distance_to(other)
			if old_span > 1.0 and new_span > 1.0:
				size = clampf(size * old_span / new_span, 0.8, maximum_size)
			_pan_pixels((event.position - previous) * 0.5)
			_update_pose()
	elif event is InputEventMouseMotion and _touches.is_empty():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			yaw -= event.relative.x * 0.008
			pitch = clampf(pitch + event.relative.y * 0.008, -1.2, 1.2)
			_update_pose()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_pan_pixels(event.relative)
			_update_pose()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			size = maxf(0.8, size * 0.9)
			_update_pose()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size = minf(maximum_size, size * 1.1)
			_update_pose()


func _pan_pixels(movement: Vector2) -> void:
	var units_per_pixel := size / maxf(1.0, get_viewport().get_visible_rect().size.y)
	focus += (-global_basis.x * movement.x + global_basis.y * movement.y) * units_per_pixel


func _update_pose() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	position = focus + offset
	look_at(focus, Vector3.UP)
