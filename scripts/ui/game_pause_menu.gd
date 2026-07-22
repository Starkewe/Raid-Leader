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
var formation_snapshot: Dictionary = {}
var settings_dropdown: OptionButton = null
var save_name_input: LineEdit = null
var overwrite_dialog: ConfirmationDialog = null
var pending_overwrite_name: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 900
	_build_ui()
	overlay.visible = false


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if _fail_screen_is_visible():
		return

	if overwrite_dialog != null and overwrite_dialog.visible:
		overwrite_dialog.hide()
		pending_overwrite_name = ""
		_mark_input_handled()
		return

	if not overlay.visible and _close_topmost_external_modal():
		_mark_input_handled()
		return

	if overlay.visible and formation_editor != null:
		_cancel_formation_edit()
	elif overlay.visible and SceneFlow.mode == "campaign_combat" and content_holder.visible:
		_show_button_menu()
	elif overlay.visible:
		_close_menu()
	else:
		_open_menu()

	_mark_input_handled()


func _close_topmost_external_modal() -> bool:
	for modal in get_tree().get_nodes_in_group("escape_modal"):
		if modal.has_method("is_open") and bool(modal.call("is_open")):
			modal.call("close_for_escape")
			return true

	return false


func _mark_input_handled() -> void:
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

	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = "Overwrite Save?"
	overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	overwrite_dialog.canceled.connect(_on_overwrite_canceled)
	add_child(overwrite_dialog)

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
		_add_button("Save Game", _show_save_game)
		_add_button("Settings", _show_settings)
		_add_button("Return to Main Menu", _return_to_main_menu)
	elif SceneFlow.mode == "campaign_combat":
		_add_button("Edit Formation", _show_formation_editor)
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
	formation_editor = null
	formation_snapshot.clear()
	get_tree().paused = false


func _show_button_menu() -> void:
	content_holder.visible = false
	menu_column.visible = true
	panel.custom_minimum_size = Vector2(620, 660)
	_clear_content_holder()
	formation_editor = null
	formation_snapshot.clear()
	settings_dropdown = null
	save_name_input = null


func _clear_content_holder() -> void:
	for child in content_holder.get_children():
		content_holder.remove_child(child)
		child.queue_free()


func _show_formation_editor() -> void:
	menu_column.visible = false
	content_holder.visible = true
	panel.custom_minimum_size = Vector2(1510, 900)
	_clear_content_holder()
	formation_snapshot = CampaignState.get_formation()
	formation_editor = FormationEditorPanelScript.new() as FormationEditorPanel
	formation_editor.configure(
		"Edits apply only after Save and Restart Fight. Back discards them and returns to the Raid Menu.",
		true
	)
	content_holder.add_child(formation_editor)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	content_holder.add_child(actions)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(180, 50)
	back.pressed.connect(_cancel_formation_edit)
	actions.add_child(back)

	var restart := Button.new()
	restart.text = "Save and Restart Fight"
	restart.custom_minimum_size = Vector2(280, 50)
	restart.pressed.connect(_save_formation_and_restart)
	actions.add_child(restart)


func _cancel_formation_edit() -> void:
	if not formation_snapshot.is_empty():
		CampaignState.replace_current_formation(formation_snapshot)

	_show_button_menu()


func _save_formation_and_restart() -> void:
	formation_snapshot.clear()
	_close_menu()
	SceneFlow.retry_campaign_combat()


func _show_settings() -> void:
	menu_column.visible = false
	content_holder.visible = true
	panel.custom_minimum_size = Vector2(760, 620)
	_clear_content_holder()

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


func _show_save_game() -> void:
	menu_column.visible = false
	content_holder.visible = true
	panel.custom_minimum_size = Vector2(760, 760)
	_clear_content_holder()

	var heading := Label.new()
	heading.text = "Save Game"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	content_holder.add_child(heading)

	var help := Label.new()
	help.text = (
		"Select a named save to overwrite it, or enter a new save name below. "
		+ "The autosave is shown for reference and updates only after returning from a fight."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("9ca4a5"))
	content_holder.add_child(help)

	var existing_heading := Label.new()
	existing_heading.text = "Available saves"
	existing_heading.add_theme_color_override("font_color", Color("d5c18a"))
	content_holder.add_child(existing_heading)

	var saves_scroll := ScrollContainer.new()
	saves_scroll.custom_minimum_size = Vector2(0, 260)
	saves_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	saves_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_holder.add_child(saves_scroll)

	var saves_list := VBoxContainer.new()
	saves_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves_list.add_theme_constant_override("separation", 7)
	saves_scroll.add_child(saves_list)

	var available_save_count := 0

	for save_entry in CampaignSaveManagerScript.list_saves():
		var kind := String(save_entry.get("kind", "manual"))

		if kind != "autosave" and kind != "manual":
			continue

		available_save_count += 1
		saves_list.add_child(_make_existing_save_button(save_entry))

	if available_save_count == 0:
		var empty := Label.new()
		empty.text = "No named saves or autosave exist yet."
		empty.add_theme_color_override("font_color", Color("778087"))
		saves_list.add_child(empty)

	var new_save_heading := Label.new()
	new_save_heading.text = "New named save"
	new_save_heading.add_theme_color_override("font_color", Color("d5c18a"))
	content_holder.add_child(new_save_heading)

	save_name_input = LineEdit.new()
	save_name_input.placeholder_text = "Save name"
	save_name_input.max_length = 80
	save_name_input.text_submitted.connect(_on_save_name_submitted)
	content_holder.add_child(save_name_input)

	var create := Button.new()
	create.text = "Create Save"
	create.custom_minimum_size = Vector2(0, 50)
	create.pressed.connect(_on_create_manual_save_pressed)
	content_holder.add_child(create)
	_add_content_back_button()
	save_name_input.grab_focus()


func _make_existing_save_button(save_entry: Dictionary) -> Button:
	var button := Button.new()
	var kind := String(save_entry.get("kind", "manual"))
	var display_name := String(save_entry.get("display_name", "Save"))
	var saved_time := int(save_entry.get("saved_unix_time", 0))
	var title_text := "[AUTOSAVE] %s" % display_name if kind == "autosave" else display_name
	button.text = "%s\n%s · %s" % [
		title_text,
		Time.get_datetime_string_from_unix_time(saved_time, true),
		String(save_entry.get("context_label", "Camp")),
	]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 64)

	if kind == "autosave":
		button.disabled = true
		button.tooltip_text = "Autosaves can only be updated by returning to camp after a fight."
	else:
		button.tooltip_text = "Select to overwrite this named save."
		button.pressed.connect(_request_overwrite_existing_save.bind(display_name))

	return button


func _on_save_name_submitted(_submitted_text: String) -> void:
	_on_create_manual_save_pressed()


func _on_create_manual_save_pressed() -> void:
	if save_name_input == null:
		return

	var result := CampaignSaveManagerScript.create_manual_save(save_name_input.text, false)
	_handle_manual_save_result(result)


func _handle_manual_save_result(result: Dictionary) -> void:
	var status := String(result.get("status", "error"))

	if status == "duplicate":
		_request_overwrite_existing_save(String(result.get("display_name", "")))
		return

	var message := String(result.get("message", "Save failed."))

	if bool(result.get("ok", false)):
		_close_menu()
	else:
		status_label.text = message


func _request_overwrite_existing_save(display_name: String) -> void:
	pending_overwrite_name = display_name.strip_edges()

	if pending_overwrite_name.is_empty():
		status_label.text = "That save does not have a valid name."
		return

	overwrite_dialog.dialog_text = "Overwrite the existing save '%s'?" % pending_overwrite_name
	overwrite_dialog.popup_centered()


func _on_overwrite_confirmed() -> void:
	if pending_overwrite_name.is_empty():
		return

	var result := CampaignSaveManagerScript.create_manual_save(
		pending_overwrite_name, true
	)
	pending_overwrite_name = ""
	_handle_manual_save_result(result)


func _on_overwrite_canceled() -> void:
	pending_overwrite_name = ""


func _return_to_camp() -> void:
	_close_menu()
	SceneFlow.enter_camp("normal", {"source": "raid_pause"})


func _return_to_main_menu() -> void:
	_close_menu()
	SceneFlow.go_to_main_menu()


func _quit_game() -> void:
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
