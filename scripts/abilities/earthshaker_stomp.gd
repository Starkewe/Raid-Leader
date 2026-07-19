extends BossAbility
class_name EarthshakerStomp

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var knockback_duration: float = 0.75


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is EarthshakerStompDefinition:
		knockback_duration = maxf(
			(definition as EarthshakerStompDefinition).knockback_duration,
			0.01
		)


func on_cast_start(boss: Node, party_members: Array) -> void:
	debug_log(boss, ability_name + " started. Raid-wide outward knockback is incoming.")


func resolve(boss: Node, party_members: Array) -> void:
	if boss == null or not is_instance_valid(boss) or not boss is Node2D:
		return

	var living_units := get_living_units(party_members)
	var resolved_damage := get_scaled_damage(boss, damage)

	for unit in living_units:
		if resolved_damage > 0 and unit.has_method("take_damage"):
			unit.take_damage(resolved_damage, boss, ability_id, {"raid_wide": true})

	var destination_groups: Dictionary = {}
	var destination_data: Dictionary = {}
	var stationary_occupancy: Dictionary = {}

	for unit in get_living_units(living_units):
		if not unit is Node2D:
			continue

		var mini_region := MovementSlotResolverScript.get_mini_region_from_position(
			boss,
			(unit as Node2D).global_position
		)
		var current_range := String(mini_region.get("range", "mid"))
		var destination_range := MovementSlotResolverScript.get_adjacent_range(
			current_range,
			MovementSlotResolverScript.RANGE_DIRECTION_OUT
		)

		if destination_range == current_range:
			var stationary_key := String(mini_region.get("key", ""))
			stationary_occupancy[stationary_key] = int(
				stationary_occupancy.get(stationary_key, 0)
			) + 1
			continue

		var region := String(mini_region.get("region", "south"))
		var destination_key := MovementSlotResolverScript.get_mini_region_key(
			region,
			destination_range
		)
		var grouped_units: Array = destination_groups.get(destination_key, [])
		grouped_units.append(unit)
		destination_groups[destination_key] = grouped_units
		destination_data[destination_key] = {
			"region": region,
			"range": destination_range
		}

	for destination_key_value in destination_groups.keys():
		var destination_key := String(destination_key_value)
		var grouped_units: Array = destination_groups[destination_key]
		var mini_region: Dictionary = destination_data[destination_key]
		var existing_count := int(stationary_occupancy.get(destination_key, 0))
		var positions := MovementSlotResolverScript.get_slot_formation_positions(
			boss,
			String(mini_region.get("region", "south")),
			String(mini_region.get("range", "far")),
			existing_count + grouped_units.size()
		)

		for index in range(grouped_units.size()):
			var unit = grouped_units[index]

			if is_valid_living_unit(unit) and unit.has_method("start_forced_movement"):
				unit.start_forced_movement(
					positions[existing_count + index],
					knockback_duration
				)

	debug_log(
		boss,
		ability_name + " hit " + str(living_units.size())
		+ " unit(s) and pushed non-far units one ring outward."
	)
