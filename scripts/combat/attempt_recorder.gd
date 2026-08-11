extends RefCounted
class_name AttemptRecorder

const AttemptSummaryBuilderScript := preload("res://scripts/combat/attempt_summary_builder.gd")

var encounter_id: String = ""
var events: Array[Dictionary] = []
var finalized: bool = false
var encounter_session = null


func setup(new_encounter_id: String, new_encounter_session = null) -> void:
	encounter_id = new_encounter_id
	encounter_session = new_encounter_session
	events.clear()
	finalized = false


func record_event(event: Dictionary) -> void:
	if finalized or event.is_empty():
		return

	var normalized: Dictionary = {}

	for key in event.keys():
		normalized[key] = _normalize_value(event[key])

	events.append(normalized)


func finalize(
	outcome: String, boss_health: int, boss_max_health: int, phase_id: String, phase_name: String
) -> Dictionary:
	if finalized:
		return {}

	finalized = true
	var summary := AttemptSummaryBuilderScript.build(
		encounter_id, outcome, events, boss_health, boss_max_health, phase_id, phase_name
	)
	if encounter_session != null:
		var metrics: Dictionary = encounter_session.build_attempt_metrics(events)
		if not metrics.is_empty():
			summary["encounter_metrics"] = metrics
	return summary


func _normalize_value(value: Variant) -> Variant:
	if value is Node:
		return _identity_for_node(value as Node)

	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}

		for key in value.keys():
			normalized_dictionary[String(key)] = _normalize_value(value[key])

		return normalized_dictionary

	if value is Array:
		var normalized_array: Array = []

		for item in value:
			normalized_array.append(_normalize_value(item))

		return normalized_array

	if value is Vector2:
		return {"x": value.x, "y": value.y}

	return value


func _identity_for_node(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}

	var identity := {"id": String(node.name), "name": String(node.name), "kind": "node"}

	if node.has_method("get_member_id"):
		var member_id := String(node.get_member_id())

		if not member_id.is_empty():
			identity["id"] = member_id
			identity["kind"] = "raid_member"

	if node.has_method("get_display_name"):
		identity["name"] = String(node.get_display_name())

	var unit_class_value: Variant = node.get("unit_class")

	if unit_class_value != null:
		identity["unit_class"] = String(unit_class_value)

	if node.is_in_group("boss") or node.name == "Boss":
		identity["id"] = "boss"
		identity["kind"] = "boss"

	return identity
