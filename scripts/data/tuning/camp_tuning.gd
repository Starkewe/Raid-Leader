extends Resource
class_name CampTuning

const KNOWN_INTERACTIVE_FACILITIES: Array[String] = [
	"command_tent", "archive", "smith", "quarters", "formation_yard", "storage"
]

@export var notable_event_record_limit: int
@export var raid_chronicle_limit: int
@export var memory: CampMemoryTuning
@export var relationships: CampRelationshipTuning
@export var conversations: CampConversationTuning
@export var activities: CampActivityTuning
@export var movement: CampMovementTuning
@export var facility_interaction_radii_pixels: Dictionary = {}


func get_facility_interaction_radius(facility_id: String) -> float:
	return float(facility_interaction_radii_pixels.get(facility_id, 0.0))


func get_summary() -> Dictionary:
	return {
		"event_limits": {
			"notable_event_records": notable_event_record_limit,
			"raid_chronicle": raid_chronicle_limit,
		},
		"memory": _resource_values(memory),
		"relationships": _resource_values(relationships),
		"conversations": _resource_values(conversations),
		"activities": _resource_values(activities),
		"movement": _resource_values(movement),
		"facility_interaction_radii_pixels": facility_interaction_radii_pixels.duplicate(true),
	}


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if notable_event_record_limit <= 0:
		errors.append("notable_event_record_limit must be greater than zero.")
	if raid_chronicle_limit <= 0:
		errors.append("raid_chronicle_limit must be greater than zero.")
	_validate_child(errors, "memory", memory)
	_validate_child(errors, "relationships", relationships)
	_validate_child(errors, "conversations", conversations)
	_validate_child(errors, "activities", activities)
	_validate_child(errors, "movement", movement)
	for facility_id in KNOWN_INTERACTIVE_FACILITIES:
		if not facility_interaction_radii_pixels.has(facility_id):
			errors.append("facility_interaction_radii_pixels is missing '%s'." % facility_id)
		elif float(facility_interaction_radii_pixels[facility_id]) <= 0.0:
			errors.append("facility interaction radius for '%s' must be greater than zero." % facility_id)
	for facility_id_value in facility_interaction_radii_pixels:
		var facility_id := String(facility_id_value)
		if facility_id not in KNOWN_INTERACTIVE_FACILITIES:
			errors.append("facility_interaction_radii_pixels references unknown facility '%s'." % facility_id)
	return errors


func _validate_child(errors: PackedStringArray, field_name: String, child: Resource) -> void:
	if child == null:
		errors.append("%s tuning resource is missing." % field_name)
		return
	for child_error in child.call("get_validation_errors"):
		errors.append("%s.%s" % [field_name, child_error])


func _resource_values(source: Resource) -> Dictionary:
	var result: Dictionary = {}
	if source == null:
		return result
	for property in source.get_property_list():
		if not property is Dictionary:
			continue
		var property_data: Dictionary = property
		if int(property_data.get("usage", 0)) & PROPERTY_USAGE_STORAGE == 0:
			continue
		var property_name := String(property_data.get("name", ""))
		if property_name == "script":
			continue
		var value: Variant = source.get(property_name)
		result[property_name] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result
