extends Node

const TwinSweepingPullScript := preload("res://scripts/abilities/twin_sweeping_pull.gd")
const BossAbilityFactoryScript := preload("res://scripts/abilities/boss_ability_factory.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const BossScript := preload("res://scripts/units/boss.gd")

var failures: Array[String] = []


class MockBoss:
	extends Node2D

	var combat_radius: float = 128.0
	var impact_calls: Array[Dictionary] = []

	func get_combat_radius() -> float:
		return combat_radius

	func play_region_impact_effect(region: String, ranges: Array) -> void:
		impact_calls.append({
			"region": region,
			"ranges": ranges.duplicate()
		})


class MockUnit:
	extends Node2D

	var health: int = 300
	var manual_move_clear_count: int = 0
	var stop_movement_count: int = 0

	func is_alive() -> bool:
		return health > 0

	func take_damage(amount: int) -> void:
		health = maxi(health - amount, 0)

	func clear_manual_move_order() -> void:
		manual_move_clear_count += 1

	func stop_movement() -> void:
		stop_movement_count += 1


func _ready() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	test_factory_and_timing_contract()
	test_relative_sweep_regions()
	test_forced_pull_interpolation()
	test_timed_sweep_damage_and_final_resolution()
	test_resolve_fallback_finishes_every_phase()
	test_boss_cast_lifecycle()

	if failures.is_empty():
		print("TwinSweepingPull tests passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)

	print("TwinSweepingPull tests failed: ", failures.size())
	get_tree().quit(1)


func test_factory_and_timing_contract() -> void:
	var ability: BossAbility = BossAbilityFactoryScript.create_twin_sweeping_pull()

	expect_true(ability is TwinSweepingPull, "Factory should create TwinSweepingPull.")
	expect_float(ability.cast_time, 7.0, "Total mechanic duration should be seven seconds.")
	expect_float(ability.get_cast_bar_max_time(0.5, 6.5), 1.0, "Pull cast bar should last one second.")
	expect_float(ability.get_cast_bar_max_time(2.0, 5.0), 2.0, "First sweep cast bar should last two seconds.")
	expect_float(ability.get_cast_bar_max_time(3.0, 4.0), 4.0, "Second sweep cast bar should last four seconds.")
	expect_float(ability.get_cast_bar_value(3.0, 4.0), 0.0, "Second sweep cast bar should restart at its phase boundary.")


func test_relative_sweep_regions() -> void:
	var ability := TwinSweepingPullScript.new()
	var first := ability.get_relative_sweep_regions(MovementSlotResolverScript.REGION_NORTH, -1)
	var second := ability.get_relative_sweep_regions(MovementSlotResolverScript.REGION_NORTH, 1)

	expect_equal(
		first,
		["north", "northwest", "west"],
		"First sweep should travel counterclockwise from north."
	)
	expect_equal(
		second,
		["north", "northeast", "east"],
		"Second sweep should travel clockwise from north."
	)


func test_forced_pull_interpolation() -> void:
	var boss := MockBoss.new()
	var unit := MockUnit.new()
	get_tree().root.add_child(boss)
	get_tree().root.add_child(unit)

	boss.global_position = Vector2.ZERO
	unit.global_position = Vector2(600.0, 400.0)
	var start_position := unit.global_position

	var ability := TwinSweepingPullScript.new()
	ability.pull_region_override = MovementSlotResolverScript.REGION_NORTH
	ability.on_cast_start(boss, [unit])

	var destination := MovementSlotResolverScript.get_slot_position(
		boss,
		MovementSlotResolverScript.REGION_NORTH,
		MovementSlotResolverScript.RANGE_CLOSE
	)

	ability.on_cast_update(boss, [unit], 0.5, 6.5)
	expect_vector(
		unit.global_position,
		start_position.lerp(destination, 0.5),
		"The pull should interpolate halfway at 0.5 seconds."
	)

	ability.on_cast_update(boss, [unit], 1.0, 6.0)
	expect_vector(unit.global_position, destination, "The pull should finish exactly at one second.")
	expect_true(ability.pull_completed, "The pull should mark itself complete.")
	expect_true(unit.manual_move_clear_count >= 2, "The pull should clear conflicting movement orders.")
	expect_true(unit.stop_movement_count >= 2, "The pull should stop unit movement at start and finish.")

	boss.queue_free()
	unit.queue_free()


func test_timed_sweep_damage_and_final_resolution() -> void:
	var boss := MockBoss.new()
	var first_danger := MockUnit.new()
	var second_danger := MockUnit.new()
	var far_safe := MockUnit.new()
	var units: Array = [first_danger, second_danger, far_safe]

	get_tree().root.add_child(boss)
	for unit in units:
		get_tree().root.add_child(unit)

	var ability := TwinSweepingPullScript.new()
	ability.pull_region_override = MovementSlotResolverScript.REGION_NORTH
	ability.on_cast_start(boss, units)
	ability.on_cast_update(boss, units, 1.0, 6.0)

	first_danger.global_position = get_slot(boss, "northwest", "close")
	second_danger.global_position = get_slot(boss, "northeast", "mid")
	far_safe.global_position = get_slot(boss, "north", "far")

	ability.on_cast_update(boss, units, 2.99, 4.01)
	expect_equal(first_danger.health, 300, "The first sweep must not resolve before three seconds.")

	ability.on_cast_update(boss, units, 3.0, 4.0)
	expect_equal(first_danger.health, 225, "The first sweep should hit its counterclockwise close lane.")
	expect_equal(second_danger.health, 300, "The clockwise lane should be safe from the first sweep.")
	expect_equal(far_safe.health, 300, "Far range should be outside both sweeps.")
	expect_equal(boss.impact_calls.size(), 3, "The first sweep should show one impact per affected region.")

	ability.on_cast_update(boss, units, 6.99, 0.01)
	expect_equal(second_danger.health, 300, "The second sweep must not resolve before seven seconds.")

	ability.on_cast_update(boss, units, 7.0, 0.0)
	expect_equal(second_danger.health, 225, "The second sweep should hit its clockwise mid lane.")
	expect_equal(first_danger.health, 225, "The counterclockwise lane should be safe from the second sweep.")
	expect_equal(boss.impact_calls.size(), 6, "Both sweeps should show six total regional impacts.")

	ability.resolve(boss, units)
	expect_equal(second_danger.health, 225, "Final resolution must not duplicate timed sweep damage.")

	boss.queue_free()
	for unit in units:
		unit.queue_free()


func test_resolve_fallback_finishes_every_phase() -> void:
	var boss := MockBoss.new()
	var unit := MockUnit.new()
	get_tree().root.add_child(boss)
	get_tree().root.add_child(unit)

	var ability := TwinSweepingPullScript.new()
	ability.pull_region_override = MovementSlotResolverScript.REGION_SOUTH
	ability.on_cast_start(boss, [unit])
	ability.resolve(boss, [unit])

	expect_true(ability.pull_completed, "Fallback resolution should complete the forced pull.")
	expect_true(ability.first_sweep_resolved, "Fallback resolution should resolve the first sweep.")
	expect_true(ability.second_sweep_resolved, "Fallback resolution should resolve the second sweep.")
	expect_equal(unit.health, 150, "A unit left in the pull lane should be hit by both fallback sweeps.")

	boss.queue_free()
	unit.queue_free()


func test_boss_cast_lifecycle() -> void:
	var boss = BossScript.new()
	var unit := MockUnit.new()
	get_tree().root.add_child(boss)
	get_tree().root.add_child(unit)

	boss.ability_ids = [BossAbilityFactoryScript.ABILITY_TWIN_SWEEPING_PULL]
	boss.next_ability_index = 0
	boss.next_ability = boss.create_next_ability()
	boss.next_ability.pull_region_override = MovementSlotResolverScript.REGION_NORTH
	boss.set_party_members([unit])
	boss.set_target(unit)
	boss.start_special_cast()

	expect_true(boss.is_casting_ability(), "Boss should enter its casting state.")
	expect_equal(boss.get_cast_name(), "North Pull", "Boss should expose the pull phase name.")

	boss.update_special_cast(1.0)
	expect_equal(
		boss.get_cast_name(),
		"First Sweep (Counterclockwise)",
		"Boss should advance to the first sweep after one second."
	)

	unit.global_position = get_slot(boss, "northwest", "close")
	boss.update_special_cast(2.0)
	expect_equal(unit.health, 225, "Boss lifecycle should resolve first-sweep damage at three seconds.")
	expect_equal(
		boss.get_cast_name(),
		"Second Sweep (Clockwise)",
		"Boss should expose the second sweep after the first impact."
	)

	unit.global_position = get_slot(boss, "northeast", "mid")
	boss.update_special_cast(4.0)
	expect_equal(unit.health, 150, "Boss lifecycle should resolve second-sweep damage at seven seconds.")
	expect_true(not boss.is_casting_ability(), "Boss should leave its casting state after the second sweep.")
	expect_true(boss.current_ability == null, "Boss should release the completed ability instance.")

	boss.queue_free()
	unit.queue_free()


func get_slot(boss: Node, region: String, range_name: String) -> Vector2:
	return MovementSlotResolverScript.get_slot_position(boss, region, range_name)


func expect_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append(message + " Expected %s, got %s." % [expected, actual])


func expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append(message + " Expected %s, got %s." % [expected, actual])


func expect_vector(actual: Vector2, expected: Vector2, message: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append(message + " Expected %s, got %s." % [expected, actual])
