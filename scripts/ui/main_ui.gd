class_name MainUI
extends CanvasLayer

const BODY_NAMES = preload("res://scripts/ui/body_names.gd")

const ACTIVE_YELLOW := Color(0.98, 0.68, 0.075)
const INACTIVE_WHITE := Color(0.88, 0.90, 0.94)
const DISABLED_GREY := Color(0.55, 0.59, 0.65, 0.75)

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
signal bones_visible_changed(visible: bool)
signal motion_grid_visible_changed(visible: bool)
signal lba2_palette_selected(index: int)
signal share_requested
signal embed_share_requested

@onready var source_field: LineEdit = $Screen/TopPanel/Vertical/SourceRow/SourceField
@onready var body_number: LineEdit = $Screen/TopPanel/Vertical/SourceRow/BodyNumber
@onready var body_label: Label = $Screen/TopPanel/Vertical/SourceRow/BodyLabel
@onready var dither_mode: OptionButton = $Screen/TopPanel/Vertical/SourceRow/DitherMode
@onready var status_label: Label = $Screen/Status
@onready var animation_list: OptionButton = $Screen/AnimationPanel/AnimationRow/AnimationList
@onready var play_button: Button = $Screen/AnimationPanel/AnimationRow/PlayButton
@onready var speed_list: OptionButton = $Screen/AnimationPanel/AnimationRow/SpeedList
@onready var frame_slider: HSlider = $Screen/AnimationPanel/AnimationRow/FrameSlider
@onready var frame_label: Label = $Screen/AnimationPanel/AnimationRow/FrameLabel
@onready var folder_dialog: FileDialog = $Screen/FolderDialog
@onready var export_dialog: FileDialog = $Screen/ExportDialog
@onready var browse_button: Button = $Screen/TopPanel/Vertical/SourceRow/BrowseButton
@onready var blender_button: Button = $Screen/TopPanel/Vertical/SourceRow/ExportBlenderButton
@onready var copy_link_button: Button = $Screen/TopPanel/Vertical/SourceRow/CopyLinkButton
@onready var copy_embed_button: Button = $Screen/TopPanel/Vertical/SourceRow/CopyEmbedButton
@onready var palette_list: OptionButton = $Screen/LBA2Palette
@onready var shadow_toggle: CheckButton = $Screen/ShadowToggle
@onready var shadow_label: Label = $Screen/ShadowLabel
@onready var platform_toggle: CheckButton = $Screen/PlatformToggle
@onready var platform_label: Label = $Screen/PlatformLabel
@onready var wireframe_toggle: CheckButton = $Screen/WireframeToggle
@onready var wireframe_label: Label = $Screen/WireframeLabel
@onready var bones_toggle: CheckButton = $Screen/BonesToggle
@onready var bones_label: Label = $Screen/BonesLabel
@onready var motion_grid_toggle: CheckButton = $Screen/MotionGridToggle
@onready var motion_grid_label: Label = $Screen/MotionGridLabel

var _syncing_frame := false
var _has_animation := false
var _animation_entries: Array = []
var _show_compatible_clips := false
var _playing := false
var _pending_export := ""
var _body_entry_count := 0
var _play_icon: Texture2D
var _pause_icon: AtlasTexture
var _body_game := "LBA1"
var _find_button: Button
var _mobile_find_button: Button
var _find_dialog: Control
var _find_panel: PanelContainer
var _find_query: LineEdit
var _find_results: ItemList
var _asset_picker: OptionButton


func _ready() -> void:
	_play_icon = play_button.icon
	_pause_icon = AtlasTexture.new()
	_pause_icon.atlas = preload("res://assets/ui/icons/pause.png")
	_pause_icon.region = Rect2(64, 48, 144, 160)
	browse_button.pressed.connect(_browse_source)
	body_number.text_submitted.connect(func(_value: String) -> void: request_load())
	$Screen/BodyNavigation/PreviousBody.pressed.connect(func() -> void: _step_body(-1))
	$Screen/BodyNavigation/NextBody.pressed.connect(func() -> void: _step_body(1))
	_setup_body_search()
	_setup_asset_picker()
	get_viewport().size_changed.connect(_update_find_layout)
	call_deferred("_update_find_layout")
	platform_toggle.toggled.connect(func(visible: bool) -> void: platform_visible_changed.emit(visible))
	shadow_toggle.toggled.connect(func(visible: bool) -> void: shadow_visible_changed.emit(visible))
	wireframe_toggle.toggled.connect(func(visible: bool) -> void: wireframe_visible_changed.emit(visible))
	bones_toggle.toggled.connect(func(visible: bool) -> void: bones_visible_changed.emit(visible))
	motion_grid_toggle.toggled.connect(func(visible: bool) -> void: motion_grid_visible_changed.emit(visible))
	_bind_switch_color(platform_toggle, platform_label)
	_bind_switch_color(shadow_toggle, shadow_label)
	_bind_switch_color(wireframe_toggle, wireframe_label)
	_bind_switch_color(bones_toggle, bones_label)
	_bind_switch_color(motion_grid_toggle, motion_grid_label)
	palette_list.item_selected.connect(func(index: int) -> void: lba2_palette_selected.emit(palette_list.get_item_id(index)))
	$Screen/TopPanel/Vertical/SourceRow/ExportGLBButton.pressed.connect(func() -> void: _request_export("glb"))
	blender_button.pressed.connect(func() -> void: _request_export("blend"))
	copy_link_button.pressed.connect(func() -> void: share_requested.emit())
	copy_embed_button.pressed.connect(func() -> void: embed_share_requested.emit())
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
	animation_list.item_selected.connect(func(index: int) -> void:
		var archive_index := animation_list.get_item_id(index)
		if archive_index == -2 or archive_index == -3:
			_show_compatible_clips = archive_index == -2
			play_changed.emit(false)
			set_play_state(false)
			_populate_animation_list()
		elif archive_index >= 0:
			play_button.disabled = false
			frame_slider.editable = true
			animation_selected.emit(archive_index)
	)
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
	else:
		copy_link_button.hide()
		copy_embed_button.hide()
	set_game("LBA1")
	set_shadow_available(false)


func set_game(game_name: String) -> void:
	_body_game = game_name
	palette_list.visible = game_name == "LBA2"
	if _asset_picker != null:
		var is_aitd := game_name.begins_with("AITD")
		_asset_picker.visible = not is_aitd
		if is_aitd:
			_asset_picker.select(0)
	_update_find_layout()
	set_current_body(body_index())


func set_current_body(index: int) -> void:
	if asset_kind() == "inventory":
		var inventory_name := BODY_NAMES.inventory_name_for(_body_game, index)
		body_label.text = "Item · %s" % inventory_name if not inventory_name.is_empty() else "Item #%d" % index
		body_label.tooltip_text = "Viewer label · source inventory model #%d" % index
		return
	if _body_game.begins_with("AITD"):
		var aitd_name := BODY_NAMES.aitd_name_for(_body_game, index)
		body_label.text = "AITD · %s" % aitd_name if not aitd_name.is_empty() else "PAK model #%d" % index
		body_label.tooltip_text = "Viewer label · LISTBODY.PAK model #%d" % index
		return
	var name := BODY_NAMES.name_for(_body_game, index)
	body_label.text = "BODY entry" if name.is_empty() else "BODY · %s" % (name.left(28) + "…" if name.length() > 28 else name)
	body_label.tooltip_text = name


func _unhandled_key_input(event: InputEvent) -> void:
	if _find_dialog.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_find_dialog.hide()
		get_viewport().set_input_as_handled()


func _setup_body_search() -> void:
	_find_button = Button.new()
	_find_button.text = "Find…"
	_find_button.tooltip_text = "Search BODY entries by name or number"
	body_number.get_parent().add_child(_find_button)
	body_number.get_parent().move_child(_find_button, body_number.get_index() + 1)
	_find_button.pressed.connect(_show_body_search)
	_mobile_find_button = Button.new()
	_mobile_find_button.text = "Find model"
	_mobile_find_button.tooltip_text = _find_button.tooltip_text
	_mobile_find_button.position = Vector2(12, 82)
	_mobile_find_button.size = Vector2(112, 38)
	_mobile_find_button.visible = false
	$Screen.add_child(_mobile_find_button)
	_mobile_find_button.pressed.connect(_show_body_search)
	_find_dialog = Control.new()
	_find_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_find_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_find_dialog.visible = false
	$Screen.add_child(_find_dialog)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.04, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_find_dialog.add_child(shade)
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_find_dialog.hide()
	)
	_find_panel = PanelContainer.new()
	_find_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_find_panel.custom_minimum_size = Vector2(620, 500)
	_find_panel.position = -_find_panel.custom_minimum_size / 2.0
	_find_panel.size = _find_panel.custom_minimum_size
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.105, 0.14, 0.19)
	panel_style.border_color = ACTIVE_YELLOW
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(18)
	_find_panel.add_theme_stylebox_override("panel", panel_style)
	_find_dialog.add_child(_find_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_find_panel.add_child(layout)
	var title := Label.new()
	title.text = "Find a model"
	title.add_theme_color_override("font_color", ACTIVE_YELLOW)
	title.add_theme_font_size_override("font_size", 21)
	layout.add_child(title)
	_find_query = LineEdit.new()
	_find_query.placeholder_text = "Name or entry number · Zoé, pram, 203…"
	layout.add_child(_find_query)
	_find_results = ItemList.new()
	_find_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_find_results.add_theme_color_override("font_color", INACTIVE_WHITE)
	_find_results.add_theme_color_override("font_selected_color", Color(0.07, 0.09, 0.12))
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.07, 0.095, 0.13)
	list_style.set_corner_radius_all(6)
	_find_results.add_theme_stylebox_override("panel", list_style)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = ACTIVE_YELLOW
	selected_style.set_corner_radius_all(4)
	_find_results.add_theme_stylebox_override("selected", selected_style)
	_find_results.add_theme_stylebox_override("selected_focus", selected_style)
	layout.add_child(_find_results)
	var note := Label.new()
	note.text = "Community labels · BODY archives contain entry numbers"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", DISABLED_GREY)
	layout.add_child(note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(buttons)
	var close_button := Button.new()
	close_button.text = "Close"
	buttons.add_child(close_button)
	close_button.pressed.connect(func() -> void: _find_dialog.hide())
	var open_button := Button.new()
	open_button.text = "Open"
	buttons.add_child(open_button)
	open_button.pressed.connect(_open_found_body)
	_find_query.text_changed.connect(func(_value: String) -> void: _refresh_body_search())
	_find_query.text_submitted.connect(func(_value: String) -> void: _open_found_body())
	_find_results.item_activated.connect(func(_index: int) -> void: _open_found_body())
	_update_find_layout()


func _setup_asset_picker() -> void:
	_asset_picker = OptionButton.new()
	_asset_picker.add_item("Bodies", 0)
	_asset_picker.add_item("Inventory", 1)
	_asset_picker.tooltip_text = "Choose bodies or inventory models"
	_asset_picker.add_theme_color_override("font_color", ACTIVE_YELLOW)
	_asset_picker.add_theme_color_override("font_pressed_color", Color(0.12, 0.10, 0.02))
	_asset_picker.get_popup().add_theme_color_override("font_color", INACTIVE_WHITE)
	var row: HBoxContainer = body_number.get_parent()
	row.add_child(_asset_picker)
	row.move_child(_asset_picker, body_label.get_index())
	_asset_picker.item_selected.connect(func(_index: int) -> void:
		body_number.text = "0"
		_body_entry_count = 0
		request_load()
	)


func asset_kind() -> String:
	if _asset_picker == null or _body_game.begins_with("AITD"):
		return "body"
	match _asset_picker.get_selected_id():
		1: return "inventory"
	return "body"


func _update_find_layout() -> void:
	if _find_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.x < 900.0
	_find_button.visible = not compact
	_mobile_find_button.visible = compact
	if _asset_picker != null:
		var target: Node = $Screen if compact else body_number.get_parent()
		if _asset_picker.get_parent() != target:
			_asset_picker.reparent(target)
		if compact:
			_asset_picker.position = Vector2(12, 126)
			_asset_picker.size = Vector2(115, 38)
		else:
			body_number.get_parent().move_child(_asset_picker, body_label.get_index())
	var panel_size := Vector2(minf(620.0, viewport_size.x - 24.0), minf(500.0, viewport_size.y - 24.0))
	_find_panel.custom_minimum_size = panel_size
	_find_panel.offset_left = -panel_size.x / 2.0
	_find_panel.offset_right = panel_size.x / 2.0
	_find_panel.offset_top = -panel_size.y / 2.0
	_find_panel.offset_bottom = panel_size.y / 2.0


func _show_body_search() -> void:
	_find_query.clear()
	_find_query.placeholder_text = "Search name or entry number…" if asset_kind() == "inventory" or _body_game.begins_with("AITD") else ("Search LBA1 models…" if _body_game == "LBA1" else "Name or entry number · Zoé, pram, 203…")
	_refresh_body_search()
	_find_dialog.show()
	_find_query.grab_focus()


func _refresh_body_search() -> void:
	_find_results.clear()
	var terms := BODY_NAMES.normalize(_find_query.text.strip_edges()).split(" ", false)
	for index in range(_body_entry_count):
		var name := BODY_NAMES.inventory_name_for(_body_game, index) if asset_kind() == "inventory" else (BODY_NAMES.aitd_name_for(_body_game, index) if _body_game.begins_with("AITD") else BODY_NAMES.name_for(_body_game, index))
		var haystack := BODY_NAMES.normalize("%d %s" % [index, name]) if asset_kind() == "inventory" or _body_game.begins_with("AITD") else BODY_NAMES.search_text(_body_game, index)
		var matches := true
		for term in terms:
			if not haystack.contains(term):
				matches = false
				break
		if not matches:
			continue
		_find_results.add_item("#%d · %s" % [index, name if not name.is_empty() else ("Unnamed item" if asset_kind() == "inventory" else "Unnamed model")])
		_find_results.set_item_metadata(_find_results.item_count - 1, index)
	if _find_results.item_count > 0:
		_find_results.select(0)


func _open_found_body() -> void:
	var selected := _find_results.get_selected_items()
	if selected.is_empty():
		return
	body_number.text = str(_find_results.get_item_metadata(selected[0]))
	_find_dialog.hide()
	request_load()


func set_shadow_available(available: bool) -> void:
	shadow_toggle.disabled = not available
	_refresh_switch_color(shadow_toggle, shadow_label)
	shadow_visible_changed.emit(available and shadow_toggle.button_pressed)


func _bind_switch_color(toggle: CheckButton, label: Label) -> void:
	toggle.toggled.connect(func(_pressed: bool) -> void: _refresh_switch_color(toggle, label))
	_refresh_switch_color(toggle, label)


func _refresh_switch_color(toggle: CheckButton, label: Label) -> void:
	var color := DISABLED_GREY if toggle.disabled else (ACTIVE_YELLOW if toggle.button_pressed else INACTIVE_WHITE)
	toggle.self_modulate = color
	label.self_modulate = color


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


func set_share_available(available: bool) -> void:
	copy_link_button.disabled = not available
	copy_embed_button.disabled = not available


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
	_animation_entries = entries
	_show_compatible_clips = false
	_populate_animation_list()


func _populate_animation_list() -> void:
	animation_list.clear()
	var associated := []
	var compatible := []
	for entry in _animation_entries:
		if entry.get("associated", true):
			associated.append(entry)
		else:
			compatible.append(entry)
	var visible_entries: Array = _animation_entries if _show_compatible_clips else associated
	_has_animation = not visible_entries.is_empty()
	if _show_compatible_clips:
		animation_list.add_item("← Associated clips", -3)
	if visible_entries.is_empty():
		animation_list.add_item("No associated animations", -1)
	else:
		for entry in visible_entries:
			animation_list.add_item("%s · ANIM #%d" % [entry["name"], entry["archive_index"]], entry["archive_index"])
	if not compatible.is_empty() and not _show_compatible_clips:
		animation_list.add_item("More compatible clips… (%d)" % compatible.size(), -2)
	animation_list.select(0)
	animation_list.disabled = _animation_entries.is_empty()
	play_button.disabled = not _has_animation or animation_list.get_item_id(0) < 0
	frame_slider.editable = not play_button.disabled
	set_play_state(false)
	set_frame(0, 0, 0)


func first_animation_id() -> int:
	return animation_list.get_item_id(0) if _has_animation and animation_list.get_item_id(0) >= 0 else -1


func selected_animation_id() -> int:
	return animation_list.get_selected_id() if _has_animation and animation_list.get_selected_id() >= 0 else -1


func select_animation_id(archive_index: int) -> bool:
	if not _has_animation:
		return false
	var item_index := animation_list.get_item_index(archive_index)
	if item_index < 0:
		return false
	animation_list.select(item_index)
	play_button.disabled = false
	frame_slider.editable = true
	return true


func set_play_state(value: bool) -> void:
	_playing = value
	play_button.icon = _pause_icon if value else _play_icon
	play_button.tooltip_text = "Pause animation" if value else "Play animation"


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
