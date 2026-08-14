extends Resource
class_name CampActivityTuning

@export var accelerated_timing_multiplier: float
@export var ambient_bubble_cap: int
@export var routine_memory_reinforcement_chance: float
@export var shared_activity_chance: float
@export var roommate_shared_activity_bonus: float
@export var shared_favored_class_bonus: float
@export var shared_personality_preference_bonus: float
@export var profile_refresh_seconds: float
@export var initial_activity_delay_min_seconds: float
@export var initial_activity_delay_max_seconds: float
@export var visit_reaction_initial_delay_seconds: float
@export var visit_reaction_interval_min_seconds: float
@export var visit_reaction_interval_max_seconds: float
@export var visit_reaction_bubble_duration_seconds: float
@export var activity_feedback_chance: float
@export var activity_feedback_bubble_duration_seconds: float
@export var navigation_failure_cooldown_seconds: float
@export var repeated_activity_weight_multiplier: float
@export var favored_class_weight_multiplier: float
@export var favored_role_weight_multiplier: float
@export var favored_attribute_weight_multiplier: float
@export var personality_preference_weight_multiplier: float
@export var preferred_activity_weight_multiplier: float
@export var wipe_activity_weight_multiplier: float
@export var victory_social_weight_multiplier: float
@export var roster_change_activity_weight_multiplier: float
@export var distance_weight_numerator: float
@export var distance_weight_scale_pixels: float
@export var distance_weight_minimum: float
@export var distance_weight_maximum: float


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		["accelerated_timing_multiplier", accelerated_timing_multiplier],
		["profile_refresh_seconds", profile_refresh_seconds],
		["initial_activity_delay_max_seconds", initial_activity_delay_max_seconds],
		["visit_reaction_initial_delay_seconds", visit_reaction_initial_delay_seconds],
		["visit_reaction_interval_min_seconds", visit_reaction_interval_min_seconds],
		["visit_reaction_interval_max_seconds", visit_reaction_interval_max_seconds],
		["visit_reaction_bubble_duration_seconds", visit_reaction_bubble_duration_seconds],
		["activity_feedback_bubble_duration_seconds", activity_feedback_bubble_duration_seconds],
		["navigation_failure_cooldown_seconds", navigation_failure_cooldown_seconds],
		["repeated_activity_weight_multiplier", repeated_activity_weight_multiplier],
		["favored_class_weight_multiplier", favored_class_weight_multiplier],
		["favored_role_weight_multiplier", favored_role_weight_multiplier],
		["favored_attribute_weight_multiplier", favored_attribute_weight_multiplier],
		["personality_preference_weight_multiplier", personality_preference_weight_multiplier],
		["preferred_activity_weight_multiplier", preferred_activity_weight_multiplier],
		["wipe_activity_weight_multiplier", wipe_activity_weight_multiplier],
		["victory_social_weight_multiplier", victory_social_weight_multiplier],
		["roster_change_activity_weight_multiplier", roster_change_activity_weight_multiplier],
		["distance_weight_numerator", distance_weight_numerator],
		["distance_weight_scale_pixels", distance_weight_scale_pixels],
		["distance_weight_maximum", distance_weight_maximum],
		["shared_favored_class_bonus", shared_favored_class_bonus],
		["shared_personality_preference_bonus", shared_personality_preference_bonus],
	]:
		if float(field[1]) <= 0.0:
			errors.append("%s must be greater than zero." % String(field[0]))
	if initial_activity_delay_min_seconds < 0.0:
		errors.append("initial_activity_delay_min_seconds must not be negative.")
	if initial_activity_delay_min_seconds > initial_activity_delay_max_seconds:
		errors.append("initial activity delay minimum must not exceed its maximum.")
	if visit_reaction_interval_min_seconds > visit_reaction_interval_max_seconds:
		errors.append("visit reaction interval minimum must not exceed its maximum.")
	if distance_weight_minimum < 0.0 or distance_weight_minimum > distance_weight_maximum:
		errors.append("distance weight minimum must be nonnegative and not exceed its maximum.")
	if ambient_bubble_cap <= 0:
		errors.append("ambient_bubble_cap must be greater than zero.")
	for field in [
		["routine_memory_reinforcement_chance", routine_memory_reinforcement_chance],
		["shared_activity_chance", shared_activity_chance],
		["activity_feedback_chance", activity_feedback_chance],
	]:
		var value := float(field[1])
		if value < 0.0 or value > 1.0:
			errors.append("%s must be in [0, 1]." % String(field[0]))
	if roommate_shared_activity_bonus < 0.0:
		errors.append("roommate_shared_activity_bonus must not be negative.")
	return errors
