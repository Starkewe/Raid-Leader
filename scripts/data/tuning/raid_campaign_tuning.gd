extends Resource
class_name RaidCampaignTuning

@export var minimum_active_raid_size: int
@export var maximum_raid_size: int
@export var raid_group_size: int
@export var campaign_cast_size: int
@export var initial_roster_size: int
@export var attempt_history_limit: int
@export var quarters_room_count: int
@export var quarters_room_capacity: int
@export var initial_class_requirements: Dictionary = {}
@export var campaign_class_requirements: Dictionary = {}


func get_raid_group_count() -> int:
	return maximum_raid_size / raid_group_size if raid_group_size > 0 else 0


func get_reserve_roster_size() -> int:
	return campaign_cast_size - initial_roster_size


func get_quarters_capacity() -> int:
	return quarters_room_count * quarters_room_capacity


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_positive_int(errors, "minimum_active_raid_size", minimum_active_raid_size)
	_validate_positive_int(errors, "maximum_raid_size", maximum_raid_size)
	_validate_positive_int(errors, "raid_group_size", raid_group_size)
	_validate_positive_int(errors, "campaign_cast_size", campaign_cast_size)
	_validate_positive_int(errors, "initial_roster_size", initial_roster_size)
	_validate_positive_int(errors, "attempt_history_limit", attempt_history_limit)
	_validate_positive_int(errors, "quarters_room_count", quarters_room_count)
	_validate_positive_int(errors, "quarters_room_capacity", quarters_room_capacity)

	if minimum_active_raid_size > maximum_raid_size:
		errors.append("minimum_active_raid_size must not exceed maximum_raid_size.")
	if raid_group_size > 0 and maximum_raid_size % raid_group_size != 0:
		errors.append("maximum_raid_size must be evenly divisible by raid_group_size.")
	if initial_roster_size < maximum_raid_size:
		errors.append("initial_roster_size must hold a complete maximum-size raid.")
	if campaign_cast_size < initial_roster_size:
		errors.append("campaign_cast_size must not be smaller than initial_roster_size.")
	if get_quarters_capacity() < campaign_cast_size:
		errors.append("quarters capacity must hold the complete campaign cast.")

	_validate_class_requirements(
		errors, "initial_class_requirements", initial_class_requirements, initial_roster_size
	)
	_validate_class_requirements(
		errors,
		"campaign_class_requirements",
		campaign_class_requirements,
		campaign_cast_size
	)
	var initial_class_names: Array = initial_class_requirements.keys()
	var campaign_class_names: Array = campaign_class_requirements.keys()
	initial_class_names.sort()
	campaign_class_names.sort()
	if initial_class_names != campaign_class_names:
		errors.append("initial and campaign class requirements must name the same classes.")
	for class_name_value in initial_class_requirements:
		if int(initial_class_requirements[class_name_value]) > int(
			campaign_class_requirements.get(class_name_value, 0)
		):
			errors.append(
				"initial_class_requirements[%s] must not exceed its campaign requirement."
				% String(class_name_value)
			)

	return errors


func _validate_positive_int(errors: PackedStringArray, field_name: String, value: int) -> void:
	if value <= 0:
		errors.append("%s must be greater than zero." % field_name)


func _validate_class_requirements(
	errors: PackedStringArray, field_name: String, requirements: Dictionary, expected_total: int
) -> void:
	if requirements.is_empty():
		errors.append("%s must not be empty." % field_name)
		return
	var total := 0
	for class_name_value in requirements:
		var class_name_text := String(class_name_value).strip_edges()
		var count := int(requirements[class_name_value])
		if class_name_text.is_empty():
			errors.append("%s contains an empty class name." % field_name)
		if count <= 0:
			errors.append("%s[%s] must be greater than zero." % [field_name, class_name_text])
		total += count
	if total != expected_total:
		errors.append("%s must total %d; it totals %d." % [field_name, expected_total, total])
