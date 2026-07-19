extends BossAbility
class_name RingStrike

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var affected_ranges: Array[String] = ["mid"]


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is RingStrikeDefinition:
		affected_ranges = (definition as RingStrikeDefinition).affected_ranges.duplicate()


func on_cast_start(boss: Node, party_members: Array) -> void:
	var telegraph_duration := cast_time

	if boss != null and is_instance_valid(boss) and boss.has_method("get_current_cast_time"):
		telegraph_duration = float(boss.get_current_cast_time())

	if boss != null and is_instance_valid(boss) and boss.has_method("play_region_telegraph"):
		for region_value in MovementSlotResolverScript.REGION_ORDER:
			boss.play_region_telegraph(
				String(region_value),
				affected_ranges,
				telegraph_duration
			)

	debug_log(boss, ability_name + " started. Dangerous rings: " + str(affected_ranges) + ".")


func resolve(boss: Node, party_members: Array) -> void:
	if boss == null or not is_instance_valid(boss) or not boss is Node2D:
		return

	var resolved_damage := get_scaled_damage(boss, damage)
	var hit_labels: Array[String] = []

	for region_value in MovementSlotResolverScript.REGION_ORDER:
		if boss.has_method("play_region_impact_effect"):
			boss.play_region_impact_effect(String(region_value), affected_ranges)

	for unit in get_living_units(party_members):
		if not unit is Node2D:
			continue

		var range_name := MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			(unit as Node2D).global_position
		)

		if not affected_ranges.has(range_name):
			continue

		if resolved_damage > 0 and unit.has_method("take_damage"):
			unit.take_damage(
				resolved_damage,
				boss,
				ability_id,
				get_damage_metadata({"ring_strike": true, "range": range_name})
			)
			hit_labels.append(_get_unit_label(unit))

	debug_log(boss, ability_name + " hit: " + ", ".join(hit_labels) + ".")


func _get_unit_label(unit: Node) -> String:
	if unit.has_method("get_display_name"):
		return String(unit.get_display_name())

	return String(unit.name)
