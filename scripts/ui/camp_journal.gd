extends Control
class_name CampJournal

const FormationEditorPanelScript := preload("res://scripts/ui/formation_editor_panel.gd")
const RosterMemberCardScript := preload("res://scripts/ui/roster_member_card.gd")
const RosterDropZoneScript := preload("res://scripts/ui/roster_drop_zone.gd")
const CampaignRosterActionsScript := preload("res://scripts/core/campaign_roster_actions.gd")
const MemberQuartersPanelScript := preload("res://scripts/ui/member_quarters_panel.gd")

const COMMAND_CLASS_COLUMN_WIDTH := 170.0
const COMMAND_NAME_COLUMN_WIDTH := 300.0

signal journal_visibility_changed(visible_now: bool)
signal embark_requested

var current_facility_id: String = ""
var header_title: Label = null
var body: VBoxContainer = null
var page: VBoxContainer = null
var member_detail_label: Label = null
var refresh_queued: bool = false
var archive_view_encounter_id: String = ""
var member_quarters_panel: MemberQuartersPanel = null


func _ready() -> void:
	add_to_group("escape_modal")
	_build_shell()
	visible = false
	CampaignState.state_changed.connect(_on_campaign_state_changed)


func open_facility(facility_id: String) -> void:
	if facility_id not in ["command_tent", "formation_yard", "archive", "quarters"]:
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


func close_for_escape() -> void:
	close_journal()


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
	center.offset_left = 55
	center.offset_top = 40
	center.offset_right = -55
	center.offset_bottom = -40
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1540, 920)
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

	root.add_child(HSeparator.new())

	body = VBoxContainer.new()
	body.custom_minimum_size = Vector2(1450, 760)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)


func _refresh_current_facility() -> void:
	if body == null:
		return

	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

	page = null
	member_detail_label = null
	member_quarters_panel = null

	match current_facility_id:
		"command_tent":
			_build_command_tent()
		"formation_yard":
			_build_formation_yard()
		"archive":
			_build_archive()
		"quarters":
			_build_member_quarters()


func _begin_scrolling_page() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var result := VBoxContainer.new()
	result.custom_minimum_size = Vector2(1420, 0)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_constant_override("separation", 12)
	scroll.add_child(result)
	page = result
	return result


func _build_command_tent() -> void:
	header_title.text = "Command Tent — Assemble the Raid Plan"
	var command_page := _begin_scrolling_page()
	_add_muted_label_to(
		command_page,
		"Drag members between Active and Reserves. A raid may embark with any active size from 1 to 20."
	)

	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 12)
	command_page.add_child(target_row)
	_add_section_label_to(target_row, "Battle map")

	var region_label := Label.new()
	region_label.text = "Beast Crucible · Unlocked"
	region_label.add_theme_color_override("font_color", Color("c7b275"))
	region_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(region_label)

	var encounter_dropdown := OptionButton.new()
	encounter_dropdown.custom_minimum_size = Vector2(330, 42)
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

	var roster_row := HBoxContainer.new()
	roster_row.add_theme_constant_override("separation", 18)
	command_page.add_child(roster_row)

	var active_members := CampaignState.get_active_members_for_roster()
	var reserve_members := CampaignState.get_reserve_members_for_roster()
	var role_counts := CampaignState.get_role_counts()
	var active_column := _build_roster_column(
		(
			"Active %d / 20  ·  %d tanks  ·  %d healers  ·  %d DPS"
			% [
				active_members.size(),
				int(role_counts.get("tank", 0)),
				int(role_counts.get("healer", 0)),
				int(role_counts.get("dps", 0))
			]
		),
		"active",
		active_members
	)
	roster_row.add_child(active_column)

	var center_note := VBoxContainer.new()
	center_note.custom_minimum_size = Vector2(210, 390)
	center_note.alignment = BoxContainer.ALIGNMENT_CENTER
	roster_row.add_child(center_note)
	var arrows := Label.new()
	arrows.text = "DRAG\n⇄"
	arrows.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrows.add_theme_font_size_override("font_size", 25)
	arrows.add_theme_color_override("font_color", Color("c9b37b"))
	center_note.add_child(arrows)
	var drag_note := Label.new()
	drag_note.text = "Drop an active member into Reserves to remove them. Drop a reserve into Active to add them."
	drag_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drag_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_note.add_theme_color_override("font_color", Color("9ca4a5"))
	center_note.add_child(drag_note)

	var reserve_column := _build_roster_column(
		"Available Reserves · %d" % reserve_members.size(), "reserve", reserve_members
	)
	roster_row.add_child(reserve_column)

	member_detail_label = Label.new()
	member_detail_label.text = "Select a member to inspect their visible attributes and identity."
	member_detail_label.custom_minimum_size = Vector2(0, 64)
	member_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	command_page.add_child(member_detail_label)

	var intelligence_row := HBoxContainer.new()
	intelligence_row.add_theme_constant_override("separation", 18)
	command_page.add_child(intelligence_row)
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
	var placements_value: Variant = formation.get("placements", {})
	var placements: Dictionary = (
		Dictionary(placements_value) if placements_value is Dictionary else {}
	)
	var placed_count := 0

	for member_id in CampaignState.get_active_member_ids():
		if placements.has(member_id):
			placed_count += 1

	var plan_summary := Label.new()
	plan_summary.text = (
		"RAID PLAN · Beast Crucible · Global formation: %s · %d/%d active members placed"
		% [String(formation.get("preset_name", "Custom")), placed_count, active_members.size()]
	)
	plan_summary.add_theme_color_override("font_color", Color("c9b37b"))
	command_page.add_child(plan_summary)

	var validation := CampaignState.validate_raid_plan()
	var validation_label := Label.new()
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.text = _validation_text(validation)
	validation_label.add_theme_color_override(
		"font_color", Color("9fc18b") if bool(validation.get("valid", false)) else Color("d78d7d")
	)
	command_page.add_child(validation_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	command_page.add_child(footer)

	if OS.is_debug_build():
		var report_button := Button.new()
		report_button.text = "Debug: Print Cast Report"
		report_button.tooltip_text = (
			"Prints the campaign seed, hidden cast IDs, distributions, and migration warnings."
		)
		report_button.pressed.connect(_on_print_cast_report)
		footer.add_child(report_button)

		var stress_button := Button.new()
		stress_button.text = "Debug: Recruit Future 20"
		stress_button.tooltip_text = (
			"Recruits this campaign's stored future cast for Camp stress testing."
		)
		stress_button.disabled = CampaignState.get_roster_members().size() >= 40
		stress_button.pressed.connect(_on_seed_debug_reserves)
		footer.add_child(stress_button)

		var event_report_button := Button.new()
		event_report_button.text = "Debug: Camp V2 Report"
		event_report_button.tooltip_text = (
			"Prints notable events, memories, Chronicle entries, relationships, and lore state."
		)
		event_report_button.pressed.connect(_on_print_camp_v2_event_report)
		footer.add_child(event_report_button)

		var event_smoke_button := Button.new()
		event_smoke_button.text = "Debug: Memory Smoke"
		event_smoke_button.tooltip_text = (
			"Emits bounded synthetic events through the real campaign pipeline, then prints the report."
		)
		event_smoke_button.pressed.connect(_on_run_camp_v2_event_smoke)
		footer.add_child(event_smoke_button)

		var activity_debug_menu := MenuButton.new()
		activity_debug_menu.text = "Debug: Activities"
		activity_debug_menu.tooltip_text = (
			"Inspect or control Camp V2 activities, stations, conversations, pressure, and cooldowns."
		)
		var activity_popup := activity_debug_menu.get_popup()
		activity_popup.add_item("Print activity/conversation report", 0)
		activity_popup.add_item("Force ordinary conversation", 1)
		activity_popup.add_item("Force authored lore exchange", 2)
		activity_popup.add_item("Toggle accelerated timing", 3)
		activity_popup.add_item("Cancel active conversations", 4)
		activity_popup.add_item("Force embedded smith conversation", 5)
		activity_popup.id_pressed.connect(_on_activity_debug_action)
		footer.add_child(activity_debug_menu)

	var embark_button := Button.new()
	embark_button.text = "Embark with this Raid Plan"
	embark_button.custom_minimum_size = Vector2(320, 52)
	embark_button.disabled = not bool(validation.get("valid", false))
	embark_button.pressed.connect(_on_embark_pressed)
	footer.add_child(embark_button)


func _build_roster_column(
	heading_text: String, zone_id: String, members: Array[Dictionary]
) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(555, 390)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var heading := Label.new()
	heading.text = heading_text
	heading.add_theme_color_override("font_color", Color("d5c18a"))
	column.add_child(heading)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 350)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10181e")
	style.border_color = Color("39464b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	column.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 4)
	margin.add_child(table)
	table.add_child(_make_command_roster_header())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.add_child(scroll)

	var drop_zone := RosterDropZoneScript.new() as RosterDropZone
	drop_zone.configure(zone_id)
	drop_zone.custom_minimum_size = Vector2(505, 325)
	drop_zone.member_dropped.connect(_on_roster_member_dropped)
	scroll.add_child(drop_zone)

	for member in members:
		var member_id := str(member.get("member_id", "")).strip_edges()
		var class_text := str(member.get("unit_class", "")).strip_edges()
		var name_text := str(member.get("display_name", "")).strip_edges()

		if class_text.is_empty():
			class_text = "Unknown"

		if name_text.is_empty():
			name_text = "Unknown"

		var card := RosterMemberCardScript.new() as RosterMemberCard
		card.configure(
			member_id,
			zone_id,
			class_text,
			name_text,
			COMMAND_CLASS_COLUMN_WIDTH,
			COMMAND_NAME_COLUMN_WIDTH
		)
		card.member_inspect_requested.connect(_on_member_inspect_requested)
		card.member_transfer_requested.connect(_on_roster_member_dropped)
		card.member_reorder_requested.connect(_on_active_member_reorder_requested)
		drop_zone.add_child(card)

	if members.is_empty():
		var empty := Label.new()
		empty.text = (
			"No active members."
			if zone_id == "active"
			else "No reserves yet. Use the debug seed during development or recruit members later."
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("778087"))
		drop_zone.add_child(empty)

	return column


func _make_command_roster_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size = Vector2(505, 32)
	var inset := Control.new()
	inset.custom_minimum_size = Vector2(4, 0)
	header.add_child(inset)
	header.add_child(_make_command_header_label("Class", COMMAND_CLASS_COLUMN_WIDTH))
	header.add_child(_make_command_header_label("Name", COMMAND_NAME_COLUMN_WIDTH))
	return header


func _make_command_header_label(label_text: String, width: float) -> Label:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.add_theme_color_override("font_color", Color("d5c18a"))
	return label


func _build_formation_yard() -> void:
	header_title.text = "Formation Yard — Raid Formation"
	var formation_page := _begin_scrolling_page()
	_add_muted_label_to(
		formation_page,
		"Formations apply to the starting position of each raid member. Drag a member to a \"Mini-region\" to move their starting position."
	)

	var formation := CampaignState.get_formation()
	var current_name := String(formation.get("preset_name", "Custom"))
	var current_formation_row := HBoxContainer.new()
	current_formation_row.add_theme_constant_override("separation", 10)
	formation_page.add_child(current_formation_row)
	_add_section_label_to(current_formation_row, "Current Formation:")

	var preset_dropdown := OptionButton.new()
	preset_dropdown.custom_minimum_size = Vector2(230, 42)
	preset_dropdown.add_item(CampaignState.DEFAULT_FORMATION_NAME)
	preset_dropdown.set_item_metadata(0, CampaignState.DEFAULT_FORMATION_NAME)
	var selected_index := 0

	for formation_name in CampaignState.get_saved_formation_names():
		var option_index := preset_dropdown.item_count
		preset_dropdown.add_item(formation_name)
		preset_dropdown.set_item_metadata(option_index, formation_name)

		if formation_name == current_name:
			selected_index = option_index

	preset_dropdown.select(selected_index)
	preset_dropdown.item_selected.connect(_on_saved_formation_selected.bind(preset_dropdown))
	current_formation_row.add_child(preset_dropdown)

	var editor := FormationEditorPanelScript.new() as FormationEditorPanel
	editor.set_map_header_builder(_build_formation_name_controls.bind(preset_dropdown))
	editor.configure("", true, false, false)
	formation_page.add_child(editor)


func _build_member_quarters() -> void:
	header_title.text = "Member Quarters — Raider Profiles"
	member_quarters_panel = MemberQuartersPanelScript.new() as MemberQuartersPanel
	member_quarters_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member_quarters_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	member_quarters_panel.back_requested.connect(close_journal)
	body.add_child(member_quarters_panel)
	member_quarters_panel.configure(_get_population_controller())


func _build_formation_name_controls(preset_dropdown: OptionButton) -> Control:
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(0, 42)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	center.add_child(controls)

	var name_input := LineEdit.new()
	name_input.placeholder_text = "New formation name"
	name_input.custom_minimum_size = Vector2(235, 42)
	name_input.tooltip_text = "Saving an existing name overwrites that saved formation."
	controls.add_child(name_input)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.custom_minimum_size = Vector2(90, 42)
	save_button.pressed.connect(_on_save_formation_pressed.bind(name_input))
	controls.add_child(save_button)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.custom_minimum_size = Vector2(90, 42)
	delete_button.disabled = (
		String(preset_dropdown.get_item_metadata(preset_dropdown.selected))
		== CampaignState.DEFAULT_FORMATION_NAME
	)
	delete_button.pressed.connect(_on_delete_formation_pressed.bind(preset_dropdown))
	controls.add_child(delete_button)

	return center


func _build_archive() -> void:
	header_title.text = "Archive — Observed Intelligence and Attempts"
	page = body
	_add_muted_label_to(
		body,
		"The archive records observed facts. Only the attempt-history panel scrolls; the target and intelligence remain anchored."
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
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content_row)

	var intel_panel := _make_text_panel(
		"Discovered intelligence", _archive_intelligence_text(selected_encounter)
	)
	intel_panel.custom_minimum_size = Vector2(480, 650)
	content_row.add_child(intel_panel)

	var history_panel := PanelContainer.new()
	history_panel.custom_minimum_size = Vector2(930, 650)
	history_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var history_style := StyleBoxFlat.new()
	history_style.bg_color = Color("10181e")
	history_style.border_color = Color("39464b")
	history_style.set_border_width_all(1)
	history_style.set_corner_radius_all(3)
	history_panel.add_theme_stylebox_override("panel", history_style)
	content_row.add_child(history_panel)

	var history_margin := MarginContainer.new()
	history_margin.add_theme_constant_override("margin_left", 14)
	history_margin.add_theme_constant_override("margin_right", 14)
	history_margin.add_theme_constant_override("margin_top", 12)
	history_margin.add_theme_constant_override("margin_bottom", 12)
	history_panel.add_child(history_margin)

	var history_root := VBoxContainer.new()
	history_root.add_theme_constant_override("separation", 8)
	history_margin.add_child(history_root)
	var history_title := Label.new()
	history_title.text = "Attempt history · newest first"
	history_title.add_theme_font_size_override("font_size", 18)
	history_title.add_theme_color_override("font_color", Color("c9b37b"))
	history_root.add_child(history_title)

	var history_scroll := ScrollContainer.new()
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_root.add_child(history_scroll)
	var history_list := VBoxContainer.new()
	history_list.custom_minimum_size = Vector2(880, 0)
	history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_list.add_theme_constant_override("separation", 9)
	history_scroll.add_child(history_list)
	_build_archive_history(selected_encounter, history_list)


func _build_archive_history(encounter_id: String, target: VBoxContainer) -> void:
	var history := CampaignState.get_attempt_history(encounter_id)

	if history.is_empty():
		var empty := Label.new()
		empty.text = "No attempts recorded."
		target.add_child(empty)
		return

	history.reverse()

	for index in range(history.size()):
		# The newest attempt starts expanded. Every retained card can be toggled independently.
		target.add_child(_make_attempt_card(history[index], index == 0, index + 1))


func _make_attempt_card(summary: Dictionary, expanded: bool, attempt_number: int) -> PanelContainer:
	var card := PanelContainer.new()
	var outcome := String(summary.get("outcome", "unknown"))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var summary_text := (
		"Attempt %d · %s · %.1fs · %.1f%% boss progress · %s"
		% [
			attempt_number,
			_humanize(outcome),
			float(summary.get("duration_seconds", 0.0)),
			float(summary.get("boss_progress_percent", 0.0)),
			String(summary.get("furthest_phase_name", "Unknown phase"))
		]
	)
	var summary_button := Button.new()
	summary_button.flat = true
	summary_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary_button.add_theme_color_override(
		"font_color", Color("a9cf9b") if outcome == "victory" else Color("d8aaa2")
	)
	column.add_child(summary_button)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 5)
	column.add_child(details)

	var totals := Label.new()
	totals.text = (
		"%d damage · %d healing · %d deaths · %d events"
		% [
			_sum_dictionary_values(summary.get("damage_by_source", {})),
			_sum_dictionary_values(summary.get("healing_by_source", {})),
			summary.get("deaths", []).size(),
			int(summary.get("event_count", 0))
		]
	)
	totals.add_theme_color_override("font_color", Color("aeb8af"))
	details.add_child(totals)

	var timeline: Array = summary.get("timeline", [])
	var recent_timeline := timeline.slice(maxi(timeline.size() - 10, 0))

	if not recent_timeline.is_empty():
		var timeline_label := Label.new()
		timeline_label.text = "Hover timeline"
		timeline_label.add_theme_color_override("font_color", Color("c9b37b"))
		details.add_child(timeline_label)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 5)
		details.add_child(flow)

		for event in recent_timeline:
			var event_label := String(event.get("display_name", ""))

			if event_label.is_empty():
				event_label = _humanize(
					String(event.get("ability_id", event.get("type", "event")))
				)

			var chip := Label.new()
			chip.text = " %.1fs · %s " % [float(event.get("time", 0.0)), event_label]
			chip.tooltip_text = _timeline_tooltip(event)
			chip.add_theme_color_override("font_color", _timeline_color(event))
			chip.add_theme_color_override("font_shadow_color", Color("080d10"))
			chip.add_theme_constant_override("shadow_offset_x", 1)
			chip.add_theme_constant_override("shadow_offset_y", 1)
			flow.add_child(chip)

	var failures: Array = summary.get("reliable_failures", [])

	for failure in failures.slice(0, 3):
		var failure_label := Label.new()
		failure_label.text = "• %s" % String(failure)
		failure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		failure_label.add_theme_color_override("font_color", Color("d3b18b"))
		details.add_child(failure_label)

	summary_button.pressed.connect(
		_on_attempt_card_toggled.bind(card, summary_button, details, outcome, summary_text)
	)
	_set_attempt_card_expanded(card, summary_button, details, outcome, summary_text, expanded)

	return card


func _on_attempt_card_toggled(
	card: PanelContainer,
	summary_button: Button,
	details: VBoxContainer,
	outcome: String,
	summary_text: String
) -> void:
	_set_attempt_card_expanded(
		card, summary_button, details, outcome, summary_text, not details.visible
	)


func _set_attempt_card_expanded(
	card: PanelContainer,
	summary_button: Button,
	details: VBoxContainer,
	outcome: String,
	summary_text: String,
	expanded: bool
) -> void:
	details.visible = expanded
	summary_button.text = ("▼ " if expanded else "▶ ") + summary_text
	summary_button.tooltip_text = "Click to minimize" if expanded else "Click to expand"

	var style := StyleBoxFlat.new()
	style.bg_color = Color("162128")
	style.border_color = Color("6e8a68") if outcome == "victory" else Color("765550")
	style.set_border_width_all(2 if expanded else 1)
	style.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", style)


func _timeline_tooltip(event: Dictionary) -> String:
	return (
		"Time: %.1fs\nType: %s\nAbility: %s\nTarget: %s"
		% [
			float(event.get("time", 0.0)),
			_humanize(String(event.get("type", "event"))),
			_humanize(String(event.get("ability_id", "unknown"))),
			String(event.get("target_name", event.get("target_id", "Unknown")))
		]
	)


func _timeline_color(event: Dictionary) -> Color:
	var event_type := String(event.get("type", ""))

	if event_type.contains("heal"):
		return Color("8dc79a")

	if event_type.contains("death") or event_type.contains("damage"):
		return Color("d38d83")

	if event_type.contains("cast") or event_type.contains("ability"):
		return Color("c9b37b")

	return Color("9ab4c4")


func _on_roster_member_dropped(member_id: String, source_zone: String, target_zone: String) -> void:
	if source_zone == "reserve" and target_zone == "active":
		CampaignRosterActionsScript.add_active_member(member_id)
	elif source_zone == "active" and target_zone == "reserve":
		CampaignRosterActionsScript.remove_active_member(member_id)


func _on_active_member_reorder_requested(
	moving_member_id: String, target_member_id: String, place_after_target: bool
) -> void:
	CampaignState.reorder_active_member(moving_member_id, target_member_id, place_after_target)


func _on_member_inspect_requested(member_id: String) -> void:
	if member_detail_label == null:
		return

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


func _on_command_target_selected(index: int, dropdown: OptionButton) -> void:
	CampaignState.set_selected_encounter(String(dropdown.get_item_metadata(index)))


func _on_seed_debug_reserves() -> void:
	CampaignState.ensure_debug_reserves()


func _on_print_cast_report() -> void:
	CampaignState.print_campaign_cast_report()


func _on_print_camp_v2_event_report() -> void:
	CampaignState.print_camp_v2_event_debug_report()


func _on_run_camp_v2_event_smoke() -> void:
	print("[Camp V2 Memory Smoke] ", CampaignState.run_camp_v2_event_debug_smoke())
	CampaignState.print_camp_v2_event_debug_report()


func _on_activity_debug_action(action_id: int) -> void:
	var controller := _get_population_controller()
	if controller == null:
		print("[Camp V2 Activities] Camp population controller is unavailable.")
		return

	match action_id:
		0:
			controller.call("print_camp_v2_runtime_debug_report")
		1:
			print("[Camp V2 Force Conversation] ", controller.call("force_conversation"))
		2:
			print("[Camp V2 Force Lore] ", controller.call("force_lore_exchange"))
		3:
			var report: Dictionary = controller.call("get_camp_v2_runtime_debug_report")
			var enabled := not bool(report.get("accelerated_timing", false))
			controller.call("set_accelerated_activity_timing", enabled)
			print("[Camp V2 Accelerated Timing] ", enabled)
		4:
			print("[Camp V2 Cancel Conversations] ", controller.call("cancel_active_conversations"))
		5:
			print(
				"[Camp V2 Force Smith Conversation] ",
				controller.call("force_conversation", "smith_embedded_hammer")
			)


func _get_population_controller() -> Node:
	var nodes := get_tree().get_nodes_in_group("camp_population_controller")
	return nodes[0] if not nodes.is_empty() else null


func _on_embark_pressed() -> void:
	embark_requested.emit()


func _on_delete_formation_pressed(dropdown: OptionButton) -> void:
	if dropdown.selected >= 0:
		CampaignState.delete_saved_formation(String(dropdown.get_item_metadata(dropdown.selected)))


func _on_save_formation_pressed(name_input: LineEdit) -> void:
	if CampaignState.save_current_formation(name_input.text):
		name_input.clear()


func _on_saved_formation_selected(
	index: int, dropdown: OptionButton
) -> void:
	if index >= 0:
		CampaignState.load_formation(String(dropdown.get_item_metadata(index)))


func _on_archive_target_selected(encounter_id: String) -> void:
	archive_view_encounter_id = encounter_id
	_queue_refresh()


func _on_campaign_state_changed() -> void:
	if (
		visible
		and current_facility_id == "quarters"
		and member_quarters_panel != null
		and is_instance_valid(member_quarters_panel)
	):
		member_quarters_panel.refresh_campaign_state()
		return
	_queue_refresh()


func _queue_refresh() -> void:
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

	return "\n".join(
		[
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
	)


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


func _validation_text(validation: Dictionary) -> String:
	if bool(validation.get("valid", false)):
		var warnings: Array = validation.get("warnings", [])
		return (
			"READY · Target, active roster, and global starting formation are valid."
			if warnings.is_empty()
			else "READY · " + "  ".join(warnings)
		)

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


func _add_section_label_to(parent: Control, text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("d5c18a"))
	parent.add_child(label)
	return label


func _add_muted_label_to(parent: Control, text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("9ca4a5"))
	parent.add_child(label)
	return label


func _humanize(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _sum_dictionary_values(values: Dictionary) -> int:
	var total := 0

	for value in values.values():
		total += int(value)

	return total
