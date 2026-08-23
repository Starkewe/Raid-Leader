extends "res://scripts/ui/facility_page_presenter.gd"
class_name TrainingPagePresenter

const RaiderClassCatalogScript := preload("res://scripts/data/raider_class_catalog.gd")
const TrainingProgressionTreeScript := preload(
	"res://scripts/ui/training_progression_tree.gd"
)

const TAB_ACTIVE := "active"
const TAB_RESERVE := "reserve"
const TAB_IDS: Array[String] = [TAB_ACTIVE, TAB_RESERVE]

var current_tab_id: String = TAB_ACTIVE
var selected_raider_id: String = ""
var action_message: String = ""
var pending_action: Dictionary = {}
var preview_lineage_by_raider: Dictionary = {}
var benefits_panel_expanded: bool = false
var _journal: Node = null
var _confirmation_dialog: ConfirmationDialog = null


func present(journal: Node) -> void:
	_journal = journal
	var header := journal.get("header_title") as Label
	if header != null:
		header.text = "Training and Recreation"
	_ensure_confirmation_dialog()
	var page := journal.call("_begin_scrolling_page") as VBoxContainer
	if page == null:
		return
	page.name = "TrainingPage"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var model := build_view_model()
	_add_roster_and_detail(page, model)
	_add_action_message(page)
	_reset_training_scroll()


func build_view_model(tab_id: String = "") -> Dictionary:
	var requested_tab := current_tab_id if tab_id.is_empty() else tab_id.to_lower()
	if requested_tab not in TAB_IDS:
		requested_tab = TAB_ACTIVE
	var members := (
		CampaignState.get_active_members_for_roster()
		if requested_tab == TAB_ACTIVE
		else CampaignState.get_reserve_members_for_roster()
	)
	var member_ids: Array[String] = []
	for member in members:
		member_ids.append(String(member.get("member_id", "")))
	if requested_tab == current_tab_id and not member_ids.has(selected_raider_id):
		selected_raider_id = member_ids[0] if not member_ids.is_empty() else ""
	var preview_id := _ensure_preview_lineage(selected_raider_id)
	var specialization := (
		CampaignState.get_raider_specialization_status(selected_raider_id, preview_id)
		if not selected_raider_id.is_empty() else {}
	)
	var entries: Array[Dictionary] = []
	for member_value in members:
		entries.append(_build_member_entry(member_value))
	return {
		"tab_id": requested_tab,
		"active_count": CampaignState.get_active_members().size(),
		"reserve_count": CampaignState.get_reserve_members().size(),
		"members": entries,
		"selected_raider_id": selected_raider_id,
		"selected_member": CampaignState.get_member(selected_raider_id),
		"specialization": specialization,
		"preview_lineage_id": String(specialization.get("preview_lineage_id", "")),
		"action_message": action_message,
		"free_for_testing": true,
	}


func select_tab(tab_id: String) -> bool:
	var normalized := tab_id.to_lower()
	if normalized not in TAB_IDS:
		return false
	current_tab_id = normalized
	selected_raider_id = ""
	action_message = ""
	_reset_training_scroll()
	_queue_refresh()
	return true


func select_raider(raider_id: String) -> bool:
	var member := CampaignState.get_member(raider_id)
	if member.is_empty():
		return false
	var member_in_tab := (
		CampaignState.is_member_active(raider_id)
		if current_tab_id == TAB_ACTIVE
		else not CampaignState.is_member_active(raider_id)
	)
	if not member_in_tab:
		return false
	selected_raider_id = raider_id
	# A previously cycled preview is intentional state; otherwise start at the
	# raider's active lineage (or let the preview resolver choose one at random).
	var has_saved_preview := (
		preview_lineage_by_raider.has(raider_id)
		and not String(preview_lineage_by_raider.get(raider_id, "")).is_empty()
	)
	if not has_saved_preview:
		var current_status := CampaignState.get_raider_specialization_status(raider_id)
		var active_id := String(current_status.get("secondary_lineage_id", ""))
		if active_id.is_empty():
			preview_lineage_by_raider.erase(raider_id)
		else:
			preview_lineage_by_raider[raider_id] = active_id
	_ensure_preview_lineage(raider_id)
	action_message = ""
	_reset_training_scroll()
	_queue_refresh()
	return true


func cycle_lineage(direction: int) -> bool:
	if selected_raider_id.is_empty() or direction == 0:
		return false
	var status := CampaignState.get_raider_specialization_status(
		selected_raider_id, _ensure_preview_lineage(selected_raider_id)
	)
	var ids: Array[String] = []
	for lineage in status.get("eligible_lineages", []):
		ids.append(String(lineage.get("lineage_id", "")))
	if ids.is_empty():
		return false
	var current_id := String(status.get("preview_lineage_id", ids[0]))
	var index := ids.find(current_id)
	if index < 0:
		index = 0
	index = posmod(index + (1 if direction > 0 else -1), ids.size())
	preview_lineage_by_raider[selected_raider_id] = ids[index]
	action_message = ""
	_queue_refresh()
	return true


func request_lineage_lock(lineage_id: String = "") -> Dictionary:
	if selected_raider_id.is_empty():
		return _show_result(_result(false, "no_raider", "Select a raider first."))
	var selected_lineage_id := (
		_ensure_preview_lineage(selected_raider_id) if lineage_id.is_empty() else lineage_id
	)
	var check := CampaignState.check_lock_raider_lineage(
		selected_raider_id, selected_lineage_id
	)
	if not bool(check.get("ok", false)):
		return _show_result(check)
	pending_action = {
		"action": "lock_lineage",
		"raider_id": selected_raider_id,
		"lineage_id": String(check.get("lineage_id", selected_lineage_id)),
	}
	var member := CampaignState.get_member(selected_raider_id)
	var lineage: Dictionary = check.get("lineage", {})
	var lineage_name := String(lineage.get("display_name", selected_lineage_id.capitalize()))
	var prompt := ""
	var confirmation_text := "Begin Lineage"
	if bool(check.get("first_lock", false)):
		prompt = (
			"Use %s to begin %s for %s?\n\nThe token is consumed by this raider. The lineage's minor stat bonus, passive, and raid role become active immediately."
			% [
				String(check.get("token_name", "Class Token")),
				lineage_name,
				String(member.get("display_name", selected_raider_id)),
			]
		)
	else:
		confirmation_text = "Change Lineage"
		var previous: Dictionary = check.get("previous_lineage", {})
		var previous_name := String(
			previous.get("display_name", check.get("previous_lineage_id", "Previous lineage"))
		)
		var roles: Array = check.get("incoming_roles", [])
		prompt = (
			"Change %s from %s to %s?\n\nIncoming raid role: %s. The previous lineage's active benefits, title, and class kit will deactivate. Completed nodes remain saved and restore if the raider returns. All unfinished quest progress in the abandoned lineage will be lost."
			% [
				String(member.get("display_name", selected_raider_id)),
				previous_name,
				lineage_name,
				", ".join(roles).capitalize(),
			]
		)
	var weapon_return: Dictionary = check.get("weapon_return", {})
	if bool(weapon_return.get("required", false)):
		prompt += (
			"\n\n%s is incompatible with the incoming class identity. It will be returned to the Armory and the appropriate default weapon will be equipped."
			% String(weapon_return.get("weapon_name", "The equipped weapon"))
		)
	_show_confirmation(prompt, confirmation_text)
	return {
		"ok": true,
		"status": "confirmation_required",
		"message": "Lineage confirmation required.",
		"check": check,
	}


func confirm_pending_action() -> Dictionary:
	if pending_action.is_empty():
		return _show_result(_result(false, "no_pending_action", "Nothing is awaiting confirmation."))
	var action := String(pending_action.get("action", ""))
	var raider_id := String(pending_action.get("raider_id", ""))
	var lineage_id := String(pending_action.get("lineage_id", ""))
	pending_action = {}
	var result: Dictionary
	if action == "lock_lineage":
		result = CampaignState.lock_raider_lineage(raider_id, lineage_id)
	else:
		result = _result(false, "unknown_action", "That training action is unavailable.")
	return _show_result(result)


func cancel_pending_action() -> void:
	pending_action = {}
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		_confirmation_dialog.hide()


func _ensure_preview_lineage(raider_id: String) -> String:
	if raider_id.is_empty():
		return ""
	var has_saved := preview_lineage_by_raider.has(raider_id)
	var saved := String(preview_lineage_by_raider.get(raider_id, ""))
	var status := CampaignState.get_raider_specialization_status(raider_id, saved)
	if not bool(status.get("ok", false)):
		return ""
	var eligible_ids: Array[String] = []
	for lineage_value in status.get("eligible_lineages", []):
		var lineage: Dictionary = lineage_value
		var lineage_id := String(lineage.get("lineage_id", ""))
		if not lineage_id.is_empty():
			eligible_ids.append(lineage_id)
	if has_saved and eligible_ids.has(saved):
		return saved
	var preview_id := String(status.get("secondary_lineage_id", ""))
	if not preview_id.is_empty() and eligible_ids.has(preview_id):
		preview_lineage_by_raider[raider_id] = preview_id
		return preview_id
	if eligible_ids.is_empty():
		preview_lineage_by_raider.erase(raider_id)
		return ""
	preview_id = eligible_ids[randi_range(0, eligible_ids.size() - 1)]
	preview_lineage_by_raider[raider_id] = preview_id
	return preview_id


func _reset_training_scroll() -> void:
	if _journal == null or not is_instance_valid(_journal):
		return
	var training_page := _journal.find_child("TrainingPage", true, false)
	if training_page == null:
		return
	var current: Node = training_page
	while current != null:
		if current is ScrollContainer:
			(current as ScrollContainer).scroll_vertical = 0
			return
		current = current.get_parent()


func _build_member_entry(member: Dictionary) -> Dictionary:
	var member_id := String(member.get("member_id", ""))
	var class_id := String(member.get("advanced_class_id", ""))
	if class_id.is_empty():
		class_id = RaiderClassCatalogScript.normalize_class_id(
			String(member.get("unit_class", ""))
		)
	var class_definition := RaiderClassCatalogScript.get_definition(class_id)
	var visual := RaiderClassCatalogScript.resolve_visual(
		RaiderClassCatalogScript.normalize_class_id(String(member.get("unit_class", ""))),
		class_id
	)
	var class_color := Color("c9ced2")
	if visual != null:
		class_color = visual.main_color.lightened(0.28)
	return {
		"raider_id": member_id,
		"display_name": String(member.get("display_name", member_id)),
		"class_id": class_id,
		"class_name": String(class_definition.get("display_name", class_id.capitalize())),
		"class_color": class_color,
		"selected": member_id == selected_raider_id,
	}


func _add_roster_and_detail(parent: VBoxContainer, model: Dictionary) -> void:
	var layout := HSplitContainer.new()
	layout.name = "TrainingLayout"
	layout.custom_minimum_size = Vector2(0, 650)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(layout)
	_add_roster_section(layout, model)
	_add_detail_section(layout, model)


func _add_roster_section(parent: HSplitContainer, model: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "TrainingRosterSection"
	panel.custom_minimum_size = Vector2(245, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111a21")
	style.border_color = Color("416379")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var tabs := HBoxContainer.new()
	tabs.name = "TrainingRosterTabs"
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	for tab_id in TAB_IDS:
		var button := Button.new()
		button.name = "Training%sTab" % tab_id.capitalize()
		button.text = "%s (%d)" % [tab_id.capitalize(), int(model.get("%s_count" % tab_id, 0))]
		button.toggle_mode = true
		button.button_pressed = tab_id == current_tab_id
		button.disabled = tab_id == current_tab_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_tab.bind(tab_id))
		tabs.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var roster := VBoxContainer.new()
	roster.name = "TrainingRosterList"
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 6)
	scroll.add_child(roster)
	var entries: Array = model.get("members", [])
	if entries.is_empty():
		roster.add_child(_make_wrapped_label(
			"No recruited reserve raiders." if current_tab_id == TAB_RESERVE else "No active raiders.",
			Color("969c9d")
		))
		return
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var member_id := String(entry.get("raider_id", ""))
		var button := Button.new()
		button.name = "TrainingRaider_%s" % member_id
		button.text = ""
		button.disabled = bool(entry.get("selected", false))
		button.custom_minimum_size = Vector2(220, 62)
		var class_color: Color = entry.get("class_color", Color("c9ced2")) as Color
		var normal_style := _make_roster_button_style(
			Color("101820"), class_color.darkened(0.45), 1
		)
		var hover_style := _make_roster_button_style(
			Color("17232c"), class_color.lightened(0.04), 1
		)
		var selected_style := _make_roster_button_style(
			Color("18242c"), class_color, 2
		)
		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("disabled", selected_style)
		button.tooltip_text = "%s\nClass: %s" % [
			String(entry.get("display_name", member_id)),
			String(entry.get("class_name", "Unknown")),
		]
		button.pressed.connect(select_raider.bind(member_id))
		roster.add_child(button)
		if bool(entry.get("selected", false)):
			var glow := button.create_tween().set_loops()
			glow.tween_property(
				selected_style, "border_color", _with_alpha(class_color, 0.36), 1.15
			)
			glow.tween_property(
				selected_style, "border_color", _with_alpha(class_color, 0.95), 1.15
			)
		var button_margin := MarginContainer.new()
		button_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button_margin.add_theme_constant_override("margin_left", 12)
		button_margin.add_theme_constant_override("margin_right", 8)
		button_margin.add_theme_constant_override("margin_top", 7)
		button_margin.add_theme_constant_override("margin_bottom", 7)
		button_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(button_margin)
		var button_text := VBoxContainer.new()
		button_text.alignment = BoxContainer.ALIGNMENT_CENTER
		button_text.add_theme_constant_override("separation", 1)
		button_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button_margin.add_child(button_text)
		var raider_name := Label.new()
		raider_name.name = "TrainingRaiderName_%s" % member_id
		raider_name.text = String(entry.get("display_name", member_id))
		raider_name.add_theme_font_size_override("font_size", 14)
		raider_name.add_theme_color_override("font_color", Color("ebe8df"))
		raider_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button_text.add_child(raider_name)
		var class_label := Label.new()
		class_label.name = "TrainingRaiderClass_%s" % member_id
		class_label.text = String(entry.get("class_name", "Unknown"))
		class_label.add_theme_font_size_override("font_size", 11)
		class_label.add_theme_color_override(
			"font_color", class_color
		)
		class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button_text.add_child(class_label)


func _make_roster_button_style(
	background: Color, border: Color, border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _with_alpha(color: Color, alpha: float) -> Color:
	var result := color
	result.a = alpha
	return result


func _add_detail_section(parent: HSplitContainer, model: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "TrainingTalentPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	var detail := Control.new()
	detail.name = "TrainingRaiderDetail"
	detail.custom_minimum_size = Vector2(0, 650)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(detail)
	var member: Dictionary = model.get("selected_member", {})
	if member.is_empty():
		detail.add_child(_make_wrapped_label("Select a raider to review their paths.", Color("a7ada9")))
		return
	var status: Dictionary = model.get("specialization", {})
	_add_identity_header(detail, member, status)
	var tree := TrainingProgressionTreeScript.new() as TrainingProgressionTree
	tree.name = "TrainingProgressionTree"
	tree.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tree.offset_top = 86
	tree.offset_bottom = 586
	tree.custom_minimum_size = Vector2(0, 500)
	tree.lineage_cycle_requested.connect(cycle_lineage)
	tree.lineage_lock_requested.connect(request_lineage_lock)
	detail.add_child(tree)
	tree.configure(String(status.get("base_class_id", member.get("unit_class", ""))), status)
	_add_bonuses_panel(detail, member, status)


func _add_identity_header(parent: Control, member: Dictionary, status: Dictionary) -> void:
	var base_class_id := RaiderClassCatalogScript.normalize_class_id(
		String(member.get("unit_class", ""))
	)
	var candidate_id := String(status.get("candidate_advanced_class_id", ""))
	if candidate_id.is_empty():
		candidate_id = String(status.get("advanced_class_id", ""))
	var class_definition := RaiderClassCatalogScript.get_definition(candidate_id)
	if class_definition.is_empty():
		class_definition = RaiderClassCatalogScript.get_definition(base_class_id)
	var visual := RaiderClassCatalogScript.resolve_visual(base_class_id, candidate_id)
	var class_color := Color("c9ced2")
	var accent_color := Color("79c6b6")
	if visual != null:
		class_color = visual.main_color.lightened(0.42)
		accent_color = visual.accent_color if visual.accent_color.a > 0.0 else class_color
	var lineage: Dictionary = status.get("preview_lineage", {})
	var roles: Array = lineage.get("raid_roles", [])
	var header := Control.new()
	header.name = "TrainingIdentityHeader"
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 78
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(header)
	var raider_column := VBoxContainer.new()
	raider_column.name = "TrainingRaiderIdentity"
	raider_column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	raider_column.offset_left = 8
	raider_column.offset_top = 2
	raider_column.offset_right = 238
	raider_column.offset_bottom = 62
	raider_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	raider_column.add_theme_constant_override("separation", 0)
	header.add_child(raider_column)
	var raider_name := Label.new()
	raider_name.name = "TrainingSelectedRaider"
	raider_name.text = String(member.get("display_name", "Unnamed"))
	raider_name.add_theme_font_size_override("font_size", 19)
	raider_name.add_theme_color_override("font_color", Color("e8dfc7"))
	raider_column.add_child(raider_name)
	var primary_class := Label.new()
	primary_class.name = "TrainingRaiderPrimaryClass"
	primary_class.text = String(member.get("unit_class", "Unknown"))
	primary_class.add_theme_font_size_override("font_size", 12)
	primary_class.add_theme_color_override("font_color", Color("9aa8b0"))
	raider_column.add_child(primary_class)
	var icon_frame := PanelContainer.new()
	icon_frame.name = "TrainingClassIconFrame"
	icon_frame.set_anchors_preset(Control.PRESET_CENTER)
	icon_frame.offset_left = -39
	icon_frame.offset_top = -31
	icon_frame.offset_right = 39
	icon_frame.offset_bottom = 47
	icon_frame.custom_minimum_size = Vector2(78, 78)
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color("080d11")
	icon_style.border_color = accent_color
	icon_style.set_border_width_all(2)
	icon_style.set_corner_radius_all(3)
	icon_frame.add_theme_stylebox_override("panel", icon_style)
	header.add_child(icon_frame)
	var icon_margin := MarginContainer.new()
	icon_margin.add_theme_constant_override("margin_left", 4)
	icon_margin.add_theme_constant_override("margin_right", 4)
	icon_margin.add_theme_constant_override("margin_top", 4)
	icon_margin.add_theme_constant_override("margin_bottom", 4)
	icon_frame.add_child(icon_margin)
	var icon := TextureRect.new()
	icon.name = "TrainingClassIcon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if visual != null:
		icon.texture = visual.icon_resource
	icon_margin.add_child(icon)
	var class_column := VBoxContainer.new()
	class_column.name = "TrainingClassIdentity"
	class_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	class_column.offset_left = -238
	class_column.offset_top = 2
	class_column.offset_right = -8
	class_column.offset_bottom = 62
	class_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	class_column.add_theme_constant_override("separation", 0)
	header.add_child(class_column)
	var class_label := Label.new()
	class_label.name = "TrainingSelectedClass"
	class_label.text = String(class_definition.get("display_name", candidate_id.capitalize()))
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	class_label.add_theme_font_size_override("font_size", 19)
	class_label.add_theme_color_override("font_color", class_color)
	class_column.add_child(class_label)
	var role := Label.new()
	role.name = "TrainingRoleLabel"
	role.text = "Role: %s" % _role_label(roles)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	role.add_theme_font_size_override("font_size", 12)
	role.add_theme_color_override("font_color", Color("9aa8b0"))
	class_column.add_child(role)


func _role_label(roles: Array) -> String:
	if roles.is_empty():
		return "Unassigned"
	var labels: Array[String] = []
	for role_value in roles:
		labels.append(String(role_value).capitalize())
	return ", ".join(labels)


func _add_bonuses_panel(
	parent: Control, member: Dictionary, status: Dictionary
) -> void:
	var lineage: Dictionary = status.get("preview_lineage", {})
	var base_class_id := RaiderClassCatalogScript.normalize_class_id(
		String(member.get("unit_class", ""))
	)
	var preview_class_id := String(status.get("candidate_advanced_class_id", ""))
	var preview_visual := RaiderClassCatalogScript.resolve_visual(base_class_id, preview_class_id)
	var accent := Color("79c6b6")
	if preview_visual != null:
		accent = preview_visual.main_color.lightened(0.22)
	# Keep the shell and action control anchored to the bottom of the detail view.
	# The content panel animates above the button, so the button never moves or
	# flickers during open/close transitions.
	var panel := Control.new()
	panel.name = "TrainingBonusesPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -44
	panel.offset_bottom = 0
	panel.offset_left = 0
	panel.offset_right = 0
	panel.custom_minimum_size = Vector2(0, 44)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var initially_expanded := benefits_panel_expanded
	panel.set_meta("expanded", initially_expanded)
	parent.add_child(panel)

	var content_panel := PanelContainer.new()
	content_panel.name = "TrainingBenefitsContentPanel"
	content_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	content_panel.offset_top = -315.0 if initially_expanded else -44.0
	content_panel.offset_bottom = -44
	content_panel.offset_left = 0
	content_panel.offset_right = 0
	content_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("0b1116F2")
	panel_style.border_color = accent
	panel_style.set_border_width_all(2)
	panel_style.border_width_bottom = 0
	panel_style.set_corner_radius_all(4)
	panel_style.corner_radius_bottom_left = 0
	panel_style.corner_radius_bottom_right = 0
	content_panel.add_theme_stylebox_override("panel", panel_style)
	panel.add_child(content_panel)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_right", 10)
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_panel.add_child(content_margin)
	var passive: Dictionary = lineage.get("passive_effect", {})
	var scroll := ScrollContainer.new()
	scroll.name = "TrainingBonusesScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = initially_expanded
	content_margin.add_child(scroll)
	var benefits := VBoxContainer.new()
	benefits.name = "TrainingBenefitsContent"
	benefits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	benefits.add_theme_constant_override("separation", 5)
	scroll.add_child(benefits)
	var active_heading := Label.new()
	active_heading.name = "TrainingActiveBenefitsHeading"
	active_heading.text = "Active"
	active_heading.add_theme_color_override("font_color", accent)
	benefits.add_child(active_heading)
	benefits.add_child(_make_wrapped_label(
		"• %s" % String(passive.get("summary", "Minor active effect remains intentionally open.")),
		Color("d9dedc")
	))
	var passive_heading := Label.new()
	passive_heading.name = "TrainingPassiveBenefitsHeading"
	passive_heading.text = "Passive"
	passive_heading.add_theme_color_override("font_color", accent)
	benefits.add_child(passive_heading)
	benefits.add_child(_make_wrapped_label(
		"• %s" % String(lineage.get("stat_bonus_summary", "Stat bonus remains open.")),
		Color("d9dedc")
	))
	var completed_rewards: Array[String] = []
	for node_value in status.get("node_statuses", []):
		var node: Dictionary = node_value
		if String(node.get("status", "")) == "completed":
			completed_rewards.append(String(node.get("reward_summary", "Milestone completed.")))
	if not completed_rewards.is_empty():
		for reward in completed_rewards:
			benefits.add_child(_make_wrapped_label("• %s" % reward, Color("c8cfcb")))
	var actions := HBoxContainer.new()
	actions.name = "TrainingBenefitsActions"
	actions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	actions.offset_top = -44
	actions.offset_bottom = 0
	actions.offset_left = 0
	actions.offset_right = 0
	actions.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(actions)
	var benefits_button := Button.new()
	benefits_button.name = "TrainingCurrentBenefitsButton"
	benefits_button.text = "Current Benefits"
	benefits_button.toggle_mode = true
	benefits_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	benefits_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	benefits_button.button_pressed = initially_expanded
	benefits_button.tooltip_text = "Review this lineage's active and passive benefits."
	_style_benefits_button(benefits_button, accent, initially_expanded)
	actions.add_child(benefits_button)
	benefits_button.pressed.connect(
		_toggle_benefits_panel.bind(panel, content_panel, scroll, benefits_button, accent)
	)


func _style_benefits_button(button: Button, accent: Color, expanded: bool) -> void:
	var normal := _make_benefits_button_style(Color("0b1116"), accent, expanded)
	var hover := _make_benefits_button_style(
		accent.darkened(0.72), accent.lightened(0.16), expanded
	)
	var pressed := _make_benefits_button_style(
		accent.darkened(0.58), accent.lightened(0.24), expanded
	)
	var disabled := _make_benefits_button_style(
		Color("0b1116"), accent.darkened(0.36), expanded
	)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("e5ebe8"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("ffffff"))
	button.add_theme_color_override("font_disabled_color", Color("8e9998"))


func _make_benefits_button_style(
	background: Color, border: Color, _expanded: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background, 0.97)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _toggle_benefits_panel(
	panel: Control,
	content_panel: PanelContainer,
	scroll: ScrollContainer,
	benefits_button: Button,
	accent: Color
) -> void:
	var expanded := not bool(panel.get_meta("expanded", false))
	benefits_button.button_pressed = expanded
	panel.set_meta("expanded", expanded)
	benefits_panel_expanded = expanded
	_style_benefits_button(benefits_button, accent, expanded)
	if expanded:
		scroll.visible = true
	var target_top := -315.0 if expanded else -44.0
	var previous_tween: Tween = null
	if panel.has_meta("benefits_tween"):
		previous_tween = panel.get_meta("benefits_tween") as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	var tween := panel.create_tween()
	panel.set_meta("benefits_tween", tween)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(content_panel, "offset_top", target_top, 0.24)
	if not expanded:
		tween.finished.connect(func() -> void:
			if is_instance_valid(scroll) and not bool(panel.get_meta("expanded", false)):
				scroll.visible = false
		)


func _add_action_message(parent: VBoxContainer) -> void:
	if action_message.is_empty():
		return
	var message := _make_wrapped_label(action_message, Color("d5b77b"))
	message.name = "TrainingActionMessage"
	parent.add_child(message)


func _make_wrapped_label(text_value: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label


func _ensure_confirmation_dialog() -> void:
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		return
	_confirmation_dialog = ConfirmationDialog.new()
	_confirmation_dialog.name = "TrainingConfirmationDialog"
	_confirmation_dialog.title = "Confirm Training Decision"
	_confirmation_dialog.confirmed.connect(_on_confirmation_confirmed)
	_confirmation_dialog.canceled.connect(cancel_pending_action)
	_journal.add_child(_confirmation_dialog)


func _show_confirmation(prompt: String, confirmation_text: String) -> void:
	_ensure_confirmation_dialog()
	_confirmation_dialog.dialog_text = prompt
	_confirmation_dialog.ok_button_text = confirmation_text
	if _journal.has_method("popup_in_right_half"):
		_journal.call("popup_in_right_half", _confirmation_dialog)
	else:
		_confirmation_dialog.popup_centered()


func _on_confirmation_confirmed() -> void:
	confirm_pending_action()


func _show_result(result: Dictionary) -> Dictionary:
	action_message = String(result.get("message", ""))
	_queue_refresh()
	return result.duplicate(true)


func _queue_refresh() -> void:
	if _journal != null and is_instance_valid(_journal) and _journal.has_method("_queue_refresh"):
		_journal.call("_queue_refresh")


func _result(ok: bool, status: String, message: String) -> Dictionary:
	return {"ok": ok, "status": status, "message": message}
