extends CanvasLayer
class_name GamePauseMenu

const FormationEditorPanelScript := preload("res://scripts/ui/formation_editor_panel.gd")
const CampaignSaveManagerScript := preload("res://scripts/core/campaign_save_manager.gd")

var overlay: Control = null
var panel: PanelContainer = null
var menu_column: VBoxContainer = null
var content_holder: VBoxContainer = null
var status_label: Label = null
var formation_editor: FormationEditorPanel = null
var settings_dropdown: OptionButton = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 900
	_build_ui()
	overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if _fail_screen_is_visible():
		return

	if overlay.visible and content_holder.visible:
		_show_button_menu()
	else:
		_toggle_menu()

	var viewport := get_viewport()

	if viewport != null:
		viewport.set_input_as_handled()


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false


func _build_ui() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color("070b0edc")
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 45
	center.offset_top = 40
	center.offset_right = -45
	center.offset_bottom = -40
	overlay.add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 660)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172027")
	style.border_color = Color("77694f")
	style.set_border_width_all(3)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = _menu_title()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("e8dfc7"))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "This menu pauses the current scene. It is separate from the main menu."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color("9ca4a5"))
	root.add_child(subtitle)

	var separator := HSeparator.new()
	root.add_child(separator)

	menu_column = VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 9)
	menu_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(menu_column)

	content_holder = VBoxContainer.new()
	content_holder.visible = false
	content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_holder)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("c9b37b"))
	root.add_child(status_label)

	_build_menu_buttons()


func _build_menu_buttons() -> void:
	_add_button("Resume", _close_menu)

	if SceneFlow.mode == "camp":
		_add_button("Create Save Snapshot", _create_save_snapshot)
		_add_button("Settings", _show_settings)
		_add_button("Return to Main Menu", _return_to_main_menu)
	elif SceneFlow.mode == "campaign_combat":
		_add_button("Edit Formation for Next Attempt", _show_formation_editor)
		_add_button("Restart Attempt with Current Plan", _restart_campaign_attempt)
		_add_button("Return to Camp", _return_to_camp)
		_add_button("Settings", _show_settings)
		_add_button("Return to Main Menu", _return_to_main_menu)
	else:
		_add_button("Settings", _show_settings)
		_add_button("Return to Main Menu", _return_to_main_menu)

	_add_button("Quit", _quit_game)


func _add_button(label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(0, 50)
	button.pressed.connect(callback)
	menu_column.add_child(button)
	return button


func _toggle_menu() -> void:
	if overlay.visible:
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	overlay.visible = true
	status_label.text = ""
	_show_button_menu()
	get_tree().paused = true


func _close_menu() -> void:
	overlay.visible = false
	get_tree().paused = false


func _show_button_menu() -> void:
	content_holder.visible = false
	menu_column.visible = true
	panel.custom_minimum_size = Vector2(620, 660)

	for child in content_holder.get_children():
		content_holder.remove_child(child)
		child.queue_free()

	formation_editor = null
	settings_dropdown = null


func _show_formation_editor() -> void:
	menu_column.visible = false
	content_holder.visible = true
	panel.custom_minimum_size = Vector2(1510, 900)
	formation_editor = FormationEditorPanelScript.new() as FormationEditorPanel
	(
		formation_editor
		. configure(
			"Formation changes made here are saved immediately and apply when the attempt is restarted.",
			true
		)
	)
	content_holder.add_child(formation_editor)
	_add_content_back_button()


func _show_settings() -> void:
	menu_column.visible = false
	content_holder.visible = true
	panel.custom_minimum_size = Vector2(760, 620)

	var heading := Label.new()
	heading.text = "Settings"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	content_holder.add_child(heading)

	var label := Label.new()
	label.text = "Speech-to-Text Model"
	content_holder.add_child(label)

	settings_dropdown = OptionButton.new()
	var current_value := GameState.get_model_setting("speech_to_text_model")

	for option_data in GameState.get_speech_to_text_model_options():
		var index := settings_dropdown.item_count
		settings_dropdown.add_item(String(option_data[0]))
		settings_dropdown.set_item_metadata(index, String(option_data[1]))

		if String(option_data[1]) == current_value:
			settings_dropdown.select(index)

	content_holder.add_child(settings_dropdown)

	var apply := Button.new()
	apply.text = "Apply Settings"
	apply.custom_minimum_size = Vector2(0, 48)
	apply.pressed.connect(_apply_settings)
	content_holder.add_child(apply)
	_add_content_back_button()


func _add_content_back_button() -> void:
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_show_button_menu)
	content_holder.add_child(back)


func _apply_settings() -> void:
	if settings_dropdown == null or settings_dropdown.selected < 0:
		return

	GameState.set_model_setting(
		"speech_to_text_model",
		String(settings_dropdown.get_item_metadata(settings_dropdown.selected))
	)
	status_label.text = "Settings applied."


func _create_save_snapshot() -> void:
	var path := CampaignSaveManagerScript.create_snapshot("Camp Manual Save")
	status_label.text = "Save snapshot created." if not path.is_empty() else "Save snapshot failed."


func _restart_campaign_attempt() -> void:
	_close_menu()
	SceneFlow.retry_campaign_combat()


func _return_to_camp() -> void:
	_close_menu()
	SceneFlow.enter_camp("normal", {"source": "raid_pause"})


func _return_to_main_menu() -> void:
	CampaignState.save_campaign()
	_close_menu()
	SceneFlow.go_to_main_menu()


func _quit_game() -> void:
	CampaignState.save_campaign()
	get_tree().paused = false
	get_tree().quit()


func _menu_title() -> String:
	match SceneFlow.mode:
		"camp":
			return "Camp Menu"
		"campaign_combat":
			return "Raid Menu"
		"tutorial_combat":
			return "Tutorial Menu"
		_:
			return "Pause Menu"


func _fail_screen_is_visible() -> bool:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return false

	var fail_screen := current_scene.get_node_or_null("UI/FailScreen")
	return fail_screen != null and fail_screen.visible
