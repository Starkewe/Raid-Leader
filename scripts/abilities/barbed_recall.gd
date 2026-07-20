extends BossAbility
class_name BarbedRecall

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var source_ranges: Array[String] = ["far"]
var destination_range: String = "mid"
var target_count: int = 4
var pull_duration: float = 0.8
var locked_targets: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is BarbedRecallDefinition:
		var recall_definition := definition as BarbedRecallDefinition
		source_ranges = recall_definition.source_ranges.duplicate()
		destination_range = recall_definition.destination_range
		target_count = maxi(recall_definition.target_count, 0)
		pull_duration = maxf(recall_definition.pull_duration, 0.01)


func on_cast_start(boss: Node, party_members: Array) -> void:
	locked_targets = _select_targets(boss, party_members)
	var source_label := "none"

	if not locked_targets.is_empty():
		source_label = String(locked_targets[0].get("source_key", "unknown"))

	debug_log(
		boss,
		ability_name + " started from " + source_label + ". Targets: "
		+ ", ".join(_get_target_labels())
	)


func resolve(boss: Node, party_members: Array) -> void:
	if boss == null or not is_instance_valid(boss) or not boss is Node2D:
		locked_targets.clear()
		return

	var assignments_by_key: Dictionary = {}
	var destination_data: Dictionary = {}

	for target_data in locked_targets:
		var target = target_data.get("target")

		if not is_valid_living_unit(target):
			continue

		var region := String(target_data.get("region", "south"))
		var key := MovementSlotResolverScript.get_mini_region_key(region, destination_range)
		var assignments: Array = assignments_by_key.get(key, [])
		assignments.append(target)
		assignments_by_key[key] = assignments
		destination_data[key] = {"region": region, "range": destination_range}

	var living_units := get_living_units(party_members)
	var pulled_labels: Array[String] = []
	var resolved_damage := get_scaled_damage(boss, damage)

	for key_value in assignments_by_key.keys():
		var key := String(key_value)
		var assignments: Array = assignments_by_key[key]
		var mini_region: Dictionary = destination_data[key]
		var existing_count := 0

		for unit in living_units:
			if assignments.has(unit) or not unit is Node2D:
				continue

			var unit_mini_region := MovementSlotResolverScript.get_mini_region_from_position(
				boss,
				(unit as Node2D).global_position
			)

			if String(unit_mini_region.get("key", "")) == key:
				existing_count += 1

		var positions := MovementSlotResolverScript.get_slot_formation_positions(
			boss,
			String(mini_region.get("region", "south")),
			destination_range,
			existing_count + assignments.size()
		)

		for assignment_index in range(assignments.size()):
			var target = assignments[assignment_index]

			if not is_valid_living_unit(target):
				continue

			if resolved_damage > 0 and target.has_method("take_damage"):
				target.take_damage(
					resolved_damage,
					boss,
					ability_id,
					get_damage_metadata({"forced_pull": true})
				)

			if is_valid_living_unit(target) and target.has_method("start_forced_movement"):
				target.start_forced_movement(
					positions[existing_count + assignment_index],
					pull_duration
				)
			pulled_labels.append(_get_unit_label(target))

	debug_log(
		boss,
		ability_name + " pulled " + ", ".join(pulled_labels)
		+ " to " + destination_range + " range."
	)
	locked_targets.clear()


func on_interrupted(boss: Node, _party_members: Array) -> void:
	locked_targets.clear()
	debug_log(boss, ability_name + " ended before pulling its targets.")


func _select_targets(boss: Node, party_members: Array) -> Array[Dictionary]:
	if boss == null or not is_instance_valid(boss) or not boss is Node2D:
		return []

	var grouped_targets: Dictionary = {}
	var maximum_count := 0
	var congested_keys: Array[String] = []

	for unit in get_living_units(party_members):
		if not unit is Node2D:
			continue

		var mini_region := MovementSlotResolverScript.get_mini_region_from_position(
			boss,
			(unit as Node2D).global_position
		)

		if not source_ranges.has(String(mini_region.get("range", "mid"))):
			continue

		var key := String(mini_region.get("key", ""))
		var targets: Array = grouped_targets.get(key, [])
		targets.append({
			"target": unit,
			"region": String(mini_region.get("region", "south")),
			"source_key": key
		})
		grouped_targets[key] = targets

		if targets.size() > maximum_count:
			maximum_count = targets.size()
			congested_keys.clear()
			congested_keys.append(key)
		elif targets.size() == maximum_count:
			if not congested_keys.has(key):
				congested_keys.append(key)

	if congested_keys.is_empty():
		return []

	var selected_key := congested_keys[rng.randi_range(0, congested_keys.size() - 1)]
	var selected: Array[Dictionary] = []

	for target_data_value in grouped_targets.get(selected_key, []):
		if target_data_value is Dictionary:
			selected.append(Dictionary(target_data_value).duplicate(true))

	selected.shuffle()

	if target_count > 0:
		var resolved_count := mini(
			get_target_count_with_phase_bonus(boss, target_count),
			selected.size()
		)
		selected.resize(resolved_count)

	return selected


func _get_target_labels() -> Array[String]:
	var labels: Array[String] = []

	for target_data in locked_targets:
		var target = target_data.get("target")

		if is_valid_living_unit(target):
			labels.append(_get_unit_label(target))

	return labels


func _get_unit_label(unit: Node) -> String:
	if unit.has_method("get_display_name"):
		return String(unit.get_display_name())

	return String(unit.name)
