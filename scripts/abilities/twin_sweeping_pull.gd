extends BossAbility
class_name TwinSweepingPull

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

const PULL_DURATION: float = 1.5
const FIRST_SWEEP_CAST_DURATION: float = 4.0
const SECOND_SWEEP_CAST_DURATION: float = 4.0

const FIRST_SWEEP_IMPACT_TIME: float = PULL_DURATION + FIRST_SWEEP_CAST_DURATION
const SECOND_SWEEP_IMPACT_TIME: float = PULL_DURATION + FIRST_SWEEP_CAST_DURATION + SECOND_SWEEP_CAST_DURATION

const PULL_RANGE: String = MovementSlotResolverScript.RANGE_CLOSE

const PHASE_PULL := "pull"
const PHASE_FIRST_SWEEP := "first_sweep"
const PHASE_SECOND_SWEEP := "second_sweep"

const AFFECTED_RANGES: Array[String] = [
	MovementSlotResolverScript.RANGE_CLOSE,
	MovementSlotResolverScript.RANGE_MID
]

const RANDOM_PULL_REGIONS: Array[String] = [
	MovementSlotResolverScript.REGION_NORTH,
	MovementSlotResolverScript.REGION_NORTHEAST,
	MovementSlotResolverScript.REGION_EAST,
	MovementSlotResolverScript.REGION_SOUTHEAST,
	MovementSlotResolverScript.REGION_SOUTH,
	MovementSlotResolverScript.REGION_SOUTHWEST,
	MovementSlotResolverScript.REGION_WEST,
	MovementSlotResolverScript.REGION_NORTHWEST
]

var rng := RandomNumberGenerator.new()

var pull_start_positions: Dictionary = {}
var pull_destination: Vector2 = Vector2.ZERO

var selected_pull_region: String = MovementSlotResolverScript.REGION_NORTH
var first_sweep_regions: Array[String] = []
var second_sweep_regions: Array[String] = []

var pull_completed: bool = false
var first_sweep_resolved: bool = false
var second_sweep_resolved: bool = false

var current_phase: String = PHASE_PULL
var last_elapsed_time: float = 0.0


func _init() -> void:
	ability_name = "Twin Sweep"
	cast_time = SECOND_SWEEP_IMPACT_TIME
	cooldown = 9.0
	damage = 75

	windup_text = "The boss drags everyone into position!"
	impact_text = "The boss sweeps the nearby lanes!"
	interruptible = false

	rng.randomize()


func can_cast(boss: Node, party_members: Array) -> bool:
	if not super.can_cast(boss, party_members):
		return false

	if not boss is Node2D:
		return false

	for unit in party_members:
		if is_valid_living_unit(unit):
			return true

	return false


func on_cast_start(boss: Node, party_members: Array) -> void:
	pull_start_positions.clear()

	pull_completed = false
	first_sweep_resolved = false
	second_sweep_resolved = false

	current_phase = PHASE_PULL
	last_elapsed_time = 0.0

	selected_pull_region = get_random_pull_region()
	first_sweep_regions = get_relative_sweep_regions(selected_pull_region, -1)
	second_sweep_regions = get_relative_sweep_regions(selected_pull_region, 1)

	if windup_text != "":
		print(
			ability_name,
			"windup:",
			windup_text,
			"Pull region:",
			selected_pull_region,
			"First sweep:",
			first_sweep_regions,
			"Second sweep:",
			second_sweep_regions
		)

	start_forced_pull(boss, party_members)


func on_cast_update(
	boss: Node,
	party_members: Array,
	elapsed_time: float,
	remaining_time: float
) -> void:
	last_elapsed_time = elapsed_time
	current_phase = get_phase_for_elapsed_time(elapsed_time)

	if not pull_completed:
		update_forced_pull(boss, party_members, elapsed_time)

	if not first_sweep_resolved and elapsed_time >= FIRST_SWEEP_IMPACT_TIME:
		first_sweep_resolved = true

		resolve_sweep(
			boss,
			party_members,
			first_sweep_regions,
			AFFECTED_RANGES,
			"first sweep"
		)

	if not second_sweep_resolved and elapsed_time >= SECOND_SWEEP_IMPACT_TIME:
		second_sweep_resolved = true

		resolve_sweep(
			boss,
			party_members,
			second_sweep_regions,
			AFFECTED_RANGES,
			"second sweep"
		)


func resolve(boss: Node, party_members: Array) -> void:
	# Timed impacts happen inside on_cast_update().
	# This fallback protects against tests or future code that directly calls resolve().
	if not second_sweep_resolved:
		second_sweep_resolved = true

		resolve_sweep(
			boss,
			party_members,
			second_sweep_regions,
			AFFECTED_RANGES,
			"second sweep"
		)


func on_interrupted(boss: Node, party_members: Array) -> void:
	pull_start_positions.clear()
	print(ability_name, "ended early.")


func get_random_pull_region() -> String:
	if RANDOM_PULL_REGIONS.is_empty():
		return MovementSlotResolverScript.REGION_NORTH

	var random_index: int = rng.randi_range(0, RANDOM_PULL_REGIONS.size() - 1)

	return String(RANDOM_PULL_REGIONS[random_index])


func get_relative_sweep_regions(center_region: String, step_direction: int) -> Array[String]:
	var regions: Array[String] = []
	var region_order: Array = MovementSlotResolverScript.REGION_ORDER
	var center_index: int = region_order.find(center_region)

	if center_index == -1:
		regions.append(center_region)
		return regions

	var region_count: int = region_order.size()

	for step in range(3):
		var region_index: int = (
			center_index
			+ (step * step_direction)
			+ region_count
		) % region_count

		regions.append(String(region_order[region_index]))

	return regions


func start_forced_pull(boss: Node, party_members: Array) -> void:
	if not is_valid_node2d(boss):
		return

	pull_destination = MovementSlotResolverScript.get_slot_position(
		boss,
		selected_pull_region,
		PULL_RANGE
	)

	var pulled_count: int = 0

	for unit in party_members:
		if not is_valid_living_unit(unit):
			continue

		if not unit is Node2D:
			continue

		if unit.has_method("clear_manual_move_order"):
			unit.clear_manual_move_order()

		if unit.has_method("stop_movement"):
			unit.stop_movement()

		pull_start_positions[unit] = unit.global_position
		pulled_count += 1

	print(
		ability_name,
		"starts pulling",
		pulled_count,
		"unit(s) to",
		selected_pull_region,
		PULL_RANGE,
		"over",
		PULL_DURATION,
		"second(s)."
	)


func update_forced_pull(boss: Node, party_members: Array, elapsed_time: float) -> void:
	if pull_completed:
		return

	var pull_progress: float = clampf(elapsed_time / PULL_DURATION, 0.0, 1.0)

	for unit_key in pull_start_positions.keys():
		var unit := unit_key as Node

		if not is_valid_living_unit(unit):
			continue

		if not unit is Node2D:
			continue

		var unit_2d := unit as Node2D
		var start_position: Vector2 = pull_start_positions[unit_key]

		unit_2d.global_position = start_position.lerp(pull_destination, pull_progress)

		if unit_2d is CharacterBody2D:
			var body := unit_2d as CharacterBody2D
			body.velocity = Vector2.ZERO

	if elapsed_time >= PULL_DURATION:
		finish_forced_pull()


func finish_forced_pull() -> void:
	if pull_completed:
		return

	pull_completed = true

	for unit_key in pull_start_positions.keys():
		var unit := unit_key as Node

		if not is_valid_living_unit(unit):
			continue

		if not unit is Node2D:
			continue

		var unit_2d := unit as Node2D
		unit_2d.global_position = pull_destination

		if unit.has_method("clear_manual_move_order"):
			unit.clear_manual_move_order()

		if unit.has_method("stop_movement"):
			unit.stop_movement()

	pull_start_positions.clear()

	print(
		ability_name,
		"pull complete.",
		"First sweep cast begins from",
		selected_pull_region
	)


func resolve_sweep(
	boss: Node,
	party_members: Array,
	affected_regions: Array[String],
	affected_ranges: Array[String],
	sweep_label: String
) -> void:
	if not is_valid_node2d(boss):
		return

	var boss_2d := boss as Node2D
	var hit_count: int = 0

	play_sweep_impact_effects(boss, affected_regions, affected_ranges)

	print(
		ability_name,
		"impact:",
		sweep_label,
		"regions:",
		affected_regions,
		"ranges:",
		affected_ranges
	)

	for unit in party_members:
		if not is_valid_living_damageable_unit(unit):
			continue

		if not unit is Node2D:
			continue

		var unit_2d := unit as Node2D

		var unit_region: String = MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var unit_range: String = MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		if not affected_regions.has(unit_region):
			continue

		if not affected_ranges.has(unit_range):
			continue

		unit.take_damage(damage)
		hit_count += 1

	print(
		ability_name,
		sweep_label,
		"hit",
		hit_count,
		"unit(s)."
	)


func play_sweep_impact_effects(
	boss: Node,
	affected_regions: Array[String],
	affected_ranges: Array[String]
) -> void:
	if boss == null:
		return

	if not is_instance_valid(boss):
		return

	if not boss.has_method("play_region_impact_effect"):
		return

	for region in affected_regions:
		boss.play_region_impact_effect(region, affected_ranges)


func get_phase_for_elapsed_time(elapsed_time: float) -> String:
	if elapsed_time < PULL_DURATION:
		return PHASE_PULL

	if elapsed_time < FIRST_SWEEP_IMPACT_TIME:
		return PHASE_FIRST_SWEEP

	return PHASE_SECOND_SWEEP


func get_status_text() -> String:
	match current_phase:
		PHASE_PULL:
			return "Pulling Raid " + selected_pull_region.capitalize()

		PHASE_FIRST_SWEEP:
			return "Casting First Sweep"

		PHASE_SECOND_SWEEP:
			return "Casting Second Sweep"

		_:
			return "Casting " + ability_name


func get_cast_name() -> String:
	match current_phase:
		PHASE_PULL:
			return selected_pull_region.capitalize() + " Pull"

		PHASE_FIRST_SWEEP:
			return "First Sweep"

		PHASE_SECOND_SWEEP:
			return "Second Sweep"

		_:
			return ability_name


func get_cast_bar_max_time(elapsed_time: float, remaining_time: float) -> float:
	match get_phase_for_elapsed_time(elapsed_time):
		PHASE_PULL:
			return PULL_DURATION

		PHASE_FIRST_SWEEP:
			return FIRST_SWEEP_CAST_DURATION

		PHASE_SECOND_SWEEP:
			return SECOND_SWEEP_CAST_DURATION

		_:
			return cast_time


func get_cast_bar_value(elapsed_time: float, remaining_time: float) -> float:
	match get_phase_for_elapsed_time(elapsed_time):
		PHASE_PULL:
			return clampf(elapsed_time, 0.0, PULL_DURATION)

		PHASE_FIRST_SWEEP:
			return clampf(
				elapsed_time - PULL_DURATION,
				0.0,
				FIRST_SWEEP_CAST_DURATION
			)

		PHASE_SECOND_SWEEP:
			return clampf(
				elapsed_time - FIRST_SWEEP_IMPACT_TIME,
				0.0,
				SECOND_SWEEP_CAST_DURATION
			)

		_:
			return clampf(elapsed_time, 0.0, cast_time)


func is_valid_living_unit(unit: Node) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if unit.has_method("is_alive"):
		return unit.is_alive()

	return true


func is_valid_living_damageable_unit(unit: Node) -> bool:
	if not is_valid_living_unit(unit):
		return false

	if not unit.has_method("take_damage"):
		return false

	return true


func is_valid_node2d(node: Node) -> bool:
	if node == null:
		return false

	if not is_instance_valid(node):
		return false

	if not node is Node2D:
		return false

	return true
