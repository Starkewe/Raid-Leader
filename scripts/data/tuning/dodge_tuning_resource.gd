extends Resource
class_name DodgeTuningResource

const REQUIRED_BASE_CLASSES: Array[String] = ["warrior", "priest", "rogue", "mage"]

@export var physical_dash_easing_strength: float
@export var rogue_second_dash_threshold_spacings: float
@export var profiles: Array[DodgeProfileTuning] = []


func get_profile(base_class: String) -> Dictionary:
	var normalized := base_class.to_lower().strip_edges()
	for profile in profiles:
		if profile != null and profile.base_class.to_lower().strip_edges() == normalized:
			return profile.to_dictionary()
	return {}


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if physical_dash_easing_strength <= 0.0:
		errors.append("physical_dash_easing_strength must be greater than zero.")
	if rogue_second_dash_threshold_spacings <= 0.0:
		errors.append("rogue_second_dash_threshold_spacings must be greater than zero.")
	var found: Dictionary = {}
	for index in range(profiles.size()):
		var profile := profiles[index]
		if profile == null:
			errors.append("profiles[%d] is missing." % index)
			continue
		var normalized := profile.base_class.to_lower().strip_edges()
		if normalized not in REQUIRED_BASE_CLASSES:
			errors.append("profiles[%d] references unknown dodge class '%s'." % [index, normalized])
		elif found.has(normalized):
			errors.append("profiles contains duplicate dodge class '%s'." % normalized)
		else:
			found[normalized] = true
		for profile_error in profile.get_validation_errors():
			errors.append("profiles[%d].%s" % [index, profile_error])
	for required_class in REQUIRED_BASE_CLASSES:
		if not found.has(required_class):
			errors.append("profiles is missing required dodge class '%s'." % required_class)
	return errors
