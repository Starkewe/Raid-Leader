extends BossAbility
class_name BoulderToss

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var target_count: int = 0
var knockback_duration: float = 0.8
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is BoulderTossDefinition:
		var toss_definition := definition as BoulderTossDefinition
		target_count = maxi(toss_definition.target_count, 0)
		knockback_duration = maxf(toss_definition.knockback_duration, 0.01)


func on_cast_start(boss: Node, party_members: Array) -> void:
	debug_log(boss, ability_name + " started. Locating the most congested mini-region.")


func resolve(boss: Node, party_members: Array) -> void:
	if boss == null or not is_instance_valid(boss) or not boss is Node2D:
		return

	var living_units := get_living_units(party_members)
	var units_by_key: Dictionary = {}
	var mini_region_by_key: Dictionary = {}

	for unit in living_units:
		if not unit is Node2D:
			continue

		var mini_region := MovementSlotResolverScript.get_mini_region_from_position(
			boss,
			(unit as Node2D).global_position
		)
		var key := String(mini_region.get("key", ""))
		var grouped_units: Array = units_by_key.get(key, [])
		grouped_units.append(unit)
		units_by_key[key] = grouped_units
		mini_region_by_key[key] = mini_region

	if units_by_key.is_empty():
		debug_log(boss, ability_name + " found no valid targets.")
		return

	var maximum_count := 0
	var congested_keys: Array[String] = []

	for key_value in units_by_key.keys():
		var key := String(key_value)
		var count := (units_by_key[key] as Array).size()

		if count > maximum_count:
			maximum_count = count
			congested_keys = [key]
		elif count == maximum_count:
			congested_keys.append(key)

	var source_key := congested_keys[rng.randi_range(0, congested_keys.size() - 1)]
	var source_mini_region: Dictionary = mini_region_by_key[source_key]
	var selected_targets: Array = (units_by_key[source_key] as Array).duplicate()
	selected_targets.shuffle()

	if target_count > 0:
		var resolved_target_count := mini(
			get_target_count_with_phase_bonus(boss, target_count),
			selected_targets.size()
		)
		selected_targets = selected_targets.slice(0, resolved_target_count)

	var neighbors := MovementSlotResolverScript.get_adjacent_mini_regions(
		String(source_mini_region.get("region", "south")),
		String(source_mini_region.get("range", "mid"))
	)

	if neighbors.is_empty():
		debug_log(boss, ability_name + " found no valid adjacent destinations.")
		return

	var base_occupancy: Dictionary = {}
	var working_occupancy: Dictionary = {}

	for neighbor in neighbors:
		var neighbor_key := String(neighbor.get("key", ""))
		var count := (units_by_key.get(neighbor_key, []) as Array).size()
		base_occupancy[neighbor_key] = count
		working_occupancy[neighbor_key] = count

	var assignments_by_key: Dictionary = {}
	var neighbor_by_key: Dictionary = {}

	for target in selected_targets:
		neighbors.shuffle()
		neighbors.sort_custom(func(a: Dictionary, b: Dictionary):
			return int(working_occupancy.get(String(a.get("key", "")), 0)) < int(
				working_occupancy.get(String(b.get("key", "")), 0)
			)
		)

		var destination: Dictionary = neighbors[0]
		var destination_key := String(destination.get("key", ""))
		var assigned_units: Array = assignments_by_key.get(destination_key, [])
		assigned_units.append(target)
		assignments_by_key[destination_key] = assigned_units
		neighbor_by_key[destination_key] = destination
		working_occupancy[destination_key] = int(working_occupancy[destination_key]) + 1

	var resolved_damage := get_scaled_damage(boss, damage)
	var target_labels: Array[String] = []

	for destination_key_value in assignments_by_key.keys():
		var destination_key := String(destination_key_value)
		var destination: Dictionary = neighbor_by_key[destination_key]
		var assigned_units: Array = assignments_by_key[destination_key]
		var existing_count := int(base_occupancy.get(destination_key, 0))
		var positions := MovementSlotResolverScript.get_slot_formation_positions(
			boss,
			String(destination.get("region", "south")),
			String(destination.get("range", "mid")),
			existing_count + assigned_units.size()
		)

		for assignment_index in range(assigned_units.size()):
			var target = assigned_units[assignment_index]

			if not is_valid_living_unit(target):
				continue

			if target.has_method("get_display_name"):
				target_labels.append(String(target.get_display_name()))
			else:
				target_labels.append(String(target.name))

			if resolved_damage > 0 and target.has_method("take_damage"):
				target.take_damage(
					resolved_damage,
					boss,
					ability_id,
					{"source_mini_region": source_key, "destination_mini_region": destination_key}
				)

			if is_valid_living_unit(target) and target.has_method("start_forced_movement"):
				target.start_forced_movement(
					positions[existing_count + assignment_index],
					knockback_duration
				)

	debug_log(
		boss,
		ability_name + " targeted congested mini-region " + source_key
		+ " (" + str(maximum_count) + " unit(s)); moved: " + ", ".join(target_labels)
	)
