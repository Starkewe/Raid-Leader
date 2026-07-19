extends BossAbility
class_name StampedeTransition

const BossAbilityFactoryScript := preload("res://scripts/abilities/boss_ability_factory.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var wave_telegraph_durations: Array[float] = [4.0, 3.25]
var wave_recovery_duration: float = 1.25
var intermission_mechanic_delay: float = 0.45
var clear_existing_encounter_objects: bool = true
var affected_ranges: Array[String] = ["close", "mid", "far"]
var tremor_damage: int = 6
var tremor_damage_type: String = "environmental"
var barbed_recall_after_wave: int = 0
var barbed_recall_definition: BarbedRecallDefinition = null
var iron_collar_after_wave: int = 0
var iron_collar_definition: IronCollarDefinition = null

var safe_axes: Array[String] = []
var wave_start_times: Array[float] = []
var wave_impact_times: Array[float] = []
var telegraph_started: Array[bool] = []
var wave_resolved: Array[bool] = []
var barbed_recall_triggered: bool = false
var iron_collar_triggered: bool = false
var current_wave_index: int = -1
var arena_origin: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is StampedeTransitionDefinition:
		var transition_definition := definition as StampedeTransitionDefinition
		clear_existing_encounter_objects = (
			transition_definition.clear_existing_encounter_objects
		)
		wave_telegraph_durations = transition_definition.wave_telegraph_durations.duplicate()
		wave_recovery_duration = maxf(transition_definition.wave_recovery_duration, 0.0)
		intermission_mechanic_delay = maxf(
			transition_definition.intermission_mechanic_delay,
			0.0
		)
		affected_ranges = transition_definition.affected_ranges.duplicate()
		tremor_damage = maxi(transition_definition.tremor_damage, 0)
		tremor_damage_type = transition_definition.tremor_damage_type
		barbed_recall_after_wave = maxi(transition_definition.barbed_recall_after_wave, 0)
		barbed_recall_definition = transition_definition.barbed_recall_definition
		iron_collar_after_wave = maxi(transition_definition.iron_collar_after_wave, 0)
		iron_collar_definition = transition_definition.iron_collar_definition

	_build_timeline()


func on_cast_start(boss: Node, party_members: Array) -> void:
	_reset_runtime_state()

	if boss != null and is_instance_valid(boss):
		if clear_existing_encounter_objects and boss.has_method("clear_encounter_objects"):
			boss.clear_encounter_objects()

		if boss.has_method("move_to_encounter_origin"):
			boss.move_to_encounter_origin()

		if boss.has_method("get_encounter_origin_position"):
			arena_origin = boss.get_encounter_origin_position()
		elif boss is Node2D:
			arena_origin = (boss as Node2D).global_position

	_select_safe_axes()
	debug_log(
		boss,
		ability_name + " started with " + str(wave_telegraph_durations.size())
		+ " wave(s). Safe axes: " + str(safe_axes) + "."
	)

	if not wave_start_times.is_empty():
		_start_wave_telegraph(boss, 0)


func on_cast_update(
	boss: Node,
	party_members: Array,
	elapsed_time: float,
	remaining_time: float
) -> void:
	for wave_index in range(wave_start_times.size()):
		if not telegraph_started[wave_index] and elapsed_time >= wave_start_times[wave_index]:
			_start_wave_telegraph(boss, wave_index)

		if not wave_resolved[wave_index] and elapsed_time >= wave_impact_times[wave_index]:
			_resolve_wave(boss, party_members, wave_index)

		var mechanic_time := wave_impact_times[wave_index] + intermission_mechanic_delay
		var completed_wave_number := wave_index + 1

		if (
			not barbed_recall_triggered
			and barbed_recall_after_wave == completed_wave_number
			and elapsed_time >= mechanic_time
		):
			barbed_recall_triggered = true
			_trigger_intermission_ability(boss, party_members, barbed_recall_definition)

		if (
			not iron_collar_triggered
			and iron_collar_after_wave == completed_wave_number
			and elapsed_time >= mechanic_time
		):
			iron_collar_triggered = true
			_trigger_intermission_ability(boss, party_members, iron_collar_definition)


func resolve(boss: Node, party_members: Array) -> void:
	for wave_index in range(wave_impact_times.size()):
		if not wave_resolved[wave_index]:
			_resolve_wave(boss, party_members, wave_index)

	if not barbed_recall_triggered and barbed_recall_after_wave > 0:
		barbed_recall_triggered = true
		_trigger_intermission_ability(boss, party_members, barbed_recall_definition)

	if not iron_collar_triggered and iron_collar_after_wave > 0:
		iron_collar_triggered = true
		_trigger_intermission_ability(boss, party_members, iron_collar_definition)

	debug_log(boss, ability_name + " completed all waves.")


func on_interrupted(boss: Node, party_members: Array) -> void:
	debug_log(boss, ability_name + " ended early; pending waves were cleared.")
	_reset_runtime_state()


func get_status_text() -> String:
	if current_wave_index < 0 or current_wave_index >= safe_axes.size():
		return "Preparing " + ability_name

	return (
		"Wave " + str(current_wave_index + 1) + "/" + str(safe_axes.size())
		+ " | Safe: " + _get_axis_display_name(safe_axes[current_wave_index])
	)


func _build_timeline() -> void:
	wave_start_times.clear()
	wave_impact_times.clear()
	var timeline_cursor := 0.0

	for duration_value in wave_telegraph_durations:
		var telegraph_duration := maxf(float(duration_value), 0.1)
		wave_start_times.append(timeline_cursor)
		wave_impact_times.append(timeline_cursor + telegraph_duration)
		timeline_cursor += telegraph_duration + wave_recovery_duration

	cast_time = maxf(timeline_cursor, 0.1)


func _reset_runtime_state() -> void:
	safe_axes.clear()
	telegraph_started.clear()
	wave_resolved.clear()
	barbed_recall_triggered = false
	iron_collar_triggered = false
	current_wave_index = -1

	for _wave_index in range(wave_telegraph_durations.size()):
		telegraph_started.append(false)
		wave_resolved.append(false)


func _select_safe_axes() -> void:
	var previous_axis := ""

	for _wave_index in range(wave_telegraph_durations.size()):
		var candidates: Array[String] = []

		for axis_value in MovementSlotResolverScript.AXIS_ORDER:
			var axis_id := String(axis_value)

			if axis_id != previous_axis:
				candidates.append(axis_id)

		if candidates.is_empty():
			candidates.append_array(MovementSlotResolverScript.AXIS_ORDER)

		var selected_axis := candidates[rng.randi_range(0, candidates.size() - 1)]
		safe_axes.append(selected_axis)
		previous_axis = selected_axis


func _start_wave_telegraph(boss: Node, wave_index: int) -> void:
	if wave_index < 0 or wave_index >= telegraph_started.size():
		return

	telegraph_started[wave_index] = true
	current_wave_index = wave_index
	var safe_axis := safe_axes[wave_index]
	var active_regions := _get_active_regions(safe_axis)
	var telegraph_duration := maxf(wave_telegraph_durations[wave_index], 0.1)

	if boss != null and is_instance_valid(boss) and boss.has_method("play_region_telegraph"):
		for region in active_regions:
			boss.play_region_telegraph(region, affected_ranges, telegraph_duration)

	debug_log(
		boss,
		"Stampede wave " + str(wave_index + 1) + " telegraphed. Safe axis: "
		+ _get_axis_display_name(safe_axis) + "."
	)


func _resolve_wave(boss: Node, party_members: Array, wave_index: int) -> void:
	if wave_index < 0 or wave_index >= wave_resolved.size() or wave_resolved[wave_index]:
		return

	wave_resolved[wave_index] = true
	current_wave_index = wave_index
	var safe_axis := safe_axes[wave_index]
	var active_regions := _get_active_regions(safe_axis)
	var direct_damage := get_scaled_damage(boss, damage)
	var resolved_tremor_damage := _get_scaled_tremor_damage(boss)
	var direct_hit_labels: Array[String] = []

	if boss != null and is_instance_valid(boss) and boss.has_method("play_region_impact_effect"):
		for region in active_regions:
			boss.play_region_impact_effect(region, affected_ranges)

	for unit in get_living_units(party_members):
		if resolved_tremor_damage > 0 and unit.has_method("take_damage"):
			unit.take_damage(
				resolved_tremor_damage,
				boss,
				ability_id + "_tremor",
				{
					"damage_type": tremor_damage_type,
					"raid_wide": true,
					"wave": wave_index + 1
				}
			)

		if not is_valid_living_unit(unit) or not unit is Node2D:
			continue

		var unit_region := MovementSlotResolverScript.get_nearest_region_from_position(
			arena_origin,
			(unit as Node2D).global_position
		)

		if not active_regions.has(unit_region):
			continue

		if direct_damage > 0 and unit.has_method("take_damage"):
			unit.take_damage(
				direct_damage,
				boss,
				ability_id,
				get_damage_metadata({"stampede": true, "wave": wave_index + 1})
			)
			direct_hit_labels.append(_get_unit_label(unit))

	debug_log(
		boss,
		"Stampede wave " + str(wave_index + 1) + " resolved; safe axis "
		+ _get_axis_display_name(safe_axis) + "; direct hits: "
		+ ", ".join(direct_hit_labels) + "."
	)


func _trigger_intermission_ability(
	boss: Node,
	party_members: Array,
	definition: BossAbilityDefinition
) -> void:
	if definition == null:
		return

	var intermission_ability := BossAbilityFactoryScript.create_ability_from_definition(definition)

	if intermission_ability == null or not intermission_ability.can_cast(boss, party_members):
		return

	debug_log(boss, "Transition inserts " + definition.display_name + ".")
	intermission_ability.on_cast_start(boss, party_members)
	intermission_ability.resolve(boss, party_members)


func _get_active_regions(safe_axis: String) -> Array[String]:
	var safe_regions := MovementSlotResolverScript.get_axis_regions(safe_axis)
	var active_regions: Array[String] = []

	for region_value in MovementSlotResolverScript.REGION_ORDER:
		var region := String(region_value)

		if not safe_regions.has(region):
			active_regions.append(region)

	return active_regions


func _get_scaled_tremor_damage(boss: Node) -> int:
	var multiplier := 1.0

	if boss != null and is_instance_valid(boss) and boss.has_method("get_ability_damage_multiplier"):
		multiplier = float(boss.get_ability_damage_multiplier())

	return maxi(int(round(float(tremor_damage) * multiplier)), 0)


func _get_axis_display_name(axis_id: String) -> String:
	var labels: Array[String] = []

	for region in MovementSlotResolverScript.get_axis_regions(axis_id):
		labels.append(region.capitalize())

	return " / ".join(labels)


func _get_unit_label(unit: Node) -> String:
	if unit.has_method("get_display_name"):
		return String(unit.get_display_name())

	return String(unit.name)
