extends Node

const HealingTargetSelectorScript := preload(
	"res://scripts/combat/healing_target_selector.gd"
)
const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")


class DummyThreatSource:
	extends Node

	var current_target: Node = null

	func get_current_target() -> Node:
		return current_target


var failures: Array[String] = []
var owned_nodes: Array[Node] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_heal_command_schema()

	var tank_one := _new_unit("Warrior", 1, 100, 45)
	var tank_two := _new_unit("Warrior", 2, 100, 55)
	var raid_target := _new_unit("Rogue", 1, 100, 35)
	var tie_first := _new_unit("Rogue", 2, 100, 50)
	var tie_larger := _new_unit("Rogue", 3, 200, 100)
	var healer := _new_priest(1)
	var other_healer := _new_priest(2)
	var party := [
		tank_one,
		tank_two,
		raid_target,
		tie_first,
		tie_larger,
		healer,
		other_healer
	]
	var first_enemy := _new_threat_source(tank_one)
	var second_enemy := _new_threat_source(tank_two)
	var selector = HealingTargetSelectorScript.new()
	selector.setup(party, [first_enemy, second_enemy])

	_expect(
		selector.get_active_tanks() == [tank_one, tank_two],
		"All enemy threat holders were not resolved as active tanks."
	)
	_expect(
		not selector.get_living_units_in_scope({"type": "raid"}).has(tank_one)
		and not selector.get_living_units_in_scope({"type": "raid"}).has(tank_two),
		"The raid scope included an active tank."
	)
	_expect(
		selector.get_living_units_in_scope(
			{"type": "class", "value": "Warrior"}
		).has(tank_one),
		"A class scope excluded a matching active tank."
	)
	_expect(
		selector.get_living_units_in_scope(
			{"type": "group", "value": 1}
		).has(tank_one),
		"A group scope excluded a matching active tank."
	)

	first_enemy.current_target = raid_target
	var raid_after_swap := selector.get_living_units_in_scope({"type": "raid"})
	_expect(
		raid_after_swap.has(tank_one) and not raid_after_swap.has(raid_target),
		"The raid scope did not update immediately after a threat swap."
	)

	first_enemy.current_target = tank_one
	raid_target.register_pending_heal("other:1", other_healer, 65)
	var projected_choice: Dictionary = selector.select_target(
		{"type": "class", "value": "Rogue"},
		healer,
		false
	)
	_expect(
		projected_choice.get("target", null) == tie_larger,
		"Committed healing from another healer was not included in target priority."
	)

	raid_target.remove_pending_heal("other:1")
	raid_target.register_pending_heal("self:1", healer, 65)
	var own_reservation_choice: Dictionary = selector.select_target(
		{"type": "class", "value": "Rogue"},
		healer,
		false
	)
	_expect(
		own_reservation_choice.get("target", null) == raid_target,
		"A healer's own reservation disqualified its selected target."
	)
	raid_target.remove_pending_heal("self:1")

	raid_target.health = raid_target.max_health
	var missing_health_tie: Dictionary = selector.select_target(
		{"type": "class", "value": "Rogue"},
		healer,
		false
	)
	_expect(
		missing_health_tie.get("target", null) == tie_larger,
		"Equal projected percentages did not prefer the greatest missing health."
	)

	tie_larger.health = tie_larger.max_health
	var stable_tie := _new_unit("Rogue", 4, 100, 50)
	party.insert(4, stable_tie)
	selector.setup(party, [first_enemy, second_enemy])
	var stable_choice: Dictionary = selector.select_target(
		{"type": "class", "value": "Rogue"},
		healer,
		false
	)
	_expect(
		stable_choice.get("target", null) == tie_first,
		"Equal healing priorities did not use stable roster order."
	)

	var fallback_choice: Dictionary = selector.select_target(
		{"type": "group", "value": 2},
		healer,
		true,
		healer.cast_range_units
	)
	_expect(
		bool(fallback_choice.get("is_fallback", false))
		and fallback_choice.get("target", null) != null,
		"An in-range injured target was not selected as out-of-scope fallback."
	)

	for party_member in party:
		if not selector.get_living_units_in_scope(
			{"type": "group", "value": 2}
		).has(party_member):
			party_member.global_position = Vector2(100000.0, 100000.0)

	var distant_fallback: Dictionary = selector.select_target(
		{"type": "group", "value": 2},
		healer,
		true,
		healer.cast_range_units
	)
	_expect(
		distant_fallback.get("target", null) == null,
		"Out-of-scope fallback selected a target that required movement."
	)

	for party_member in party:
		party_member.global_position = Vector2.ZERO

	_expect(
		healer.command_heal_scope(
			{"type": "class", "value": "Rogue"},
			selector
		),
		"Priest rejected a valid persistent healing assignment."
	)
	healer.try_start_cast()
	var cast_target := healer.heal_target
	_expect(
		healer.is_casting and healer.has_healing_assignment(),
		"Priest did not begin a cast from its persistent assignment."
	)
	_expect(
		cast_target.get_incoming_healing_total() == healer.heal_amount,
		"Starting a cast did not reserve its expected incoming healing."
	)
	healer.cancel_current_cast()
	_expect(
		cast_target.get_incoming_healing_total() == 0,
		"Cancelling a cast did not remove its incoming-heal reservation."
	)
	healer.try_start_cast()
	healer.finish_cast()
	_expect(
		healer.has_healing_assignment()
		and cast_target.get_incoming_healing_total() == 0,
		"Completing a heal cleared the assignment or left a reservation behind."
	)

	for node in owned_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()

	if failures.is_empty():
		print("Persistent healing assignment regressions passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)

	get_tree().quit(1)


func _validate_heal_command_schema() -> void:
	var command_data := {
		"who_type": CommandSchemaScript.SELECTOR_CLASS,
		"who_value": "Priest",
		"unit": null,
		"who_selectors": [
			{
				"type": CommandSchemaScript.SELECTOR_CLASS,
				"value": "Priest"
			}
		],
		"what": CommandSchemaScript.ACTION_HEAL,
		"where": CommandSchemaScript.DESTINATION_HEALING_SCOPE,
		"when": "now"
	}
	_expect(
		not bool(CommandSchemaScript.validate(command_data).get("ok", false)),
		"A heal command without a target passed schema validation."
	)

	command_data["healing_scope"] = {
		"type": CommandSchemaScript.SELECTOR_EVERYONE,
		"value": ""
	}
	_expect(
		not bool(CommandSchemaScript.validate(command_data).get("ok", false)),
		"Everyone passed schema validation as a healing target."
	)


func _new_unit(
	unit_class: String,
	unit_number: int,
	max_health: int,
	current_health: int
) -> BaseCombatUnit:
	var unit := BaseCombatUnit.new()
	unit.unit_class = unit_class
	unit.unit_number = unit_number
	unit.max_health = max_health
	get_tree().root.add_child(unit)
	unit.health = current_health
	owned_nodes.append(unit)
	return unit


func _new_priest(unit_number: int) -> Priest:
	var priest := Priest.new()
	priest.unit_class = "Priest"
	priest.unit_number = unit_number
	get_tree().root.add_child(priest)
	owned_nodes.append(priest)
	return priest


func _new_threat_source(target: Node) -> DummyThreatSource:
	var source := DummyThreatSource.new()
	source.current_target = target
	get_tree().root.add_child(source)
	owned_nodes.append(source)
	return source


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
