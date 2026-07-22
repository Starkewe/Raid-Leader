extends Button
class_name RosterMemberCard

signal member_reorder_requested(
	moving_member_id: String, target_member_id: String, place_after_target: bool
)
signal member_inspect_requested(member_id: String)
signal member_transfer_requested(member_id: String, source_zone: String, target_zone: String)

var member_id: String = ""
var zone_id: String = ""
var drag_label: String = ""


func configure(
	new_member_id: String,
	new_zone_id: String,
	class_text: String,
	name_text: String,
	class_width: float,
	name_width: float
) -> void:
	member_id = new_member_id
	zone_id = new_zone_id
	drag_label = "%s · %s" % [class_text, name_text]
	text = ""
	custom_minimum_size = Vector2(0, 42)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = (
		"%s · %s\nDrag between Active and Reserves. "
		+ "Active members can also be dropped onto another "
		+ "active row to reorder the raid."
	) % [class_text, name_text]

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(_make_column(class_text, class_width))
	row.add_child(_make_column(name_text, name_width))
	pressed.connect(_on_pressed)


func _make_column(label_text: String, width: float) -> Label:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = label_text
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
