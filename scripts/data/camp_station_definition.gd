extends Resource
class_name CampStationDefinition

@export var station_id: String = ""
@export var facility_id: String = ""
@export var supported_activity_ids: Array[String] = []
@export var participant_offsets: Array[Vector2] = []
@export var facing: Vector2 = Vector2.DOWN
@export_range(1, 20, 1) var capacity: int = 1
@export var participant_arrangement: String = "individual"
@export var animation_profile: String = "idle"
@export var prop_references: Array[String] = []
@export var conversation_compatible: bool = false
@export var allowed_conversation_tones: Array[String] = []
@export var allowed_conversation_categories: Array[String] = []
@export var station_tags: Array[String] = []


func validate() -> Array[String]:
	var issues: Array[String] = []
	if station_id.strip_edges().is_empty():
		issues.append("Station ID is empty.")
	if facility_id.strip_edges().is_empty():
		issues.append("Facility ID is empty for " + station_id)
	if supported_activity_ids.is_empty():
		issues.append("No activities are supported by " + station_id)
	if capacity <= 0 or participant_offsets.size() < capacity:
		issues.append("Capacity/offsets are invalid for " + station_id)
	return issues


func to_dictionary() -> Dictionary:
	return {
		"station_id": station_id,
		"facility_id": facility_id,
		"supported_activity_ids": supported_activity_ids.duplicate(),
		"participant_offsets": participant_offsets.duplicate(),
		"facing": facing,
		"capacity": capacity,
		"participant_arrangement": participant_arrangement,
		"animation_profile": animation_profile,
		"prop_references": prop_references.duplicate(),
		"conversation_compatible": conversation_compatible,
		"allowed_conversation_tones": allowed_conversation_tones.duplicate(),
		"allowed_conversation_categories": allowed_conversation_categories.duplicate(),
		"station_tags": station_tags.duplicate(),
	}
