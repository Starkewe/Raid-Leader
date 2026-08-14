extends Resource
class_name CampRelationshipTuning

@export var value_minimum: int
@export var value_maximum: int
@export var pair_memory_limit: int
@export var permanent_pair_memory_limit: int
@export var recent_conversation_limit: int
@export var shared_context_history_limit: int
@export var thresholds: Array[int] = []
@export var routine_activity_changes_relationships: bool
@export var maximum_normal_dimension_delta: int
@export var qualifying_event_minimum_significance: int
@export var permanent_memory_threshold_magnitude: int
@export var standard_threshold_event_significance: int
@export var high_threshold_event_significance: int
@export var close_friend_minimum_affinity: int
@export var close_friend_minimum_trust: int
@export var close_friend_reciprocal_minimum_affinity: int
@export var close_friend_reciprocal_minimum_trust: int
@export var trusted_companion_minimum_trust: int
@export var trusted_companion_minimum_respect: int
@export var respectful_rival_minimum_respect: int
@export var respectful_rival_minimum_tension: int
@export var respectful_rival_maximum_affinity_exclusive: int
@export var fond_minimum_affinity: int
@export var fond_maximum_trust_exclusive: int
@export var strained_minimum_tension: int
@export var strained_maximum_affinity: int
@export var strained_maximum_trust: int
@export var becoming_friend_minimum_affinity: int
@export var becoming_friend_minimum_trust: int


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if value_minimum >= value_maximum:
		errors.append("value_minimum must be less than value_maximum.")
	for field in [
		["pair_memory_limit", pair_memory_limit],
		["permanent_pair_memory_limit", permanent_pair_memory_limit],
		["recent_conversation_limit", recent_conversation_limit],
		["shared_context_history_limit", shared_context_history_limit],
		["maximum_normal_dimension_delta", maximum_normal_dimension_delta],
		["permanent_memory_threshold_magnitude", permanent_memory_threshold_magnitude],
	]:
		if int(field[1]) <= 0:
			errors.append("%s must be greater than zero." % String(field[0]))
	if permanent_pair_memory_limit > pair_memory_limit:
		errors.append("permanent_pair_memory_limit must not exceed pair_memory_limit.")
	if thresholds.is_empty():
		errors.append("thresholds must not be empty.")
	for field in [
		["qualifying_event_minimum_significance", qualifying_event_minimum_significance],
		["standard_threshold_event_significance", standard_threshold_event_significance],
		["high_threshold_event_significance", high_threshold_event_significance],
	]:
		if int(field[1]) < 0 or int(field[1]) > 100:
			errors.append("%s must be in [0, 100]." % String(field[0]))
	if high_threshold_event_significance < standard_threshold_event_significance:
		errors.append("high threshold event significance must not be below standard significance.")
	for field in [
		["close_friend_minimum_affinity", close_friend_minimum_affinity],
		["close_friend_minimum_trust", close_friend_minimum_trust],
		["close_friend_reciprocal_minimum_affinity", close_friend_reciprocal_minimum_affinity],
		["close_friend_reciprocal_minimum_trust", close_friend_reciprocal_minimum_trust],
		["trusted_companion_minimum_trust", trusted_companion_minimum_trust],
		["trusted_companion_minimum_respect", trusted_companion_minimum_respect],
		["respectful_rival_minimum_respect", respectful_rival_minimum_respect],
		["respectful_rival_minimum_tension", respectful_rival_minimum_tension],
		[
			"respectful_rival_maximum_affinity_exclusive",
			respectful_rival_maximum_affinity_exclusive,
		],
		["fond_minimum_affinity", fond_minimum_affinity],
		["fond_maximum_trust_exclusive", fond_maximum_trust_exclusive],
		["strained_minimum_tension", strained_minimum_tension],
		["strained_maximum_affinity", strained_maximum_affinity],
		["strained_maximum_trust", strained_maximum_trust],
		["becoming_friend_minimum_affinity", becoming_friend_minimum_affinity],
		["becoming_friend_minimum_trust", becoming_friend_minimum_trust],
	]:
		if int(field[1]) < value_minimum or int(field[1]) > value_maximum:
			errors.append("%s must be inside the relationship value range." % String(field[0]))
	var previous := value_minimum - 1
	for threshold in thresholds:
		if threshold <= value_minimum or threshold >= value_maximum:
			errors.append("relationship threshold %d must be inside the value range." % threshold)
		if threshold <= previous:
			errors.append("thresholds must be strictly increasing.")
		previous = threshold
	return errors
