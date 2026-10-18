extends Node3D

@onready var ui: MainUI = $MainUI
@onready var viewer: CharacterViewer = $CharacterViewer
@onready var orbit_camera: OrbitCamera = $OrbitCamera
@onready var stand_point: Marker3D = $CharacterStandPoint
@onready var web_picker: WebArchivePicker = $WebArchivePicker

var _web_archives: Dictionary = {}


func _ready() -> void:
	viewer.stand_position = stand_point.position
	ui.load_requested.connect(_load_source)
	ui.archive_files_requested.connect(web_picker.pick)
	web_picker.archives_ready.connect(_on_archives_ready)
	web_picker.failed.connect(ui.set_status)
	ui.dither_changed.connect(viewer.set_dither_mode)
	ui.animation_selected.connect(_select_animation)
	ui.play_changed.connect(viewer.set_playing)
	ui.speed_changed.connect(viewer.set_speed)
	ui.scrubbed.connect(viewer.scrub_to)
	viewer.playback_frame_changed.connect(ui.set_frame)
	var directory := ""
	var body_index := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lba-source="):
			directory = argument.trim_prefix("--lba-source=")
		elif argument.begins_with("--body-index="):
			body_index = int(argument.trim_prefix("--body-index="))
	ui.set_source(directory, body_index)
	if not directory.is_empty():
		call_deferred("_load_source", directory, body_index)


func _load_source(directory: String, body_index: int) -> void:
	if OS.has_feature("web") and _web_archives.is_empty():
		ui.set_status("Choose the four LBA1 HQR archives first.")
		return
	if not OS.has_feature("web") and directory.is_empty():
		ui.set_status("Choose a local LBA1 installation folder first.")
		return
	var result := viewer.load_archives(_web_archives, body_index) if OS.has_feature("web") else viewer.load_body(directory, body_index)
	if not result["ok"]:
		ui.set_status(result["error"])
		return
	orbit_camera.frame_points(result["points"], stand_point.position)
	viewer.set_dither_mode(ui.dither_mode.get_selected_id())
	ui.set_animations(result["animations"])
	var shadow_note := "source shadow" if result["shadow_loaded"] else "shadow unavailable"
	ui.set_status("%s; %s; %d associated animations." % [result["summary"], shadow_note, result["animations"].size()])
	var first_animation := ui.first_animation_id()
	if first_animation >= 0:
		_select_animation(first_animation)


func _on_archives_ready(archives: Dictionary) -> void:
	_web_archives = archives
	_load_source("", ui.body_index())


func _select_animation(archive_index: int) -> void:
	var result := viewer.select_animation(archive_index)
	if not result["ok"]:
		ui.set_status("ANIM.HQR #%d: %s" % [archive_index, result["error"]])
		ui.set_play_state(false)
		return
	ui.set_play_state(true)
