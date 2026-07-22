extends Button
class_name FormationMemberCard

signal member_reorder_requested(
	moving_member_id: String, target_member_id: String, place_after_target: bool
)

var member_id: String = ""
var drag_label: String = ""


func configure(
	new_member_id: String,
	class_text: String,
	name_text: String,
	miniregion_text: String,
	class_width: float,
	name_width: float,
	miniregion_width: float
) -> void:
	member_id = new_member_id
	drag_label = "%s · %s · %s" % [class_text, name_text, miniregion_text]
	text = ""
	custom_minimum_size = Vector2(510, 42)
	tooltip_text = (
		"%s\nDrag onto a mini-region to place this member. "
		+ "Drop onto another roster row to reorder the active raid."
	) % drag_label
	focus_mode = Control.FOCUS_NONE

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(_make_column(class_text, class_width, class_text))
	row.add_child(_make_column(name_text, name_width, name_text))
	row.add_child(_make_column(miniregion_text, miniregion_width, miniregion_text))


func _make_column(label_text: String, width: float, full_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = full_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _get_drag_data(_at_position: Vector2) -> Variant:
	if member_id.is_empty():
		return null

	var preview := Label.new()
	preview.text = drag_label
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", Color("f0e5c8"))
	preview.add_theme_constant_override("outline_size", 5)
	preview.add_theme_color_override("font_outline_color", Color("11171c"))
	set_drag_preview(preview)
	return {"type": "formation_member", "member_id": member_id}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false

	return (
		String(data.get("type", "")) == "formation_member"
		and String(data.get("member_id", "")) != member_id
	)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return

	member_reorder_requested.emit(
		String(data.get("member_id", "")), member_id, at_position.y >= size.y * 0.5
	)
