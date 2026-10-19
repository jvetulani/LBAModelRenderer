extends SceneTree

const BODY_NAMES = preload("res://scripts/ui/body_names.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	assert(BODY_NAMES.LBA2_RETAIL.size() == 469)
	assert(BODY_NAMES.name_for("LBA2", 203) == "Zoé + pram (1)")
	assert(BODY_NAMES.name_for("LBA2-96", 4).contains("Zoé"))
	var ui: MainUI = load("res://assets/scenes/mainui.tscn").instantiate()
	root.add_child(ui)
	ui.set_body_entry_count(469)
	ui.set_game("LBA2")
	var query: LineEdit = ui.get("_find_query")
	var results: ItemList = ui.get("_find_results")
	query.text = "zoe pram"
	ui.call("_refresh_body_search")
	assert(results.item_count == 2, "Both Zoé/pram variants must be searchable without accents")
	assert(results.get_item_metadata(0) == 203 and results.get_item_metadata(1) == 204)
	results.select(1)
	ui.call("_open_found_body")
	assert(ui.body_index() == 204, "Opening a search result must select its BODY entry")
	ui.set_current_body(204)
	assert(ui.body_label.text.contains("Zoé + pram"), "Current BODY name must be visible")
	assert(ui.get("_find_dialog") is Control, "Model picker should be themed in the viewer scene")
	ui.queue_free()
	print("PASS: retail model names, accent-free search, and BODY selection")
	quit()
