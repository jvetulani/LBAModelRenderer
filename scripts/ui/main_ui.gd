class_name MainUI
extends CanvasLayer

signal load_requested(directory: String, body_index: int)
signal dither_changed(mode: int)
signal animation_selected(archive_index: int)
signal play_changed(playing: bool)
signal speed_changed(speed: float)
signal scrubbed(frame_index: int)
signal archive_files_requested
signal export_requested(format: String, destination: String)
signal platform_visible_changed(visible: bool)
signal shadow_visible_changed(visible: bool)
signal wireframe_visible_changed(visible: bool)
signal lba2_palette_selected(index: int)

@onready var source_field: LineEdit = $Screen/TopPanel/Vertical/SourceRow/SourceField
@onready var body_number: LineEdit = $Screen/TopPanel/Vertical/SourceRow/BodyNumber
@onready var dither_mode: OptionButton = $Screen/TopPanel/Vertical/SourceRow/DitherMode
@onready var status_label: Label = $Screen/TopPanel/Vertical/Status
@onready var animation_list: OptionButton = $Screen/AnimationPanel/AnimationRow/AnimationList
@onready var play_button: Button = $Screen/AnimationPanel/AnimationRow/PlayButton
@onready var speed_list: OptionButton = $Screen/AnimationPanel/AnimationRow/SpeedList
@onready var frame_slider: HSlider = $Screen/AnimationPanel/AnimationRow/FrameSlider
@onready var frame_label: Label = $Screen/AnimationPanel/AnimationRow/FrameLabel
@onready var folder_dialog: FileDialog = $Screen/FolderDialog
@onready var export_dialog: FileDialog = $Screen/ExportDialog
@onready var browse_button: Button = $Screen/TopPanel/Vertical/SourceRow/BrowseButton
@onready var blender_button: Button = $Screen/TopPanel/Vertical/SourceRow/ExportBlenderButton
@onready var palette_list: OptionButton = $Screen/LBA2Palette
@onready var shadow_toggle: CheckButton = $Screen/ShadowToggle
@onready var shadow_label: Label = $Screen/ShadowLabel

var _syncing_frame := false
var _has_animation := false
var _playing := false
var _pending_export := ""
var _body_entry_count := 0


func _ready() -> void:
	browse_button.pressed.connect(_browse_source)
	body_number.text_submitted.connect(func(_value: String) -> void: request_load())
	$Screen/BodyNavigation/PreviousBody.pressed.connect(func() -> void: _step_body(-1))
	$Screen/BodyNavigation/NextBody.pressed.connect(func() -> void: _step_body(1))
	$Screen/PlatformToggle.toggled.connect(func(visible: bool) -> void: platform_visible_changed.emit(visible))
	shadow_toggle.toggled.connect(func(visible: bool) -> void: shadow_visible_changed.emit(visible))
	$Screen/WireframeToggle.toggled.connect(func(visible: bool) -> void: wireframe_visible_changed.emit(visible))
	palette_list.item_selected.connect(func(index: int) -> void: lba2_palette_selected.emit(palette_list.get_item_id(index)))
	$Screen/TopPanel/Vertical/SourceRow/ExportGLBButton.pressed.connect(func() -> void: _request_export("glb"))
	blender_button.pressed.connect(func() -> void: _request_export("blend"))
	export_dialog.file_selected.connect(func(path: String) -> void: export_requested.emit(_pending_export, path))
	folder_dialog.dir_selected.connect(func(path: String) -> void:
		source_field.text = path
		body_number.text = "0"
		_body_entry_count = 0
		request_load()
	)
	source_field.text_submitted.connect(func(_unused: String) -> void:
		body_number.text = "0"
		_body_entry_count = 0
		request_load()
	)
	dither_mode.item_selected.connect(func(index: int) -> void: dither_changed.emit(dither_mode.get_item_id(index)))
	animation_list.item_selected.connect(func(index: int) -> void: animation_selected.emit(animation_list.get_item_id(index)))
	play_button.pressed.connect(_toggle_play)
	speed_list.item_selected.connect(_on_speed_selected)
	frame_slider.value_changed.connect(_on_frame_changed)
	speed_list.select(1)
	set_animations([])
	if OS.has_feature("web"):
		source_field.editable = true
		source_field.placeholder_text = "Choose your game folder"
		browse_button.text = "Choose folder"
		blender_button.hide()
	set_game("LBA1")


func set_game(game_name: String) -> void:
	palette_list.visible = game_name == "LBA2"


func set_shadow_available(available: bool) -> void:
	shadow_toggle.visible = available
	shadow_label.visible = available
	shadow_visible_changed.emit(shadow_toggle.button_pressed)


func _browse_source() -> void:
	if OS.has_feature("web"):
		archive_files_requested.emit()
	else:
		folder_dialog.popup_centered_ratio(0.7)


func _request_export(format: String) -> void:
	if OS.has_feature("web"):
		export_requested.emit(format, "")
		return
	_pending_export = format
	export_dialog.clear_filters()
	if format == "blend":
		export_dialog.add_filter("*.blend", "Blender project")
		export_dialog.title = "Save Blender project"
	else:
		export_dialog.add_filter("*.glb", "glTF binary")
		export_dialog.title = "Save GLB"
	export_dialog.popup_centered_ratio(0.7)


func set_source(directory: String, body_index: int) -> void:
	source_field.text = directory
	body_number.text = str(body_index)
	_body_entry_count = 0


func set_body_entry_count(count: int) -> void:
	_body_entry_count = maxi(count, 0)


func request_load() -> void:
	var index := body_index()
	body_number.text = str(index)
	load_requested.emit(source_field.text.strip_edges(), index)


func body_index() -> int:
	return clampi(int(body_number.text), 0, _body_entry_count - 1 if _body_entry_count > 0 else 999)


func _step_body(direction: int) -> void:
	if _body_entry_count < 1:
		return
	body_number.text = str(posmod(body_index() + direction, _body_entry_count))
	request_load()


func set_status(message: String) -> void:
	status_label.text = message


func set_animations(entries: Array) -> void:
	animation_list.clear()
	_has_animation = not entries.is_empty()
	if entries.is_empty():
		animation_list.add_item("No associated animations", -1)
	else:
		for entry in entries:
			animation_list.add_item("%s · ANIM #%d" % [entry["name"], entry["archive_index"]], entry["archive_index"])
	animation_list.select(0)
	animation_list.disabled = not _has_animation
	play_button.disabled = not _has_animation
	frame_slider.editable = _has_animation
	set_play_state(false)
	set_frame(0, 0, 0)


func first_animation_id() -> int:
	return animation_list.get_item_id(0) if _has_animation else -1


func set_play_state(value: bool) -> void:
	_playing = value
	play_button.text = "Pause" if value else "Play"


func set_frame(frame_index: int, frame_count: int, duration_ticks: int) -> void:
	_syncing_frame = true
	frame_slider.max_value = max(0, frame_count - 1)
	frame_slider.value = frame_index
	_syncing_frame = false
	frame_label.text = "Frame %d/%d · %d ticks" % [frame_index + 1, frame_count, duration_ticks] if frame_count > 0 else "No animation"


func _toggle_play() -> void:
	set_play_state(not _playing)
	play_changed.emit(_playing)


func _on_speed_selected(index: int) -> void:
	var speeds := [0.5, 1.0, 2.0]
	speed_changed.emit(speeds[index])


func _on_frame_changed(value: float) -> void:
	if not _syncing_frame and _has_animation:
		scrubbed.emit(int(value))
