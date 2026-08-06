extends Control
class_name FormationMap

signal member_dropped(member_id: String, region: String, range_name: String)
signal mini_region_dropped(
	source_region: String,
	source_range: String,
	destination_region: String,
	destination_range: String
)

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


func _get_drag_data(at_position: Vector2) -> Variant:
	var slot := _slot_from_position(at_position)
	if slot.is_empty():
		return null

	var member_ids := _member_ids_for_slot(String(slot.get("key", "")))
	if member_ids.is_empty():
		return null

	var preview := Label.new()
	preview.text = _group_drag_preview_text(member_ids.size())
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", Color("f0e5c8"))
	preview.add_theme_constant_override("outline_size", 5)
	preview.add_theme_color_override("font_outline_color", Color("11171c"))
	set_drag_preview(preview)

	return _build_mini_region_drag_data(slot, member_ids)


func _build_mini_region_drag_data(
	slot: Dictionary, member_ids: Array[String]
) -> Dictionary:
	return {
		"type": "formation_mini_region",
		"source_region": String(slot.get("region", "")),
		"source_range": String(slot.get("range", "")),
		"member_ids": member_ids,
	}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var slot := _slot_from_position(at_position)
	var accepted := false

	if _is_member_drag(data):
		accepted = not slot.is_empty()
	elif _is_mini_region_drag(data):
		accepted = _is_valid_mini_region_drop(data, slot)

	var next_hover := String(slot.get("key", ""))
	if not accepted:
		next_hover = ""

	if next_hover != hovered_slot_key:
		hovered_slot_key = next_hover
		queue_redraw()

	return accepted and not slot.is_empty()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var slot := _slot_from_position(at_position)

	if not _can_drop_data(at_position, data):
		return

	hovered_slot_key = ""
	queue_redraw()

	if _is_mini_region_drag(data):
		mini_region_dropped.emit(
			String(data.get("source_region", "")),
			String(data.get("source_range", "")),
			String(slot.get("region", "")),
			String(slot.get("range", ""))
		)
		return

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
		tooltip_text = (
			"Drag an active member or an occupied mini-region onto one of the 24 mini-regions."
		)
		return

	var slot_key := String(slot.get("key", ""))
	var occupant_member_ids := _member_ids_for_slot(slot_key)
	var occupant_labels := _occupant_labels_for_slot(slot_key)
	var occupants_text := "Empty" if occupant_labels.is_empty() else "\n".join(occupant_labels)
	var drag_hint := "Drop a member here. Occupied destinations merge groups."

	if not occupant_member_ids.is_empty():
		drag_hint = (
			"Drag group of %d raider%s to move it. Occupied destinations merge groups; "
			+ "the source becomes empty."
		% [occupant_member_ids.size(), "" if occupant_member_ids.size() == 1 else "s"]
		)
	tooltip_text = (
		"%s · %s\n%s"
		% [
			String(slot.get("region", "")).capitalize(),
			String(slot.get("range", "")).capitalize(),
			occupants_text + "\n" + drag_hint
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


func _is_mini_region_drag(data: Variant) -> bool:
	return data is Dictionary and String(data.get("type", "")) == "formation_mini_region"


func _is_valid_mini_region_drop(data: Variant, destination_slot: Dictionary) -> bool:
	if not _is_mini_region_drag(data) or destination_slot.is_empty():
		return false

	var source_region := String(data.get("source_region", ""))
	var source_range := String(data.get("source_range", ""))
	var destination_region := String(destination_slot.get("region", ""))
	var destination_range := String(destination_slot.get("range", ""))

	if not _is_valid_slot_coordinates(source_region, source_range):
		return false

	if not _is_valid_slot_coordinates(destination_region, destination_range):
		return false

	if _slot_key(source_region, source_range) == _slot_key(destination_region, destination_range):
		return false

	var payload_member_ids := _member_ids_from_drag_data(data)
	var source_member_ids := _member_ids_for_slot(_slot_key(source_region, source_range))

	if payload_member_ids.is_empty() or source_member_ids.is_empty():
		return false

	if payload_member_ids.size() != source_member_ids.size():
		return false

	for member_id in payload_member_ids:
		if not source_member_ids.has(member_id):
			return false

	return true


func _is_valid_slot_coordinates(region: String, range_name: String) -> bool:
	return DIRECTION_IDS.has(region) and RANGE_IDS.has(range_name)


func _member_ids_from_drag_data(data: Variant) -> Array[String]:
	var member_ids: Array[String] = []
	if not data is Dictionary:
		return member_ids

	var member_ids_value: Variant = data.get("member_ids", [])
	if not member_ids_value is Array:
		return member_ids

	for member_id_value in member_ids_value:
		var member_id := String(member_id_value).strip_edges()
		if not member_id.is_empty() and not member_ids.has(member_id):
			member_ids.append(member_id)

	return member_ids


func _group_drag_preview_text(group_size: int) -> String:
	return (
		"Move group of %d raider%s\nOccupied destinations merge groups"
		% [group_size, "" if group_size == 1 else "s"]
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


func _member_ids_for_slot(slot_key: String) -> Array[String]:
	var member_ids: Array[String] = []

	for member in active_members:
		var member_id := String(member.get("member_id", ""))
		var placement_value: Variant = placements.get(member_id, {})

		if member_id.is_empty() or not placement_value is Dictionary:
			continue

		var placement: Dictionary = placement_value
		var member_slot_key := _slot_key(
			String(placement.get("region", "")), String(placement.get("range", ""))
		)

		if member_slot_key == slot_key and not member_ids.has(member_id):
			member_ids.append(member_id)

	return member_ids


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
