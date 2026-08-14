extends Resource
class_name CampConversationTuning

@export var summary_limit: int
@export var pressure_source_limit: int
@export var initial_pressure: float
@export var first_conversation_delay_seconds: float
@export var minimum_cooldown_seconds: float
@export var baseline_cooldown_seconds: float
@export var maximum_cooldown_seconds: float
@export var pressure_decay_per_second: float
@export var concurrent_conversation_pressure_decay_per_second: float
@export var focused_completion_pressure_reduction: float
@export var embedded_completion_pressure_reduction: float
@export var schedule_miss_pressure_reduction: float
@export var schedule_miss_retry_seconds: float
@export var schedule_miss_debounce_seconds: float
@export var bubble_duration_seconds: float
@export var minimum_bubble_duration_seconds: float
@export var pause_between_bubbles_seconds: float
@export var default_frame_cooldown_seconds: float
@export var participant_conversation_radius_pixels: float
@export var participant_conversation_spacing_pixels: float
@export var lore_schedule_chance: float
@export var debug_history_limit: int
@export var population_for_second_conversation: int
@export var maximum_conversations_small_camp: int
@export var maximum_conversations_large_camp: int
@export var recent_summary_limit: int
@export var recent_frame_window: int
@export var recent_pair_window: int
@export var recent_context_window: int
@export var recent_frame_repetition_multiplier: float
@export var recent_pair_repetition_multiplier: float
@export var recent_context_repetition_multiplier: float
@export var minimum_repetition_multiplier: float
@export var roommate_selection_multiplier: float
@export var authored_connection_selection_multiplier: float
@export var pressure_by_event: Dictionary = {}
@export var pressure_by_visit: Dictionary = {}


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		["summary_limit", summary_limit],
		["pressure_source_limit", pressure_source_limit],
		["debug_history_limit", debug_history_limit],
		["population_for_second_conversation", population_for_second_conversation],
		["maximum_conversations_small_camp", maximum_conversations_small_camp],
		["maximum_conversations_large_camp", maximum_conversations_large_camp],
		["recent_summary_limit", recent_summary_limit],
		["recent_frame_window", recent_frame_window],
		["recent_pair_window", recent_pair_window],
		["recent_context_window", recent_context_window],
	]:
		if int(field[1]) <= 0:
			errors.append("%s must be greater than zero." % String(field[0]))
	for field in [
		["first_conversation_delay_seconds", first_conversation_delay_seconds],
		["minimum_cooldown_seconds", minimum_cooldown_seconds],
		["baseline_cooldown_seconds", baseline_cooldown_seconds],
		["maximum_cooldown_seconds", maximum_cooldown_seconds],
		["pressure_decay_per_second", pressure_decay_per_second],
		[
			"concurrent_conversation_pressure_decay_per_second",
			concurrent_conversation_pressure_decay_per_second,
		],
		["focused_completion_pressure_reduction", focused_completion_pressure_reduction],
		["embedded_completion_pressure_reduction", embedded_completion_pressure_reduction],
		["schedule_miss_pressure_reduction", schedule_miss_pressure_reduction],
		["schedule_miss_retry_seconds", schedule_miss_retry_seconds],
		["schedule_miss_debounce_seconds", schedule_miss_debounce_seconds],
		["bubble_duration_seconds", bubble_duration_seconds],
		["minimum_bubble_duration_seconds", minimum_bubble_duration_seconds],
		["pause_between_bubbles_seconds", pause_between_bubbles_seconds],
		["default_frame_cooldown_seconds", default_frame_cooldown_seconds],
		["participant_conversation_radius_pixels", participant_conversation_radius_pixels],
		["participant_conversation_spacing_pixels", participant_conversation_spacing_pixels],
		["roommate_selection_multiplier", roommate_selection_multiplier],
		["authored_connection_selection_multiplier", authored_connection_selection_multiplier],
	]:
		if float(field[1]) <= 0.0:
			errors.append("%s must be greater than zero." % String(field[0]))
	if initial_pressure < 0.0 or initial_pressure > 100.0:
		errors.append("initial_pressure must be in [0, 100].")
	if not minimum_cooldown_seconds <= baseline_cooldown_seconds or not (
		baseline_cooldown_seconds <= maximum_cooldown_seconds
	):
		errors.append("conversation cooldowns must satisfy minimum <= baseline <= maximum.")
	if maximum_conversations_large_camp < maximum_conversations_small_camp:
		errors.append("large-camp conversation capacity must not be smaller than small-camp capacity.")
	for field in [
		["lore_schedule_chance", lore_schedule_chance],
		["recent_frame_repetition_multiplier", recent_frame_repetition_multiplier],
		["recent_pair_repetition_multiplier", recent_pair_repetition_multiplier],
		["recent_context_repetition_multiplier", recent_context_repetition_multiplier],
		["minimum_repetition_multiplier", minimum_repetition_multiplier],
	]:
		var value := float(field[1])
		if value < 0.0 or value > 1.0:
			errors.append("%s must be in [0, 1]." % String(field[0]))
	_validate_nonnegative_dictionary(errors, "pressure_by_event", pressure_by_event)
	_validate_nonnegative_dictionary(errors, "pressure_by_visit", pressure_by_visit)
	return errors


func _validate_nonnegative_dictionary(
	errors: PackedStringArray, field_name: String, values: Dictionary
) -> void:
	if values.is_empty():
		errors.append("%s must not be empty." % field_name)
	for key in values:
		if String(key).strip_edges().is_empty():
			errors.append("%s contains an empty key." % field_name)
		if float(values[key]) < 0.0:
			errors.append("%s[%s] must not be negative." % [field_name, String(key)])
