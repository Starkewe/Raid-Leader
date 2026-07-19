extends BossAbility
class_name TwinSweepingPull

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

const PHASE_PULL := "pull"
const PHASE_FIRST_SWEEP := "first_sweep"
const PHASE_SECOND_SWEEP := "second_sweep"

var pull_duration: float = 1.5
var first_sweep_cast_duration: float = 2.5
var second_sweep_cast_duration: float = 4.0
var pull_range: String = MovementSlotResolverScript.RANGE_CLOSE

var affected_ranges: Array[String] = [
	MovementSlotResolverScript.RANGE_CLOSE,
	MovementSlotResolverScript.RANGE_MID
]

var random_pull_regions: Array[String] = [
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
var pull_region_override: String = ""

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
	ability_id = "twin_sweeping_pull"
	ability_name = "Twin Sweeping Pull"
	cast_time = get_second_sweep_impact_time()
	cooldown = 9.0
	damage = 75

	windup_text = "The boss drags everyone into position!"
	impact_text = "The boss sweeps the nearby lanes!"
	interruptible = false

	rng.randomize()


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if not definition is TwinSweepingPullDefinition:
		return

	var sweep_definition := definition as TwinSweepingPullDefinition
	pull_duration = maxf(sweep_definition.pull_duration, 0.01)
	first_sweep_cast_duration = maxf(sweep_definition.first_sweep_cast_duration, 0.01)
	second_sweep_cast_duration = maxf(sweep_definition.second_sweep_cast_duration, 0.01)
	pull_range = sweep_definition.pull_range
	affected_ranges = sweep_definition.affected_ranges.duplicate()
	random_pull_regions = sweep_definition.random_pull_regions.duplicate()
	cast_time = get_second_sweep_impact_time()


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

	selected_pull_region = get_next_pull_region()
	first_sweep_regions = get_relative_sweep_regions(selected_pull_region, -1)
	second_sweep_regions = get_relative_sweep_regions(selected_pull_region, 1)

	if windup_text != "":
		debug_log(
			boss,
			ability_name + " started. Pull region: " + selected_pull_region
			+ "; first sweep: " + str(first_sweep_regions)
			+ "; second sweep: " + str(second_sweep_regions) + "."
		)

	start_forced_pull(boss, party_members)


func on_cast_update(
	boss: Node,
	party_members: Array,
	elapsed_time: float,
	remaining_time: float
) -> void:
	last_elapsed_time = elapsed_time
	set_current_phase(get_phase_for_elapsed_time(elapsed_time))

	if not pull_completed:
		update_forced_pull(boss, party_members, elapsed_time)

	if not first_sweep_resolved and elapsed_time >= get_first_sweep_impact_time():
		first_sweep_resolved = true

		resolve_sweep(
			boss,
			party_members,
			first_sweep_regions,
			affected_ranges,
			"first sweep"
		)

	if not second_sweep_resolved and elapsed_time >= get_second_sweep_impact_time():
		second_sweep_resolved = true

		resolve_sweep(
			boss,
			party_members,
			second_sweep_regions,
			affected_ranges,
			"second sweep"
		)


func resolve(boss: Node, party_members: Array) -> void:
	# Timed impacts happen inside on_cast_update().
	# These fallbacks protect against a large final frame or future callers that
	# finish a cast without delivering every intermediate update.
	if not pull_completed:
		finish_forced_pull()

	if not first_sweep_resolved:
		first_sweep_resolved = true

		resolve_sweep(
			boss,
			party_members,
			first_sweep_regions,
			affected_ranges,
			"first sweep"
		)

	if not second_sweep_resolved:
		second_sweep_resolved = true

		resolve_sweep(
			boss,
			party_members,
			second_sweep_regions,
			affected_ranges,
			"second sweep"
		)


func on_interrupted(boss: Node, party_members: Array) -> void:
	for unit in party_members:
		if is_valid_living_unit(unit) and unit.has_method("cancel_forced_movement"):
			unit.cancel_forced_movement()

	pull_start_positions.clear()
	debug_log(boss, ability_name + " ended early and cleared forced movement.")


func get_next_pull_region() -> String:
	if MovementSlotResolverScript.REGION_ORDER.has(pull_region_override):
		return pull_region_override

	return get_random_pull_region()


func get_random_pull_region() -> String:
	if random_pull_regions.is_empty():
		return MovementSlotResolverScript.REGION_NORTH

	var random_index: int = rng.randi_range(0, random_pull_regions.size() - 1)

	return String(random_pull_regions[random_index])


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
		pull_range
	)

	var living_units: Array = []

	for unit in party_members:
		if is_valid_living_unit(unit) and unit is Node2D:
			living_units.append(unit)

	var destinations := MovementSlotResolverScript.get_slot_formation_positions(
		boss,
		selected_pull_region,
		pull_range,
		living_units.size()
	)
	var pulled_count: int = 0

	for unit_index in range(living_units.size()):
		var unit = living_units[unit_index]
		var destination: Vector2 = destinations[unit_index]

		pull_start_positions[unit] = destination

		if unit.has_method("start_forced_movement"):
			unit.start_forced_movement(destination, pull_duration)
		else:
			unit.global_position = destination

		pulled_count += 1

	debug_log(
		boss,
		ability_name + " is pulling " + str(pulled_count) + " unit(s) to "
		+ selected_pull_region + " " + pull_range + " over "
		+ str(pull_duration) + " second(s)."
	)


func update_forced_pull(boss: Node, party_members: Array, elapsed_time: float) -> void:
	if pull_completed:
		return

	if elapsed_time >= pull_duration:
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
		var destination: Vector2 = pull_start_positions[unit_key]

		if unit.has_method("finish_forced_movement"):
			unit.finish_forced_movement()
		else:
			unit_2d.global_position = destination

		if unit.has_method("clear_manual_move_order"):
			unit.clear_manual_move_order()

		if unit.has_method("stop_movement"):
			unit.stop_movement()

	pull_start_positions.clear()

	# The boss argument is unavailable here; the next phase transition logs the sweep path.


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

	debug_log(
		boss,
		ability_name + " " + sweep_label + " impacted regions "
		+ str(affected_regions) + " at ranges " + str(affected_ranges) + "."
	)
	var resolved_damage := get_scaled_damage(boss, damage)

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

		unit.take_damage(resolved_damage, boss, ability_id, {"sweep": sweep_label})
		hit_count += 1

	debug_log(boss, ability_name + " " + sweep_label + " hit " + str(hit_count) + " unit(s).")


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
	if elapsed_time < pull_duration:
		return PHASE_PULL

	if elapsed_time < get_first_sweep_impact_time():
		return PHASE_FIRST_SWEEP

	return PHASE_SECOND_SWEEP


func set_current_phase(next_phase: String) -> void:
	if next_phase == current_phase:
		return

	current_phase = next_phase

	match current_phase:
		PHASE_FIRST_SWEEP:
			pass

		PHASE_SECOND_SWEEP:
			pass


func get_status_text() -> String:
	match current_phase:
		PHASE_PULL:
			return "Pulling Raid " + selected_pull_region.capitalize()

		PHASE_FIRST_SWEEP:
			return "First Sweep: " + get_region_path_text(first_sweep_regions)

		PHASE_SECOND_SWEEP:
			return "Second Sweep: " + get_region_path_text(second_sweep_regions)

		_:
			return "Casting " + ability_name


func get_cast_name() -> String:
	match current_phase:
		PHASE_PULL:
			return selected_pull_region.capitalize() + " Pull"

		PHASE_FIRST_SWEEP:
			return "First Sweep (Counterclockwise)"

		PHASE_SECOND_SWEEP:
			return "Second Sweep (Clockwise)"

		_:
			return ability_name


func get_region_path_text(regions: Array[String]) -> String:
	var labels: Array[String] = []

	for region in regions:
		labels.append(region.capitalize())

	return " -> ".join(labels)


func get_cast_bar_max_time(elapsed_time: float, remaining_time: float) -> float:
	match get_phase_for_elapsed_time(elapsed_time):
		PHASE_PULL:
			return pull_duration

		PHASE_FIRST_SWEEP:
			return first_sweep_cast_duration

		PHASE_SECOND_SWEEP:
			return second_sweep_cast_duration

		_:
			return cast_time


func get_cast_bar_value(elapsed_time: float, remaining_time: float) -> float:
	match get_phase_for_elapsed_time(elapsed_time):
		PHASE_PULL:
			return clampf(elapsed_time, 0.0, pull_duration)

		PHASE_FIRST_SWEEP:
			return clampf(
				elapsed_time - pull_duration,
				0.0,
				first_sweep_cast_duration
			)

		PHASE_SECOND_SWEEP:
			return clampf(
				elapsed_time - get_first_sweep_impact_time(),
				0.0,
				second_sweep_cast_duration
			)

		_:
			return clampf(elapsed_time, 0.0, cast_time)


func get_first_sweep_impact_time() -> float:
	return pull_duration + first_sweep_cast_duration


func get_second_sweep_impact_time() -> float:
	return pull_duration + first_sweep_cast_duration + second_sweep_cast_duration


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
