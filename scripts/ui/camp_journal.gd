extends Control
class_name CampJournal

const FormationMapScript := preload("res://scripts/ui/formation_map.gd")
const FormationMemberCardScript := preload("res://scripts/ui/formation_member_card.gd")

signal journal_visibility_changed(visible_now: bool)
signal embark_requested

var current_facility_id: String = ""
var header_title: Label = null
var body: VBoxContainer = null
var active_list: ItemList = null
var reserve_list: ItemList = null
var member_detail_label: Label = null
var refresh_queued: bool = false
var archive_view_encounter_id: String = ""


func _ready() -> void:
	_build_shell()
	visible = false
	CampaignState.state_changed.connect(_on_campaign_state_changed)


func open_facility(facility_id: String) -> void:
	if facility_id not in ["command_tent", "formation_yard", "archive"]:
		return

	current_facility_id = facility_id

	if facility_id == "archive" and archive_view_encounter_id.is_empty():
		archive_view_encounter_id = CampaignState.get_selected_encounter_id()

	visible = true
	_refresh_current_facility()
	journal_visibility_changed.emit(true)


func close_journal() -> void:
	if not visible:
		return

	visible = false
	current_facility_id = ""
	journal_visibility_changed.emit(false)


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_journal()
		get_viewport().set_input_as_handled()


func _build_shell() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color("090e12c7")
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 70
	center.offset_top = 55
	center.offset_right = -70
	center.offset_bottom = -55
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1500, 870)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("172027")
	panel_style.border_color = Color("77694f")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	header_title = Label.new()
	header_title.text = "Camp Journal"
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_title.add_theme_font_size_override("font_size", 30)
	header_title.add_theme_color_override("font_color", Color("e8dfc7"))
	header.add_child(header_title)

	var close_button := Button.new()
	close_button.text = "Close  [Esc]"
	close_button.custom_minimum_size = Vector2(140, 42)
	close_button.pressed.connect(close_journal)
	header.add_child(close_button)

	var separator := HSeparator.new()
	root.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	body = VBoxContainer.new()
	body.custom_minimum_size = Vector2(1410, 720)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)


func _refresh_current_facility() -> void:
	if body == null:
		return

	for child in body.get_children():
		child.free()

	match current_facility_id:
		"command_tent":
			_build_command_tent()
		"formation_yard":
			_build_formation_yard()
		"archive":
			_build_archive()


func _build_command_tent() -> void:
	header_title.text = "Command Tent — Assemble the Raid Plan"
	_add_muted_label(
		"Target and active-roster decisions belong here. Formation editing remains at the yard; detailed analysis remains at the archive."
	)

	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 12)
	body.add_child(target_row)
	_add_section_label_to(target_row, "Battle map")

	var region_label := Label.new()
	region_label.text = "Beast Crucible · Unlocked"
	region_label.add_theme_color_override("font_color", Color("c7b275"))
	region_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(region_label)

	var locked_label := Label.new()
	locked_label.text = "Two uncharted regions · Locked until a future apex victory"
	locked_label.add_theme_color_override("font_color", Color("778087"))
	target_row.add_child(locked_label)

	var encounter_dropdown := OptionButton.new()
	encounter_dropdown.custom_minimum_size = Vector2(300, 42)
	var selected_encounter := CampaignState.get_selected_encounter_id()

	for encounter_id in CampaignState.get_available_encounter_ids():
		var definition := GameState.get_encounter_definition(encounter_id)
		var option_index := encounter_dropdown.item_count
		encounter_dropdown.add_item(encounter_id if definition == null else definition.display_name)
		encounter_dropdown.set_item_metadata(option_index, encounter_id)

		if encounter_id == selected_encounter:
			encounter_dropdown.select(option_index)

	encounter_dropdown.item_selected.connect(_on_command_target_selected.bind(encounter_dropdown))
	target_row.add_child(encounter_dropdown)

	_add_section_label("Active Twenty and Reserves")
	var roster_row := HBoxContainer.new()
	roster_row.add_theme_constant_override("separation", 14)
	body.add_child(roster_row)

	var active_column := VBoxContainer.new()
	active_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_row.add_child(active_column)
	var role_counts := CampaignState.get_role_counts()
	var active_heading := Label.new()
	active_heading.text = (
		"Active 20  ·  %d tanks  ·  %d healers  ·  %d DPS"
		% [
			int(role_counts.get("tank", 0)),
			int(role_counts.get("healer", 0)),
			int(role_counts.get("dps", 0))
		]
	)
	active_column.add_child(active_heading)

	active_list = ItemList.new()
	active_list.custom_minimum_size = Vector2(540, 330)
	active_list.select_mode = ItemList.SELECT_SINGLE
	active_column.add_child(active_list)
	_fill_member_list(active_list, CampaignState.get_active_members(), true)
	active_list.item_selected.connect(_on_member_list_selected.bind(active_list))

	var swap_column := VBoxContainer.new()
	swap_column.custom_minimum_size = Vector2(210, 330)
	swap_column.alignment = BoxContainer.ALIGNMENT_CENTER
	roster_row.add_child(swap_column)

	var swap_button := Button.new()
	swap_button.text = "Swap selected\n↔"
	swap_button.custom_minimum_size = Vector2(190, 70)
	swap_button.pressed.connect(_on_swap_selected_members)
	swap_column.add_child(swap_button)

	var swap_note := Label.new()
	swap_note.text = "The incoming member inherits the outgoing member's saved formation slot."
	swap_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	swap_note.add_theme_font_size_override("font_size", 13)
	swap_note.add_theme_color_override("font_color", Color("9aa2a5"))
	swap_column.add_child(swap_note)

	var reserve_column := VBoxContainer.new()
	reserve_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_row.add_child(reserve_column)
	var reserve_heading := Label.new()
	reserve_heading.text = "Available Reserves  ·  %d" % CampaignState.get_reserve_members().size()
	reserve_column.add_child(reserve_heading)

	reserve_list = ItemList.new()
	reserve_list.custom_minimum_size = Vector2(540, 330)
	reserve_list.select_mode = ItemList.SELECT_SINGLE
	reserve_column.add_child(reserve_list)
	_fill_member_list(reserve_list, CampaignState.get_reserve_members(), false)
	reserve_list.item_selected.connect(_on_member_list_selected.bind(reserve_list))

	member_detail_label = Label.new()
	member_detail_label.text = "Select a member to inspect their visible attributes and identity."
	member_detail_label.custom_minimum_size = Vector2(0, 58)
	member_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(member_detail_label)

	var intelligence_row := HBoxContainer.new()
	intelligence_row.add_theme_constant_override("separation", 18)
	body.add_child(intelligence_row)

	var intel_panel := _make_text_panel(
		"Known target facts", _command_intelligence_text(selected_encounter)
	)
	intel_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intelligence_row.add_child(intel_panel)
	var attempt_panel := _make_text_panel(
		"Latest useful attempt", _latest_attempt_brief(selected_encounter)
	)
	attempt_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intelligence_row.add_child(attempt_panel)

	var formation := CampaignState.get_formation()
	var placed_count := 0
	var placements: Dictionary = formation.get("placements", {})

	for member_id in CampaignState.get_active_member_ids():
		if placements.has(member_id):
			placed_count += 1

	var plan_summary := Label.new()
	plan_summary.text = (
		"RAID PLAN · Beast Crucible · Global formation: %s · %d/20 placed · Supports: none unlocked"
		% [String(formation.get("preset_name", "Custom")), placed_count]
	)
	plan_summary.add_theme_color_override("font_color", Color("c9b37b"))
	body.add_child(plan_summary)

	var validation := CampaignState.validate_raid_plan()
	var validation_label := Label.new()
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.text = _validation_text(validation)
	validation_label.add_theme_color_override(
		"font_color", Color("9fc18b") if bool(validation.get("valid", false)) else Color("d78d7d")
	)
	body.add_child(validation_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	body.add_child(footer)

	if OS.is_debug_build():
		var stress_button := Button.new()
		stress_button.text = "Debug: Seed 20 Reserves"
		stress_button.tooltip_text = "Adds the mature 40-member role mix once for roster and Camp stress testing."
		stress_button.disabled = CampaignState.get_roster_members().size() >= 40
		stress_button.pressed.connect(_on_seed_debug_reserves)
		footer.add_child(stress_button)

	var embark_button := Button.new()
	embark_button.text = "Embark with this Raid Plan"
	embark_button.custom_minimum_size = Vector2(320, 52)
	embark_button.disabled = not bool(validation.get("valid", false))
	embark_button.pressed.connect(_on_embark_pressed)
	footer.add_child(embark_button)


func _build_formation_yard() -> void:
	header_title.text = "Formation Yard — Raid Formation"
	_add_muted_label(
		(
			"Formations apply to every target. Drag a roster row onto any mini-region to place it; "
			+ "drop one roster row onto another to choose the active order."
		)
	)

	var formation := CampaignState.get_formation()
	var current_name := String(formation.get("preset_name", "Custom"))
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 10)
	body.add_child(preset_row)
	_add_section_label_to(preset_row, "Saved formations")

	var current_label := Label.new()
	current_label.text = "Current: %s" % current_name
	current_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_label.add_theme_color_override("font_color", Color("d7c38f"))
	preset_row.add_child(current_label)

	var preset_dropdown := OptionButton.new()
	preset_dropdown.custom_minimum_size = Vector2(230, 42)
	preset_dropdown.add_item(CampaignState.DEFAULT_FORMATION_NAME)
	preset_dropdown.set_item_metadata(0, CampaignState.DEFAULT_FORMATION_NAME)

	for formation_name in CampaignState.get_saved_formation_names():
		var option_index := preset_dropdown.item_count
		preset_dropdown.add_item(formation_name)
		preset_dropdown.set_item_metadata(option_index, formation_name)

		if formation_name == current_name:
			preset_dropdown.select(option_index)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.custom_minimum_size = Vector2(90, 42)
	load_button.pressed.connect(_on_load_formation_pressed.bind(preset_dropdown))
	preset_row.add_child(preset_dropdown)
	preset_row.add_child(load_button)

	var delete_button := Button.new()
	delete_button.text = "Delete save"
	delete_button.custom_minimum_size = Vector2(120, 42)
	delete_button.disabled = (
		String(preset_dropdown.get_item_metadata(preset_dropdown.selected))
		== CampaignState.DEFAULT_FORMATION_NAME
	)
	delete_button.pressed.connect(_on_delete_formation_pressed.bind(preset_dropdown))
	preset_dropdown.item_selected.connect(
		_on_saved_formation_selected.bind(preset_dropdown, delete_button)
	)
	preset_row.add_child(delete_button)

	var name_input := LineEdit.new()
	name_input.placeholder_text = "New formation name"
	name_input.custom_minimum_size = Vector2(235, 42)
	name_input.tooltip_text = "Saving an existing name overwrites that saved formation."
	preset_row.add_child(name_input)

	var save_button := Button.new()
	save_button.text = "Save current"
	save_button.custom_minimum_size = Vector2(130, 42)
	save_button.pressed.connect(_on_save_formation_pressed.bind(name_input))
	preset_row.add_child(save_button)

	var editor_row := HBoxContainer.new()
	editor_row.add_theme_constant_override("separation", 22)
	body.add_child(editor_row)

	var member_column := VBoxContainer.new()
	member_column.custom_minimum_size = Vector2(540, 610)
	editor_row.add_child(member_column)
	var member_heading := Label.new()
	member_heading.text = "Active roster and placements · drag to sort"
	member_column.add_child(member_heading)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(530, 570)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	member_column.add_child(roster_scroll)
	var roster_cards := VBoxContainer.new()
	roster_cards.custom_minimum_size = Vector2(500, 0)
	roster_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_cards.add_theme_constant_override("separation", 4)
	roster_scroll.add_child(roster_cards)
	var placements: Dictionary = formation.get("placements", {})
	var active_members := CampaignState.get_active_members()

	for member_index in range(active_members.size()):
		var member: Dictionary = active_members[member_index]
		var member_id := String(member.get("member_id", ""))
		var placement: Dictionary = placements.get(member_id, {})
		var card := FormationMemberCardScript.new() as FormationMemberCard
		card.configure(
			member_id,
			(
				"%02d  %-24s  %s / %s"
				% [
					member_index + 1,
					CampaignState.format_member_label(member),
					_humanize(String(placement.get("region", "unassigned"))),
					_humanize(String(placement.get("range", "unassigned")))
				]
			)
		)
		card.member_reorder_requested.connect(_on_formation_member_reorder_requested)
		roster_cards.add_child(card)

	var map_column := VBoxContainer.new()
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.custom_minimum_size = Vector2(780, 610)
	editor_row.add_child(map_column)
	var map_heading := Label.new()
	map_heading.text = "All 24 mini-regions · C close · M mid · F far"
	map_column.add_child(map_heading)

	var formation_map := FormationMapScript.new() as FormationMap
	formation_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	formation_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	formation_map.configure(active_members, formation)
	formation_map.member_dropped.connect(_on_formation_member_dropped)
	map_column.add_child(formation_map)

	var validation := CampaignState.validate_raid_plan()
	var validation_label := Label.new()
	validation_label.text = _validation_text(validation)
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.add_theme_color_override(
		"font_color", Color("9fc18b") if bool(validation.get("valid", false)) else Color("d78d7d")
	)
	body.add_child(validation_label)


func _build_archive() -> void:
	header_title.text = "Archive — Observed Intelligence and Attempts"
	_add_muted_label(
		"The archive records observed facts. It does not prescribe a composition or invent mechanic failures."
	)

	var encounter_tabs := HBoxContainer.new()
	encounter_tabs.add_theme_constant_override("separation", 10)
	body.add_child(encounter_tabs)

	for encounter_id in CampaignState.get_available_encounter_ids():
		var definition := GameState.get_encounter_definition(encounter_id)
		var button := Button.new()
		button.text = encounter_id if definition == null else definition.display_name
		button.disabled = encounter_id == archive_view_encounter_id
		button.pressed.connect(_on_archive_target_selected.bind(encounter_id))
		encounter_tabs.add_child(button)

	var selected_encounter := archive_view_encounter_id
	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 18)
	body.add_child(content_row)

	var intel_text := _archive_intelligence_text(selected_encounter)
	var intel_panel := _make_text_panel("Discovered intelligence", intel_text)
	intel_panel.custom_minimum_size = Vector2(610, 610)
	content_row.add_child(intel_panel)

	var history_text := _archive_history_text(selected_encounter)
	var history_panel := _make_text_panel("Attempt history · newest first", history_text)
	history_panel.custom_minimum_size = Vector2(760, 610)
	content_row.add_child(history_panel)


func _fill_member_list(list: ItemList, members: Array[Dictionary], active: bool) -> void:
	for member in members:
		var member_id := String(member.get("member_id", ""))
		var marker := "●" if active else "○"
		list.add_item(
			(
				"%s  %-24s  %s"
				% [
					marker,
					CampaignState.format_member_label(member),
					_humanize(String(member.get("role", "")))
				]
			)
		)
		list.set_item_metadata(list.item_count - 1, member_id)

	if members.is_empty():
		list.add_item("No reserve members yet.")
		list.set_item_disabled(0, true)


func _on_command_target_selected(index: int, dropdown: OptionButton) -> void:
	CampaignState.set_selected_encounter(String(dropdown.get_item_metadata(index)))


func _on_member_list_selected(index: int, source_list: ItemList) -> void:
	if member_detail_label == null or index < 0 or index >= source_list.item_count:
		return

	var member_id := String(source_list.get_item_metadata(index))
	var member := CampaignState.get_member(member_id)

	if member.is_empty():
		return

	member_detail_label.text = (
		"%s · %s\nAttributes: %s\n%s"
		% [
			CampaignState.format_member_label(member),
			_humanize(String(member.get("role", ""))),
			", ".join(member.get("attributes", [])),
			String(member.get("description", ""))
		]
	)


func _on_swap_selected_members() -> void:
	if active_list == null or reserve_list == null:
		return

	var active_selection := active_list.get_selected_items()
	var reserve_selection := reserve_list.get_selected_items()

	if active_selection.is_empty() or reserve_selection.is_empty():
		return

	var active_id := String(active_list.get_item_metadata(active_selection[0]))
	var reserve_id := String(reserve_list.get_item_metadata(reserve_selection[0]))
	CampaignState.swap_active_member(active_id, reserve_id)


func _on_seed_debug_reserves() -> void:
	CampaignState.ensure_debug_reserves()


func _on_embark_pressed() -> void:
	embark_requested.emit()


func _on_formation_member_dropped(member_id: String, region: String, range_name: String) -> void:
	CampaignState.set_member_placement(member_id, region, range_name)


func _on_formation_member_reorder_requested(
	moving_member_id: String, target_member_id: String, place_after_target: bool
) -> void:
	CampaignState.reorder_active_member(moving_member_id, target_member_id, place_after_target)


func _on_load_formation_pressed(dropdown: OptionButton) -> void:
	if dropdown.selected < 0:
		return

	CampaignState.load_formation(String(dropdown.get_item_metadata(dropdown.selected)))


func _on_delete_formation_pressed(dropdown: OptionButton) -> void:
	if dropdown.selected < 0:
		return

	CampaignState.delete_saved_formation(String(dropdown.get_item_metadata(dropdown.selected)))


func _on_save_formation_pressed(name_input: LineEdit) -> void:
	if CampaignState.save_current_formation(name_input.text):
		name_input.clear()


func _on_saved_formation_selected(
	index: int, dropdown: OptionButton, delete_button: Button
) -> void:
	delete_button.disabled = (
		String(dropdown.get_item_metadata(index)) == CampaignState.DEFAULT_FORMATION_NAME
	)


func _on_archive_target_selected(encounter_id: String) -> void:
	archive_view_encounter_id = encounter_id
	_refresh_current_facility()


func _on_campaign_state_changed() -> void:
	if not visible or refresh_queued:
		return

	refresh_queued = true
	call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	refresh_queued = false

	if visible:
		_refresh_current_facility()


func _command_intelligence_text(encounter_id: String) -> String:
	var discoveries := CampaignState.get_discoveries(encounter_id)
	var abilities: Array = discoveries.get("ability_ids", [])
	var phases: Array = discoveries.get("phase_names", [])

	if abilities.is_empty() and phases.is_empty():
		return "No attempt evidence yet. The archive will record abilities and phases as the raid observes them."

	var lines: Array[String] = []

	for phase_name in phases.slice(0, 2):
		lines.append("Reached: %s" % String(phase_name))

	for ability_id in abilities.slice(0, 4):
		lines.append("Observed: %s" % _humanize(String(ability_id)))

	return "\n".join(lines)


func _latest_attempt_brief(encounter_id: String) -> String:
	var summary := CampaignState.get_latest_attempt(encounter_id)

	if summary.is_empty():
		return "No attempts recorded for this target."

	var lines := [
		(
			"%s · %.1fs"
			% [
				_humanize(String(summary.get("outcome", "unknown"))),
				float(summary.get("duration_seconds", 0.0))
			]
		),
		(
			"Boss progress: %.1f%% · Furthest phase: %s"
			% [
				float(summary.get("boss_progress_percent", 0.0)),
				String(summary.get("furthest_phase_name", "Unknown"))
			]
		),
		(
			"Deaths: %d · Logged events: %d"
			% [summary.get("deaths", []).size(), int(summary.get("event_count", 0))]
		)
	]
	return "\n".join(lines)


func _archive_intelligence_text(encounter_id: String) -> String:
	var discoveries := CampaignState.get_discoveries(encounter_id)

	if discoveries.is_empty():
		return "No facts have been observed for this target."

	var lines: Array[String] = []
	var phase_names: Array = discoveries.get("phase_names", [])
	var abilities: Array = discoveries.get("ability_ids", [])
	var failures: Array = discoveries.get("reliable_failures", [])

	if not phase_names.is_empty():
		lines.append("PHASES REACHED")
		for phase_name in phase_names:
			lines.append("• %s" % String(phase_name))

	if not abilities.is_empty():
		lines.append("\nABILITIES OBSERVED")
		for ability_id in abilities:
			lines.append("• %s" % _humanize(String(ability_id)))

	if not failures.is_empty():
		lines.append("\nRELIABLY DETECTED EVENTS")
		for failure in failures:
			lines.append("• %s" % String(failure))

	return "\n".join(lines)


func _archive_history_text(encounter_id: String) -> String:
	var history := CampaignState.get_attempt_history(encounter_id)

	if history.is_empty():
		return "No attempts recorded."

	var lines: Array[String] = []
	history.reverse()

	for history_index in range(history.size()):
		var summary: Dictionary = history[history_index]
		lines.append(
			(
				"%s · %.1fs · %.1f%% boss progress · %s · %d damage / %d healing"
				% [
					_humanize(String(summary.get("outcome", "unknown"))),
					float(summary.get("duration_seconds", 0.0)),
					float(summary.get("boss_progress_percent", 0.0)),
					String(summary.get("furthest_phase_name", "Unknown phase")),
					_sum_dictionary_values(summary.get("damage_by_source", {})),
					_sum_dictionary_values(summary.get("healing_by_source", {}))
				]
			)
		)

		for death in summary.get("deaths", []).slice(0, 4):
			lines.append(
				(
					"  • %.1fs: %s — %s"
					% [
						float(death.get("time", 0.0)),
						String(death.get("member_name", "Unknown")),
						_humanize(String(death.get("cause_ability_id", "unknown")))
					]
				)
			)

		for failure in summary.get("reliable_failures", []).slice(0, 3):
			lines.append("  • Detected: %s" % String(failure))

		if history_index < 5:
			var timeline: Array = summary.get("timeline", [])
			var recent_timeline := timeline.slice(maxi(timeline.size() - 6, 0))

			if not recent_timeline.is_empty():
				lines.append("  Recent timeline")

				for event in recent_timeline:
					var event_label := String(event.get("display_name", ""))

					if event_label.is_empty():
						event_label = _humanize(
							String(event.get("ability_id", event.get("type", "event")))
						)

					lines.append("    %.1fs · %s" % [float(event.get("time", 0.0)), event_label])

		lines.append("")

	return "\n".join(lines)


func _validation_text(validation: Dictionary) -> String:
	if bool(validation.get("valid", false)):
		return "READY · Target, active twenty, and the global starting formation are valid. No support choices are currently unlocked."

	return "NOT READY · " + "  ".join(validation.get("errors", []))


func _make_text_panel(title: String, text_value: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10181e")
	style.border_color = Color("39464b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("c9b37b"))
	column.add_child(title_label)
	var content_label := Label.new()
	content_label.text = text_value
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_label.add_theme_color_override("font_color", Color("c8c9c3"))
	column.add_child(content_label)
	return panel


func _add_section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color("d5c18a"))
	body.add_child(label)
	return label


func _add_section_label_to(parent: Control, text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("d5c18a"))
	parent.add_child(label)
	return label


func _add_muted_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("9ca4a5"))
	body.add_child(label)
	return label


func _humanize(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _sum_dictionary_values(values: Dictionary) -> int:
	var total := 0

	for value in values.values():
		total += int(value)

	return total
