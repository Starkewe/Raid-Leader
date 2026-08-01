extends Node

const BossScript := preload("res://scripts/units/boss.gd")
const BossAbilityScript := preload("res://scripts/abilities/boss_ability.gd")
const TwinSweepingPullScript := preload("res://scripts/abilities/twin_sweeping_pull.gd")
const EARTHGNASHER: EncounterDefinition = preload("res://data/encounters/ogre.tres")
const CHAINMASTER: EncounterDefinition = preload("res://data/encounters/chainmaster.tres")


class DummyTarget:
	extends Node2D

	var damage_events: int = 0
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

	func get_status_effect_stacks(_effect_id: String) -> int:
		return status_stacks

	func apply_status_effect(_definition: StatusEffectDefinition, _source: Node) -> void:
		status_stacks += 1

	func get_unit_display_name() -> String:
		return "Timer Target"


var failures: Array[String] = []
var owned_nodes: Array[Node] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ordinary_phase_rollover()
	_test_allowed_queue_and_canonical_frenzy_rotation()
	_test_disallowed_queue_skips_forward()
	_test_twin_starts_phase_adjusted_auto_recovery()
	_test_twin_recovery_gates_auto_and_preserves_state()
	_test_other_special_recovery_does_not_reset_auto()
	_test_chainmaster_transition_behavior()

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


func _test_ordinary_phase_rollover() -> void:
	var boss = _new_boss(EARTHGNASHER)
	var active_twin = boss.next_ability
	boss.current_ability = active_twin
	boss.next_ability = boss.create_next_ability()
	boss.is_casting = true
	boss.current_cast_speed_multiplier = 1.0
	boss.cast_timer = 4.25
	boss.current_cast_elapsed = 2.75
	boss.attack_timer = 0.73
	boss.special_timer = 2.4
	var queued_roar = boss.next_ability

	_enter_phase(boss, 60.0)

	_expect(
		boss.get_current_phase_id() == "phase_2",
		"Earthgnasher did not enter Phase 2."
	)
	_expect_close(
		boss.attack_timer,
		0.73,
		"Phase 2 rescaled or restarted the remaining basic-attack timer."
	)
	_expect_close(
		boss.special_timer,
		2.4,
		"Phase 2 rescaled or restarted the remaining special timer."
	)
	_expect(
		boss.next_ability == queued_roar
		and boss.next_ability.ability_id == "grabbing_roar",
		"Phase 2 replaced the queued post-Twin ability instead of preserving it."
	)
	_expect(
		boss.current_ability == active_twin
		and boss.is_casting
		and is_equal_approx(boss.cast_timer, 4.25)
		and is_equal_approx(boss.current_cast_elapsed, 2.75)
		and is_equal_approx(boss.current_cast_speed_multiplier, 1.0),
		"An ordinary phase change altered the cast already in progress."
	)


func _test_allowed_queue_and_canonical_frenzy_rotation() -> void:
	var boss = _new_boss(EARTHGNASHER)
	boss.next_ability = boss.create_next_ability()
	boss.next_ability = boss.create_next_ability()
	boss.next_ability = boss.create_next_ability()
	var queued_boulder = boss.next_ability
	boss.attack_timer = 1.1
	boss.special_timer = 3.2

	_enter_phase(boss, 25.0)

	_expect(
		boss.next_ability == queued_boulder
		and boss.next_ability.ability_id == "boulder_toss",
		"Frenzy replaced an allowed queued Boulder Toss."
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
			"boulder_toss",
			"earthshaker_stomp",
			"boulder_toss"
		],
		"Frenzy did not continue the canonical rotation after the preserved queue: "
		+ str(following_ids)
	)


func _test_disallowed_queue_skips_forward() -> void:
	var twin_boss = _new_boss(EARTHGNASHER)
	twin_boss.special_timer = 1.7
	_enter_phase(twin_boss, 25.0)
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
	roar_boss.next_ability = roar_boss.create_next_ability()
	roar_boss.special_timer = 0.45
	_enter_phase(roar_boss, 25.0)
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
		after_stomp != null and after_stomp.ability_id == "boulder_toss",
		"The filtered rotation restarted instead of continuing to Boulder Toss."
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
			boss.attack_cooldown / boss.current_phase.attack_speed_multiplier,
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
		4.0 * phase_two.ability_cooldown_multiplier / phase_two.ability_speed_multiplier,
		"Normal special recovery changed while adding Twin's auto delay."
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
		twin.cooldown * phase_two.ability_cooldown_multiplier / phase_two.ability_speed_multiplier,
		"Twin's existing special recovery changed."
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
	_expect(
		boss.next_ability != null
		and boss.next_ability.ability_id == CHAINMASTER.abilities[0].ability_id
		and boss.next_ability_index == 1,
		"Chainmaster's explicit transition no longer resets its normal rotation."
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


func _get_phase(boss, phase_id: String) -> BossPhaseDefinition:
	for phase in boss.phase_definitions:
		if phase != null and phase.phase_id == phase_id:
			return phase

	return null


func _enter_phase(boss, health_percent: float) -> void:
	boss.health = int(floor(float(boss.max_health) * health_percent / 100.0))
	boss.update_current_phase()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _expect_close(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append(message + " Expected " + str(expected) + ", got " + str(actual) + ".")
