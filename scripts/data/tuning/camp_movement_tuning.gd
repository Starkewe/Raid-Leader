extends Resource
class_name CampMovementTuning

@export var player_speed_pixels_per_second: float
@export var member_speed_pixels_per_second: float
@export var population_collision_margin_pixels: float
@export var population_occupancy_distance_pixels: float
@export var waypoint_arrival_distance_pixels: float
@export var redundant_waypoint_distance_pixels: float
@export var navigation_timeout_seconds: float
@export var conversation_anchor_arrival_distance_pixels: float
@export var interrupted_idle_delay_min_seconds: float
@export var interrupted_idle_delay_max_seconds: float
@export var conversation_end_idle_delay_min_seconds: float
@export var conversation_end_idle_delay_max_seconds: float


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		["player_speed_pixels_per_second", player_speed_pixels_per_second],
		["member_speed_pixels_per_second", member_speed_pixels_per_second],
		["population_collision_margin_pixels", population_collision_margin_pixels],
		["population_occupancy_distance_pixels", population_occupancy_distance_pixels],
		["waypoint_arrival_distance_pixels", waypoint_arrival_distance_pixels],
		["redundant_waypoint_distance_pixels", redundant_waypoint_distance_pixels],
		["navigation_timeout_seconds", navigation_timeout_seconds],
		["conversation_anchor_arrival_distance_pixels", conversation_anchor_arrival_distance_pixels],
		["interrupted_idle_delay_max_seconds", interrupted_idle_delay_max_seconds],
		["conversation_end_idle_delay_max_seconds", conversation_end_idle_delay_max_seconds],
	]:
		if float(field[1]) <= 0.0:
			errors.append("%s must be greater than zero." % String(field[0]))
	if interrupted_idle_delay_min_seconds < 0.0 or (
		interrupted_idle_delay_min_seconds > interrupted_idle_delay_max_seconds
	):
		errors.append("interrupted idle delay must be a nonnegative minimum/maximum pair.")
	if conversation_end_idle_delay_min_seconds < 0.0 or (
		conversation_end_idle_delay_min_seconds > conversation_end_idle_delay_max_seconds
	):
		errors.append("conversation-end idle delay must be a nonnegative minimum/maximum pair.")
	return errors
