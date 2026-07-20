extends Control
class_name FailScreen

signal retry_requested
signal return_requested(outcome: String)
signal formation_changed

var outcome: String = "wipe"
var summary: Dictionary = {}
var campaign_mode: bool = false
var title_label: Label = null
var summary_label: Label = null
var detail_label: Label = null
var formation_editor: VBoxContainer = null
var formation_member_list: ItemList = null
var region_dropdown: OptionButton = null
var range_dropdown: OptionButton = null
var retry_button: Button = null
var formation_button: Button = null
var return_button: Button = null


func _ready() -> void:
	_build_ui()
	visible = false


func show_result(new_summary: Dictionary, new_outcome: String, is_campaign: bool) -> void:
	summary = new_summary.duplicate(true)
	outcome = new_outcome
	campaign_mode = is_campaign
	visible = true
	formation_editor.visible = false
	title_label.text = "Victory" if outcome == "victory" else "The Raid Has Fallen"
	summary_label.text = _summary_brief()
	detail_label.text = ""
	detail_label.visible = false
	retry_button.text = "Attempt Again" if outcome == "victory" else "Retry Exact Raid Plan"
	formation_button.visible = campaign_mode and outcome == "wipe"
	return_button.text = "Return to Camp" if campaign_mode else "Return to Main Menu"
	_refresh_formation_members()


func hide_result() -> void:
	visible = false


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 500

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color("070b0edc")
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 190
	center.offset_top = 90
	center.offset_right = -190
	center.offset_bottom = -90
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120, 790)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171e23")
	style.border_color = Color("75574d")
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color("e0c7ae"))
	root.add_child(title_label)

	summary_label = Label.new()
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_font_size_override("font_size", 19)
	root.add_child(summary_label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 10)
	root.add_child(button_row)

	retry_button = Button.new()
	retry_button.text = "Retry Exact Raid Plan"
	retry_button.custom_minimum_size = Vector2(230, 48)
	retry_button.pressed.connect(_on_retry_pressed)
	button_row.add_child(retry_button)

	formation_button = Button.new()
	formation_button.text = "Minor Formation Edit"
	formation_button.custom_minimum_size = Vector2(220, 48)
	formation_button.pressed.connect(_on_formation_pressed)
	button_row.add_child(formation_button)

	var review_button := Button.new()
	review_button.text = "Attempt Review"
	review_button.custom_minimum_size = Vector2(200, 48)
	review_button.pressed.connect(_on_review_pressed)
	button_row.add_child(review_button)

	return_button = Button.new()
	return_button.text = "Return to Camp"
	return_button.custom_minimum_size = Vector2(190, 48)
	return_button.pressed.connect(_on_return_pressed)
	button_row.add_child(return_button)

	formation_editor = VBoxContainer.new()
	formation_editor.visible = false
	formation_editor.add_theme_constant_override("separation", 9)
	root.add_child(formation_editor)
	var boundary_note := Label.new()
	boundary_note.text = "Post-wipe exception: starting regions may be adjusted here. Roster, target, and support settings remain locked to the current Raid Plan."
	boundary_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boundary_note.add_theme_color_override("font_color", Color("c5af78"))
	formation_editor.add_child(boundary_note)

	var formation_row := HBoxContainer.new()
	formation_row.add_theme_constant_override("separation", 12)
	formation_editor.add_child(formation_row)
	formation_member_list = ItemList.new()
	formation_member_list.custom_minimum_size = Vector2(490, 250)
	formation_member_list.item_selected.connect(_on_formation_member_selected)
	formation_row.add_child(formation_member_list)

	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	formation_row.add_child(controls)
	var region_label := Label.new()
	region_label.text = "Starting region"
	controls.add_child(region_label)
	region_dropdown = OptionButton.new()
	for region in [
		"north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"
	]:
		region_dropdown.add_item(_humanize(region))
		region_dropdown.set_item_metadata(region_dropdown.item_count - 1, region)
	controls.add_child(region_dropdown)
	var range_label := Label.new()
	range_label.text = "Range ring"
	controls.add_child(range_label)
	range_dropdown = OptionButton.new()
	for range_name in ["close", "mid", "far"]:
		range_dropdown.add_item(_humanize(range_name))
		range_dropdown.set_item_metadata(range_dropdown.item_count - 1, range_name)
	controls.add_child(range_dropdown)
	var save_button := Button.new()
	save_button.text = "Save Minor Placement"
	save_button.custom_minimum_size = Vector2(0, 44)
	save_button.pressed.connect(_on_save_formation_pressed)
	controls.add_child(save_button)

	detail_label = Label.new()
	detail_label.visible = false
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_color_override("font_color", Color("c7cbc7"))
	root.add_child(detail_label)


func _summary_brief() -> String:
	if summary.is_empty():
		return "No structured attempt summary was available."

	var brief := (
		"%.1f seconds · %.1f%% boss progress · Furthest phase: %s · %d raid deaths"
		% [
			float(summary.get("duration_seconds", 0.0)),
			float(summary.get("boss_progress_percent", 0.0)),
			String(summary.get("furthest_phase_name", "Unknown")),
			summary.get("deaths", []).size()
		]
	)

	if String(summary.get("outcome", "")) == "victory" and campaign_mode:
		brief += "\nReward secured immediately · latest camp trophy updated."

	return brief


func _review_text() -> String:
	if summary.is_empty():
		return "No structured attempt data was available."

	var lines: Array[String] = []
	lines.append("OUTCOME  %s" % _humanize(String(summary.get("outcome", "unknown"))))
	lines.append("BOSS  %.1f%% health remaining" % float(summary.get("boss_health_percent", 0.0)))
	lines.append("EVENTS  %d structured entries" % int(summary.get("event_count", 0)))
	lines.append(
		(
			"TOTALS  %d damage · %d healing"
			% [
				_sum_dictionary_values(summary.get("damage_by_source", {})),
				_sum_dictionary_values(summary.get("healing_by_source", {}))
			]
		)
	)

	var failures: Array = summary.get("reliable_failures", [])
	var new_abilities: Array = summary.get("newly_discovered_ability_ids", [])
	var new_phases: Array = summary.get("newly_discovered_phase_ids", [])

	if not new_abilities.is_empty() or not new_phases.is_empty():
		lines.append("\nNEWLY OBSERVED")

		for phase_id in new_phases:
			lines.append("• Phase: %s" % _humanize(String(phase_id)))

		for ability_id in new_abilities:
			lines.append("• Ability: %s" % _humanize(String(ability_id)))

	if not failures.is_empty():
		lines.append("\nRELIABLY DETECTED")
		for failure in failures:
			lines.append("• %s" % String(failure))

	var deaths: Array = summary.get("deaths", [])

	if not deaths.is_empty():
		lines.append("\nDEATHS")
		for death in deaths.slice(0, 12):
			lines.append(
				(
					"• %.1fs  %s — %s"
					% [
						float(death.get("time", 0.0)),
						String(death.get("member_name", "Unknown")),
						_humanize(String(death.get("cause_ability_id", "unknown")))
					]
				)
			)

	var timeline: Array = summary.get("timeline", [])

	if not timeline.is_empty():
		lines.append("\nCOMPACT WIPE TIMELINE")
		for event in timeline:
			var event_label := String(event.get("display_name", ""))

			if event_label.is_empty():
				event_label = _humanize(String(event.get("ability_id", event.get("type", "event"))))

			lines.append("• %.1fs  %s" % [float(event.get("time", 0.0)), event_label])

	return "\n".join(lines)


func _refresh_formation_members() -> void:
	if formation_member_list == null:
		return

	formation_member_list.clear()

	for member in CampaignState.get_active_members():
		formation_member_list.add_item(
			(
				"%-24s  %s"
				% [
					CampaignState.format_member_label(member),
					_humanize(String(member.get("role", "")))
				]
			)
		)
		formation_member_list.set_item_metadata(
			formation_member_list.item_count - 1, String(member.get("member_id", ""))
		)

	if formation_member_list.item_count > 0:
		formation_member_list.select(0)
		_on_formation_member_selected(0)


func _on_formation_member_selected(index: int) -> void:
	if index < 0 or index >= formation_member_list.item_count:
		return

	var member_id := String(formation_member_list.get_item_metadata(index))
	var placement: Dictionary = CampaignState.get_formation().get("placements", {}).get(
		member_id, {}
	)
	_select_dropdown_metadata(region_dropdown, String(placement.get("region", "south")))
	_select_dropdown_metadata(range_dropdown, String(placement.get("range", "mid")))


func _on_retry_pressed() -> void:
	visible = false
	retry_requested.emit()


func _on_return_pressed() -> void:
	visible = false
	return_requested.emit(outcome)


func _on_review_pressed() -> void:
	formation_editor.visible = false
	detail_label.visible = not detail_label.visible
	detail_label.text = _review_text()


func _on_formation_pressed() -> void:
	if not campaign_mode or outcome != "wipe":
		return

	detail_label.visible = false
	formation_editor.visible = not formation_editor.visible


func _on_save_formation_pressed() -> void:
	var selected := formation_member_list.get_selected_items()

	if selected.is_empty():
		return

	var member_id := String(formation_member_list.get_item_metadata(selected[0]))
	var region := String(region_dropdown.get_item_metadata(region_dropdown.selected))
	var range_name := String(range_dropdown.get_item_metadata(range_dropdown.selected))

	if CampaignState.set_member_placement(member_id, region, range_name):
		formation_changed.emit()


func _humanize(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _sum_dictionary_values(values: Dictionary) -> int:
	var total := 0

	for value in values.values():
		total += int(value)

	return total


func _select_dropdown_metadata(dropdown: OptionButton, value: String) -> void:
	if dropdown == null:
		return

	for item_index in range(dropdown.item_count):
		if String(dropdown.get_item_metadata(item_index)) == value:
			dropdown.select(item_index)
			return
