class_name ExportController
extends Node

@onready var viewer: CharacterViewer = $"../CharacterViewer"
@onready var ui: MainUI = $"../MainUI"


func _ready() -> void:
	ui.export_requested.connect(_export)


func _export(format: String, destination: String) -> void:
	var input := viewer.export_input()
	if not input["ok"]:
		ui.set_status(input["error"])
		return
	ui.set_status("Building LBA1 character and actions…")
	var result := LBA1GLBExporter.build(input)
	if not result["ok"]:
		ui.set_status(result["error"])
		return
	var filename := "lba1-body-%03d.glb" % ui.body_index()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(result["bytes"], filename, "model/gltf-binary")
		ui.set_status("Downloaded %s with %d source actions and shadow." % [filename, result["source_actions"]])
	elif format == "blend":
		_save_blender(result["bytes"], destination, result["source_actions"])
	else:
		var error := _write_bytes(destination, result["bytes"])
		ui.set_status("Saved %s with %d source actions and shadow." % [destination, result["source_actions"]] if error.is_empty() else error)


func _save_blender(bytes: PackedByteArray, destination: String, action_count: int) -> void:
	var source_script := FileAccess.open("res://tools/import_lba1_glb.py", FileAccess.READ)
	if source_script == null:
		ui.set_status("Blender conversion script is missing from the project")
		return
	var script_bytes := source_script.get_buffer(source_script.get_length())
	var script_path := ProjectSettings.globalize_path("user://import_lba1_glb.py")
	var glb_path := ProjectSettings.globalize_path("user://lba1-export-temp.glb")
	var script_error := _write_bytes(script_path, script_bytes)
	var glb_error := _write_bytes(glb_path, bytes)
	if not script_error.is_empty() or not glb_error.is_empty():
		ui.set_status(script_error if not script_error.is_empty() else glb_error)
		return
	var blender := OS.get_environment("LBA_BLENDER")
	if blender.is_empty():
		blender = "blender"
	var output := []
	var exit_code := OS.execute(blender, PackedStringArray(["-b", "-noaudio", "--factory-startup", "--python", script_path, "--", glb_path, destination]), output, true)
	var log := str(output[0]) if not output.is_empty() else ""
	if exit_code != 0 or not log.contains("SAVED %s:" % destination) or not FileAccess.file_exists(destination):
		ui.set_status("Blender export failed. Install Blender or set LBA_BLENDER. %s" % log.right(160))
		return
	ui.set_status("Saved %s with %d source actions, palette, dither and shadow." % [destination, action_count])


func _write_bytes(path: String, bytes: PackedByteArray) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes)
	file.close()
	return ""
