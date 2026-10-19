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
var _embed_mode := false
var _transparent_mode := false


func _ready() -> void:
	viewer.stand_position = stand_point.position
	ui.load_requested.connect(_load_source)
	ui.archive_files_requested.connect(web_picker.pick)
	web_picker.archives_ready.connect(_on_archives_ready)
	web_picker.failed.connect(_on_web_load_failed)
	web_picker.share_finished.connect(ui.set_status)
	ui.share_requested.connect(_copy_link)
	ui.embed_share_requested.connect(_copy_embed_link)
	ui.dither_changed.connect(viewer.set_dither_mode)
	ui.dither_changed.connect(display_platform.set_dither_mode)
	ui.platform_visible_changed.connect(func(visible: bool) -> void: display_platform.visible = visible)
	ui.shadow_visible_changed.connect(viewer.set_shadow_visible)
	ui.wireframe_visible_changed.connect(viewer.set_wireframe_visible)
	ui.motion_grid_visible_changed.connect(viewer.set_motion_grid_visible)
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
					anim: page.searchParams.get('anim') || '-1',
					embed: page.searchParams.get('embed') === '1' || page.searchParams.get('ui') === '0',
					transparent: page.searchParams.get('transparent') === '1'
				});
			})()
		""")))
		if deep_link is Dictionary:
			_embed_mode = bool(deep_link.get("embed", false))
			_transparent_mode = bool(deep_link.get("transparent", false))
			if not str(deep_link.get("link", "")).is_empty():
				directory = str(deep_link["link"])
				body_index = maxi(0, int(deep_link.get("body", "0")))
				_pending_animation = int(deep_link.get("anim", "-1"))
				if _embed_mode:
					ui.visible = false
					display_platform.visible = false
					viewer.set_motion_grid_visible(false)
				if _transparent_mode:
					_enable_transparent_background()
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
		_on_web_load_failed(result["error"])
		return
	_active_source = directory
	ui.set_body_entry_count(result["entry_count"])
	ui.set_share_available(OS.has_feature("web") and (directory.begins_with("https://") or directory.begins_with("http://")))
	orbit_camera.frame_points(result["points"], stand_point.position)
	display_platform.set_game(viewer.game)
	ui.set_game(viewer.game)
	ui.set_current_body(body_index)
	ui.set_shadow_available(result["shadow_loaded"])
	viewer.set_dither_mode(ui.dither_mode.get_selected_id())
	ui.set_animations(result["animations"])
	var shadow_note := "source shadow" if result["shadow_loaded"] else "shadow unavailable"
	ui.set_status("%s; %s; %d associated animations." % [result["summary"], shadow_note, result["animations"].size()])
	var animation_id := _pending_animation if ui.select_animation_id(_pending_animation) else ui.first_animation_id()
	_pending_animation = -1
	if animation_id >= 0:
		_select_animation(animation_id)
	if _embed_mode:
		ui.visible = false
		display_platform.visible = false


func _enable_transparent_background() -> void:
	get_viewport().transparent_bg = true
	var stage_environment: WorldEnvironment = $StageEnvironment
	stage_environment.environment = stage_environment.environment.duplicate()
	stage_environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	JavaScriptBridge.eval("document.documentElement.style.background = 'transparent'; document.body.style.background = 'transparent'; const canvas = document.querySelector('canvas'); if (canvas) canvas.style.background = 'transparent';")


func _on_web_load_failed(message: String) -> void:
	if _embed_mode:
		ui.visible = true
	ui.set_status(message)


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


func _copy_embed_link() -> void:
	if not OS.has_feature("web") or not (_active_source.begins_with("https://") or _active_source.begins_with("http://")):
		ui.set_status("Load an HTTP or HTTPS archive folder to make an embed link.")
		return
	web_picker.copy_deep_link(_active_source, ui.body_index(), ui.selected_animation_id(), true)


func _select_animation(archive_index: int) -> void:
	var result := viewer.select_animation(archive_index)
	if not result["ok"]:
		ui.set_status("ANIM.HQR #%d: %s" % [archive_index, result["error"]])
		ui.set_play_state(false)
		return
	if result.get("display_body_index", ui.body_index()) != ui.body_index():
		ui.set_status("ANIM.HQR #%d uses BODY.HQR #%d from this character's alternate form." % [archive_index, result["display_body_index"]])
	elif result.get("skeleton_review", false):
		ui.set_status("ANIM.HQR #%d has %d groups; BODY.HQR #%d has %d. This shared action may need another form." % [archive_index, result["group_count"], ui.body_index(), result["body_group_count"]])
	ui.set_play_state(true)
