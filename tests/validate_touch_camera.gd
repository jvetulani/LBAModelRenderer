extends SceneTree


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var camera := OrbitCamera.new()
	root.add_child(camera)
	var initial_yaw := camera.yaw
	_touch(camera, 0, Vector2(100, 100), true)
	_drag(camera, 0, Vector2(120, 100))
	assert(camera.yaw < initial_yaw, "One finger must orbit")
	_touch(camera, 1, Vector2(220, 100), true)
	var initial_size := camera.size
	_drag(camera, 1, Vector2(260, 100))
	assert(camera.size < initial_size, "Pinching fingers apart must zoom in")
	var initial_focus := camera.focus
	_drag(camera, 0, Vector2(140, 120))
	_drag(camera, 1, Vector2(280, 120))
	assert(camera.focus.distance_to(initial_focus) > 0.01, "Two finger drag must pan")
	_drag(camera, 1, Vector2(180, 120))
	assert(camera.size > initial_size * 0.95, "Pinching fingers together must zoom out")
	_touch(camera, 0, Vector2(140, 120), false)
	_touch(camera, 1, Vector2(180, 120), false)
	assert(camera.get("_touches").is_empty(), "Released fingers must clear gesture state")
	print("PASS: one finger orbit, pinch zoom, two finger pan, and touch release")
	quit()


func _touch(camera: OrbitCamera, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	camera._unhandled_input(event)


func _drag(camera: OrbitCamera, index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	camera._unhandled_input(event)
