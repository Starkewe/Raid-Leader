extends Node

const BossScript := preload("res://scripts/units/boss.gd")
const BossAbilityScript := preload("res://scripts/abilities/boss_ability.gd")
const BossAbilityFactoryScript := preload("res://scripts/abilities/boss_ability_factory.gd")
const TwinSweepingPullScript := preload("res://scripts/abilities/twin_sweeping_pull.gd")
const EARTHGNASHER: EncounterDefinition = preload("res://data/encounters/ogre.tres")
const CHAINMASTER: EncounterDefinition = preload("res://data/encounters/chainmaster.tres")


class DummyTarget:
	extends Node2D

	var damage_events: int = 0
	var damage_received: int = 0
	var status_stacks: int = 3

	func is_alive() -> bool:
		return true

	func take_damage(
		_amount: int,
		_source: Node = null,
		_ability_id: String = "",
		_metadata: Dictionary = {}
	) -> void:
		damage_events += 1
		damage_received += _amount

	func get_status_effect_stacks(_effect_id: String) -> int:
		return status_stacks

	func apply_status_effect(_definition: StatusEffectDefinition, _source: Node) -> void:
		status_stacks += 1

	func get_unit_display_name() -> String:
		return "Timer Target"


class StompTarget:
	extends Node2D

	var roles: Array[String] = []
	var damage_received: int = 0
	var movement_calls: int = 0

	func is_alive() -> bool:
		return true

	func has_role(role_name: String) -> bool:
		return roles.has(role_name)

	func take_damage(
		amount: int,
		_source: Node = null,
		_ability_id: String = "",
		_metadata: Dictionary = {}
	) -> void:
		damage_received += amount

	func start_forced_movement(_destination: Vector2, _duration: float) -> void:
		movement_calls += 1


class ForcedPullTarget:
	extends Node2D

	var start_calls: int = 0
	var finish_calls: int = 0
	var clear_calls: int = 0
	var stop_calls: int = 0
	var forced_destination: Vector2 = Vector2.ZERO

	func is_alive() -> bool:
		return true

	func start_forced_movement(destination: Vector2, _duration: float) -> void:
		start_calls += 1
		forced_destination = destination

	func finish_forced_movement() -> void:
		finish_calls += 1

	func clear_manual_move_order() -> void:
		clear_calls += 1

	func stop_movement() -> void:
		stop_calls += 1


var failures: Array[String] = []
var owned_nodes: Array[Node] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_deferred_phase_transitions()
	_test_frenzy_ability_loadout_and_rotation()
	_test_frenzy_preserves_empowered_slam_threshold()
	_test_frenzy_weapon_modifiers()
	_test_scheduler_cooldowns_and_variance()
	_test_disallowed_queue_skips_forward()
	_test_twin_starts_phase_adjusted_auto_recovery()
	_test_twin_recovery_gates_auto_and_preserves_state()
	_test_twin_forced_pull_cleanup()
	_test_other_special_recovery_does_not_reset_auto()
	_test_chainmaster_transition_behavior()
	_test_earthshaker_stomp_tank_exemptions()

	for node in owned_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()

	if failures.is_empty():
		print("Earthgnasher phase rollover and Twin recovery regressions passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)

	get_tree().quit(1)


func _test_deferred_phase_transitions() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var target := DummyTarget.new()
	add_child(target)
	owned_nodes.append(target)
	target.global_position = boss.global_position + Vector2(160.0, 0.0)
	boss.set_party_members([target])
	boss.set_target(target)
	boss.attack_timer = 0.73
	boss.special_timer = 2.4
	boss.next_ability = _ability_for_id(boss, "grabbing_roar")

	boss.health = int(float(boss.max_health) * 0.60)
	boss.update_current_phase()

	_expect(
		boss.get_current_phase_id() == "phase_1"
		and boss.pending_phase == _get_phase(boss, "phase_2")
		and boss.phase_transition_pending,
		"Earthgnasher applied Phase 2 before its transition began."
	)
	_expect(
		boss.get_status_text() == "You will not break my ground!",
		"Phase 2 transition text did not appear through the boss status API."
	)
	_expect_close(
		boss.get_effective_attack_cooldown(),
		boss.attack_cooldown,
		"Phase 2 attack speed applied during the intermission."
	)
	boss.auto_attack()
	_expect(
		target.damage_events == 0,
		"The boss performed a normal attack during the Phase 2 intermission."
	)

	boss.start_special_cast()
	_expect(
		boss.is_casting
		and boss.current_ability_is_phase_transition
		and boss.current_ability.ability_id == "earthgnasher_phase_2_transition"
		and is_equal_approx(boss.cast_timer, 5.0)
		and boss.get_current_phase_id() == "phase_1",
		"The five-second Phase 2 transition did not start while Phase 1 remained active."
	)
	boss.take_damage(100, target, "test_damage")
	_expect(
		boss.health == int(float(boss.max_health) * 0.60) - 100
		and boss.get_current_phase_id() == "phase_1",
		"The boss could not receive damage while its Phase 2 transition was casting."
	)
	boss.update_special_cast(4.99)
	_expect(
		boss.is_casting and boss.get_current_phase_id() == "phase_1",
		"Phase 2 completed before its full five-second cast elapsed."
	)
	boss.update_special_cast(0.01)
	_expect(
		not boss.is_casting
		and not boss.phase_transition_pending
		and boss.get_current_phase_id() == "phase_2"
		and boss.pending_phase == null,
		"Phase 2 did not apply when its five-second transition resolved."
	)
	_expect_close(
		boss.attack_timer,
		boss.attack_cooldown / _get_phase(boss, "phase_2").attack_speed_multiplier,
		"Phase 2 did not reset the basic-attack timer with the newly applied phase."
	)
	_expect_close(
		boss.special_timer,
		boss.get_effective_ability_base_gap(),
		"The existing four-second special-ability gap was not preserved after Phase 2."
	)

	boss.health = int(float(boss.max_health) * 0.25)
	boss.update_current_phase()
	_expect(
		boss.get_current_phase_id() == "phase_2"
		and boss.pending_phase == _get_phase(boss, "phase_3")
		and boss.phase_transition_pending
		and boss.get_status_text() == "Enough! I will tear you apart with my bare hands!",
		"Frenzy did not queue its eight-second transition while Phase 2 remained active."
	)
	boss.start_special_cast()
	boss.update_special_cast(7.99)
	_expect(
		boss.is_casting and boss.get_current_phase_id() == "phase_2",
		"Frenzy's transition did not retain Phase 2 for the full eight-second pause."
	)
	boss.update_special_cast(0.01)
	_expect(
		boss.get_current_phase_id() == "phase_3"
		and boss.get_basic_attack_weapon_mode() == "fists"
		and boss.pending_phase == null,
		"Frenzy weapon state did not apply after its transition resolved."
	)


func _test_frenzy_ability_loadout_and_rotation() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var phase_one := _get_phase(boss, "phase_1")
	var phase_two := _get_phase(boss, "phase_2")
	var frenzy := _get_phase(boss, "phase_3")
	_expect(
		phase_one != null
		and phase_two != null
		and phase_one.allows_ability("boulder_toss")
		and phase_two.allows_ability("boulder_toss"),
		"Boulder Toss was removed from an earlier Earthgnasher phase."
	)
	_expect(
		frenzy != null
		and frenzy.enabled_ability_ids == ["earthshaker_stomp"]
		and frenzy.allows_ability("earthshaker_stomp")
		and not frenzy.allows_ability("boulder_toss"),
		"Frenzy did not retain only Earthshaker Stomp in its enabled ability list."
	)
	var queued_boulder = _ability_for_id(boss, "boulder_toss")
	boss.next_ability = queued_boulder
	boss.attack_timer = 1.1
	boss.special_timer = 3.2

	_activate_phase_immediately(boss, 25.0, "phase_3")

	_expect(
		boss.next_ability != queued_boulder
		and boss.next_ability != null
		and boss.next_ability.ability_id == "earthshaker_stomp"
		and boss.next_ability_index == 3,
		"Frenzy did not replace a queued Boulder Toss with Earthshaker Stomp."
	)
	_expect_close(
		boss.attack_timer,
		1.1,
		"Frenzy changed the raw remaining basic-attack timer."
	)
	_expect_close(
		boss.special_timer,
		3.2,
		"Frenzy changed the raw remaining special timer."
	)

	var following_ids: Array[String] = []

	for _iteration in range(4):
		var ability = boss.create_next_ability()
		following_ids.append("" if ability == null else ability.ability_id)

	_expect(
		following_ids == [
			"earthshaker_stomp",
			"earthshaker_stomp",
			"earthshaker_stomp",
			"earthshaker_stomp"
		],
		"Frenzy did not repeat Earthshaker Stomp without Boulder Toss: "
		+ str(following_ids)
	)


func _test_frenzy_preserves_empowered_slam_threshold() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var target := DummyTarget.new()
	add_child(target)
	owned_nodes.append(target)
	target.global_position = boss.global_position + Vector2(160.0, 0.0)
	boss.set_party_members([target])
	boss.set_target(target)
	boss.basic_attack_trigger_count = 4

	_activate_phase_immediately(boss, 25.0, "phase_3")

	_expect(
		boss.basic_attack_triggered_ability_definition != null
		and boss.basic_attack_triggered_ability_definition.ability_id == "empowered_slam"
		and boss.basic_attack_trigger_threshold == 10
		and boss.get_current_basic_attack_trigger_threshold() == 5,
		"Frenzy changed the Empowered Slam configuration or five-Slam threshold."
	)
	_expect(
		boss.basic_attack_trigger_count == 4
		and boss.get_basic_attack_trigger_reason(target) == "",
		"Frenzy did not preserve the four-of-five Empowered Slam charge state."
	)

	boss.advance_basic_attack_trigger_sequence()
	_expect(
		boss.basic_attack_trigger_count == 5
		and boss.get_basic_attack_trigger_reason(target) == "charge_threshold",
		"Empowered Slam did not become ready on the fifth Frenzy Slam."
	)

	var empowered_slam := _ability_for_id(boss, "empowered_slam")
	_expect(
		empowered_slam != null
		and empowered_slam.damage == 40
		and empowered_slam.get_scaled_damage(boss, empowered_slam.damage) == 50,
		"Empowered Slam did not preserve 40 base damage and Frenzy scaling."
	)


func _test_frenzy_weapon_modifiers() -> void:
	var boss = _new_boss(EARTHGNASHER)
	_activate_phase_immediately(boss, 25.0, "phase_3")
	var target := DummyTarget.new()
	add_child(target)
	owned_nodes.append(target)
	target.global_position = boss.global_position + Vector2(160.0, 0.0)
	boss.set_party_members([target])
	boss.set_target(target)
	boss.attack_damage = 100
	boss.attack_timer = 0.0

	_expect(
		boss.get_basic_attack_weapon_mode() == "fists"
		and is_equal_approx(boss.get_basic_attack_weapon_damage_multiplier(), 0.5)
		and is_equal_approx(boss.get_basic_attack_weapon_speed_multiplier(), 2.0),
		"Frenzy did not expose its fists weapon state and modifiers."
	)
	_expect_close(
		boss.get_attack_damage_multiplier(),
		1.25 * 0.5,
		"Frenzy's fists did not halve its existing basic-attack damage scaling."
	)
	_expect_close(
		boss.get_effective_attack_cooldown(),
		boss.attack_cooldown / 1.45 / 2.0,
		"Frenzy's fists did not double its existing basic-attack speed."
	)

	boss.auto_attack()
	_expect(
		target.damage_received == 63,
		"Frenzy's basic attack did not deal half of its existing scaled damage."
	)


func _test_scheduler_cooldowns_and_variance() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var phase_two := _get_phase(boss, "phase_2")
	var frenzy := _get_phase(boss, "phase_3")
	boss.current_phase = phase_two
	boss.ability_cooldown_remaining = {
		"twin_sweeping_pull": 5.0,
		"grabbing_roar": 7.0,
		"earthshaker_stomp": 9.0,
		"boulder_toss": 11.0
	}
	var soonest = boss.create_next_ability()
	_expect(
		soonest != null and soonest.ability_id == "twin_sweeping_pull",
		"The scheduler did not select the soonest available ability when all skills were cooling down."
	)

	boss.current_phase = frenzy
	boss.ability_cooldown_remaining.clear()
	boss.ability_cooldown_variance = 0.0
	var stomp: BossAbility = _ability_for_id(boss, "earthshaker_stomp")
	boss.current_ability = stomp
	boss.is_casting = true
	boss.current_ability_is_phase_transition = false
	boss.current_ability_is_basic_attack_trigger = false
	boss.finish_special_cast()
	var expected_stomp_recovery: float = (
		stomp.cooldown
		* frenzy.ability_cooldown_multiplier
		/ frenzy.ability_speed_multiplier
	)
	_expect_close(
		boss.get_ability_cooldown_remaining("earthshaker_stomp"),
		expected_stomp_recovery,
		"The scheduler did not retain Earthshaker Stomp's phase-adjusted cooldown."
	)
	_expect_close(
		boss.special_timer,
		expected_stomp_recovery,
		"Frenzy did not wait for Earthshaker Stomp's cooldown after the 4-second base gap."
	)

	var seeded_a = _new_boss(EARTHGNASHER)
	var seeded_b = _new_boss(EARTHGNASHER)
	var seeded_phase := _get_phase(seeded_a, "phase_2")
	var seeded_ability := _ability_for_id(seeded_a, "earthshaker_stomp")
	var nominal_recovery: float = (
		seeded_ability.cooldown
		* seeded_phase.ability_cooldown_multiplier
		/ seeded_phase.ability_speed_multiplier
	)

	for seeded_boss in [seeded_a, seeded_b]:
		seeded_boss.current_phase = seeded_phase
		seeded_boss.ability_cooldown_variance = 0.05
		seeded_boss.ability_random_seed = 987654
		seeded_boss.ability_rng_initialized = false

	var varied_a: float = seeded_a.get_randomized_ability_recovery_time(seeded_ability)
	var varied_b: float = seeded_b.get_randomized_ability_recovery_time(
		_ability_for_id(seeded_b, "earthshaker_stomp")
	)
	_expect(
		varied_a >= nominal_recovery * 0.95
		and varied_a <= nominal_recovery * 1.05
		and is_equal_approx(varied_a, varied_b),
		"Per-fight cooldown variance was not bounded and reproducible from its seed."
	)


func _test_disallowed_queue_skips_forward() -> void:
	var twin_boss = _new_boss(EARTHGNASHER)
	twin_boss.next_ability = _ability_for_id(twin_boss, "twin_sweeping_pull")
	twin_boss.special_timer = 1.7
	_activate_phase_immediately(twin_boss, 25.0, "phase_3")
	_expect(
		twin_boss.next_ability != null
		and twin_boss.next_ability.ability_id == "earthshaker_stomp"
		and twin_boss.next_ability_index == 3,
		"Frenzy did not skip forward from queued Twin to Earthshaker Stomp."
	)
	_expect_close(
		twin_boss.special_timer,
		1.7,
		"Skipping a forbidden Twin changed the remaining special timer."
	)

	var roar_boss = _new_boss(EARTHGNASHER)
	roar_boss.next_ability = _ability_for_id(roar_boss, "grabbing_roar")
	roar_boss.special_timer = 0.45
	_activate_phase_immediately(roar_boss, 25.0, "phase_3")
	_expect(
		roar_boss.next_ability != null
		and roar_boss.next_ability.ability_id == "earthshaker_stomp"
		and roar_boss.next_ability_index == 3,
		"Frenzy did not skip forward from queued Roar to Earthshaker Stomp."
	)
	_expect_close(
		roar_boss.special_timer,
		0.45,
		"Skipping a forbidden Roar changed the remaining special timer."
	)
	var after_stomp = roar_boss.create_next_ability()
	_expect(
		after_stomp != null and after_stomp.ability_id == "earthshaker_stomp",
		"The filtered rotation did not continue repeating Earthshaker Stomp."
	)


func _test_twin_starts_phase_adjusted_auto_recovery() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var timer_before_resolve := [0.0, 0.37, 0.0]

	for phase_index in range(boss.phase_definitions.size()):
		boss.current_phase = boss.phase_definitions[phase_index]
		boss.attack_timer = timer_before_resolve[phase_index]
		boss.basic_attack_sequence_count = 6
		boss.basic_attack_trigger_count = 4
		var twin = _resolved_twin(boss)
		twin.resolve(boss, [])
		_expect_close(
			boss.attack_timer,
			boss.get_effective_attack_cooldown(),
			"Twin did not begin a full effective auto recovery in "
			+ boss.current_phase.display_name + "."
		)
		_expect(
			boss.basic_attack_sequence_count == 6
			and boss.basic_attack_trigger_count == 4,
			"Twin's auto recovery changed attack or Slam charge state in "
			+ boss.current_phase.display_name + "."
		)


func _test_twin_recovery_gates_auto_and_preserves_state() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var target := DummyTarget.new()
	add_child(target)
	owned_nodes.append(target)
	target.global_position = Vector2(160.0, 0.0)
	boss.set_party_members([target])
	boss.set_target(target)
	boss.basic_attack_triggered_ability_definition = null
	boss.basic_attack_sequence_count = 8
	boss.basic_attack_trigger_count = 3
	var twin = _resolved_twin(boss)
	twin.resolve(boss, [target])

	_expect(
		target.damage_events == 0
		and target.status_stacks == 3
		and boss.basic_attack_sequence_count == 8
		and boss.basic_attack_trigger_count == 3,
		"Resolving Twin changed damage, vulnerability, or attack charge state."
	)
	boss.auto_attack()
	boss.attack_timer = 0.001
	boss.auto_attack()
	_expect(
		target.damage_events == 0 and target.status_stacks == 3,
		"A Slam landed before Twin's new auto recovery expired."
	)

	boss.attack_timer = 0.0
	boss.auto_attack()
	_expect(
		target.damage_events == 1 and target.status_stacks == 4,
		"Slam did not become available when Twin's auto recovery expired."
	)


func _test_twin_forced_pull_cleanup() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var target := ForcedPullTarget.new()
	add_child(target)
	owned_nodes.append(target)
	var twin := TwinSweepingPullScript.new()
	twin.pull_region_override = "northeast"
	twin.pull_range = MovementSlotResolver.RANGE_CLOSE
	twin.start_forced_pull(boss, [target])

	_expect(
		target.start_calls == 1
		and twin.pull_start_positions.size() == 1
		and twin.pull_start_positions[0].get("unit") == target,
		"Twin did not retain a forced-pull unit reference safely."
	)

	twin.finish_forced_pull()
	_expect(
		target.finish_calls == 1
		and target.clear_calls == 1
		and target.stop_calls == 1
		and twin.pull_start_positions.is_empty(),
		"Twin forced-pull cleanup could not finish a stored unit reference."
	)


func _test_other_special_recovery_does_not_reset_auto() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var phase_two := _get_phase(boss, "phase_2")
	boss.current_phase = phase_two
	boss.attack_timer = 0.62
	var other_ability = BossAbilityScript.new()
	other_ability.ability_id = "ordinary_special"
	other_ability.ability_name = "Ordinary Special"
	other_ability.cooldown = 4.0
	boss.current_ability = other_ability
	boss.is_casting = true
	boss.current_ability_is_phase_transition = false
	boss.current_ability_is_basic_attack_trigger = false
	boss.finish_special_cast()

	_expect_close(
		boss.attack_timer,
		0.62,
		"A non-Twin special reset the basic-attack timer."
	)
	_expect_close(
		boss.special_timer,
		boss.get_effective_ability_base_gap(),
		"Normal special recovery did not respect the global ability gap."
	)

	var twin = _resolved_twin(boss)
	boss.attack_timer = 0.0
	boss.basic_attack_sequence_count = 5
	boss.basic_attack_trigger_count = 2
	boss.current_ability = twin
	boss.is_casting = true
	boss.finish_special_cast()
	_expect_close(
		boss.special_timer,
		boss.get_effective_ability_base_gap(),
		"Twin's short cooldown did not respect the global ability gap."
	)
	_expect_close(
		boss.attack_timer,
		boss.attack_cooldown / phase_two.attack_speed_multiplier,
		"Finishing Twin did not start its full phase-adjusted auto recovery."
	)
	_expect(
		boss.basic_attack_sequence_count == 5
		and boss.basic_attack_trigger_count == 2,
		"Finishing Twin changed attack counters or Empowered Slam charge state."
	)


func _test_chainmaster_transition_behavior() -> void:
	var boss = _new_boss(CHAINMASTER)
	boss.next_ability = boss.create_next_ability()
	boss.attack_timer = 0.8
	boss.special_timer = 2.6
	boss.basic_attack_sequence_count = 2
	boss.current_ability = BossAbilityScript.new()
	boss.is_casting = true
	boss.cast_timer = 1.4

	_enter_phase(boss, 60.0)

	_expect(
		boss.get_current_phase_id() == "phase_2"
		and boss.phase_transition_pending
		and boss.pending_phase_transition_definition != null
		and boss.pending_phase_transition_definition.ability_id == "break_the_kennels",
		"Chainmaster's scripted Phase 2 transition was not queued."
	)
	_expect(
		not boss.is_casting
		and boss.current_ability == null
		and is_zero_approx(boss.special_timer)
		and boss.basic_attack_sequence_count == 0,
		"Chainmaster's scripted transition no longer interrupts and takes priority."
	)
	_expect_close(
		boss.attack_timer,
		0.8,
		"Queueing Chainmaster's scripted transition changed its auto timer early."
	)
	var has_next_normal_ability := false
	for definition in boss.ability_definitions:
		if (
			boss.next_ability != null
			and definition != null
			and definition.ability_id == boss.next_ability.ability_id
		):
			has_next_normal_ability = true
			break
	_expect(
		boss.next_ability != null
		and has_next_normal_ability,
		"Chainmaster's explicit transition did not resume its normal ability scheduler."
	)


func _test_earthshaker_stomp_tank_exemptions() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var resolver := preload("res://scripts/combat/movement_slot_resolver.gd")
	var main_tank := StompTarget.new()
	main_tank.roles = ["tank"]
	var off_tank := StompTarget.new()
	off_tank.roles = ["tank"]
	var melee_dps := StompTarget.new()
	var healer := StompTarget.new()

	for unit in [main_tank, off_tank, melee_dps, healer]:
		add_child(unit)
		owned_nodes.append(unit)

	main_tank.global_position = resolver.get_slot_position(
		boss, "south", "close"
	)
	off_tank.global_position = resolver.get_slot_position(
		boss, "east", "close"
	)
	melee_dps.global_position = resolver.get_slot_position(
		boss, "north", "mid"
	)
	healer.global_position = resolver.get_slot_position(
		boss, "west", "mid"
	)

	var party: Array = [main_tank, off_tank, melee_dps, healer]
	boss.set_party_members(party)
	boss.set_target(main_tank)
	var stomp: BossAbility = _ability_for_id(boss, "earthshaker_stomp")
	stomp.resolve(boss, party)

	_expect(
		main_tank.movement_calls == 0 and off_tank.movement_calls == 0,
		"Earthshaker Stomp moved a main tank or off tank."
	)
	_expect(
		melee_dps.movement_calls == 1 and healer.movement_calls == 1,
		"Earthshaker Stomp stopped moving non-tanks outward."
	)
	_expect(
		main_tank.damage_received == 8
		and off_tank.damage_received == 8
		and melee_dps.damage_received == 8
		and healer.damage_received == 8,
		"Earthshaker Stomp did not damage every affected unit, including tanks."
	)


func _new_boss(definition: EncounterDefinition):
	var boss = BossScript.new()
	add_child(boss)
	owned_nodes.append(boss)
	boss.debug_logging_enabled = false
	boss.encounter_definition = definition
	boss.boss_display_name = definition.boss_display_name
	boss.max_health = definition.max_health
	boss.health = definition.max_health
	boss.attack_damage = definition.attack_damage
	boss.attack_cooldown = definition.attack_cooldown
	boss.basic_attack_id = definition.basic_attack_id
	boss.basic_attack_display_name = definition.basic_attack_display_name
	boss.basic_attack_status_effect = definition.basic_attack_status_effect
	boss.basic_attack_targeting_mode = definition.basic_attack_targeting_mode
	boss.basic_attack_secondary_damage = definition.basic_attack_secondary_damage
	boss.basic_attack_secondary_target_count = definition.basic_attack_secondary_target_count
	boss.basic_attack_secondary_damage_multiplier = (
		definition.basic_attack_secondary_damage_multiplier
	)
	boss.basic_attack_triggered_ability_definition = definition.basic_attack_triggered_ability
	boss.basic_attack_trigger_threshold = definition.basic_attack_trigger_threshold
	boss.basic_attack_trigger_when_target_outside_required_range = (
		definition.basic_attack_trigger_when_target_outside_required_range
	)
	boss.basic_attack_required_range = definition.basic_attack_required_range
	boss.ability_base_gap = definition.ability_base_gap
	boss.ability_cooldown_variance = 0.0
	boss.ability_random_seed = 12345
	boss.ability_rng_initialized = false
	boss.ability_definitions = definition.abilities.duplicate()
	boss.phase_definitions = definition.phases.duplicate()
	boss.phase_definitions.sort_custom(func(a: BossPhaseDefinition, b: BossPhaseDefinition):
		return a.starts_at_health_percent > b.starts_at_health_percent
	)
	boss.current_phase = null
	boss.next_ability_index = 0
	boss.next_ability = null
	boss.current_ability = null
	boss.is_casting = false
	boss.phase_transition_pending = false
	boss.pending_phase_transition_definition = null
	boss.update_current_phase(false)
	return boss


func _resolved_twin(boss) -> TwinSweepingPull:
	var twin = TwinSweepingPullScript.new()
	twin.configure(boss.ability_definitions[0])
	twin.pull_completed = true
	twin.first_sweep_resolved = true
	twin.second_sweep_resolved = true
	return twin


func _ability_for_id(boss, ability_id: String) -> BossAbility:
	for definition in boss.ability_definitions:
		if definition != null and definition.ability_id == ability_id:
			return BossAbilityFactoryScript.create_ability_from_definition(definition)

	return null


func _get_phase(boss, phase_id: String) -> BossPhaseDefinition:
	for phase in boss.phase_definitions:
		if phase != null and phase.phase_id == phase_id:
			return phase

	return null


func _enter_phase(boss, health_percent: float) -> void:
	boss.health = int(floor(float(boss.max_health) * health_percent / 100.0))
	boss.update_current_phase()


func _activate_phase_immediately(
	boss,
	health_percent: float,
	phase_id: String
) -> void:
	boss.health = int(floor(float(boss.max_health) * health_percent / 100.0))
	boss.current_phase = _get_phase(boss, phase_id)
	boss.phase_transition_pending = false
	boss.pending_phase_transition_definition = null
	boss.pending_phase = null
	boss.pending_phase_definition = null
	boss.next_ability_index = 0
	boss.next_ability = boss.create_next_ability()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _expect_close(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append(message + " Expected " + str(expected) + ", got " + str(actual) + ".")
