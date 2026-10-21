extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	root.add_child(scene)
	var source := "/home/asia/Projekty/LBA/LBAModelVIewer/AITD_GOG"
	scene._active_source = source
	scene._load_source(source, 4)
	var ui: MainUI = scene.get_node("MainUI")
	if scene.get_node("CharacterViewer").game != "AITD1" or ui._asset_picker.visible:
		push_error("AITD model list did not load: " + ui.status_label.text)
		quit(1)
		return
	var path := "/tmp/aitd-rocking-horse.blend"
	scene.get_node("ExportController")._export("blend", path)
	if not FileAccess.file_exists(path) or not ui.status_label.text.begins_with("Saved "):
		push_error("AITD Blender export failed: " + ui.status_label.text)
		quit(1)
		return
	print("PASS AITD1 rocking horse Blender export: ", path)
	quit()
