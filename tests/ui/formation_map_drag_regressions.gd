extends Node

const FormationMapScript := preload("res://scripts/ui/formation_map.gd")

var failures: Array[String] = []
var last_group_drop: Array[String] = []
var last_member_drop: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var formation_map := FormationMapScript.new() as FormationMap
	formation_map.size = Vector2(700, 520)
	add_child(formation_map)
	formation_map.mini_region_dropped.connect(_on_mini_region_dropped)
	formation_map.member_dropped.connect(_on_member_dropped)
	formation_map.configure(
		[
			{"member_id": "member_a", "display_name": "A", "unit_class": "Mage"},
			{"member_id": "member_b", "display_name": "B", "unit_class": "Rogue"},
			{"member_id": "member_c", "display_name": "C", "unit_class": "Priest"},
		],
		{
			"placements": {
				"member_a": {"region": "east", "range": "close"},
				"member_b": {"region": "east", "range": "close"},
				"member_c": {"region": "west", "range": "close"},
			}
		}
	)
	await get_tree().process_frame

	var source_position := _slot_position(formation_map, "east", "close")
	var occupied_target_position := _slot_position(formation_map, "west", "close")
	var empty_target_position := _slot_position(formation_map, "north", "far")
	var empty_source_position := _slot_position(formation_map, "south", "far")
	var source_member_ids: Array[String] = formation_map._member_ids_for_slot("east:close")
	var group_data: Variant = formation_map._build_mini_region_drag_data(
		{"region": "east", "range": "close", "key": "east:close"}, source_member_ids
	)

	_expect(
		source_member_ids.size() == 2,
		"An occupied mini-region did not expose its complete source group."
	)
	if group_data is Dictionary:
		_expect(
			String(group_data.get("type", "")) == "formation_mini_region",
			"The occupied mini-region drag payload used the wrong type."
		)
		_expect(
			String(group_data.get("source_region", "")) == "east"
			and String(group_data.get("source_range", "")) == "close",
			"The group drag payload omitted its source coordinates."
		)
		_expect(
			Array(group_data.get("member_ids", [])).size() == 2,
			"The group drag payload did not contain every source member."
		)
		_expect(
			formation_map._can_drop_data(occupied_target_position, group_data),
			"An occupied destination rejected a valid group drop."
		)
		_expect(
			not formation_map._can_drop_data(source_position, group_data),
			"A group drop onto its source mini-region was accepted."
		)

	var empty_source_data := {
		"type": "formation_mini_region",
		"source_region": "south",
		"source_range": "far",
		"member_ids": [],
	}
	_expect(
		formation_map._get_drag_data(empty_source_position) == null,
		"An empty mini-region created a group drag payload."
	)
	_expect(
		not formation_map._can_drop_data(empty_target_position, empty_source_data),
		"An empty source group payload was accepted."
	)
	_expect(
		not formation_map._can_drop_data(Vector2.ZERO, group_data),
		"A group drop onto an invalid target was accepted."
	)

	if group_data is Dictionary:
		formation_map._drop_data(empty_target_position, group_data)
	_expect(
		last_group_drop == ["east", "close", "north", "far"],
		"The group-drop signal did not preserve source and destination coordinates."
	)

	var member_data := {"type": "formation_member", "member_id": "member_a"}
	_expect(
		formation_map._can_drop_data(empty_target_position, member_data),
		"The existing individual member drop path no longer accepts valid targets."
	)
	formation_map._drop_data(empty_target_position, member_data)
	_expect(
		last_member_drop == ["member_a", "north", "far"],
		"The individual member-drop signal path no longer emits correctly."
	)

	formation_map.queue_free()
	await get_tree().process_frame
	_finish()


func _slot_position(formation_map: FormationMap, region: String, range_name: String) -> Vector2:
	var direction_index := formation_map.DIRECTION_IDS.find(region)
	var range_index := formation_map.RANGE_IDS.find(range_name)
	var center := formation_map.size * 0.5
	var maximum_radius := formation_map._maximum_radius()
	var boss_radius := maximum_radius * 0.2
	var ring_width := (maximum_radius - boss_radius) / 3.0
	var radius := boss_radius + ring_width * (float(range_index) + 0.5)
	return center + Vector2.from_angle(float(direction_index) * PI / 4.0) * radius


func _on_mini_region_dropped(
	source_region: String,
	source_range: String,
	destination_region: String,
	destination_range: String
) -> void:
	last_group_drop = [source_region, source_range, destination_region, destination_range]


func _on_member_dropped(member_id: String, region: String, range_name: String) -> void:
	last_member_drop = [member_id, region, range_name]


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
		return

	print("Formation map drag regressions passed.")
	get_tree().quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
