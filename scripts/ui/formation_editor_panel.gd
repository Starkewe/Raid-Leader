extends VBoxContainer
class_name FormationEditorPanel

const FormationMapScript := preload("res://scripts/ui/formation_map.gd")
const FormationMemberCardScript := preload("res://scripts/ui/formation_member_card.gd")

const CLASS_COLUMN_WIDTH := 125.0
const NAME_COLUMN_WIDTH := 175.0
const MINIREGION_COLUMN_WIDTH := 160.0

signal formation_changed

var note_text: String = ""
var allow_reorder: bool = true
var refresh_queued: bool = false


func configure(new_note_text: String = "", new_allow_reorder: bool = true) -> void:
	note_text = new_note_text
	allow_reorder = new_allow_reorder
	_rebuild()


func refresh() -> void:
	_queue_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	add_theme_constant_override("separation", 10)

	if not note_text.is_empty():
		var note := Label.new()
		note.text = note_text
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color("c5af78"))
		add_child(note)

	var formation := CampaignState.get_formation()
	var placements_value: Variant = formation.get("placements", {})
	var placements: Dictionary = (
		Dictionary(placements_value) if placements_value is Dictionary else {}
	)
	var active_members := CampaignState.get_active_members_for_roster()
	var editor_row := HBoxContainer.new()
	editor_row.add_theme_constant_override("separation", 18)
	editor_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(editor_row)

	var member_column := VBoxContainer.new()
	member_column.custom_minimum_size = Vector2(530, 560)
	member_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_row.add_child(member_column)

	var member_heading := Label.new()
	member_heading.text = (
		"Active roster · drag members onto the map"
		if not allow_reorder
		else "Active roster · drag onto the map or another row"
	)
	member_column.add_child(member_heading)
	member_column.add_child(_make_roster_header())

	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(520, 486)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	member_column.add_child(roster_scroll)

	var roster_cards := VBoxContainer.new()
	roster_cards.custom_minimum_size = Vector2(510, 0)
	roster_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_cards.add_theme_constant_override("separation", 4)
	roster_scroll.add_child(roster_cards)

	for member in active_members:
		var member_id := _string_or_default(member.get("member_id", ""), "")
		var placement_value: Variant = placements.get(member_id, {})
		var placement: Dictionary = (
			Dictionary(placement_value) if placement_value is Dictionary else {}
		)
		var miniregion := "%s · %s" % [
			_humanize(_string_or_default(placement.get("region", null), "unassigned")),
			_humanize(_string_or_default(placement.get("range", null), "unassigned")),
		]
		var card := FormationMemberCardScript.new() as FormationMemberCard
		card.configure(
			member_id,
			_string_or_default(member.get("unit_class", null), "Unknown"),
			_string_or_default(member.get("display_name", null), "Unknown"),
			miniregion,
			CLASS_COLUMN_WIDTH,
			NAME_COLUMN_WIDTH,
			MINIREGION_COLUMN_WIDTH
		)

		if allow_reorder:
			card.member_reorder_requested.connect(_on_member_reorder_requested)

		roster_cards.add_child(card)

	var map_column := VBoxContainer.new()
	map_column.custom_minimum_size = Vector2(720, 560)
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_row.add_child(map_column)

	var map_heading := Label.new()
	map_heading.text = "All 24 starting mini-regions · C close · M mid · F far"
	map_column.add_child(map_heading)

	var formation_map := FormationMapScript.new() as FormationMap
	formation_map.custom_minimum_size = Vector2(700, 520)
	formation_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	formation_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	formation_map.configure(active_members, formation)
	formation_map.member_dropped.connect(_on_member_dropped)
	map_column.add_child(formation_map)

	var validation := CampaignState.validate_raid_plan()
	var validation_label := Label.new()
	validation_label.text = _validation_text(validation)
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.add_theme_color_override(
		"font_color", Color("9fc18b") if bool(validation.get("valid", false)) else Color("d78d7d")
	)
	add_child(validation_label)


func _make_roster_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size = Vector2(510, 32)
	var inset := Control.new()
	inset.custom_minimum_size = Vector2(4, 0)
	header.add_child(inset)
	header.add_child(_make_header_label("Class", CLASS_COLUMN_WIDTH))
	header.add_child(_make_header_label("Name", NAME_COLUMN_WIDTH))
	header.add_child(_make_header_label("Miniregion", MINIREGION_COLUMN_WIDTH))
	return header


func _make_header_label(label_text: String, width: float) -> Label:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.add_theme_color_override("font_color", Color("d5c18a"))
	return label


func _on_member_dropped(member_id: String, region: String, range_name: String) -> void:
	if CampaignState.set_member_placement(member_id, region, range_name):
		formation_changed.emit()
		_queue_rebuild()


func _on_member_reorder_requested(
	moving_member_id: String, target_member_id: String, place_after_target: bool
) -> void:
	if CampaignState.reorder_active_member(moving_member_id, target_member_id, place_after_target):
		formation_changed.emit()
		_queue_rebuild()


func _queue_rebuild() -> void:
	if refresh_queued:
		return

	refresh_queued = true
	call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	refresh_queued = false
	_rebuild()


func _validation_text(validation: Dictionary) -> String:
	if bool(validation.get("valid", false)):
		var warnings: Array = validation.get("warnings", [])
		return "READY" if warnings.is_empty() else "READY · " + "  ".join(warnings)

	return "NOT READY · " + "  ".join(validation.get("errors", []))


func _humanize(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _string_or_default(value: Variant, default_value: String) -> String:
	if value == null:
		return default_value

	var converted := str(value).strip_edges()
	return default_value if converted.is_empty() else converted
