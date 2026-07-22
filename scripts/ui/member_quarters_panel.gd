extends HBoxContainer
class_name MemberQuartersPanel

const ProfilePresenterScript := preload(
	"res://scripts/ui/member_quarters_profile_presenter.gd"
)
const CampV2TuningScript := preload("res://scripts/core/camp_v2_tuning.gd")

signal back_requested

const ROSTER_COLUMN_TITLES := ["Name", "Class", "Status", "Activity", "Room", "New"]
const ROSTER_COLUMN_WIDTHS := [150, 95, 80, 175, 85, 40]
const RUNTIME_REFRESH_SECONDS: float = CampV2TuningScript.ACTIVITIES[
	"profile_refresh_seconds"
]

var population_controller: Node = null
var roster_tree: Tree = null
var profile_column: VBoxContainer = null
var search_input: LineEdit = null
var status_filter: OptionButton = null
var class_filter: OptionButton = null
var room_filter: OptionButton = null
var recent_filter: CheckButton = null
var sort_dropdown: OptionButton = null
var result_label: Label = null
var current_activity_label: Label = null
var debug_toggle: CheckButton = null
var debug_text: TextEdit = null
var room_status_label: Label = null
var row_by_id: Dictionary = {}
var selected_raider_id: String = ""
var runtime_snapshots: Dictionary = {}
var refresh_timer: Timer = null
var rebuilding_roster: bool = false
var rebuilding_profile: bool = false
var filters_ready: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_interface()
	refresh_campaign_state()


func configure(controller: Node) -> void:
	population_controller = controller
	_refresh_runtime_snapshots()
	_refresh_runtime_only()


func refresh_campaign_state() -> void:
	if roster_tree == null:
		return

	_populate_filter_options()
	_refresh_runtime_snapshots()
	_refresh_roster()


func get_selected_raider_id() -> String:
	return selected_raider_id


func _build_interface() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(610, 720)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 9)
	add_child(left)

	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	left.add_child(navigation)
	var back_button := Button.new()
	back_button.text = "Back to Camp"
	back_button.custom_minimum_size = Vector2(135, 38)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	navigation.add_child(back_button)
	var roster_title := Label.new()
	roster_title.text = "Raider Roster"
	roster_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roster_title.add_theme_font_size_override("font_size", 22)
	roster_title.add_theme_color_override("font_color", Color("d5c18a"))
	navigation.add_child(roster_title)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Filter by name"
	search_input.clear_button_enabled = true
	search_input.text_changed.connect(_on_filter_changed)
	left.add_child(search_input)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 7)
	left.add_child(filter_row)
	status_filter = _make_filter_dropdown(Vector2(125, 38))
	status_filter.item_selected.connect(_on_filter_selected)
	filter_row.add_child(status_filter)
	class_filter = _make_filter_dropdown(Vector2(125, 38))
	class_filter.item_selected.connect(_on_filter_selected)
	filter_row.add_child(class_filter)
	room_filter = _make_filter_dropdown(Vector2(145, 38))
	room_filter.item_selected.connect(_on_filter_selected)
	filter_row.add_child(room_filter)
	recent_filter = CheckButton.new()
	recent_filter.text = "Updated"
	recent_filter.tooltip_text = "Show only raiders with unseen profile developments."
	recent_filter.toggled.connect(_on_recent_filter_toggled)
	filter_row.add_child(recent_filter)

	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 8)
	left.add_child(sort_row)
	var sort_label := Label.new()
	sort_label.text = "Sort"
	sort_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sort_label.add_theme_color_override("font_color", Color("9ca4a5"))
	sort_row.add_child(sort_label)
	sort_dropdown = OptionButton.new()
	sort_dropdown.custom_minimum_size = Vector2(235, 38)
	_add_option(sort_dropdown, "Class, then name", "class_name")
	_add_option(sort_dropdown, "Name", "name")
	_add_option(sort_dropdown, "Active, then reserve", "status")
	_add_option(sort_dropdown, "Current activity", "activity")
	_add_option(sort_dropdown, "Room", "room")
	_add_option(sort_dropdown, "Recently updated", "updated")
	sort_dropdown.item_selected.connect(_on_sort_selected)
	sort_row.add_child(sort_dropdown)
	result_label = Label.new()
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_color_override("font_color", Color("78858a"))
	sort_row.add_child(result_label)

	var roster_panel := PanelContainer.new()
	roster_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_panel.add_theme_stylebox_override("panel", _panel_style("10181e", "39464b"))
	left.add_child(roster_panel)
	var roster_margin := MarginContainer.new()
	roster_margin.add_theme_constant_override("margin_left", 7)
	roster_margin.add_theme_constant_override("margin_right", 7)
	roster_margin.add_theme_constant_override("margin_top", 7)
	roster_margin.add_theme_constant_override("margin_bottom", 7)
	roster_panel.add_child(roster_margin)
	roster_tree = Tree.new()
	roster_tree.hide_root = true
	roster_tree.columns = ROSTER_COLUMN_TITLES.size()
	roster_tree.column_titles_visible = true
	roster_tree.select_mode = Tree.SELECT_ROW
	roster_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for column_index in range(ROSTER_COLUMN_TITLES.size()):
		roster_tree.set_column_title(column_index, ROSTER_COLUMN_TITLES[column_index])
		roster_tree.set_column_custom_minimum_width(column_index, ROSTER_COLUMN_WIDTHS[column_index])
		roster_tree.set_column_expand(column_index, column_index in [0, 3])
	roster_tree.item_selected.connect(_on_roster_item_selected)
	roster_margin.add_child(roster_tree)

	var separator := VSeparator.new()
	separator.custom_minimum_size = Vector2(2, 0)
	add_child(separator)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(780, 720)
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(right_scroll)
	profile_column = VBoxContainer.new()
	profile_column.custom_minimum_size = Vector2(755, 0)
	profile_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_column.add_theme_constant_override("separation", 11)
	right_scroll.add_child(profile_column)

	refresh_timer = Timer.new()
	refresh_timer.wait_time = RUNTIME_REFRESH_SECONDS
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(_on_runtime_refresh)
	add_child(refresh_timer)


func _populate_filter_options() -> void:
	var selected_status := _selected_metadata(status_filter, "all")
	var selected_class := _selected_metadata(class_filter, "all")
	var selected_room := _selected_metadata(room_filter, "all")
	filters_ready = false

	_clear_options(status_filter)
	_add_option(status_filter, "All raiders", "all")
	_add_option(status_filter, "Active", "active")
	_add_option(status_filter, "Reserve", "reserve")
	_select_metadata(status_filter, selected_status)

	_clear_options(class_filter)
	_add_option(class_filter, "All classes", "all")
	var classes: Array[String] = []
	for member in CampaignState.get_roster_members():
		var unit_class_name := String(member.get("unit_class", "Unknown"))
		if not classes.has(unit_class_name):
			classes.append(unit_class_name)
	classes.sort()
	for unit_class_name in classes:
		_add_option(class_filter, unit_class_name, unit_class_name)
	_select_metadata(class_filter, selected_class)

	_clear_options(room_filter)
	_add_option(room_filter, "All rooms", "all")
	for option in CampaignState.get_room_options():
		_add_option(
			room_filter,
			String(option.get("label", "Room")),
			String(option.get("room_id", ""))
		)
	_select_metadata(room_filter, selected_room)
	filters_ready = true


func _refresh_roster() -> void:
	if roster_tree == null:
		return

	rebuilding_roster = true
	row_by_id.clear()
	roster_tree.clear()
	var root := roster_tree.create_item()
	var members := _filtered_members()
	_sort_members(members)
	var selected_item: TreeItem = null

	for member in members:
		var raider_id := String(member.get("member_id", ""))
		var item := roster_tree.create_item(root)
		item.set_metadata(0, raider_id)
		item.set_text(0, String(member.get("display_name", "Unknown")))
		item.set_text(1, String(member.get("unit_class", "Unknown")))
		item.set_text(2, "Active" if CampaignState.is_member_active(raider_id) else "Reserve")
		item.set_text(3, ProfilePresenterScript.runtime_text(_runtime_for(raider_id)))
		item.set_text(4, CampaignState.get_room_assignment_label(raider_id).trim_prefix("Room "))
		item.set_text(5, "●" if CampaignState.has_unseen_profile_development(raider_id) else "")
		item.set_tooltip_text(5, "Unseen profile developments" if not item.get_text(5).is_empty() else "No unseen developments")
		if CampaignState.has_unseen_profile_development(raider_id):
			item.set_custom_color(5, Color("d5c18a"))
		row_by_id[raider_id] = item
		if raider_id == selected_raider_id:
			selected_item = item

	result_label.text = "%d shown" % members.size()
	if selected_item == null and not members.is_empty():
		selected_raider_id = String(members[0].get("member_id", ""))
		selected_item = row_by_id.get(selected_raider_id) as TreeItem
	if selected_item != null:
		selected_item.select(0)
	rebuilding_roster = false

	if selected_raider_id.is_empty():
		_show_empty_profile("No raiders match the current filters.")
	else:
		_select_raider(selected_raider_id)


func _filtered_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var search := search_input.text.strip_edges().to_lower()
	var status := _selected_metadata(status_filter, "all")
	var selected_unit_class := _selected_metadata(class_filter, "all")
	var room_id := _selected_metadata(room_filter, "all")

	for member in CampaignState.get_roster_members():
		var raider_id := String(member.get("member_id", ""))
		var active := CampaignState.is_member_active(raider_id)
		if not search.is_empty() and not String(member.get("display_name", "")).to_lower().contains(search):
			continue
		if status == "active" and not active:
			continue
		if status == "reserve" and active:
			continue
		if (
			selected_unit_class != "all"
			and String(member.get("unit_class", "")) != selected_unit_class
		):
			continue
		if room_id != "all" and String(member.get("room_assignment_id", "")) != room_id:
			continue
		if recent_filter.button_pressed and not CampaignState.has_unseen_profile_development(raider_id):
			continue
		result.append(member.duplicate(true))
	return result


func _sort_members(members: Array[Dictionary]) -> void:
	var mode := _selected_metadata(sort_dropdown, "class_name")
	members.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_id := String(a.get("member_id", ""))
			var b_id := String(b.get("member_id", ""))
			var primary := 0
			match mode:
				"name":
					primary = String(a.get("display_name", "")).naturalnocasecmp_to(String(b.get("display_name", "")))
				"status":
					primary = int(not CampaignState.is_member_active(a_id)) - int(not CampaignState.is_member_active(b_id))
				"activity":
					primary = ProfilePresenterScript.runtime_text(_runtime_for(a_id)).naturalnocasecmp_to(ProfilePresenterScript.runtime_text(_runtime_for(b_id)))
				"room":
					primary = String(a.get("room_assignment_id", "")).naturalnocasecmp_to(String(b.get("room_assignment_id", "")))
				"updated":
					primary = CampaignState.get_unseen_profile_development_count(b_id) - CampaignState.get_unseen_profile_development_count(a_id)
				_:
					primary = String(a.get("unit_class", "")).naturalnocasecmp_to(String(b.get("unit_class", "")))
			if primary != 0:
				return primary < 0
			var name_order := String(a.get("display_name", "")).naturalnocasecmp_to(String(b.get("display_name", "")))
			return name_order < 0 if name_order != 0 else a_id < b_id
	)


func _select_raider(raider_id: String) -> void:
	var member := CampaignState.get_member(raider_id)
	if member.is_empty():
		selected_raider_id = ""
		_refresh_roster()
		return

	selected_raider_id = raider_id
	CampaignState.mark_raider_profile_seen(raider_id)
	var row := row_by_id.get(raider_id) as TreeItem
	if row != null:
		row.set_text(5, "")
		row.set_tooltip_text(5, "No unseen developments")
	_build_profile(ProfilePresenterScript.build_profile(raider_id, _runtime_for(raider_id)))


func _build_profile(profile: Dictionary) -> void:
	rebuilding_profile = true
	_clear_profile()
	if profile.is_empty():
		_show_empty_profile("The selected raider is no longer available.")
		rebuilding_profile = false
		return

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	profile_column.add_child(top)
	top.add_child(_build_visual(profile))

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 6)
	top.add_child(identity)
	var name_label := Label.new()
	name_label.text = String(profile.get("display_name", "Unknown Raider"))
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color("e8dfc7"))
	identity.add_child(name_label)
	var title := String(profile.get("descriptive_title", ""))
	if not title.is_empty():
		var title_label := Label.new()
		title_label.text = title
		title_label.add_theme_color_override("font_color", Color("c9b37b"))
		identity.add_child(title_label)
	var class_status := Label.new()
	class_status.text = "%s · %s" % [profile.get("unit_class", "Unknown"), profile.get("roster_status", "Reserve")]
	class_status.add_theme_font_size_override("font_size", 18)
	class_status.add_theme_color_override("font_color", Color("bfc8c8"))
	identity.add_child(class_status)
	current_activity_label = Label.new()
	current_activity_label.text = String(profile.get("runtime_text", "Available in camp"))
	current_activity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	current_activity_label.add_theme_color_override("font_color", Color("8fb5c5"))
	identity.add_child(current_activity_label)
	_add_compact_fact(identity, "Recruitment", String(profile.get("recruitment_origin", "Unknown")))
	_add_compact_fact(identity, "Preferred activities", String(profile.get("preferred_activities", "None recorded")))
	_build_room_controls(identity, String(profile.get("room_assignment_id", "")))

	_add_profile_section("Biography", [String(profile.get("biography", "No biography is available."))])
	_add_profile_section("Personality", [String(profile.get("personality_description", "No description is available."))])
	_add_connection_section(profile.get("close_connections", []))
	_add_profile_section("Lasting memories", profile.get("lasting_memories", []), "No lasting memories yet.")
	_add_profile_section("Recent experiences", profile.get("recent_experiences", []), "No recent experiences have become personal memories.")
	_add_profile_section("Current personal themes", profile.get("personal_themes", []), "No strong personal theme is currently visible.")
	_add_profile_section("Recent social summaries", profile.get("social_summaries", []), "No completed conversations are recorded yet.")
	_add_profile_section("Combat-history highlights", profile.get("combat_highlights", []), "No combat history is recorded yet.")

	if OS.is_debug_build():
		debug_toggle = CheckButton.new()
		debug_toggle.text = "Developer details (raw state)"
		debug_toggle.toggled.connect(_on_debug_toggled)
		profile_column.add_child(debug_toggle)
		debug_text = TextEdit.new()
		debug_text.custom_minimum_size = Vector2(0, 250)
		debug_text.editable = false
		debug_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
		debug_text.visible = false
		profile_column.add_child(debug_text)

	rebuilding_profile = false


func _build_visual(profile: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 285)
	panel.add_theme_stylebox_override("panel", _panel_style("0d1419", "596a70"))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var visual: Dictionary = profile.get("visual", {})
	var path := String(visual.get("path", ""))
	var loaded: Resource = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	if loaded is Texture2D:
		var texture := TextureRect.new()
		texture.texture = loaded as Texture2D
		texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		margin.add_child(texture)
	else:
		var center := CenterContainer.new()
		margin.add_child(center)
		var initials := Label.new()
		initials.text = _initials(String(profile.get("display_name", "?")))
		initials.add_theme_font_size_override("font_size", 58)
		initials.add_theme_color_override("font_color", Color("9fb0b5"))
		center.add_child(initials)
	return panel


func _build_room_controls(parent: VBoxContainer, current_room_id: String) -> void:
	var heading := Label.new()
	heading.text = "Room assignment"
	heading.add_theme_color_override("font_color", Color("9ca4a5"))
	parent.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	var dropdown := OptionButton.new()
	dropdown.custom_minimum_size = Vector2(185, 38)
	var automatic_index := dropdown.item_count
	dropdown.add_item("Automatic valid room")
	dropdown.set_item_metadata(automatic_index, "auto")
	var selected_index := automatic_index
	for option in CampaignState.get_room_options(selected_raider_id):
		var index := dropdown.item_count
		var room_id := String(option.get("room_id", ""))
		var occupants: Array = option.get("occupant_ids", [])
		dropdown.add_item("%s · %d/%d" % [option.get("label", "Room"), occupants.size(), int(option.get("capacity", 2))])
		dropdown.set_item_metadata(index, room_id)
		dropdown.set_item_disabled(index, not bool(option.get("available", false)) and room_id != current_room_id)
		if room_id == current_room_id:
			selected_index = index
	dropdown.select(selected_index)
	dropdown.item_selected.connect(_on_room_selected.bind(dropdown))
	row.add_child(dropdown)
	room_status_label = Label.new()
	room_status_label.text = CampaignState.get_roommate_summary(selected_raider_id)
	room_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_status_label.add_theme_color_override("font_color", Color("a9b6b8"))
	row.add_child(room_status_label)


func _add_connection_section(value: Variant) -> void:
	var lines: Array[String] = []
	if value is Array:
		for connection_value in value:
			if not connection_value is Dictionary:
				continue
			var connection: Dictionary = connection_value
			var text := "%s — %s" % [connection.get("name", "Unknown"), connection.get("label", "Familiar but distant")]
			var context := String(connection.get("context", "")).strip_edges()
			if not context.is_empty():
				text += "\n  " + context
			lines.append(text)
	_add_profile_section("Close connections", lines, "No close connections have emerged yet.")


func _add_profile_section(title: String, value: Variant, empty_text: String = "") -> void:
	var lines: Array[String] = []
	if value is Array:
		for line in value:
			var text := String(line).strip_edges()
			if not text.is_empty():
				lines.append(text)
	elif not String(value).strip_edges().is_empty():
		lines.append(String(value).strip_edges())
	if lines.is_empty() and not empty_text.is_empty():
		lines.append(empty_text)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style("10181e", "39464b"))
	profile_column.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_right", 13)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 11)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("c9b37b"))
	column.add_child(heading)
	var body := Label.new()
	body.text = "\n".join(lines) if lines.size() == 1 else "• " + "\n• ".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color("c8c9c3"))
	column.add_child(body)


func _add_compact_fact(parent: VBoxContainer, label_text: String, value: String) -> void:
	var label := Label.new()
	label.text = "%s: %s" % [label_text, value]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("aeb7b6"))
	parent.add_child(label)


func _show_empty_profile(message: String) -> void:
	_clear_profile()
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color("78858a"))
	profile_column.add_child(label)


func _clear_profile() -> void:
	if profile_column == null:
		return
	for child in profile_column.get_children():
		profile_column.remove_child(child)
		child.queue_free()
	current_activity_label = null
	debug_toggle = null
	debug_text = null
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
		var item := row_by_id.get(raider_id) as TreeItem
		if item != null:
			item.set_text(3, ProfilePresenterScript.runtime_text(_runtime_for(raider_id)))
	if current_activity_label != null and not selected_raider_id.is_empty():
		current_activity_label.text = ProfilePresenterScript.runtime_text(_runtime_for(selected_raider_id))
	if debug_toggle != null and debug_toggle.button_pressed:
		_refresh_debug_text()


func _runtime_for(raider_id: String) -> Dictionary:
	var value: Variant = runtime_snapshots.get(raider_id, {})
	return Dictionary(value) if value is Dictionary else {}


func _on_runtime_refresh() -> void:
	if not is_visible_in_tree():
		return
	_refresh_runtime_snapshots()
	_refresh_runtime_only()


func _on_roster_item_selected() -> void:
	if rebuilding_roster:
		return
	var item := roster_tree.get_selected()
	if item == null:
		return
	_select_raider(String(item.get_metadata(0)))


func _on_filter_changed(_value: String) -> void:
	if filters_ready:
		_refresh_roster()


func _on_filter_selected(_index: int) -> void:
	if filters_ready:
		_refresh_roster()


func _on_recent_filter_toggled(_enabled: bool) -> void:
	if filters_ready:
		_refresh_roster()


func _on_sort_selected(_index: int) -> void:
	_refresh_roster()


func _on_room_selected(index: int, dropdown: OptionButton) -> void:
	if rebuilding_profile or selected_raider_id.is_empty():
		return
	var room_id := String(dropdown.get_item_metadata(index))
	var changed := (
		CampaignState.assign_raider_room_automatically(selected_raider_id)
		if room_id == "auto"
		else CampaignState.set_room_assignment(selected_raider_id, room_id)
	)
	if not changed and room_status_label != null:
		room_status_label.text = "That room is no longer available."


func _on_debug_toggled(enabled: bool) -> void:
	if debug_text == null:
		return
	debug_text.visible = enabled
	if enabled:
		_refresh_debug_text()


func _refresh_debug_text() -> void:
	if debug_text == null or selected_raider_id.is_empty():
		return
	debug_text.text = JSON.stringify(
		ProfilePresenterScript.build_debug_payload(
			selected_raider_id, _runtime_for(selected_raider_id)
		),
		"\t"
	)


func _make_filter_dropdown(minimum_size: Vector2) -> OptionButton:
	var dropdown := OptionButton.new()
	dropdown.custom_minimum_size = minimum_size
	return dropdown


func _add_option(dropdown: OptionButton, label: String, metadata: String) -> void:
	var index := dropdown.item_count
	dropdown.add_item(label)
	dropdown.set_item_metadata(index, metadata)


func _clear_options(dropdown: OptionButton) -> void:
	if dropdown != null:
		dropdown.clear()


func _selected_metadata(dropdown: OptionButton, fallback: String) -> String:
	if dropdown == null or dropdown.selected < 0 or dropdown.item_count <= 0:
		return fallback
	return String(dropdown.get_item_metadata(dropdown.selected))


func _select_metadata(dropdown: OptionButton, metadata: String) -> void:
	for index in range(dropdown.item_count):
		if String(dropdown.get_item_metadata(index)) == metadata:
			dropdown.select(index)
			return
	dropdown.select(0)


func _panel_style(background: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


func _initials(display_name: String) -> String:
	var result := ""
	for part in display_name.split(" ", false):
		if not part.is_empty():
			result += part.left(1).to_upper()
	return result.left(2) if not result.is_empty() else "?"
