extends Control
class_name FormationMap

signal member_dropped(member_id: String, region: String, range_name: String)

const DIRECTION_IDS := [
	"east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"
]
const DIRECTION_LABELS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const RANGE_IDS := ["close", "mid", "far"]
const RANGE_LABELS := ["C", "M", "F"]
const RANGE_COLORS := [Color("564236"), Color("354852"), Color("30413e")]

var active_members: Array[Dictionary] = []
var placements: Dictionary = {}
var hovered_slot_key: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(700, 610)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()


func configure(members: Array[Dictionary], formation: Dictionary) -> void:
	active_members.clear()

	for member in members:
		active_members.append(member.duplicate(true))

	var placement_value: Variant = formation.get("placements", {})
	placements = (
		Dictionary(placement_value).duplicate(true) if placement_value is Dictionary else {}
	)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var maximum_radius := _maximum_radius()
	var boss_radius := maximum_radius * 0.2
	var ring_width := (maximum_radius - boss_radius) / 3.0
	var fallback_font := ThemeDB.fallback_font

	for range_index in range(RANGE_IDS.size()):
		var inner_radius := boss_radius + ring_width * range_index
		var outer_radius := inner_radius + ring_width

		for direction_index in range(DIRECTION_IDS.size()):
			var center_angle := float(direction_index) * PI / 4.0
			var start_angle := center_angle - PI / 8.0
			var end_angle := center_angle + PI / 8.0
			var polygon := _sector_polygon(
				center, inner_radius, outer_radius, start_angle, end_angle
			)
			var slot_key := _slot_key(
				String(DIRECTION_IDS[direction_index]), String(RANGE_IDS[range_index])
			)
			var fill_color: Color = RANGE_COLORS[range_index]

			if slot_key == hovered_slot_key:
				fill_color = fill_color.lightened(0.28)

			draw_colored_polygon(polygon, fill_color)
			var outline := polygon.duplicate()
			outline.append(polygon[0])
			draw_polyline(outline, Color("8f8065"), 1.5, true)

			var label_radius := (inner_radius + outer_radius) * 0.5
			var label_center := center + Vector2.from_angle(center_angle) * label_radius
			var slot_label := (
				"%s · %s"
				% [String(DIRECTION_LABELS[direction_index]), String(RANGE_LABELS[range_index])]
			)
			var occupant_count := _occupant_labels_for_slot(slot_key).size()
			draw_string(
				fallback_font,
				label_center + Vector2(-38, -2),
				slot_label,
				HORIZONTAL_ALIGNMENT_CENTER,
				76,
				14,
				Color("e8dec4")
			)
			draw_string(
				fallback_font,
				label_center + Vector2(-38, 17),
				"empty" if occupant_count == 0 else "×%d" % occupant_count,
				HORIZONTAL_ALIGNMENT_CENTER,
				76,
				12,
				Color("aeb8af") if occupant_count == 0 else Color("e2bd6d")
			)

	draw_circle(center, boss_radius - 4.0, Color("321f22"))
	draw_arc(center, boss_radius - 4.0, 0.0, TAU, 48, Color("b36f65"), 3.0, true)
	draw_string(
		fallback_font,
		center + Vector2(-48, 6),
		"BOSS",
		HORIZONTAL_ALIGNMENT_CENTER,
		96,
		20,
		Color("e7aaa0")
	)


func _get_drag_data(_at_position: Vector2) -> Variant:
	return null


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var accepted := _is_member_drag(data)
	var slot := _slot_from_position(at_position) if accepted else {}
	var next_hover := String(slot.get("key", ""))

	if next_hover != hovered_slot_key:
		hovered_slot_key = next_hover
		queue_redraw()

	return accepted and not slot.is_empty()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var slot := _slot_from_position(at_position)

	if not _is_member_drag(data) or slot.is_empty():
		return

	hovered_slot_key = ""
	queue_redraw()
	member_dropped.emit(
		String(data.get("member_id", "")),
		String(slot.get("region", "")),
		String(slot.get("range", ""))
	)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return

	var motion := event as InputEventMouseMotion
	var slot := _slot_from_position(motion.position)

	if slot.is_empty():
		tooltip_text = "Drag an active member onto one of the 24 mini-regions."
		return

	var occupant_labels := _occupant_labels_for_slot(String(slot.get("key", "")))
	var occupants_text := "Empty" if occupant_labels.is_empty() else "\n".join(occupant_labels)
	tooltip_text = (
		"%s · %s\n%s"
		% [
			String(slot.get("region", "")).capitalize(),
			String(slot.get("range", "")).capitalize(),
			occupants_text
		]
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not hovered_slot_key.is_empty():
		hovered_slot_key = ""
		queue_redraw()


func _is_member_drag(data: Variant) -> bool:
	return (
		data is Dictionary
		and String(data.get("type", "")) == "formation_member"
		and not String(data.get("member_id", "")).is_empty()
	)


func _slot_from_position(local_position: Vector2) -> Dictionary:
	var center := size * 0.5
	var offset := local_position - center
	var distance := offset.length()
	var maximum_radius := _maximum_radius()
	var boss_radius := maximum_radius * 0.2

	if distance < boss_radius or distance > maximum_radius:
		return {}

	var ring_width := (maximum_radius - boss_radius) / 3.0
	var range_index := clampi(int(floor((distance - boss_radius) / ring_width)), 0, 2)
	var normalized_angle := fposmod(offset.angle() + PI / 8.0, TAU)
	var direction_index := int(floor(normalized_angle / (PI / 4.0))) % 8
	var region := String(DIRECTION_IDS[direction_index])
	var range_name := String(RANGE_IDS[range_index])
	return {"region": region, "range": range_name, "key": _slot_key(region, range_name)}


func _maximum_radius() -> float:
	return maxf(minf(size.x, size.y) * 0.47, 100.0)


func _sector_polygon(
	center: Vector2, inner_radius: float, outer_radius: float, start_angle: float, end_angle: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var arc_steps := 5

	for step in range(arc_steps + 1):
		var weight := float(step) / float(arc_steps)
		points.append(
			center + Vector2.from_angle(lerpf(start_angle, end_angle, weight)) * outer_radius
		)

	for step in range(arc_steps, -1, -1):
		var weight := float(step) / float(arc_steps)
		points.append(
			center + Vector2.from_angle(lerpf(start_angle, end_angle, weight)) * inner_radius
		)

	return points


func _slot_key(region: String, range_name: String) -> String:
	return region + ":" + range_name


func _occupant_labels_for_slot(slot_key: String) -> Array[String]:
	var labels: Array[String] = []

	for member in active_members:
		var member_id := String(member.get("member_id", ""))
		var placement_value: Variant = placements.get(member_id, {})

		if not placement_value is Dictionary:
			continue

		var placement: Dictionary = placement_value
		var member_slot_key := _slot_key(
			String(placement.get("region", "")), String(placement.get("range", ""))
		)

		if member_slot_key == slot_key:
			labels.append(CampaignState.format_member_label(member))

	return labels
