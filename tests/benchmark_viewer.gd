extends SceneTree

func _initialize() -> void:
	call_deferred("_benchmark")


func _benchmark() -> void:
	var scene: Node3D = load("res://assets/scenes/main.tscn").instantiate()
	root.add_child(scene)
	var viewer: CharacterViewer = scene.get_node("CharacterViewer")
	var camera: OrbitCamera = scene.get_node("OrbitCamera")
	for index in range(101):
		var start := Time.get_ticks_usec()
		var loaded := viewer.load_body("/home/asia/Games/LBA2gog", index)
		assert(loaded["ok"], str(loaded.get("error", "load failed")))
		camera.frame_points(loaded["points"], Vector3.ZERO)
		if not viewer.animation_entries.is_empty():
			var selected := viewer.select_animation(viewer.animation_entries[0]["archive_index"])
			assert(selected["ok"])
		for frame in range(6):
			await process_frame
		if index in [0, 20, 40, 60, 80, 100]:
			print("BODY ", index, ": load+6 frames ms=", float(Time.get_ticks_usec() - start) / 1000.0, " staticMB=", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, " objects=", Performance.get_monitor(Performance.OBJECT_COUNT), " fps=", Performance.get_monitor(Performance.TIME_FPS))
	quit()
