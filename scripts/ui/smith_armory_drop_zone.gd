extends PanelContainer
class_name SmithArmoryDropZone

signal equipment_action_completed(result: Dictionary)

var drop_hovered: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_apply_style(false)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var accepted := (
		data is Dictionary
		and String(data.get("type", "")) in [
			"smith_equipped_weapon", "smith_reserve_weapon"
		]
		and not String(data.get("source_raider_id", "")).is_empty()
	)
	if drop_hovered != accepted:
		drop_hovered = accepted
		_apply_style(accepted)
	return accepted


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	drop_hovered = false
	_apply_style(false)
	var result := CampaignState.unequip_weapon(
		String(data.get("source_raider_id", ""))
	)
	equipment_action_completed.emit(result)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and drop_hovered:
		drop_hovered = false
		_apply_style(false)


func _apply_style(active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c2b28") if active else Color("151d21")
	style.border_color = Color("8fc88b") if active else Color("77694f")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
