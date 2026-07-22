extends RefCounted
class_name CampActivityStation

const VALID_RESERVATION_LEVELS := [
	"free",
	"station_reserved",
	"socially_or_partially_reserved",
	"exclusively_reserved",
	"temporarily_unavailable",
]

var definition: Dictionary = {}
var reservations: Dictionary = {}
var unavailable: bool = false


static func create(source: Dictionary) -> CampActivityStation:
	var station := CampActivityStation.new()
	station.definition = _sanitize_definition(source)
	return station


func get_station_id() -> String:
	return String(definition.get("station_id", ""))


func get_facility_id() -> String:
	return String(definition.get("facility_id", ""))


func supports_activity(activity_id: String) -> bool:
	return definition.get("supported_activity_ids", []).has(activity_id)


func is_conversation_compatible(tone: String = "", category: String = "") -> bool:
	if not bool(definition.get("conversation_compatible", false)):
		return false

	var tones: Array = definition.get("allowed_conversation_tones", [])
	var categories: Array = definition.get("allowed_conversation_categories", [])
	return (tone.is_empty() or tones.is_empty() or tones.has(tone)) and (
		category.is_empty() or categories.is_empty() or categories.has(category)
	)


func get_free_capacity() -> int:
	if unavailable:
		return 0

	return maxi(int(definition.get("capacity", 1)) - reservations.size(), 0)


func can_reserve(participant_ids: Array[String]) -> bool:
	if unavailable or participant_ids.is_empty():
		return false

	var additional := 0

	for participant_id in participant_ids:
		if participant_id.is_empty():
			return false
		if not reservations.has(participant_id):
			additional += 1

	return additional <= get_free_capacity()


func reserve(
	participant_ids: Array[String], reservation_level: String = "station_reserved"
) -> Dictionary:
	if not can_reserve(participant_ids):
		return {"ok": false, "reason": "capacity_or_availability"}

	var level := (
		reservation_level
		if reservation_level in VALID_RESERVATION_LEVELS
		else "station_reserved"
	)
	var assignments: Dictionary = {}

	for participant_id in participant_ids:
		if reservations.has(participant_id):
			assignments[participant_id] = Dictionary(reservations[participant_id]).duplicate(true)
			continue

		var slot_index := _first_free_slot_index()
		var offsets: Array = definition.get("participant_offsets", [])
		var assignment := {
			"participant_id": participant_id,
			"slot_index": slot_index,
			"position_offset": _vector_from(offsets[slot_index] if slot_index < offsets.size() else []),
			"facing": _vector_from(definition.get("facing", [0.0, 1.0])),
			"reservation_level": level,
		}
		reservations[participant_id] = assignment
		assignments[participant_id] = assignment.duplicate(true)

	return {"ok": true, "assignments": assignments}


func set_reservation_level(participant_id: String, level: String) -> void:
	if not reservations.has(participant_id) or level not in VALID_RESERVATION_LEVELS:
		return

	var assignment: Dictionary = reservations[participant_id]
	assignment["reservation_level"] = level
	reservations[participant_id] = assignment


func release(participant_id: String) -> void:
	reservations.erase(participant_id)


func release_all() -> void:
	reservations.clear()


func set_temporarily_unavailable(value: bool) -> void:
	unavailable = value


func get_reservation_state() -> String:
	if unavailable:
		return "temporarily_unavailable"
	if reservations.is_empty():
		return "free"

	var levels: Array[String] = []

	for reservation_value in reservations.values():
		var level := String(Dictionary(reservation_value).get("reservation_level", "station_reserved"))
		if not levels.has(level):
			levels.append(level)

	return levels[0] if levels.size() == 1 else "socially_or_partially_reserved"


func get_debug_data() -> Dictionary:
	var result := definition.duplicate(true)
	result["reservation_state"] = get_reservation_state()
	result["reservations"] = reservations.duplicate(true)
	result["free_capacity"] = get_free_capacity()
	return result


func _first_free_slot_index() -> int:
	var occupied: Array[int] = []

	for value in reservations.values():
		occupied.append(int(Dictionary(value).get("slot_index", -1)))

	for index in range(int(definition.get("capacity", 1))):
		if not occupied.has(index):
			return index

	return maxi(occupied.size(), 0)


static func _sanitize_definition(source: Dictionary) -> Dictionary:
	var capacity := maxi(int(source.get("capacity", 1)), 1)
	var offsets: Array = source.get("participant_offsets", []) if source.get("participant_offsets", []) is Array else []

	while offsets.size() < capacity:
		offsets.append([float(offsets.size()) * 34.0, 0.0])

	return {
		"station_id": String(source.get("station_id", "")).strip_edges(),
		"facility_id": String(source.get("facility_id", "")).strip_edges(),
		"supported_activity_ids": _string_array(source.get("supported_activity_ids", [])),
		"participant_offsets": offsets.duplicate(true),
		"facing": source.get("facing", [0.0, 1.0]),
		"capacity": capacity,
		"participant_arrangement": String(source.get("participant_arrangement", "individual")),
		"animation_profile": String(source.get("animation_profile", "idle")),
		"prop_references": _string_array(source.get("prop_references", [])),
		"conversation_compatible": bool(source.get("conversation_compatible", false)),
		"allowed_conversation_tones": _string_array(source.get("allowed_conversation_tones", [])),
		"allowed_conversation_categories": _string_array(source.get("allowed_conversation_categories", [])),
		"station_tags": _string_array(source.get("station_tags", [])),
	}


static func _vector_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)

	return result
