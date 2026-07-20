extends Control
class_name FailScreen

const FormationEditorPanelScript := preload("res://scripts/ui/formation_editor_panel.gd")

signal retry_requested
signal return_requested(outcome: String)
signal formation_changed

var outcome: String = "wipe"
var summary: Dictionary = {}
var campaign_mode: bool = false
var title_label: Label = null
var summary_label: Label = null
var content_holder: VBoxContainer = null
var review_scroll: ScrollContainer = null
var formation_editor: FormationEditorPanel = null
var retry_button: Button = null
var formation_button: Button = null
var review_button: Button = null
var return_button: Button = null


func _ready() -> void:
	_build_ui()
	visible = false


func show_result(new_summary: Dictionary, new_outcome: String, is_campaign: bool) -> void:
	summary = new_summary.duplicate(true)
	outcome = new_outcome
	campaign_mode = is_campaign
	visible = true
	title_label.text = "Victory" if outcome == "victory" else "The Raid Has Fallen"
	summary_label.text = _summary_brief()
	retry_button.text = "Attempt Again" if outcome == "victory" else "Retry Exact Raid Plan"
	formation_button.visible = campaign_mode and outcome == "wipe"
	return_button.text = "Return to Camp" if campaign_mode else "Return to Main Menu"
	_show_summary_only()


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
	center.offset_left = 45
	center.offset_top = 35
	center.offset_right = -45
	center.offset_bottom = -35
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1540, 920)
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
	root.add_theme_constant_override("separation", 12)
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
	formation_button.text = "Formation Edit"
	formation_button.custom_minimum_size = Vector2(220, 48)
	formation_button.pressed.connect(_on_formation_pressed)
	button_row.add_child(formation_button)

	review_button = Button.new()
	review_button.text = "Attempt Review"
	review_button.custom_minimum_size = Vector2(200, 48)
	review_button.pressed.connect(_on_review_pressed)
	button_row.add_child(review_button)

	return_button = Button.new()
	return_button.text = "Return to Camp"
	return_button.custom_minimum_size = Vector2(190, 48)
	return_button.pressed.connect(_on_return_pressed)
	button_row.add_child(return_button)

	root.add_child(HSeparator.new())

	content_holder = VBoxContainer.new()
	content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_holder)


func _show_summary_only() -> void:
	_clear_content()
	var note := Label.new()
	note.text = (
		"Choose Attempt Review for the scrollable breakdown, or Formation Edit to make full radial changes before retrying."
		if campaign_mode and outcome == "wipe"
		else "Choose Attempt Review for the scrollable breakdown."
	)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("aeb8af"))
	content_holder.add_child(note)


func _show_formation_editor() -> void:
	_clear_content()
	formation_editor = FormationEditorPanelScript.new() as FormationEditorPanel
	(
		formation_editor
		. configure(
			"Post-wipe exception: the full starting formation may be edited here. Roster, target, and support settings remain locked to the current Raid Plan.",
			true
		)
	)
	formation_editor.formation_changed.connect(_on_editor_formation_changed)
	content_holder.add_child(formation_editor)


func _show_review() -> void:
	_clear_content()
	review_scroll = ScrollContainer.new()
	review_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	review_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_holder.add_child(review_scroll)

	var review_label := Label.new()
	review_label.text = _review_text()
	review_label.custom_minimum_size = Vector2(1420, 0)
	review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review_label.add_theme_color_override("font_color", Color("c7cbc7"))
	review_scroll.add_child(review_label)


func _clear_content() -> void:
	for child in content_holder.get_children():
		content_holder.remove_child(child)
		child.queue_free()

	formation_editor = null
	review_scroll = null


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
		for death in deaths:
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
		lines.append("\nATTEMPT TIMELINE")
		for event in timeline:
			var event_label := String(event.get("display_name", ""))

			if event_label.is_empty():
				event_label = _humanize(String(event.get("ability_id", event.get("type", "event"))))

			lines.append("• %.1fs  %s" % [float(event.get("time", 0.0)), event_label])

	return "\n".join(lines)


func _on_retry_pressed() -> void:
	visible = false
	retry_requested.emit()


func _on_return_pressed() -> void:
	visible = false
	return_requested.emit(outcome)


func _on_review_pressed() -> void:
	_show_review()


func _on_formation_pressed() -> void:
	if campaign_mode and outcome == "wipe":
		_show_formation_editor()


func _on_editor_formation_changed() -> void:
	formation_changed.emit()


func _humanize(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _sum_dictionary_values(values: Dictionary) -> int:
	var total := 0

	for value in values.values():
		total += int(value)

	return total
