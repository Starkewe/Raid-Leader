extends Button
class_name RosterMemberCard

signal member_reorder_requested(
	moving_member_id: String, target_member_id: String, place_after_target: bool
)
signal member_inspect_requested(member_id: String)
signal member_transfer_requested(member_id: String, source_zone: String, target_zone: String)

var member_id: String = ""
var zone_id: String = ""


func configure(new_member_id: String, new_zone_id: String, label_text: String) -> void:
	member_id = new_member_id
	zone_id = new_zone_id
	text = label_text
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(0, 42)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = (
		"Drag between Active and Reserves. Active members can also be dropped onto another "
		+ "active row to reorder the raid."
	)
	pressed.connect(_on_pressed)


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
	return {"type": "roster_member", "member_id": member_id, "source_zone": zone_id}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or String(data.get("type", "")) != "roster_member":
		return false

	var dragged_member_id := String(data.get("member_id", ""))
	var source_zone := String(data.get("source_zone", ""))

	if dragged_member_id.is_empty() or dragged_member_id == member_id:
		return false

	return source_zone != zone_id or zone_id == "active"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return

	var dragged_member_id := String(data.get("member_id", ""))
	var source_zone := String(data.get("source_zone", ""))

	if source_zone != zone_id:
		member_transfer_requested.emit(dragged_member_id, source_zone, zone_id)
		return

	member_reorder_requested.emit(dragged_member_id, member_id, at_position.y >= size.y * 0.5)


func _on_pressed() -> void:
	member_inspect_requested.emit(member_id)
