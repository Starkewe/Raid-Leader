extends BossAbility
class_name IronCollar

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const IronCollarEffectScript := preload("res://scripts/combat/iron_collar_effect.gd")

var target_behavior: String = "random_non_tank"
var target_count: int = 3
var eligible_ranges: Array[String] = ["close", "mid"]
var locked_targets: Array = []


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is IronCollarDefinition:
		var collar_definition := definition as IronCollarDefinition
		target_behavior = collar_definition.target_behavior
		target_count = maxi(collar_definition.target_count, 0)
		eligible_ranges = collar_definition.eligible_ranges.duplicate()


func on_cast_start(boss: Node, party_members: Array) -> void:
	locked_targets = _select_targets(boss, party_members)
	debug_log(
		boss,
		ability_name + " started. Targets: " + ", ".join(_get_target_labels())
	)


func resolve(boss: Node, party_members: Array) -> void:
	if not definition_is_valid() or boss == null or not is_instance_valid(boss):
		locked_targets.clear()
		return

	var parent := boss.get_parent()

	if parent == null:
		locked_targets.clear()
		return

	var applied_labels: Array[String] = []

	for target in locked_targets:
		if not is_valid_living_unit(target) or not target is Node2D:
			continue

		var collar_effect := IronCollarEffectScript.new()
		collar_effect.name = "IronCollar_" + String(target.name)
		parent.add_child(collar_effect)
		collar_effect.configure(_get_definition(), boss, target as Node2D)

		if boss.has_method("register_encounter_object"):
			boss.register_encounter_object(collar_effect)

		applied_labels.append(_get_unit_label(target))

	debug_log(boss, ability_name + " applied to: " + ", ".join(applied_labels) + ".")
	locked_targets.clear()


func on_interrupted(boss: Node, party_members: Array) -> void:
	locked_targets.clear()
	debug_log(boss, ability_name + " ended before applying collars.")


func _select_targets(boss: Node, party_members: Array) -> Array:
	if boss == null or not is_instance_valid(boss):
		return []

	var current_target = boss.get_current_target() if boss.has_method("get_current_target") else null
	var candidates: Array = []

	for unit in get_living_units(party_members):
		if not unit is Node2D:
			continue

		if target_behavior == "random_non_tank" and unit == current_target:
			continue

		var range_name := MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			(unit as Node2D).global_position
		)

		if eligible_ranges.has(range_name):
			candidates.append(unit)

	candidates.shuffle()
	var resolved_count := candidates.size() if target_count <= 0 else mini(
		get_target_count_with_phase_bonus(boss, target_count),
		candidates.size()
	)
	return candidates.slice(0, resolved_count)


func _get_target_labels() -> Array[String]:
	var labels: Array[String] = []

	for target in locked_targets:
		if is_valid_living_unit(target):
			labels.append(_get_unit_label(target))

	return labels


func definition_is_valid() -> bool:
	return _get_definition() != null


func _get_definition() -> IronCollarDefinition:
	return configured_definition as IronCollarDefinition


func _get_unit_label(unit: Node) -> String:
	if unit.has_method("get_display_name"):
		return String(unit.get_display_name())

	return String(unit.name)
