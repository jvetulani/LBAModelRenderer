@tool
class_name DisplayPlatform
extends MeshInstance3D

@export_range(0, 255, 1) var palette_index := 240:
	set(value):
		palette_index = value
		_apply_palette_index()

@export_range(0, 255, 1) var lba2_palette_index := 228


func _ready() -> void:
	_apply_palette_index()
	if Engine.is_editor_hint():
		return
	var viewer: CharacterViewer = get_node_or_null("../CharacterViewer")
	if viewer != null:
		viewer.palette_texture_ready.connect(set_palette_texture)


func set_palette_texture(texture: Texture2D) -> void:
	var material := material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("palette_texture", texture)


func set_dither_mode(mode: int) -> void:
	var material := material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("dither_mode", mode)


func set_game(game: String) -> void:
	var material := material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("palette_index_override", lba2_palette_index if game == "LBA2" else palette_index)


func _apply_palette_index() -> void:
	var material := material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("palette_index_override", palette_index)
