class_name OrbitCamera
extends Camera3D

var yaw := deg_to_rad(20.0)
var pitch := deg_to_rad(12.0)
var distance := 4.4
var focus := Vector3(0.0, 0.75, 0.0)


func _ready() -> void:
	_update_pose()


func frame_points(points: PackedVector3Array, stand_position: Vector3) -> void:
	var min_y := points[0].y
	var max_y := min_y
	for point in points:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var height := (max_y - min_y) * CharacterMeshBuilder.UNIT_SCALE
	focus = stand_position + Vector3.UP * height * 0.5
	distance = maxf(3.0, height * 1.8)
	size = maxf(1.8, height * 1.45)
	_update_pose()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			yaw -= event.relative.x * 0.008
			pitch = clampf(pitch + event.relative.y * 0.008, -1.2, 1.2)
			_update_pose()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			var units_per_pixel := size / maxf(1.0, get_viewport().get_visible_rect().size.y)
			focus += (-global_basis.x * event.relative.x + global_basis.y * event.relative.y) * units_per_pixel
			_update_pose()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			size = maxf(0.8, size * 0.9)
			_update_pose()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size = minf(12.0, size * 1.1)
			_update_pose()


func _update_pose() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	position = focus + offset
	look_at(focus, Vector3.UP)
