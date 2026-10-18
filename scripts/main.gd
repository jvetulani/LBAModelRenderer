extends Node3D

var _source_field: LineEdit
var _entry_number: SpinBox
var _status: Label
var _dither_mode: OptionButton
var _loaded_body_summary := ""
var _character: Node3D
var _camera: Camera3D
var _orbit_yaw := deg_to_rad(20.0)
var _orbit_pitch := deg_to_rad(12.0)
var _orbit_distance := 4.4
var _orbit_focus := Vector3(0.0, 0.75, 0.0)


func _ready() -> void:
	_build_stage()
	_build_controls()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba-source="):
			_source_field.text = argument.trim_prefix("--lba-source=")
		if argument.begins_with("--body-index="):
			_entry_number.value = int(argument.trim_prefix("--body-index="))
	if not _source_field.text.is_empty():
		call_deferred("_load_source")


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.11, 0.14, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.38, 0.43)
	environment.ambient_light_energy = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.4
	add_child(_camera)
	_update_camera()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy = 1.0
	add_child(sun)

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.offset_bottom = 78.0
	screen.add_child(panel)
	var vertical := VBoxContainer.new()
	panel.add_child(vertical)
	var row := HBoxContainer.new()
	vertical.add_child(row)
	_source_field = LineEdit.new()
	_source_field.placeholder_text = "Choose your local LBA1 installation folder"
	_source_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_source_field)
	var choose := Button.new()
	choose.text = "Browse"
	row.add_child(choose)
	row.add_child(Label.new())
	var entry_label := Label.new()
	entry_label.text = "BODY entry"
	row.add_child(entry_label)
	_entry_number = SpinBox.new()
	_entry_number.min_value = 0
	_entry_number.max_value = 999
	_entry_number.step = 1
	row.add_child(_entry_number)
	var load_button := Button.new()
	load_button.text = "Load"
	row.add_child(load_button)
	_dither_mode = OptionButton.new()
	_dither_mode.add_item("Dither off", 0)
	_dither_mode.add_item("Source faces", 1)
	_dither_mode.add_item("Full model", 2)
	_dither_mode.select(2)
	_dither_mode.tooltip_text = "Full model dithers Gouraud faces such as the tunic. Source faces follows material tags. Both use an approximate pattern."
	row.add_child(_dither_mode)
	_status = Label.new()
	_status.text = "LBA1 static-pose proof of concept. Drag to orbit; wheel to zoom."
	vertical.add_child(_status)

	var folder_dialog := FileDialog.new()
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.title = "Select LBA1 installation folder"
	screen.add_child(folder_dialog)
	choose.pressed.connect(func() -> void: folder_dialog.popup_centered_ratio(0.7))
	folder_dialog.dir_selected.connect(func(path: String) -> void: _source_field.text = path)
	load_button.pressed.connect(_load_source)
	_dither_mode.item_selected.connect(_set_dither_mode)
	_source_field.text_submitted.connect(func(_unused: String) -> void: _load_source())


func _load_source() -> void:
	_loaded_body_summary = ""
	var directory := _source_field.text.strip_edges()
	if directory.is_empty():
		_status.text = "Choose a local LBA1 installation folder first."
		return
	var body_result := HQRReader.read_entry(directory.path_join("BODY.HQR"), int(_entry_number.value))
	if not body_result["ok"]:
		_status.text = body_result["error"]
		return
	var palette_result := HQRReader.read_entry(directory.path_join("RESS.HQR"), 0)
	if not palette_result["ok"]:
		_status.text = palette_result["error"]
		return
	var palette_bytes: PackedByteArray = palette_result["data"]
	if palette_bytes.size() != 768:
		_status.text = "RESS.HQR entry 0 is not the expected LBA1 768-byte palette."
		return
	var body_bytes: PackedByteArray = body_result["data"]
	var decoded := LBA1BodyDecoder.decode(body_bytes)
	if not decoded["ok"]:
		_status.text = decoded["error"]
		return
	if is_instance_valid(_character):
		_character.queue_free()
	_character = CharacterMeshBuilder.build_static_pose(decoded, palette_bytes)
	_set_dither_mode(_dither_mode.selected)
	var posed_points: PackedVector3Array = decoded["pose_points"]
	var min_y := posed_points[0].y
	var max_y := min_y
	for point in posed_points:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var stand_point: Marker3D = $CharacterStandPoint
	_character.position = stand_point.position - Vector3.UP * min_y * CharacterMeshBuilder.UNIT_SCALE
	add_child(_character)
	_orbit_focus = stand_point.position + Vector3.UP * (max_y - min_y) * CharacterMeshBuilder.UNIT_SCALE * 0.5
	_orbit_distance = maxf(3.0, (max_y - min_y) * CharacterMeshBuilder.UNIT_SCALE * 1.8)
	_camera.size = maxf(1.8, (max_y - min_y) * CharacterMeshBuilder.UNIT_SCALE * 1.45)
	_update_camera()
	_loaded_body_summary = "BODY.HQR #%d: %d points, %d polygons, %d lines, %d spheres." % [
		int(_entry_number.value),
		decoded["points"].size(),
		decoded["polygons"].size(),
		decoded["lines"].size(),
		decoded["spheres"].size(),
	]
	_refresh_status()


func _set_dither_mode(mode: int) -> void:
	_dither_mode.select(mode)
	if not is_instance_valid(_character):
		return
	var polygon_mesh: MeshInstance3D = _character.get_node("Polygons")
	var material: ShaderMaterial = polygon_mesh.material_override
	material.set_shader_parameter("dither_mode", mode)
	_refresh_status()


func _refresh_status() -> void:
	if not _loaded_body_summary.is_empty():
		var dither_description := "dither off" if _dither_mode.selected == 0 else "%s dither approximation" % _dither_mode.get_item_text(_dither_mode.selected)
		_status.text = "%s Source-index shading; %s." % [
			_loaded_body_summary, dither_description
		]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_orbit_yaw -= event.relative.x * 0.008
		_orbit_pitch = clamp(_orbit_pitch + event.relative.y * 0.008, -1.2, 1.2)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = maxf(0.8, _camera.size * 0.9)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = minf(12.0, _camera.size * 1.1)
			_update_camera()


func _update_camera() -> void:
	var offset := Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch),
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos(_orbit_pitch)
	) * _orbit_distance
	_camera.position = _orbit_focus + offset
	_camera.look_at(_orbit_focus, Vector3.UP)
