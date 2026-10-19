extends SceneTree

const BODY_NAMES = preload("res://scripts/ui/body_names.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	assert(BODY_NAMES.LBA2_RETAIL.size() == 469)
	assert(BODY_NAMES.LBA1_RETAIL.size() == 132)
	assert(BODY_NAMES.name_for("LBA1", 28) == "Surveillance device")
	assert(not BODY_NAMES.search_text("LBA1", 28).contains("tank"))
	assert(BODY_NAMES.name_for("LBA1", 29) == "Hairdryer Salesman")
	assert(BODY_NAMES.search_text("LBA1", 29).contains("hairdryer"))
	assert(not BODY_NAMES.search_text("LBA1", 29).contains("surveillance"))
	assert(BODY_NAMES.name_for("LBA1", 51) == "Ferryboat")
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
	ui.set_body_entry_count(132)
	ui.set_game("LBA1")
	query.text = "surveillance"
	ui.call("_refresh_body_search")
	assert(results.item_count == 1 and results.get_item_metadata(0) == 28, "Surveillance device must be BODY #28")
	query.text = "hairdryer"
	ui.call("_refresh_body_search")
	assert(results.item_count == 1 and results.get_item_metadata(0) == 29, "Hairdryer Salesman must be BODY #29")
	query.text = "ferry"
	ui.call("_refresh_body_search")
	assert(results.item_count == 1 and results.get_item_metadata(0) == 51, "LBA1 ferry should be searchable")
	query.text = "zoe"
	ui.call("_refresh_body_search")
	assert(results.item_count == 1 and results.get_item_metadata(0) == 48, "LBA1 Zoé should be searchable without accents")
	root.size = Vector2i(390, 780)
	ui.call("_update_find_layout")
	assert(not (ui.get("_find_button") as Button).visible and (ui.get("_mobile_find_button") as Button).visible)
	assert((ui.get("_find_panel") as PanelContainer).size.x <= 390, "Picker must fit a phone viewport")
	root.size = Vector2i(1440, 900)
	ui.call("_update_find_layout")
	assert((ui.get("_find_button") as Button).visible and not (ui.get("_mobile_find_button") as Button).visible)
	ui.queue_free()
	print("PASS: LBA1/LBA2 names, accent-free search, BODY selection, and responsive Find controls")
	quit()
