extends Node3D

@onready var ui: MainUI = $MainUI
@onready var viewer: CharacterViewer = $CharacterViewer
@onready var orbit_camera: OrbitCamera = $OrbitCamera
@onready var stand_point: Marker3D = $CharacterStandPoint
@onready var display_platform: DisplayPlatform = $DisplayBlock
@onready var web_picker: WebArchivePicker = $WebArchivePicker

var _web_archives: Dictionary = {}
var _active_source := ""
var _pending_remote_body := 0
var _pending_animation := -1


func _ready() -> void:
	viewer.stand_position = stand_point.position
	ui.load_requested.connect(_load_source)
	ui.archive_files_requested.connect(web_picker.pick)
	web_picker.archives_ready.connect(_on_archives_ready)
	web_picker.failed.connect(ui.set_status)
	web_picker.share_finished.connect(ui.set_status)
	ui.share_requested.connect(_copy_link)
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
	if OS.has_feature("web"):
		var deep_link = JSON.parse_string(str(JavaScriptBridge.eval("""
			(() => {
				const page = new URL(window.location.href);
				const pathValue = page.pathname.split('/').find(part => part.startsWith('link='));
				return JSON.stringify({
					link: page.searchParams.get('link') || (pathValue ? decodeURIComponent(pathValue.slice(5)) : ''),
					body: page.searchParams.get('body') || '0',
					anim: page.searchParams.get('anim') || '-1'
				});
			})()
		""")))
		if deep_link is Dictionary and not str(deep_link.get("link", "")).is_empty():
			directory = str(deep_link["link"])
			body_index = maxi(0, int(deep_link.get("body", "0")))
			_pending_animation = int(deep_link.get("anim", "-1"))
	ui.set_source(directory, body_index)
	if not directory.is_empty():
		_active_source = directory
		call_deferred("_load_source", directory, body_index)


func _load_source(directory: String, body_index: int) -> void:
	if directory != _active_source:
		body_index = 0
		ui.set_source(directory, 0)
	if OS.has_feature("web") and (directory.begins_with("https://") or directory.begins_with("http://")) and (directory != web_picker.archives.get("_source_url", "")):
		_pending_remote_body = body_index
		ui.set_share_available(false)
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
		ui.set_share_available(false)
		ui.set_status(result["error"])
		return
	_active_source = directory
	ui.set_body_entry_count(result["entry_count"])
	ui.set_share_available(OS.has_feature("web") and (directory.begins_with("https://") or directory.begins_with("http://")))
	orbit_camera.frame_points(result["points"], stand_point.position)
	display_platform.set_game(viewer.game)
	ui.set_game(viewer.game)
	ui.set_shadow_available(result["shadow_loaded"])
	viewer.set_dither_mode(ui.dither_mode.get_selected_id())
	ui.set_animations(result["animations"])
	var shadow_note := "source shadow" if result["shadow_loaded"] else "shadow unavailable"
	ui.set_status("%s; %s; %d associated animations." % [result["summary"], shadow_note, result["animations"].size()])
	var animation_id := _pending_animation if ui.select_animation_id(_pending_animation) else ui.first_animation_id()
	_pending_animation = -1
	if animation_id >= 0:
		_select_animation(animation_id)


func _select_lba2_palette(index: int) -> void:
	var result := viewer.select_lba2_palette(index)
	if not result["ok"]:
		ui.set_status("LBA2 palette #%d: %s" % [index, result["error"]])
		return
	viewer.set_dither_mode(ui.dither_mode.get_selected_id())


func _on_archives_ready(archives: Dictionary, folder_name: String) -> void:
	_web_archives = archives
	var body_index := 0
	if folder_name.begins_with("https://") or folder_name.begins_with("http://"):
		web_picker.archives["_source_url"] = folder_name
		body_index = _pending_remote_body
	ui.set_source(folder_name, body_index)
	_load_source(folder_name, body_index)


func _copy_link() -> void:
	if not OS.has_feature("web") or not (_active_source.begins_with("https://") or _active_source.begins_with("http://")):
		ui.set_status("Load an HTTP or HTTPS archive folder to make a shareable link.")
		return
	web_picker.copy_deep_link(_active_source, ui.body_index(), ui.selected_animation_id())


func _select_animation(archive_index: int) -> void:
	var result := viewer.select_animation(archive_index)
	if not result["ok"]:
		ui.set_status("ANIM.HQR #%d: %s" % [archive_index, result["error"]])
		ui.set_play_state(false)
		return
	ui.set_play_state(true)
