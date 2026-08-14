extends Resource
class_name CombatTuning

@export_group("Measurements")
@export var pixels_per_range_unit: float
@export var default_boss_combat_radius_pixels: float
@export var base_movement_speed_range_units_per_second: float
@export var close_range_units: float
@export var mid_range_units: float
@export var far_range_units: float
@export var mini_region_half_angle_radians: float
@export var mini_region_entry_margin_pixels: float
@export var raider_formation_spacing_pixels: float
@export var raid_spawn_grid_cell_spacing_pixels: Vector2

@export_group("Movement safety")
@export var local_destination_max_adjustment_spacings: float
@export var local_destination_adjustment_step_pixels: float
@export var local_destination_candidate_directions: int
@export var mini_region_safety_buffer_pixels: float
@export var manual_move_stop_distance_pixels: float
@export var mini_region_footprint_radius_pixels: float
@export var combat_player_speed_pixels_per_second: float

@export_group("Automatic positioning")
@export var automatic_route_arrival_distance_pixels: float
@export var automatic_candidate_radial_step_pixels: float
@export var automatic_candidate_directions: int
@export var automatic_candidate_extra_radial_steps: int

@export_group("Threat and healing")
@export var normal_threat_switch_multiplier: float
@export var taunt_threat_multiplier: float
@export var taunt_forced_target_duration_seconds: float
@export var taunt_cooldown_duration_seconds: float
@export var tank_role_threat_multiplier: float
@export var class_threat_multipliers: Dictionary = {}
@export var healing_interruption_cast_safety_seconds: float


func range_units_to_pixels(range_units: float) -> float:
	return range_units * pixels_per_range_unit


func pixels_to_range_units(pixels: float) -> float:
	return pixels / pixels_per_range_unit


func get_base_movement_speed_pixels_per_second() -> float:
	return range_units_to_pixels(base_movement_speed_range_units_per_second)


func get_local_destination_max_adjustment_pixels() -> float:
	return raider_formation_spacing_pixels * local_destination_max_adjustment_spacings


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		["pixels_per_range_unit", pixels_per_range_unit],
		["default_boss_combat_radius_pixels", default_boss_combat_radius_pixels],
		["base_movement_speed_range_units_per_second", base_movement_speed_range_units_per_second],
		["close_range_units", close_range_units],
		["mid_range_units", mid_range_units],
		["far_range_units", far_range_units],
		["mini_region_half_angle_radians", mini_region_half_angle_radians],
		["raider_formation_spacing_pixels", raider_formation_spacing_pixels],
		["local_destination_max_adjustment_spacings", local_destination_max_adjustment_spacings],
		["local_destination_adjustment_step_pixels", local_destination_adjustment_step_pixels],
		["manual_move_stop_distance_pixels", manual_move_stop_distance_pixels],
		["mini_region_footprint_radius_pixels", mini_region_footprint_radius_pixels],
		["combat_player_speed_pixels_per_second", combat_player_speed_pixels_per_second],
		["automatic_route_arrival_distance_pixels", automatic_route_arrival_distance_pixels],
		["automatic_candidate_radial_step_pixels", automatic_candidate_radial_step_pixels],
		["normal_threat_switch_multiplier", normal_threat_switch_multiplier],
		["taunt_threat_multiplier", taunt_threat_multiplier],
		["taunt_forced_target_duration_seconds", taunt_forced_target_duration_seconds],
		["taunt_cooldown_duration_seconds", taunt_cooldown_duration_seconds],
		["tank_role_threat_multiplier", tank_role_threat_multiplier],
		["healing_interruption_cast_safety_seconds", healing_interruption_cast_safety_seconds],
	]:
		if float(field[1]) <= 0.0:
			errors.append("%s must be greater than zero." % String(field[0]))
	for field in [
		["mini_region_entry_margin_pixels", mini_region_entry_margin_pixels],
		["mini_region_safety_buffer_pixels", mini_region_safety_buffer_pixels],
	]:
		if float(field[1]) < 0.0:
			errors.append("%s must not be negative." % String(field[0]))
	if not close_range_units < mid_range_units or not mid_range_units < far_range_units:
		errors.append("close, mid, and far range units must be strictly increasing.")
	if mini_region_half_angle_radians >= PI:
		errors.append("mini_region_half_angle_radians must be less than PI.")
	if local_destination_candidate_directions <= 0:
		errors.append("local_destination_candidate_directions must be greater than zero.")
	if automatic_candidate_directions <= 0:
		errors.append("automatic_candidate_directions must be greater than zero.")
	if automatic_candidate_extra_radial_steps <= 0:
		errors.append("automatic_candidate_extra_radial_steps must be greater than zero.")
	if raid_spawn_grid_cell_spacing_pixels.x <= 0.0 or raid_spawn_grid_cell_spacing_pixels.y <= 0.0:
		errors.append("raid_spawn_grid_cell_spacing_pixels components must be greater than zero.")
	if class_threat_multipliers.is_empty():
		errors.append("class_threat_multipliers must not be empty.")
	for class_name_value in class_threat_multipliers:
		if String(class_name_value).strip_edges().is_empty():
			errors.append("class_threat_multipliers contains an empty class name.")
		if float(class_threat_multipliers[class_name_value]) <= 0.0:
			errors.append(
				"class_threat_multipliers[%s] must be greater than zero."
				% String(class_name_value)
			)
	return errors
