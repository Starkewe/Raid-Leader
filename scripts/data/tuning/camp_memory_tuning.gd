extends Resource
class_name CampMemoryTuning

const REQUIRED_CATEGORIES: Array[String] = [
	"combat", "social", "roster", "camp_life", "personal_reflection"
]
const REQUIRED_STATES: Array[String] = ["active", "latent", "permanent"]

@export var day_seconds: int
@export var normal_reinforcement_ceiling_days: int
@export var self_reinforcement_limit: int
@export var rejection_limit: int
@export var life_memory_capacity: int
@export var latent_multiplier: int
@export var duplicate_episode_window_days: int
@export var diminishing_extension_rate: float
@export var resolution_external_reinforcements: int
@export var identity_promotion_strength: float
@export var selection_state_weights: Dictionary = {}
@export var selection_strength_weight: float
@export var selection_reinforcement_weight: float
@export var selection_reinforcement_score_cap: float
@export var selection_recency_window_days: float
@export var category_capacities: Dictionary = {}
@export var category_active_days: Dictionary = {}
@export var category_latent_days: Dictionary = {}


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		["day_seconds", day_seconds],
		["normal_reinforcement_ceiling_days", normal_reinforcement_ceiling_days],
		["self_reinforcement_limit", self_reinforcement_limit],
		["rejection_limit", rejection_limit],
		["life_memory_capacity", life_memory_capacity],
		["latent_multiplier", latent_multiplier],
		["duplicate_episode_window_days", duplicate_episode_window_days],
		["resolution_external_reinforcements", resolution_external_reinforcements],
	]:
		if int(field[1]) <= 0:
			errors.append("%s must be greater than zero." % String(field[0]))
	for field in [
		["diminishing_extension_rate", diminishing_extension_rate],
		["identity_promotion_strength", identity_promotion_strength],
	]:
		_validate_probability(errors, String(field[0]), float(field[1]), false)
	if selection_strength_weight < 0.0:
		errors.append("selection_strength_weight must not be negative.")
	if selection_reinforcement_weight < 0.0:
		errors.append("selection_reinforcement_weight must not be negative.")
	_validate_probability(
		errors,
		"selection_reinforcement_score_cap",
		selection_reinforcement_score_cap,
		false
	)
	if selection_recency_window_days <= 0.0:
		errors.append("selection_recency_window_days must be greater than zero.")
	_validate_positive_dictionary(errors, "selection_state_weights", selection_state_weights, REQUIRED_STATES)
	_validate_positive_dictionary(errors, "category_capacities", category_capacities, REQUIRED_CATEGORIES)
	_validate_positive_dictionary(errors, "category_active_days", category_active_days, REQUIRED_CATEGORIES)
	_validate_positive_dictionary(errors, "category_latent_days", category_latent_days, REQUIRED_CATEGORIES)
	for category in REQUIRED_CATEGORIES:
		if int(category_latent_days.get(category, 0)) < int(category_active_days.get(category, 0)):
			errors.append("category_latent_days[%s] must not be shorter than active days." % category)
	return errors


func _validate_probability(
	errors: PackedStringArray, field_name: String, value: float, allow_zero: bool
) -> void:
	if value > 1.0 or value < 0.0 or (not allow_zero and value == 0.0):
		errors.append("%s must be in the range %s." % [field_name, "[0, 1]" if allow_zero else "(0, 1]"])


func _validate_positive_dictionary(
	errors: PackedStringArray, field_name: String, values: Dictionary, required_keys: Array[String]
) -> void:
	for key in required_keys:
		if not values.has(key):
			errors.append("%s is missing '%s'." % [field_name, key])
		elif float(values[key]) <= 0.0:
			errors.append("%s[%s] must be greater than zero." % [field_name, key])
	for key in values:
		if String(key) not in required_keys:
			errors.append("%s contains unknown key '%s'." % [field_name, String(key)])
