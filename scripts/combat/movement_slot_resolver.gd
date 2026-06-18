extends RefCounted
class_name MovementSlotResolver

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")

const RANGE_CLOSE := "close"
const RANGE_MID := "mid"
const RANGE_FAR := "far"

const REGION_NORTH := "north"
const REGION_NORTHEAST := "northeast"
const REGION_EAST := "east"
const REGION_SOUTHEAST := "southeast"
const REGION_SOUTH := "south"
const REGION_SOUTHWEST := "southwest"
const REGION_WEST := "west"
const REGION_NORTHWEST := "northwest"

const ROTATION_COUNTERCLOCKWISE := "counterclockwise"
const ROTATION_CLOCKWISE := "clockwise"
const RANGE_DIRECTION_IN := "in"
const RANGE_DIRECTION_OUT := "out"

const RANGE_ORDER := [
	RANGE_CLOSE,
	RANGE_MID,
	RANGE_FAR
]

const REGION_ORDER := [
	REGION_NORTH,
	REGION_NORTHEAST,
	REGION_EAST,
	REGION_SOUTHEAST,
	REGION_SOUTH,
	REGION_SOUTHWEST,
	REGION_WEST,
	REGION_NORTHWEST
]

const REGION_DIRECTIONS := {
	REGION_NORTH: Vector2(0, -1),
	REGION_NORTHEAST: Vector2(1, -1),
	REGION_EAST: Vector2(1, 0),
	REGION_SOUTHEAST: Vector2(1, 1),
	REGION_SOUTH: Vector2(0, 1),
	REGION_SOUTHWEST: Vector2(-1, 1),
	REGION_WEST: Vector2(-1, 0),
	REGION_NORTHWEST: Vector2(-1, -1)
}

const DEFAULT_BOSS_COMBAT_RADIUS: float = 90.0

const CLOSE_SLOT_RANGE_UNITS: float = 5.0
const MID_SLOT_RANGE_UNITS: float = 20.0
const FAR_SLOT_RANGE_UNITS: float = 40.0

static func get_adjacent_region(current_region: String, rotation_direction: String) -> String:
	var current_index: int = REGION_ORDER.find(current_region)

	if current_index == -1:
		return REGION_NORTH

	var region_count: int = REGION_ORDER.size()
	var step_direction: int = 1

	if rotation_direction == ROTATION_COUNTERCLOCKWISE:
		step_direction = -1

	var next_index: int = (current_index + step_direction + region_count) % region_count

	return String(REGION_ORDER[next_index])
static func get_adjacent_range(current_range: String, range_direction: String) -> String:
	var current_index: int = RANGE_ORDER.find(current_range)

	if current_index == -1:
		return RANGE_MID

	var step_direction: int = 0

	if range_direction == RANGE_DIRECTION_IN:
		step_direction = -1
	elif range_direction == RANGE_DIRECTION_OUT:
		step_direction = 1

	var next_index: int = clampi(
		current_index + step_direction,
		0,
		RANGE_ORDER.size() - 1
	)

	return String(RANGE_ORDER[next_index])
static func get_slot_position(boss_node: Node, region: String, range_name: String) -> Vector2:
	if boss_node == null or not is_instance_valid(boss_node):
		return Vector2.ZERO

	if not boss_node is Node2D:
		return Vector2.ZERO

	var boss_2d := boss_node as Node2D
	var direction: Vector2 = get_region_direction(region)
	var boss_radius: float = get_boss_combat_radius(boss_node)
	var range_offset: float = get_range_offset(range_name)
	var total_distance: float = boss_radius + range_offset

	return boss_2d.global_position + direction * total_distance
	
static func get_boss_combat_radius(boss_node: Node) -> float:
	if boss_node == null or not is_instance_valid(boss_node):
		return CombatMeasurementsScript.DEFAULT_BOSS_COMBAT_RADIUS_PIXELS

	if boss_node.has_method("get_combat_radius"):
		var radius_value: Variant = boss_node.get_combat_radius()
		return maxf(float(radius_value), 0.0)

	var property_value: Variant = boss_node.get("combat_radius")

	if property_value == null:
		return CombatMeasurementsScript.DEFAULT_BOSS_COMBAT_RADIUS_PIXELS

	return maxf(float(property_value), 0.0)

static func get_region_direction(region: String) -> Vector2:
	var direction: Vector2 = REGION_DIRECTIONS.get(region, REGION_DIRECTIONS[REGION_NORTH])
	return direction.normalized()

static func get_range_offset_units(range_name: String) -> float:
	match range_name:
		RANGE_CLOSE:
			return CLOSE_SLOT_RANGE_UNITS
		RANGE_MID:
			return MID_SLOT_RANGE_UNITS
		RANGE_FAR:
			return FAR_SLOT_RANGE_UNITS
		_:
			return MID_SLOT_RANGE_UNITS


static func get_range_offset(range_name: String) -> float:
	var range_units: float = get_range_offset_units(range_name)
	return CombatMeasurementsScript.range_units_to_pixels(range_units)

static func get_nearest_range_from_position(boss_node: Node, unit_position: Vector2) -> String:
	if boss_node == null or not is_instance_valid(boss_node):
		return RANGE_MID

	if not boss_node is Node2D:
		return RANGE_MID

	var boss_2d := boss_node as Node2D
	var boss_radius: float = get_boss_combat_radius(boss_node)
	var center_distance: float = boss_2d.global_position.distance_to(unit_position)
	var edge_distance_pixels: float = maxf(center_distance - boss_radius, 0.0)
	var edge_distance_units: float = CombatMeasurementsScript.pixels_to_range_units(edge_distance_pixels)

	var best_range: String = RANGE_MID
	var best_difference: float = 999999.0

	var ranges: Array[String] = [
		RANGE_CLOSE,
		RANGE_MID,
		RANGE_FAR
	]

	for range_name in ranges:
		var range_units: float = get_range_offset_units(range_name)
		var difference: float = absf(edge_distance_units - range_units)

		if difference < best_difference:
			best_difference = difference
			best_range = range_name

	return best_range
	
static func get_nearest_region_from_position(boss_position: Vector2, unit_position: Vector2) -> String:
	var offset: Vector2 = unit_position - boss_position

	if offset.length() <= 0.01:
		return REGION_SOUTH

	var unit_direction: Vector2 = offset.normalized()
	var best_region: String = REGION_SOUTH
	var best_dot: float = -999999.0

	for region in REGION_DIRECTIONS.keys():
		var region_direction: Vector2 = get_region_direction(String(region))
		var dot: float = unit_direction.dot(region_direction)

		if dot > best_dot:
			best_dot = dot
			best_region = String(region)

	return best_region
	
static func get_region_rotation_path(current_region: String, target_region: String) -> Array[String]:
	var path: Array[String] = []

	var current_index: int = REGION_ORDER.find(current_region)
	var target_index: int = REGION_ORDER.find(target_region)

	if target_index == -1:
		path.append(REGION_NORTH)
		return path

	if current_index == -1:
		path.append(target_region)
		return path

	if current_index == target_index:
		path.append(target_region)
		return path

	var region_count: int = REGION_ORDER.size()

	var clockwise_steps: int = (target_index - current_index + region_count) % region_count
	var counterclockwise_steps: int = (current_index - target_index + region_count) % region_count

	var step_direction: int = 1
	var step_count: int = clockwise_steps

	if counterclockwise_steps < clockwise_steps:
		step_direction = -1
		step_count = counterclockwise_steps

	var index: int = current_index

	for _step in range(step_count):
		index = (index + step_direction + region_count) % region_count
		path.append(String(REGION_ORDER[index]))

	return path
