extends RefCounted
class_name CombatMeasurements

const PIXELS_PER_RANGE_UNIT: float = 20.0
const DEFAULT_BOSS_COMBAT_RADIUS_PIXELS: float = 128.0
const BASE_MOVEMENT_SPEED_RANGE_UNITS_PER_SECOND: float = 7.0


static func range_units_to_pixels(range_units: float) -> float:
	return range_units * PIXELS_PER_RANGE_UNIT


static func pixels_to_range_units(pixels: float) -> float:
	if PIXELS_PER_RANGE_UNIT <= 0.0:
		return 0.0

	return pixels / PIXELS_PER_RANGE_UNIT


static func get_base_movement_speed_pixels_per_second() -> float:
	return range_units_to_pixels(BASE_MOVEMENT_SPEED_RANGE_UNITS_PER_SECOND)
