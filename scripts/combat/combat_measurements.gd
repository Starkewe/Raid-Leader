extends RefCounted
class_name CombatMeasurements

static var PIXELS_PER_RANGE_UNIT: float = TuningCatalogAccess.get_combat().pixels_per_range_unit
static var DEFAULT_BOSS_COMBAT_RADIUS_PIXELS: float = (
	TuningCatalogAccess.get_combat().default_boss_combat_radius_pixels
)
static var BASE_MOVEMENT_SPEED_RANGE_UNITS_PER_SECOND: float = (
	TuningCatalogAccess.get_combat().base_movement_speed_range_units_per_second
)


static func range_units_to_pixels(range_units: float) -> float:
	return range_units * PIXELS_PER_RANGE_UNIT


static func pixels_to_range_units(pixels: float) -> float:
	if PIXELS_PER_RANGE_UNIT <= 0.0:
		return 0.0

	return pixels / PIXELS_PER_RANGE_UNIT


static func get_base_movement_speed_pixels_per_second() -> float:
	return range_units_to_pixels(BASE_MOVEMENT_SPEED_RANGE_UNITS_PER_SECOND)
