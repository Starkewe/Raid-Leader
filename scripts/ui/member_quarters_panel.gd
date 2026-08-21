extends VBoxContainer
class_name MemberQuartersPanel

const ProfilePresenterScript := preload(
	"res://scripts/ui/member_quarters_profile_presenter.gd"
)

static var RUNTIME_REFRESH_SECONDS: float = (
	TuningCatalogAccess.get_camp().activities.profile_refresh_seconds
)

const NARRATIVE_BIOGRAPHY := "biography"
const NARRATIVE_CATEGORIES := [
	"close_connections",
	"memories",
	"recent_experiences",
	"personal_themes",
	"recent_social_memories",
]
const NARRATIVE_TITLES := {
	"biography": "Biography and personality",
	"close_connections": "Close connections",
	"memories": "Memories",
	"recent_experiences": "Recent experiences",
	"personal_themes": "Personal themes",
	"recent_social_memories": "Recent social memories",
}
const PREFERRED_ACTIVITY_COLOR := Color("dc9149")

var population_controller: Node = null
var quarters_tabs: HBoxContainer = null
var active_tab_button: Button = null
var reserve_tab_button: Button = null
var roster_scroll: ScrollContainer = null
var roster_entries: VBoxContainer = null
var profile_section: PanelContainer = null
var profile_column: VBoxContainer = null
var current_activity_label: Label = null
var room_status_label: Label = null
var row_by_id: Dictionary = {}
var selected_raider_id: String = ""
var selected_tab_id: String = "active"
var expanded_narrative_category: String = ""
var runtime_snapshots: Dictionary = {}
var refresh_timer: Timer = null
var rebuilding_roster: bool = false
var rebuilding_profile: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_interface()
	refresh_campaign_state()


func configure(controller: Node) -> void:
	population_controller = controller
	_refresh_runtime_snapshots()
	_refresh_runtime_only()


func refresh_campaign_state() -> void:
	if roster_entries == null:
		return
	_refresh_runtime_snapshots()
	_refresh_roster()


func get_selected_raider_id() -> String:
	return selected_raider_id


func get_selected_tab_id() -> String:
	return selected_tab_id


func _build_interface() -> void:
	var content := HBoxContainer.new()
	content.name = "QuartersContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	add_child(content)

	var roster_section := VBoxContainer.new()
	roster_section.name = "QuartersRosterSection"
	roster_section.custom_minimum_size = Vector2(320, 0)
	roster_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_section.add_theme_constant_override("separation", 7)
	content.add_child(roster_section)

	quarters_tabs = HBoxContainer.new()
	quarters_tabs.name = "QuartersTabs"
	quarters_tabs.custom_minimum_size = Vector2(0, 40)
	quarters_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quarters_tabs.add_theme_constant_override("separation", 6)
	roster_section.add_child(quarters_tabs)

	active_tab_button = _make_tab_button("QuartersActiveTab", "Active", "active")
	reserve_tab_button = _make_tab_button("QuartersReserveTab", "Reserve", "reserve")
	quarters_tabs.add_child(active_tab_button)
	quarters_tabs.add_child(reserve_tab_button)
	_update_tab_buttons()

	var roster_panel := PanelContainer.new()
	roster_panel.name = "QuartersRosterPanel"
	roster_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_panel.add_theme_stylebox_override("panel", _panel_style("10181e", "39464b"))
	roster_section.add_child(roster_panel)

	var roster_margin := MarginContainer.new()
	roster_margin.add_theme_constant_override("margin_left", 7)
	roster_margin.add_theme_constant_override("margin_right", 7)
	roster_margin.add_theme_constant_override("margin_top", 7)
	roster_margin.add_theme_constant_override("margin_bottom", 7)
	roster_panel.add_child(roster_margin)

	roster_scroll = ScrollContainer.new()
	roster_scroll.name = "QuartersRosterScroll"
	roster_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	roster_scroll.follow_focus = true
	roster_margin.add_child(roster_scroll)

	roster_entries = VBoxContainer.new()
	roster_entries.name = "QuartersRosterEntries"
	roster_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_entries.add_theme_constant_override("separation", 5)
	roster_scroll.add_child(roster_entries)

	profile_section = PanelContainer.new()
	profile_section.name = "QuartersProfileSection"
	profile_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile_section.add_theme_stylebox_override("panel", _panel_style("0d1419", "596a70"))
	content.add_child(profile_section)

	var profile_margin := MarginContainer.new()
	profile_margin.add_theme_constant_override("margin_left", 12)
	profile_margin.add_theme_constant_override("margin_right", 12)
	profile_margin.add_theme_constant_override("margin_top", 10)
	profile_margin.add_theme_constant_override("margin_bottom", 10)
	profile_section.add_child(profile_margin)

	profile_column = VBoxContainer.new()
	profile_column.name = "QuartersProfileContent"
	profile_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile_column.add_theme_constant_override("separation", 8)
	profile_margin.add_child(profile_column)

	refresh_timer = Timer.new()
	refresh_timer.name = "QuartersRuntimeRefresh"
	refresh_timer.wait_time = RUNTIME_REFRESH_SECONDS
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(_on_runtime_refresh)
	add_child(refresh_timer)


func _make_tab_button(node_name: String, label: String, tab_id: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("quarters_tab_id", tab_id)
	button.pressed.connect(_on_tab_pressed.bind(tab_id))
	return button


func _update_tab_buttons() -> void:
	if active_tab_button == null or reserve_tab_button == null:
		return
	_style_tab_button(active_tab_button, selected_tab_id == "active")
	_style_tab_button(reserve_tab_button, selected_tab_id == "reserve")


func _style_tab_button(button: Button, selected: bool) -> void:
	button.disabled = selected
	button.set_meta("quarters_tab_selected", selected)
	button.add_theme_color_override(
		"font_color", Color("c9b37b") if selected else Color("c8c9c3")
	)
	button.add_theme_color_override(
		"font_disabled_color", Color("e8dfc7") if selected else Color("c8c9c3")
	)
	button.add_theme_stylebox_override(
		"normal", _button_style("39464b" if selected else "1d2a31", "c9b37b" if selected else "4a575b")
	)
	button.add_theme_stylebox_override(
		"hover", _button_style("46545a", "d5c18a")
	)
	button.add_theme_stylebox_override(
		"pressed", _button_style("39464b", "c9b37b")
	)
	button.add_theme_stylebox_override(
		"disabled", _button_style("39464b", "c9b37b")
	)


func _refresh_roster() -> void:
	if roster_entries == null:
		return

	rebuilding_roster = true
	row_by_id.clear()
	_clear_children(roster_entries)

	var members := _members_for_selected_tab()
	var visible_ids: Dictionary = {}
	for member in members:
		visible_ids[String(member.get("member_id", ""))] = true

	if selected_raider_id.is_empty() or not visible_ids.has(selected_raider_id):
		selected_raider_id = (
			String(members[0].get("member_id", "")) if not members.is_empty() else ""
		)

	for member in members:
		var raider_id := String(member.get("member_id", ""))
		if raider_id.is_empty():
			continue
		var entry := _make_roster_entry(member, raider_id == selected_raider_id)
		row_by_id[raider_id] = entry
		roster_entries.add_child(entry)

	rebuilding_roster = false
	_update_tab_buttons()

	if selected_raider_id.is_empty():
		_show_empty_profile(
			"No raiders are assigned to this tab yet."
			if selected_tab_id == "active"
			else "No raiders are currently in reserve."
		)
	else:
		# The first selection on a tab is automatic and must not clear its star.
		_render_selected_raider()


func _members_for_selected_tab() -> Array[Dictionary]:
	if selected_tab_id == "reserve":
		return CampaignState.get_reserve_members_for_roster()
	return CampaignState.get_active_members_for_roster()


func _make_roster_entry(member: Dictionary, selected: bool) -> Button:
	var raider_id := String(member.get("member_id", ""))
	var entry := Button.new()
	entry.name = "QuartersRosterEntry_%s" % _safe_node_suffix(raider_id)
	entry.custom_minimum_size = Vector2(0, 64)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	entry.set_meta("raider_id", raider_id)
	entry.set_meta("selected", selected)
	entry.toggle_mode = true
	entry.button_pressed = selected
	entry.pressed.connect(_on_roster_entry_pressed.bind(raider_id))
	var content := VBoxContainer.new()
	content.name = "QuartersRosterEntryContent"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 7
	content.offset_bottom = -7
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 1)
	var name_label := Label.new()
	name_label.name = "QuartersRosterEntryName"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	content.add_child(name_label)
	var class_label := Label.new()
	class_label.name = "QuartersRosterEntryClass"
	class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	class_label.add_theme_font_size_override("font_size", 13)
	content.add_child(class_label)
	entry.add_child(content)
	_update_roster_entry(entry, member, selected)
	return entry


func _update_roster_entry(entry: Button, member: Dictionary, selected: bool = false) -> void:
	var raider_id := String(member.get("member_id", entry.get_meta("raider_id", "")))
	var unseen := CampaignState.has_unseen_profile_development(raider_id)
	var marker := "★ " if unseen else ""
	var name := String(member.get("display_name", "Unknown Raider"))
	var unit_class := String(member.get("unit_class", "Unknown"))
	var class_id := String(member.get("advanced_class_id", "")).strip_edges()
	if class_id.is_empty():
		class_id = unit_class
	var class_color := RaiderClassCatalog.get_camp_color(class_id)
	var roster_text := "%s%s\n%s" % [marker, name, unit_class]
	# The visible name/class labels are the roster entry UI. Keep the formatted
	# value as metadata without letting Button render a second copy when pressed.
	entry.text = ""
	entry.set_meta("roster_text", roster_text)
	entry.tooltip_text = ""
	entry.set_meta("has_unseen_profile_development", unseen)
	entry.set_meta("class_id", class_id)
	entry.set_meta("class_color", class_color)
	entry.set_meta("roster_display_name", name)
	entry.set_meta("roster_class_name", unit_class)
	entry.set_meta("selected", selected)
	entry.button_pressed = selected
	entry.add_theme_color_override("font_hover_color", Color("fff4d6"))
	entry.add_theme_color_override("font_pressed_color", Color("fff4d6"))
	entry.add_theme_color_override("font_focus_color", Color("fff4d6"))
	# Render the two lines with separate labels so only the class line receives
	# the catalog color.
	var transparent := Color(1.0, 1.0, 1.0, 0.0)
	entry.add_theme_color_override("font_color", transparent)
	entry.add_theme_color_override("font_disabled_color", transparent)
	entry.add_theme_color_override("font_hover_color", transparent)
	entry.add_theme_color_override("font_pressed_color", transparent)
	entry.add_theme_color_override("font_focus_color", transparent)
	entry.add_theme_color_override("font_outline_color", transparent)
	entry.add_theme_constant_override("outline_size", 0)
	var name_label := entry.find_child("QuartersRosterEntryName", true, false) as Label
	if name_label != null:
		name_label.text = "%s%s" % [marker, name]
		name_label.add_theme_color_override(
			"font_color", Color("e8dfc7") if selected else Color("c8c9c3")
		)
	var class_label := entry.find_child("QuartersRosterEntryClass", true, false) as Label
	if class_label != null:
		class_label.text = unit_class
		class_label.add_theme_color_override("font_color", class_color)
	entry.add_theme_stylebox_override(
		"normal", _button_style("39464b" if selected else "18242a", "c9b37b" if selected else "3a484d")
	)
	entry.add_theme_stylebox_override("hover", _button_style("46545a", "d5c18a"))
	entry.add_theme_stylebox_override("pressed", _button_style("39464b", "c9b37b"))
	entry.add_theme_stylebox_override("focus", _button_style("39464b" if selected else "26343a", "d5c18a"))


func _on_tab_pressed(tab_id: String) -> void:
	if tab_id == selected_tab_id:
		return
	selected_tab_id = tab_id
	expanded_narrative_category = ""
	# Selection changes caused by the tab are automatic; they do not mark a profile seen.
	_refresh_roster()


func _on_roster_entry_pressed(raider_id: String) -> void:
	if rebuilding_roster or raider_id.is_empty():
		return
	var member := CampaignState.get_member(raider_id)
	if member.is_empty():
		return
	selected_raider_id = raider_id
	expanded_narrative_category = ""
	CampaignState.mark_raider_profile_seen(raider_id)
	for row_id in row_by_id:
		var row := row_by_id[row_id] as Button
		if row == null:
			continue
		var row_member := CampaignState.get_member(String(row_id))
		_update_roster_entry(row, row_member, String(row_id) == selected_raider_id)
	_render_selected_raider()


func _render_selected_raider() -> void:
	if selected_raider_id.is_empty():
		_show_empty_profile("Select a raider to review their quarters profile.")
		return
	var member := CampaignState.get_member(selected_raider_id)
	if member.is_empty():
		selected_raider_id = ""
		_show_empty_profile("The selected raider is no longer available.")
		return
	_build_profile(ProfilePresenterScript.build_profile(selected_raider_id, _runtime_for(selected_raider_id)))


func _build_profile(profile: Dictionary) -> void:
	rebuilding_profile = true
	_clear_profile()
	if profile.is_empty():
		_show_empty_profile("The selected raider is no longer available.")
		rebuilding_profile = false
		return

	var artwork := _build_visual(profile)
	artwork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_column.add_child(artwork)

	var profile_header := HBoxContainer.new()
	profile_header.name = "QuartersProfileHeader"
	profile_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_header.add_theme_constant_override("separation", 10)
	profile_column.add_child(profile_header)

	var identity := VBoxContainer.new()
	identity.name = "QuartersProfileIdentity"
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 4)
	profile_header.add_child(identity)

	var name_label := Label.new()
	name_label.name = "QuartersProfileName"
	name_label.text = String(profile.get("display_name", "Unknown Raider"))
	name_label.add_theme_font_size_override("font_size", 25)
	name_label.add_theme_color_override("font_color", Color("e8dfc7"))
	identity.add_child(name_label)

	var title := String(profile.get("descriptive_title", "")).strip_edges()
	if not title.is_empty():
		var title_label := Label.new()
		title_label.name = "QuartersProfileTitle"
		title_label.text = title
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_label.add_theme_color_override("font_color", Color("c9b37b"))
		identity.add_child(title_label)

	var class_label := Label.new()
	class_label.name = "QuartersProfileClass"
	class_label.text = String(profile.get("unit_class", "Unknown"))
	class_label.add_theme_font_size_override("font_size", 17)
	class_label.add_theme_color_override(
		"font_color", profile.get("class_color", Color("bfc8c8")) as Color
	)
	identity.add_child(class_label)

	var victory_label := Label.new()
	victory_label.name = "QuartersProfileVictoryCount"
	victory_label.text = "%d victories" % int(profile.get("victory_count", 0))
	victory_label.add_theme_color_override("font_color", Color("c9b37b"))
	identity.add_child(victory_label)

	var room_column := VBoxContainer.new()
	room_column.name = "QuartersProfileRoomColumn"
	room_column.custom_minimum_size = Vector2(190, 0)
	room_column.size_flags_horizontal = Control.SIZE_SHRINK_END
	room_column.add_theme_constant_override("separation", 0)
	profile_header.add_child(room_column)
	_build_room_controls(room_column, String(profile.get("room_assignment_id", "")))

	current_activity_label = Label.new()
	current_activity_label.name = "QuartersProfileCurrentActivity"
	_set_activity_label(
		current_activity_label,
		String(profile.get("full_activity_text", profile.get("runtime_text", "Available in camp")))
	)
	current_activity_label.custom_minimum_size = Vector2(0, 24)
	current_activity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_activity_label.clip_text = true
	current_activity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	current_activity_label.add_theme_color_override("font_color", Color("8fb5c5"))
	current_activity_label.tooltip_text = current_activity_label.text
	current_activity_label.set_meta("full_activity_text", current_activity_label.text)
	profile_column.add_child(current_activity_label)

	var preferred_separator := HSeparator.new()
	preferred_separator.name = "QuartersProfilePreferredSeparator"
	profile_column.add_child(preferred_separator)
	_add_preferred_activities(profile)

	var narrative_separator := HSeparator.new()
	narrative_separator.name = "QuartersProfileNarrativeSeparator"
	profile_column.add_child(narrative_separator)

	var narrative_scroll := ScrollContainer.new()
	narrative_scroll.name = "QuartersProfileNarrativeScroll"
	narrative_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrative_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	narrative_scroll.custom_minimum_size = Vector2(0, 190)
	narrative_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	narrative_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	narrative_scroll.follow_focus = true
	profile_column.add_child(narrative_scroll)

	var narrative_content := VBoxContainer.new()
	narrative_content.name = "QuartersProfileNarrativeContent"
	narrative_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrative_content.add_theme_constant_override("separation", 7)
	narrative_scroll.add_child(narrative_content)
	_build_narrative_sections(narrative_content, profile)

	rebuilding_profile = false


func _build_visual(profile: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "QuartersRaiderArtwork"
	panel.custom_minimum_size = Vector2(0, 190)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style("10181e", "596a70"))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var visual_value: Variant = profile.get("visual", {})
	var visual: Dictionary = Dictionary(visual_value) if visual_value is Dictionary else {}
	var path := String(visual.get("path", ""))
	var loaded: Resource = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	if loaded is Texture2D:
		var texture := TextureRect.new()
		texture.name = "QuartersRaiderArtworkTexture"
		texture.texture = loaded as Texture2D
		texture.custom_minimum_size = Vector2(0, 174)
		texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		margin.add_child(texture)
	else:
		var fallback := CenterContainer.new()
		fallback.name = "QuartersRaiderArtworkFallback"
		fallback.custom_minimum_size = Vector2(0, 174)
		fallback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_child(fallback)
		var initials := Label.new()
		initials.name = "QuartersRaiderInitials"
		initials.text = _initials(String(profile.get("display_name", "?")))
		initials.add_theme_font_size_override("font_size", 52)
		initials.add_theme_color_override("font_color", Color("9fb0b5"))
		fallback.add_child(initials)
	return panel


func _build_room_controls(parent: VBoxContainer, current_room_id: String) -> void:
	var row := HBoxContainer.new()
	row.name = "QuartersRoomAssignment"
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var dropdown := OptionButton.new()
	dropdown.name = "QuartersRoomSelector"
	dropdown.custom_minimum_size = Vector2(174, 34)
	dropdown.size_flags_horizontal = Control.SIZE_SHRINK_END
	var room_options := CampaignState.get_room_options(selected_raider_id)
	var automatic_index := dropdown.item_count
	var automatic_label := "Automatic valid room"
	if current_room_id.is_empty():
		for option_value in room_options:
			var option: Dictionary = option_value
			if bool(option.get("available", false)):
				var available_occupants: Array = option.get("occupant_ids", [])
				automatic_label = "Automatic · %d/%d" % [
					available_occupants.size(), int(option.get("capacity", 4))
				]
				break
	dropdown.add_item(automatic_label)
	dropdown.set_item_metadata(automatic_index, "auto")
	var selected_index := automatic_index
	for option_value in room_options:
		var option: Dictionary = option_value
		var index := dropdown.item_count
		var room_id := String(option.get("room_id", ""))
		var occupants: Array = option.get("occupant_ids", [])
		dropdown.add_item(
			"%s · %d/%d" % [
				option.get("label", "Room"),
				occupants.size(),
				int(option.get("capacity", 4)),
			]
		)
		dropdown.set_item_metadata(index, room_id)
		dropdown.set_item_disabled(
			index,
			not bool(option.get("available", false)) and room_id != current_room_id
		)
		if room_id == current_room_id:
			selected_index = index
	dropdown.select(selected_index)
	dropdown.item_selected.connect(_on_room_selected.bind(dropdown))
	dropdown.tooltip_text = "Change raider room assignment.\n%s" % CampaignState.get_roommate_summary(selected_raider_id)
	row.add_child(dropdown)


func _set_activity_label(label: Label, full_activity_text: String) -> void:
	if label == null:
		return
	label.text = full_activity_text if not full_activity_text.is_empty() else "Available in camp"
	label.tooltip_text = label.text
	label.set_meta("full_activity_text", label.text)


func _add_preferred_activities(profile: Dictionary) -> void:
	var preferred := VBoxContainer.new()
	preferred.name = "QuartersProfilePreferredActivities"
	preferred.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preferred.add_theme_constant_override("separation", 2)
	profile_column.add_child(preferred)

	var heading := Label.new()
	heading.name = "QuartersPreferredActivitiesHeading"
	heading.text = "Preferred activities:"
	heading.add_theme_color_override("font_color", PREFERRED_ACTIVITY_COLOR)
	preferred.add_child(heading)

	var labels_value: Variant = profile.get("preferred_activity_labels", [])
	var labels: Array = labels_value if labels_value is Array else []
	if labels.is_empty():
		labels = ["None recorded"]
	for index in range(labels.size()):
		var bullet := Label.new()
		bullet.name = "QuartersPreferredActivity_%d" % index
		bullet.text = "• " + String(labels[index])
		bullet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bullet.add_theme_color_override("font_color", PREFERRED_ACTIVITY_COLOR)
		preferred.add_child(bullet)


func _build_narrative_sections(parent: VBoxContainer, profile: Dictionary) -> void:
	var biography_lines: Array[String] = [
		String(profile.get("biography", "No biography is available.")),
		String(profile.get("personality_description", "No personality description is available.")),
	]
	_add_narrative_section(parent, NARRATIVE_BIOGRAPHY, biography_lines)
	_add_narrative_section(
		parent, "close_connections", _connection_lines(profile.get("close_connections", [])),
		"No close connections have emerged yet."
	)
	_add_narrative_section(
		parent, "memories", profile.get("lasting_memories", []), "No lasting memories yet."
	)
	_add_narrative_section(
		parent, "recent_experiences", profile.get("recent_experiences", []),
		"No recent experiences have become personal memories."
	)
	_add_narrative_section(
		parent, "personal_themes", profile.get("personal_themes", []),
		"No strong personal theme is currently visible."
	)
	_add_narrative_section(
		parent, "recent_social_memories", profile.get("social_summaries", []),
		"No completed conversations are recorded yet."
	)
	_update_narrative_sections()


func _add_narrative_section(
	parent: VBoxContainer, category: String, value: Variant, empty_text: String = "No record yet."
) -> void:
	var title := String(NARRATIVE_TITLES.get(category, category))
	var section := VBoxContainer.new()
	section.name = "QuartersNarrativeSection_%s" % _safe_node_suffix(category)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 4)
	parent.add_child(section)

	var toggle := Button.new()
	toggle.name = "QuartersNarrativeToggle_%s" % _safe_node_suffix(category)
	toggle.text = title
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size = Vector2(0, 34)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.toggle_mode = true
	toggle.set_meta("narrative_category", category)
	toggle.set_meta("narrative_title", title)
	toggle.pressed.connect(_on_narrative_toggle.bind(category))
	_style_narrative_toggle(toggle, false)
	section.add_child(toggle)

	var body := PanelContainer.new()
	body.name = "QuartersNarrativeBody_%s" % _safe_node_suffix(category)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_stylebox_override("panel", _panel_style("10181e", "39464b"))
	section.add_child(body)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	body.add_child(margin)
	var body_column := VBoxContainer.new()
	body_column.name = "QuartersNarrativeBodyContent"
	body_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_column.add_theme_constant_override("separation", 5)
	margin.add_child(body_column)
	for line in _full_text_lines(value, empty_text):
		var label := Label.new()
		label.name = "QuartersNarrativeText"
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = false
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color("d9dcda"))
		body_column.add_child(label)


func _full_text_lines(value: Variant, empty_text: String) -> Array[String]:
	var lines: Array[String] = []
	if value is Array:
		for line_value in value:
			var line := String(line_value).strip_edges()
			if not line.is_empty():
				lines.append(line)
	else:
		var line := String(value).strip_edges()
		if not line.is_empty():
			lines.append(line)
	if lines.is_empty():
		lines.append(empty_text)
	return lines


func _on_narrative_toggle(category: String) -> void:
	if rebuilding_profile:
		return
	expanded_narrative_category = "" if expanded_narrative_category == category else category
	_update_narrative_sections()


func _update_narrative_sections() -> void:
	if profile_column == null:
		return
	var categories: Array[String] = [NARRATIVE_BIOGRAPHY]
	categories.append_array(NARRATIVE_CATEGORIES)
	for category in categories:
		var toggle := profile_column.find_child(
			"QuartersNarrativeToggle_%s" % _safe_node_suffix(category), true, false
		) as Button
		var body := profile_column.find_child(
			"QuartersNarrativeBody_%s" % _safe_node_suffix(category), true, false
		) as Control
		if toggle == null or body == null:
			continue
		var open := (
			(expanded_narrative_category.is_empty() and category == NARRATIVE_BIOGRAPHY)
			or expanded_narrative_category == category
		)
		toggle.button_pressed = open
		toggle.set_meta("narrative_expanded", open)
		body.visible = open
		_style_narrative_toggle(toggle, open)


func _style_narrative_toggle(button: Button, selected: bool) -> void:
	button.add_theme_color_override("font_color", Color("e8c97f") if selected else Color("c9b37b"))
	button.add_theme_color_override("font_hover_color", Color("fff0c2"))
	button.add_theme_stylebox_override(
		"normal", _button_style("26343a" if selected else "18242a", "c9b37b" if selected else "39464b")
	)
	button.add_theme_stylebox_override("hover", _button_style("35454c", "d5c18a"))
	button.add_theme_stylebox_override("pressed", _button_style("39464b", "d5c18a"))


func _connection_lines(value: Variant) -> Array[String]:
	var lines: Array[String] = []
	if value is Array:
		for connection_value in value:
			if not connection_value is Dictionary:
				continue
			var connection: Dictionary = connection_value
			var line := "%s - %s" % [
				connection.get("name", "Unknown"),
				connection.get("label", "Familiar but distant"),
			]
			var context := String(connection.get("context", "")).strip_edges()
			if not context.is_empty():
				line += ": " + context
			lines.append(line)
	return lines


func _show_empty_profile(message: String) -> void:
	_clear_profile()
	var label := Label.new()
	label.name = "QuartersProfileEmpty"
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("78858a"))
	profile_column.add_child(label)


func _clear_profile() -> void:
	if profile_column == null:
		return
	for child in profile_column.get_children():
		profile_column.remove_child(child)
		child.queue_free()
	current_activity_label = null
	room_status_label = null


func _refresh_runtime_snapshots() -> void:
	if (
		population_controller != null
		and is_instance_valid(population_controller)
		and population_controller.has_method("get_profile_runtime_snapshots")
	):
		var value: Variant = population_controller.call("get_profile_runtime_snapshots")
		runtime_snapshots = Dictionary(value).duplicate(true) if value is Dictionary else {}
	else:
		runtime_snapshots = {}


func _refresh_runtime_only() -> void:
	for raider_id_value in row_by_id.keys():
		var raider_id := String(raider_id_value)
		var row := row_by_id.get(raider_id) as Button
		if row == null:
			continue
		var member := CampaignState.get_member(raider_id)
		if member.is_empty():
			continue
		_update_roster_entry(row, member, raider_id == selected_raider_id)
	if current_activity_label != null and not selected_raider_id.is_empty():
		_set_activity_label(
			current_activity_label,
			ProfilePresenterScript.runtime_text(_runtime_for(selected_raider_id))
		)


func _runtime_for(raider_id: String) -> Dictionary:
	var value: Variant = runtime_snapshots.get(raider_id, {})
	return Dictionary(value) if value is Dictionary else {}


func _on_runtime_refresh() -> void:
	if not is_visible_in_tree():
		return
	_refresh_runtime_snapshots()
	_refresh_runtime_only()


func _on_room_selected(index: int, dropdown: OptionButton) -> void:
	if rebuilding_profile or selected_raider_id.is_empty():
		return
	var room_id := String(dropdown.get_item_metadata(index))
	var changed := (
		CampaignState.assign_raider_room_automatically(selected_raider_id)
		if room_id == "auto"
		else CampaignState.set_room_assignment(selected_raider_id, room_id)
	)
	if not changed:
		dropdown.tooltip_text = "That room is no longer available."


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _panel_style(background: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


func _button_style(background: String, border: String) -> StyleBoxFlat:
	var style := _panel_style(background, border)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _safe_node_suffix(value: String) -> String:
	var suffix := value.replace(" ", "_").replace("/", "_").replace(":", "_")
	return suffix if not suffix.is_empty() else "Unknown"


func _initials(display_name: String) -> String:
	var result := ""
	for part in display_name.split(" ", false):
		if not part.is_empty():
			result += part.left(1).to_upper()
	return result.left(2) if not result.is_empty() else "?"
