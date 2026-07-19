extends BossAbility
class_name GrabbingRoar

var target_behavior: String = "random"
var target_count: int = 4
var slow_effect: StatusEffectDefinition = null
var locked_targets: Array = []


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is GrabbingRoarDefinition:
		var roar_definition := definition as GrabbingRoarDefinition
		target_behavior = roar_definition.target_behavior
		target_count = maxi(roar_definition.target_count, 0)
		slow_effect = roar_definition.slow_effect


func on_cast_start(boss: Node, party_members: Array) -> void:
	locked_targets = _select_targets(boss, party_members)
	debug_log(
		boss,
		ability_name + " started. Targets: " + ", ".join(_get_target_labels(locked_targets))
	)


func resolve(boss: Node, party_members: Array) -> void:
	if slow_effect == null:
		debug_log(boss, ability_name + " has no configured slow effect.")
		return

	var applied_labels: Array[String] = []

	for target in locked_targets:
		if not is_valid_living_unit(target) or not target.has_method("apply_status_effect"):
			continue

		target.apply_status_effect(slow_effect, boss)
		applied_labels.append_array(_get_target_labels([target]))

	debug_log(
		boss,
		ability_name + " applied " + slow_effect.display_name + " to: "
		+ ", ".join(applied_labels)
	)
	locked_targets.clear()


func on_interrupted(boss: Node, party_members: Array) -> void:
	locked_targets.clear()
	debug_log(boss, ability_name + " ended before applying its slow.")


func _select_targets(boss: Node, party_members: Array) -> Array:
	var living_units := get_living_units(party_members)

	match target_behavior:
		"all":
			return living_units

		"current_target":
			if boss != null and is_instance_valid(boss) and boss.has_method("get_current_target"):
				var current_target = boss.get_current_target()

				if is_valid_living_unit(current_target):
					return [current_target]

			return []

		_:
			living_units.shuffle()
			var resolved_count := mini(
				get_target_count_with_phase_bonus(boss, target_count),
				living_units.size()
			)
			return living_units.slice(0, resolved_count)


func _get_target_labels(targets: Array) -> Array[String]:
	var labels: Array[String] = []

	for target in targets:
		if target == null or not is_instance_valid(target):
			continue

		if target.has_method("get_display_name"):
			labels.append(String(target.get_display_name()))
		else:
			labels.append(String(target.name))

	return labels
