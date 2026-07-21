extends Control

const CampaignSaveManagerScript := preload("res://scripts/core/campaign_save_manager.gd")

var main_panel: VBoxContainer = null
var secondary_panel: VBoxContainer = null
var tutorial_description: Label = null
var tutorial_start_button: Button = null
var settings_dropdown: OptionButton = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rebuild_root()
	_show_main_menu()


func _rebuild_root() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color("0c1318")
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 40
	center.offset_top = 35
	center.offset_right = -40
	center.offset_bottom = -35
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 820)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172027")
	style.border_color = Color("77694f")
	style.set_border_width_all(3)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 34)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Raid Leader"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("e8dfc7"))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The 20fold Writ"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color("c9b37b"))
	root.add_child(subtitle)

	root.add_child(HSeparator.new())

	main_panel = VBoxContainer.new()
	main_panel.add_theme_constant_override("separation", 10)
	main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main_panel)

	secondary_panel = VBoxContainer.new()
	secondary_panel.visible = false
	secondary_panel.add_theme_constant_override("separation", 10)
	secondary_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(secondary_panel)


func _show_main_menu() -> void:
	_clear_secondary()
	secondary_panel.visible = false
	main_panel.visible = true

	for child in main_panel.get_children():
		main_panel.remove_child(child)
		child.queue_free()

	_add_main_button("New Game", _on_new_game_pressed)
	var continue_button := _add_main_button("Continue", _on_continue_pressed)
	continue_button.disabled = not CampaignSaveManagerScript.has_any_save()
	_add_main_button("Load Game", _show_load_game)
	_add_main_button("Tutorial", _show_tutorial)
	_add_main_button("Settings", _show_settings)
	_add_main_button("Quit", _on_quit_pressed)


func _add_main_button(label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0, 58)
	button.pressed.connect(callback)
	main_panel.add_child(button)
	return button


func _begin_secondary(title_text: String) -> void:
	_clear_secondary()
	main_panel.visible = false
	secondary_panel.visible = true

	var heading := Label.new()
	heading.text = title_text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("e8dfc7"))
	secondary_panel.add_child(heading)


func _show_load_game() -> void:
	_begin_secondary("Load Game")
	var saves := CampaignSaveManagerScript.list_saves()
	var note := Label.new()
	note.text = "Named saves remain until deleted or overwritten. Autosave is one slot updated only after a fight returns to camp."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("9ca4a5"))
	secondary_panel.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	secondary_panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)

	if saves.is_empty():
		var empty := Label.new()
		empty.text = "No saves are available yet. Create a named save from the Camp Menu or return from a fight to create the autosave."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(empty)
	else:
		for save_entry in saves:
			list.add_child(_make_save_row(save_entry))

	_add_back_button()


func _make_save_row(save_entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10181e")
	style.border_color = Color("39464b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)

	var title := Label.new()
	var kind := String(save_entry.get("kind", "manual"))
	title.text = "%s%s" % [
		String(save_entry.get("display_name", "Save")),
		" · AUTOSAVE" if kind == "autosave" else "",
	]
	title.add_theme_color_override("font_color", Color("e8dfc7"))
	details.add_child(title)

	var metadata := Label.new()
	var saved_time := int(save_entry.get("saved_unix_time", 0))
	metadata.text = "%s · %s" % [
		Time.get_datetime_string_from_unix_time(saved_time, true),
		String(save_entry.get("context_label", "Camp")),
	]
	metadata.add_theme_color_override("font_color", Color("9ca4a5"))
	details.add_child(metadata)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.custom_minimum_size = Vector2(90, 48)
	load_button.pressed.connect(_on_snapshot_pressed.bind(String(save_entry.get("path", ""))))
	row.add_child(load_button)

	if bool(save_entry.get("deletable", false)):
		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.custom_minimum_size = Vector2(90, 48)
		delete_button.pressed.connect(
			_on_delete_save_pressed.bind(String(save_entry.get("path", "")))
		)
		row.add_child(delete_button)

	return panel


func _show_tutorial() -> void:
	_begin_secondary("Tutorial")
	_apply_tutorial_default_roster()
	var note := Label.new()
	note.text = "Tutorial roster: 2 Warriors · 5 Priests · 6 Rogues · 7 Mages"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("c9b37b"))
	secondary_panel.add_child(note)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	secondary_panel.add_child(grid)

	var boss_ids := GameState.get_tutorial_boss_ids()

	for boss_id in boss_ids:
		var data := GameState.get_tutorial_boss_data(boss_id)
		var button := Button.new()
		button.text = String(data.get("display_name", boss_id))
		button.custom_minimum_size = Vector2(290, 58)
		button.pressed.connect(_on_tutorial_boss_selected.bind(boss_id))
		grid.add_child(button)

	tutorial_description = Label.new()
	tutorial_description.custom_minimum_size = Vector2(0, 150)
	tutorial_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	secondary_panel.add_child(tutorial_description)

	tutorial_start_button = Button.new()
	tutorial_start_button.text = "Start Tutorial"
	tutorial_start_button.custom_minimum_size = Vector2(0, 54)
	tutorial_start_button.pressed.connect(_on_start_tutorial_pressed)
	secondary_panel.add_child(tutorial_start_button)

	if not boss_ids.is_empty():
		_on_tutorial_boss_selected(boss_ids[0])

	_add_back_button()


func _show_settings() -> void:
	_begin_secondary("Settings")
	var label := Label.new()
	label.text = "Speech-to-Text Model"
	secondary_panel.add_child(label)

	settings_dropdown = OptionButton.new()
	var current_value := GameState.get_model_setting("speech_to_text_model")

	for option_data in GameState.get_speech_to_text_model_options():
		var index := settings_dropdown.item_count
		settings_dropdown.add_item(String(option_data[0]))
		settings_dropdown.set_item_metadata(index, String(option_data[1]))

		if String(option_data[1]) == current_value:
			settings_dropdown.select(index)

	secondary_panel.add_child(settings_dropdown)

	var apply := Button.new()
	apply.text = "Apply Settings"
	apply.custom_minimum_size = Vector2(0, 52)
	apply.pressed.connect(_on_apply_settings_pressed)
	secondary_panel.add_child(apply)
	_add_back_button()


func _add_back_button() -> void:
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 50)
	back.pressed.connect(_show_main_menu)
	secondary_panel.add_child(back)


func _clear_secondary() -> void:
	for child in secondary_panel.get_children():
		secondary_panel.remove_child(child)
		child.queue_free()

	tutorial_description = null
	tutorial_start_button = null
	settings_dropdown = null


func _on_new_game_pressed() -> void:
	CampaignSaveManagerScript.start_new_campaign()
	SceneFlow.enter_camp("normal")


func _on_continue_pressed() -> void:
	if CampaignSaveManagerScript.load_most_recent_save():
		SceneFlow.enter_camp("normal")


func _on_snapshot_pressed(path: String) -> void:
	if CampaignSaveManagerScript.load_save(path):
		SceneFlow.enter_camp("normal", {"loaded_save": true})


func _on_delete_save_pressed(path: String) -> void:
	# Rebuilding this menu from inside the button's signal would free the emitter mid-signal.
	call_deferred("_delete_save_and_refresh", path)


func _delete_save_and_refresh(path: String) -> void:
	CampaignSaveManagerScript.delete_save(path)
	_show_load_game()


func _apply_tutorial_default_roster() -> void:
	for unit_class in GameState.get_available_classes():
		GameState.set_class_count(unit_class, 0)

	GameState.set_class_count("Warrior", 2)
	GameState.set_class_count("Priest", 5)
	GameState.set_class_count("Rogue", 6)
	GameState.set_class_count("Mage", 7)


func _on_tutorial_boss_selected(boss_id: String) -> void:
	GameState.set_selected_tutorial_boss(boss_id)
	var data := GameState.get_tutorial_boss_data(boss_id)

	if tutorial_description != null:
		tutorial_description.text = String(data.get("description", ""))

	if tutorial_start_button != null:
		tutorial_start_button.disabled = not GameState.has_valid_team()


func _on_start_tutorial_pressed() -> void:
	SceneFlow.launch_tutorial(GameState.get_selected_tutorial_boss_id())


func _on_apply_settings_pressed() -> void:
	if settings_dropdown == null or settings_dropdown.selected < 0:
		return

	GameState.set_model_setting(
		"speech_to_text_model",
		String(settings_dropdown.get_item_metadata(settings_dropdown.selected))
	)


func _on_quit_pressed() -> void:
	get_tree().quit()
