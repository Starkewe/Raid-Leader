extends VBoxContainer
class_name FormationEditorPanel

const FormationMapScript := preload("res://scripts/ui/formation_map.gd")
const FormationMemberCardScript := preload("res://scripts/ui/formation_member_card.gd")

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
	var active_members := CampaignState.get_active_members()
	var editor_row := HBoxContainer.new()
	editor_row.add_theme_constant_override("separation", 18)
	editor_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(editor_row)

	var member_column := VBoxContainer.new()
	member_column.custom_minimum_size = Vector2(500, 560)
	member_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_row.add_child(member_column)

	var member_heading := Label.new()
	member_heading.text = (
		"Active roster · drag members onto the map"
		if not allow_reorder
		else "Active roster · drag onto the map or another row"
	)
	member_column.add_child(member_heading)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(490, 520)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	member_column.add_child(roster_scroll)

	var roster_cards := VBoxContainer.new()
	roster_cards.custom_minimum_size = Vector2(465, 0)
	roster_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_cards.add_theme_constant_override("separation", 4)
	roster_scroll.add_child(roster_cards)

	for member_index in range(active_members.size()):
		var member: Dictionary = active_members[member_index]
		var member_id := String(member.get("member_id", ""))
		var placement_value: Variant = placements.get(member_id, {})
		var placement: Dictionary = (
			Dictionary(placement_value) if placement_value is Dictionary else {}
		)
		var card := FormationMemberCardScript.new() as FormationMemberCard
		card.configure(
			member_id,
			(
				"%02d  %-22s  %s / %s"
				% [
					member_index + 1,
					CampaignState.format_member_label(member),
					_humanize(String(placement.get("region", "unassigned"))),
					_humanize(String(placement.get("range", "unassigned")))
				]
			)
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
