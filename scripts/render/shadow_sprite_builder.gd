class_name ShadowSpriteBuilder
extends RefCounted

const SHADOW_SHADER := preload("res://shaders/lba_shadow.gdshader")


static func build(sprite: Dictionary, palette: PackedByteArray) -> MeshInstance3D:
	var texture := ImageTexture.create_from_image(make_image(sprite, palette))
	var material := ShaderMaterial.new()
	material.shader = SHADOW_SHADER
	material.set_shader_parameter("shadow_texture", texture)
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.72, 0.45)
	var node := MeshInstance3D.new()
	node.name = "LBA1ActorShadow"
	node.mesh = plane
	node.material_override = material
	return node


static func make_image(sprite: Dictionary, palette: PackedByteArray) -> Image:
	var width: int = sprite["width"]
	var height: int = sprite["height"]
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			var at := y * width + x
			if sprite["coverage"][at] == 0:
				continue
			var palette_at := int(sprite["pixels"][at]) * 3
			image.set_pixel(x, y, Color(
				float(palette[palette_at] >> 2) / 63.0,
				float(palette[palette_at + 1] >> 2) / 63.0,
				float(palette[palette_at + 2] >> 2) / 63.0,
				1.0
			))
	return image
