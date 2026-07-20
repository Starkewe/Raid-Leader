extends Button
class_name FormationMemberCard

signal member_reorder_requested(
	moving_member_id: String, target_member_id: String, place_after_target: bool
)

var member_id: String = ""


func configure(new_member_id: String, label_text: String) -> void:
	member_id = new_member_id
	text = label_text
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(0, 42)
	tooltip_text = (
		"Drag onto a mini-region to place this member. "
		+ "Drop onto another roster row to reorder the active raid."
	)
	focus_mode = Control.FOCUS_NONE


func _get_drag_data(_at_position: Vector2) -> Variant:
	if member_id.is_empty():
		return null

	var preview := Label.new()
	preview.text = text
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
