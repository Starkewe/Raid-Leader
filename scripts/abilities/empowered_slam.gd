extends BossAbility
class_name EmpoweredSlam

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const CombatHazardScript := preload("res://scripts/combat/combat_hazard.gd")

const FISSURE_LINE_STATE_KEY := "empowered_slam_fissure_lines_by_region"

var affected_ranges: Array[String] = ["close"]
var fissure_ranges: Array[String] = ["close", "mid", "far"]
var fissure_definition: HazardDefinition = null
var maximum_fissure_lines_per_region: int = 3

var locked_region: String = "south"
var locked_origin: Vector2 = Vector2.ZERO


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is EmpoweredSlamDefinition:
		var slam_definition := definition as EmpoweredSlamDefinition
		affected_ranges = slam_definition.affected_ranges.duplicate()
		fissure_ranges = slam_definition.fissure_ranges.duplicate()
		fissure_definition = slam_definition.fissure_definition
		maximum_fissure_lines_per_region = maxi(
			slam_definition.maximum_fissure_lines_per_region,
			0
		)


func on_cast_start(boss: Node, party_members: Array) -> void:
	if boss != null and is_instance_valid(boss) and boss is Node2D:
		locked_origin = (boss as Node2D).global_position

		if boss.has_method("get_current_target"):
			var target = boss.get_current_target()

			if target != null and is_instance_valid(target) and target is Node2D:
				locked_region = MovementSlotResolverScript.get_nearest_region_from_position(
					locked_origin,
					(target as Node2D).global_position
				)

	debug_log(boss, ability_name + " started and locked the " + locked_region + " lane.")


func resolve(boss: Node, party_members: Array) -> void:
	if boss == null or not is_instance_valid(boss) or not boss is Node2D:
		return

	var hit_labels: Array[String] = []
	var resolved_damage := get_scaled_damage(boss, damage)

	if boss.has_method("play_region_impact_effect"):
		boss.play_region_impact_effect(locked_region, affected_ranges)

	for unit in get_living_units(party_members):
		if not unit is Node2D:
			continue

		var unit_2d := unit as Node2D
		var unit_region := MovementSlotResolverScript.get_nearest_region_from_position(
			locked_origin,
			unit_2d.global_position
		)
		var unit_range := MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		if unit_region != locked_region or not affected_ranges.has(unit_range):
			continue

		if resolved_damage > 0 and unit.has_method("take_damage"):
			unit.take_damage(
				resolved_damage,
				boss,
				ability_id,
				{"region": locked_region, "range": unit_range}
			)

		if unit.has_method("get_display_name"):
			hit_labels.append(String(unit.get_display_name()))
		else:
			hit_labels.append(String(unit.name))

	var spawned_fissures := _spawn_fissure_line(boss, party_members)
	debug_log(
		boss,
		ability_name + " hit [" + ", ".join(hit_labels) + "] and spawned "
		+ str(spawned_fissures) + " fissure(s) through " + locked_region + "."
	)


func _spawn_fissure_line(boss: Node, party_members: Array) -> int:
	if fissure_definition == null:
		return 0

	var line_counts: Dictionary = {}

	if boss.has_method("get_mechanic_state"):
		var state_value = boss.get_mechanic_state(FISSURE_LINE_STATE_KEY, {})

		if state_value is Dictionary:
			line_counts = (state_value as Dictionary).duplicate()

	var existing_lines := int(line_counts.get(locked_region, 0))

	if maximum_fissure_lines_per_region > 0 and existing_lines >= maximum_fissure_lines_per_region:
		debug_log(
			boss,
			"Cracked Ground skipped: " + locked_region + " is at its line cap of "
			+ str(maximum_fissure_lines_per_region) + "."
		)
		return 0

	var parent := boss.get_parent()

	if parent == null:
		return 0

	var spawned_count := 0
	var direction := MovementSlotResolverScript.get_region_direction(locked_region)
	var boss_radius := MovementSlotResolverScript.get_boss_combat_radius(boss)

	for range_name in fissure_ranges:
		var hazard := CombatHazardScript.new()
		hazard.name = "CrackedGround_" + locked_region.capitalize() + "_" + range_name.capitalize()
		hazard.z_index = 20
		parent.add_child(hazard)
		hazard.global_position = (
			locked_origin
			+ direction * (
				boss_radius + MovementSlotResolverScript.get_range_offset(range_name)
			)
		)
		hazard.configure(fissure_definition, boss, party_members)

		if boss.has_method("register_encounter_object"):
			boss.register_encounter_object(hazard)

		spawned_count += 1

	line_counts[locked_region] = existing_lines + 1

	if boss.has_method("set_mechanic_state"):
		boss.set_mechanic_state(FISSURE_LINE_STATE_KEY, line_counts)

	return spawned_count
