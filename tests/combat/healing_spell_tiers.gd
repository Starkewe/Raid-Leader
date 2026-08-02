extends Node

const HealingSpellSelectorScript := preload(
	"res://scripts/combat/healing_spell_selector.gd"
)
const HealingTargetSelectorScript := preload(
	"res://scripts/combat/healing_target_selector.gd"
)
const BossScript := preload("res://scripts/units/boss.gd")


class DummyPressureSelector:
	extends RefCounted

	var active_tank: bool = false
	var tank_damage: int = 0
	var raid_pressure_multiplier: float = 1.0

	func is_active_tank(_target: Node) -> bool:
		return active_tank

	func get_projected_tank_damage(
		_target: Node,
		_horizon_seconds: float,
		_fallback_damage_per_second: float
	) -> int:
		return tank_damage

	func get_raid_pressure_multiplier() -> float:
		return raid_pressure_multiplier


class DummyLandingSource:
	extends Node

	var landing_times: Dictionary = {}

	func is_alive() -> bool:
		return true

	func get_pending_heal_landing_time_seconds(reservation_id: String) -> float:
		return float(landing_times.get(reservation_id, -1.0))


var failures: Array[String] = []
var owned_nodes: Array[Node] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_resources_and_policy()
	_test_tier_selection()
	_test_incoming_heal_horizon_and_targeting()
	_test_boss_swing_estimation()
	_test_priest_cast_state_events_and_cadence()
	_test_mage_and_cure_recovery()

	for node in owned_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()

	if failures.is_empty():
		print("Healing spell tier and cast-cadence regressions passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)

	get_tree().quit(1)


func _test_resources_and_policy() -> void:
	var expected := {
		"lesser_heal": {"amount": 10, "cast_time": 1.5},
		"heal": {"amount": 18, "cast_time": 2.0},
		"greater_heal": {"amount": 30, "cast_time": 3.0}
	}

	for action_id in expected:
		var action := load("res://data/unit_actions/%s.tres" % action_id) as UnitActionDefinition
		var values: Dictionary = expected[action_id]
		_expect(action != null, "Healing resource %s did not load." % action_id)

		if action == null:
			continue

		_expect(action.amount == int(values["amount"]), "%s has the wrong amount." % action_id)
		_expect(
			is_equal_approx(action.cast_time, float(values["cast_time"])),
			"%s has the wrong cast time." % action_id
		)
		_expect(is_zero_approx(action.cooldown), "%s retained post-cast recovery." % action_id)

	var fireball := load("res://data/unit_actions/fireball.tres") as UnitActionDefinition
	var cure := load("res://data/unit_actions/cure.tres") as UnitActionDefinition
	_expect(fireball != null and is_zero_approx(fireball.cooldown), "Fireball retained recovery.")
	_expect(
		cure != null
		and is_equal_approx(cure.cast_time, 1.0)
		and is_equal_approx(cure.cooldown, 0.5),
		"Cure timing changed from its one-second cast and half-second recovery."
	)


func _test_tier_selection() -> void:
	var policy := load(
		"res://data/healing/healing_decision_policy.tres"
	) as HealingDecisionPolicy
	var selector = HealingSpellSelectorScript.new()
	selector.setup(policy)
	var pressure := DummyPressureSelector.new()
	var target := _new_unit("TierTarget", 100, 90)

	_expect_action(selector, target, pressure, "lesser_heal", "small deficit")
	target.health = 80
	_expect_action(selector, target, pressure, "heal", "normal deficit")
	target.health = 60
	_expect_action(selector, target, pressure, "greater_heal", "large deficit")
	target.health = 30
	_expect_action(selector, target, pressure, "lesser_heal", "raid emergency")

	pressure.active_tank = true
	target.health = 45
	_expect_action(selector, target, pressure, "lesser_heal", "tank emergency")
	target.health = 80
	pressure.tank_damage = 20
	_expect_action(selector, target, pressure, "greater_heal", "scheduled tank swings")

	pressure.active_tank = false
	pressure.raid_pressure_multiplier = 4.0
	target.health = 80
	_expect_action(selector, target, pressure, "greater_heal", "phase raid pressure")

	var incoming_source := _new_landing_source()
	pressure.raid_pressure_multiplier = 1.0
	target.health = 65
	incoming_source.landing_times["soon"] = 1.0
	target.register_pending_heal("soon", incoming_source, 18, 1.0, "heal", "Heal", 2.0)
	_expect_action(selector, target, pressure, "heal", "near-term incoming healing")
	target.remove_pending_heal("soon")
	incoming_source.landing_times["late"] = 3.0
	target.register_pending_heal(
		"late", incoming_source, 30, 3.0, "greater_heal", "Greater Heal", 3.0
	)
	_expect_action(selector, target, pressure, "greater_heal", "late incoming healing")
	target.remove_pending_heal("late")


func _test_incoming_heal_horizon_and_targeting() -> void:
	var target := _new_unit("ReservationTarget", 100, 40)
	var alternate := _new_unit("AlternateTarget", 100, 70)
	var healer := _new_unit("Healer", 100, 100)
	var source := _new_landing_source()
	source.landing_times = {"soon": 1.0, "late": 3.0}
	target.register_pending_heal("soon", source, 10, 1.0, "lesser_heal", "Lesser Heal", 1.5)
	target.register_pending_heal("late", source, 30, 3.0, "greater_heal", "Greater Heal", 3.0)

	_expect(target.get_incoming_healing_total() == 40, "All incoming heals were not retained.")
	_expect(
		target.get_incoming_healing_total(null, 2.0) == 10,
		"The landing-time horizon included a heal outside the decision window."
	)
	var reservations := target.get_pending_heal_reservations()
	var lesser_reservation: Dictionary = reservations.get("soon", {})
	_expect(
		String(lesser_reservation.get("ability_id", "")) == "lesser_heal"
		and String(lesser_reservation.get("display_name", "")) == "Lesser Heal"
		and int(lesser_reservation.get("amount", 0)) == 10
		and is_equal_approx(float(lesser_reservation.get("cast_time", 0.0)), 1.5),
		"Incoming-heal reservations did not retain selected-tier details."
	)
	target.remove_pending_heal("soon")
	_expect(
		target.get_incoming_healing_total() == 30,
		"Cancelling one reservation removed another healer's reservation."
	)

	var target_selector = HealingTargetSelectorScript.new()
	target.health = 70
	target_selector.setup([target, alternate, healer], [])
	var selection: Dictionary = target_selector.select_target(
		{"type": "class", "value": "ReservationTarget"},
		healer,
		true,
		40.0
	)
	_expect(
		selection.get("target", null) == alternate,
		"A fully reserved target prevented fallback reselection."
	)
	target.remove_pending_heal("late")


func _test_boss_swing_estimation() -> void:
	var tank := _new_unit("SwingTank", 100, 100)
	var boss = BossScript.new()
	get_tree().root.add_child(boss)
	owned_nodes.append(boss)
	boss.set_party_members([tank])
	boss.set_target(tank)
	boss.attack_timer = 0.5
	boss.attack_damage = 10
	boss.attack_cooldown = 1.0
	boss.is_casting = false
	var phase := BossPhaseDefinition.new()
	phase.attack_speed_multiplier = 2.0
	phase.attack_damage_multiplier = 1.5
	boss.current_phase = phase
	_expect(
		boss.estimate_scheduled_basic_attack_damage(tank, 2.0) == 60,
		"Boss swing estimation did not apply timer, cooldown, speed, and damage multipliers."
	)


func _test_priest_cast_state_events_and_cadence() -> void:
	var target := _new_unit("CastTarget", 100, 80)
	var priest_scene := load("res://scenes/units/priest.tscn") as PackedScene
	var priest := priest_scene.instantiate() as Priest
	priest.show_world_cast_bar = true
	get_tree().root.add_child(priest)
	owned_nodes.append(priest)
	var events: Array[Dictionary] = []
	target.combat_event.connect(func(event: Dictionary) -> void:
		var recorded_event := event.duplicate(true)
		recorded_event["encounter_time_seconds"] = 1.0
		events.append(recorded_event)
	)

	_expect(priest.command_heal(target), "Priest rejected a direct Heal assignment.")
	priest.try_start_cast()
	_expect(priest.heal_ability_id == "heal", "Priest did not select the normal Heal tier.")
	var cast_details := priest.get_active_cast_details()
	_expect(
		String(cast_details.get("display_name", "")) == "Heal"
		and int(cast_details.get("amount", 0)) == 18
		and is_equal_approx(float(cast_details.get("cast_time", 0.0)), 2.0)
		and String(cast_details.get("ability_id", "")) == "heal",
		"The active cast did not expose all selected-tier details."
	)
	_expect(
		priest.cast_bar != null
		and String(priest.cast_bar.get_meta("ability_id", "")) == "heal"
		and int(priest.cast_bar.get_meta("amount", 0)) == 18
		and is_equal_approx(float(priest.cast_bar.max_value), 2.0),
		"The cast bar did not retain the selected tier and timing."
	)
	var pending := target.get_pending_heal_reservations()
	var reservation: Dictionary = pending.get(priest.pending_heal_id, {})
	_expect(
		String(reservation.get("ability_id", "")) == "heal"
		and int(reservation.get("amount", 0)) == 18,
		"The live cast reservation did not use the selected tier."
	)
	var primary_reservation_id := priest.pending_heal_id
	var second_priest := Priest.new()
	get_tree().root.add_child(second_priest)
	owned_nodes.append(second_priest)
	second_priest.command_heal(target)
	second_priest.try_start_cast()
	_expect(
		second_priest.heal_ability_id == "lesser_heal",
		"A second Priest did not downgrade its tier for a near-term incoming Heal."
	)
	var secondary_reservation_id := second_priest.pending_heal_id
	second_priest.cancel_current_cast()
	var reservations_after_cancel := target.get_pending_heal_reservations()
	_expect(
		reservations_after_cancel.has(primary_reservation_id)
		and not reservations_after_cancel.has(secondary_reservation_id),
		"Cancelling one Priest removed the wrong incoming-heal reservation."
	)

	priest.finish_cast()
	_expect(is_zero_approx(priest.cooldown_timer), "Heal added recovery after completion.")
	_expect(
		_has_event(events, "cast_started", "heal")
		and _has_event(events, "cast_resolved", "heal")
		and _has_event(events, "healing", "heal"),
		"Structured combat events did not use the selected Heal tier."
	)

	var recorder := AttemptRecorder.new()
	recorder.setup("healing_test")

	for event in events:
		recorder.record_event(event)

	var summary := recorder.finalize("test", 1, 1, "", "")
	var healing_casts: Array = summary.get("healing_casts", [])
	var summarized_cast: Dictionary = healing_casts[0] if not healing_casts.is_empty() else {}
	_expect(
		String(summarized_cast.get("ability_id", "")) == "heal"
		and String(summarized_cast.get("display_name", "")) == "Heal"
		and int(summarized_cast.get("amount", 0)) == 18
		and is_equal_approx(float(summarized_cast.get("cast_time", 0.0)), 2.0),
		"Attempt summaries did not retain the selected tier details."
	)

	for cast_case in [
		{"health": 90, "ability_id": "lesser_heal"},
		{"health": 80, "ability_id": "heal"},
		{"health": 60, "ability_id": "greater_heal"}
	]:
		target.health = int(cast_case["health"])
		priest.refresh_heal_target_for_assignment(true)
		priest.try_start_cast()
		_expect(
			priest.is_casting and priest.heal_ability_id == String(cast_case["ability_id"]),
			"Priest could not begin %s immediately after the previous cast."
			% String(cast_case["ability_id"])
		)
		priest.finish_cast()
		_expect(is_zero_approx(priest.cooldown_timer), "%s added recovery." % cast_case["ability_id"])

	target.health = 70
	priest.refresh_heal_target_for_assignment(true)
	priest.try_start_cast()
	var cancelled_reservation_id := priest.pending_heal_id
	priest.on_manual_move_started()
	_expect(
		not priest.is_casting
		and not target.get_pending_heal_reservations().has(cancelled_reservation_id),
		"Manual movement did not cleanly cancel the selected heal reservation."
	)


func _test_mage_and_cure_recovery() -> void:
	var damage_target := _new_unit("DamageTarget", 100, 100)
	var mage := Mage.new()
	get_tree().root.add_child(mage)
	owned_nodes.append(mage)
	mage.command_attack(damage_target)
	mage.try_start_cast()
	mage.finish_cast()
	_expect(is_zero_approx(mage.cooldown_timer), "Fireball added post-cast recovery.")
	mage.try_start_cast()
	_expect(mage.is_casting, "Mage could not recast immediately after Fireball.")
	mage.cancel_current_cast()

	var cure_target := _new_unit("CureTarget", 100, 100)
	var curable := StatusEffectDefinition.new()
	curable.effect_id = "tier_test_curable"
	curable.is_harmful = true
	curable.dispellable = true
	curable.dispel_category = "cure"
	cure_target.apply_status_effect(curable)
	var priest := Priest.new()
	get_tree().root.add_child(priest)
	owned_nodes.append(priest)
	priest.command_cure(cure_target)
	priest.try_start_cure_cast()
	priest.finish_cast()
	_expect(
		is_equal_approx(priest.cure_cooldown_timer, 0.5),
		"Cure lost its half-second recovery."
	)


func _expect_action(
	selector,
	target: Node,
	pressure,
	expected_action_id: String,
	case_label: String
) -> void:
	var action: UnitActionDefinition = selector.select_spell(target, null, pressure)
	_expect(
		action != null and action.action_id == expected_action_id,
		"Healing policy selected %s instead of %s for %s."
		% [action.action_id if action != null else "none", expected_action_id, case_label]
	)


func _has_event(events: Array[Dictionary], event_type: String, ability_id: String) -> bool:
	for event in events:
		if (
			String(event.get("type", "")) == event_type
			and String(event.get("ability_id", "")) == ability_id
		):
			return true

	return false


func _new_unit(unit_class_name: String, maximum_health: int, current_health: int) -> BaseCombatUnit:
	var unit := BaseCombatUnit.new()
	unit.unit_class = unit_class_name
	unit.max_health = maximum_health
	get_tree().root.add_child(unit)
	unit.health = current_health
	owned_nodes.append(unit)
	return unit


func _new_landing_source() -> DummyLandingSource:
	var source := DummyLandingSource.new()
	get_tree().root.add_child(source)
	owned_nodes.append(source)
	return source


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
