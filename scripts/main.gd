extends Node3D

@onready var ui: MainUI = $MainUI
@onready var viewer: CharacterViewer = $CharacterViewer
@onready var orbit_camera: OrbitCamera = $OrbitCamera
@onready var stand_point: Marker3D = $CharacterStandPoint
@onready var display_platform: DisplayPlatform = $DisplayBlock
@onready var web_picker: WebArchivePicker = $WebArchivePicker

var _web_archives: Dictionary = {}
var _active_source := ""


func _ready() -> void:
	viewer.stand_position = stand_point.position
	ui.load_requested.connect(_load_source)
	ui.archive_files_requested.connect(web_picker.pick)
	web_picker.archives_ready.connect(_on_archives_ready)
	web_picker.failed.connect(ui.set_status)
	ui.dither_changed.connect(viewer.set_dither_mode)
	ui.dither_changed.connect(display_platform.set_dither_mode)
	ui.platform_visible_changed.connect(func(visible: bool) -> void: display_platform.visible = visible)
	ui.shadow_visible_changed.connect(viewer.set_shadow_visible)
	ui.wireframe_visible_changed.connect(viewer.set_wireframe_visible)
	ui.lba2_palette_selected.connect(_select_lba2_palette)
	display_platform.set_dither_mode(ui.dither_mode.get_selected_id())
	ui.animation_selected.connect(_select_animation)
	ui.play_changed.connect(viewer.set_playing)
	ui.speed_changed.connect(viewer.set_speed)
	ui.scrubbed.connect(viewer.scrub_to)
	viewer.playback_frame_changed.connect(ui.set_frame)
	viewer.playback_ended.connect(func() -> void: ui.set_play_state(false))
	var directory := ""
	var body_index := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba-source="):
			directory = argument.trim_prefix("--lba-source=")
		elif argument.begins_with("--body-index="):
			body_index = int(argument.trim_prefix("--body-index="))
	ui.set_source(directory, body_index)
	if not directory.is_empty():
		_active_source = directory
		call_deferred("_load_source", directory, body_index)


func _load_source(directory: String, body_index: int) -> void:
	if directory != _active_source:
		body_index = 0
		ui.set_source(directory, 0)
	if OS.has_feature("web") and (directory.begins_with("https://") or directory.begins_with("http://")) and (directory != web_picker.archives.get("_source_url", "")):
		ui.set_status("Loading source archives…")
		web_picker.load_url(directory)
		return
	if OS.has_feature("web") and _web_archives.is_empty():
		ui.set_status("Choose your game folder first.")
		return
	if not OS.has_feature("web") and directory.is_empty():
		ui.set_status("Choose a local game installation folder first.")
		return
	var result := viewer.load_archives(_web_archives, body_index) if OS.has_feature("web") else viewer.load_body(directory, body_index)
	if not result["ok"]:
		ui.set_status(result["error"])
		return
	_active_source = directory
	ui.set_body_entry_count(result["entry_count"])
	orbit_camera.frame_points(result["points"], stand_point.position)
	display_platform.set_game(viewer.game)
	ui.set_game(viewer.game)
	ui.set_shadow_available(result["shadow_loaded"])
	viewer.set_dither_mode(ui.dither_mode.get_selected_id())
	ui.set_animations(result["animations"])
	var shadow_note := "source shadow" if result["shadow_loaded"] else "shadow unavailable"
	ui.set_status("%s; %s; %d associated animations." % [result["summary"], shadow_note, result["animations"].size()])
	var first_animation := ui.first_animation_id()
	if first_animation >= 0:
		_select_animation(first_animation)


func _select_lba2_palette(index: int) -> void:
	var result := viewer.select_lba2_palette(index)
	if not result["ok"]:
		ui.set_status("LBA2 palette #%d: %s" % [index, result["error"]])
		return
	viewer.set_dither_mode(ui.dither_mode.get_selected_id())


func _on_archives_ready(archives: Dictionary, folder_name: String) -> void:
	_web_archives = archives
	if folder_name.begins_with("https://") or folder_name.begins_with("http://"):
		web_picker.archives["_source_url"] = folder_name
	ui.set_source(folder_name, 0)
	_load_source(folder_name, 0)


func _select_animation(archive_index: int) -> void:
	var result := viewer.select_animation(archive_index)
	if not result["ok"]:
		ui.set_status("ANIM.HQR #%d: %s" % [archive_index, result["error"]])
		ui.set_play_state(false)
		return
	ui.set_play_state(true)
