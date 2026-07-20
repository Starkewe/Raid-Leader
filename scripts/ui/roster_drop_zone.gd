extends VBoxContainer
class_name RosterDropZone

signal member_dropped(member_id: String, source_zone: String, target_zone: String)

var zone_id: String = ""
var hover_active: bool = false


func configure(new_zone_id: String) -> void:
	zone_id = new_zone_id
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var accepted := (
		data is Dictionary
		and String(data.get("type", "")) == "roster_member"
		and String(data.get("source_zone", "")) != zone_id
	)

	if hover_active != accepted:
		hover_active = accepted
		modulate = Color("d9c88f") if accepted else Color.WHITE

	return accepted


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	hover_active = false
	modulate = Color.WHITE

	if not data is Dictionary:
		return

	member_dropped.emit(
		String(data.get("member_id", "")), String(data.get("source_zone", "")), zone_id
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		hover_active = false
		modulate = Color.WHITE
