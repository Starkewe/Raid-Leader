extends RefCounted
class_name StatusEffectController

var owner: Node = null
var active_effects: Dictionary = {}


func setup(new_owner: Node) -> void:
	owner = new_owner


func apply(definition: StatusEffectDefinition, source: Node = null) -> bool:
	if definition == null or definition.effect_id.is_empty() or not _owner_is_alive():
		return false

	var state_key := _get_state_key(definition, source)
	var state: Dictionary = active_effects.get(state_key, {})
	var stacks := mini(int(state.get("stacks", 0)) + 1, maxi(definition.max_stacks, 1))
	var remaining := float(state.get("remaining", definition.duration))

	if state.is_empty() or definition.refresh_duration_on_stack:
		remaining = maxf(definition.duration, 0.0)

	active_effects[state_key] = {
		"definition": definition,
		"source": source,
		"stacks": stacks,
		"remaining": remaining,
		"tick_elapsed": float(state.get("tick_elapsed", 0.0)),
		"applied_at_msec": int(state.get("applied_at_msec", Time.get_ticks_msec()))
	}

	_emit_event("status_applied", source, definition.effect_id, stacks)
	return true


func clear(effect_id: String) -> int:
	var matching_keys := _get_matching_keys(effect_id)

	for state_key in matching_keys:
		_remove_state(state_key)

	return matching_keys.size()


func clear_from_source(effect_id: String, source: Node) -> bool:
	for state_key_value in active_effects.keys():
		var state_key := String(state_key_value)
		var state: Dictionary = active_effects[state_key]
		var definition := state.get("definition") as StatusEffectDefinition

		if definition == null or definition.effect_id != effect_id:
			continue

		if state.get("source") != source:
			continue

		_remove_state(state_key)
		return true

	return false


func clear_all() -> void:
	for state_key_value in active_effects.keys():
		_remove_state(String(state_key_value))


func clear_dispellable(dispel_category: String, maximum_effects: int = 1) -> Array[String]:
	var candidates: Array[Dictionary] = []

	for state_key_value in active_effects.keys():
		var state_key := String(state_key_value)
		var state: Dictionary = active_effects[state_key]
		var definition := state.get("definition") as StatusEffectDefinition

		if definition == null or not definition.dispellable:
			continue

		if not dispel_category.is_empty() and definition.dispel_category != dispel_category:
			continue

		candidates.append({
			"state_key": state_key,
			"effect_id": definition.effect_id,
			"applied_at_msec": int(state.get("applied_at_msec", 0))
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.get("applied_at_msec", 0)) < int(b.get("applied_at_msec", 0))
	)

	var removed_effect_ids: Array[String] = []
	var removal_limit := candidates.size() if maximum_effects <= 0 else maximum_effects

	for candidate in candidates:
		if removed_effect_ids.size() >= removal_limit:
			break

		var state_key := String(candidate.get("state_key", ""))
		var effect_id := String(candidate.get("effect_id", ""))

		if active_effects.has(state_key):
			_remove_state(state_key)
			removed_effect_ids.append(effect_id)

	return removed_effect_ids


func has_dispellable(dispel_category: String = "") -> bool:
	for state_value in active_effects.values():
		var state: Dictionary = state_value
		var definition := state.get("definition") as StatusEffectDefinition

		if definition == null or not definition.dispellable:
			continue

		if dispel_category.is_empty() or definition.dispel_category == dispel_category:
			return true

	return false


func get_stacks(effect_id: String) -> int:
	var total_stacks := 0

	for state_key in _get_matching_keys(effect_id):
		total_stacks += int(active_effects[state_key].get("stacks", 0))

	return total_stacks


func get_display_text() -> String:
	var summaries: Dictionary = {}

	for state_value in active_effects.values():
		var state: Dictionary = state_value
		var definition := state.get("definition") as StatusEffectDefinition

		if definition == null:
			continue

		var summary: Dictionary = summaries.get(definition.effect_id, {
			"display_name": definition.display_name,
			"stacks": 0
		})
		summary["stacks"] = int(summary.get("stacks", 0)) + int(state.get("stacks", 1))
		summaries[definition.effect_id] = summary

	var labels: Array[String] = []

	for effect_id_value in summaries.keys():
		var summary: Dictionary = summaries[effect_id_value]
		var label := String(summary.get("display_name", effect_id_value))
		var stacks := int(summary.get("stacks", 1))

		if stacks > 1:
			label += " x" + str(stacks)

		labels.append(label)

	labels.sort()
	return ", ".join(labels)


func update(delta: float) -> void:
	if not _owner_is_alive() or active_effects.is_empty():
		return

	var expired_keys: Array[String] = []

	for state_key_value in active_effects.keys():
		var state_key := String(state_key_value)
		var state: Dictionary = active_effects[state_key]
		var definition := state.get("definition") as StatusEffectDefinition

		if definition == null:
			expired_keys.append(state_key)
			continue

		if definition.duration > 0.0:
			state["remaining"] = maxf(float(state.get("remaining", 0.0)) - delta, 0.0)

		_update_periodic_damage(state, definition, delta)

		if not _owner_is_alive():
			return

		active_effects[state_key] = state

		if definition.duration > 0.0 and float(state.get("remaining", 0.0)) <= 0.0:
			expired_keys.append(state_key)

	for state_key in expired_keys:
		_remove_state(state_key)


func get_movement_multiplier() -> float:
	var multiplier := 1.0

	for state_value in active_effects.values():
		var state: Dictionary = state_value
		var definition := state.get("definition") as StatusEffectDefinition

		if definition != null:
			multiplier *= pow(
				definition.movement_speed_multiplier_per_stack,
				int(state.get("stacks", 1))
			)

	return maxf(multiplier, 0.0)


func get_incoming_damage_multiplier() -> float:
	var multiplier := 1.0

	for state_value in active_effects.values():
		var state: Dictionary = state_value
		var definition := state.get("definition") as StatusEffectDefinition

		if definition == null or definition.incoming_damage_percent_per_stack <= 0.0:
			continue

		multiplier *= (
			1.0
			+ definition.incoming_damage_percent_per_stack * float(state.get("stacks", 1))
		)

	return maxf(multiplier, 0.0)


func _get_state_key(definition: StatusEffectDefinition, source: Node) -> String:
	if not definition.unique_per_source:
		return definition.effect_id

	var source_id := 0

	if source != null and is_instance_valid(source):
		source_id = source.get_instance_id()

	return definition.effect_id + ":source:" + str(source_id)


func _get_matching_keys(effect_id: String) -> Array[String]:
	var matching_keys: Array[String] = []

	for state_key_value in active_effects.keys():
		var state_key := String(state_key_value)
		var state: Dictionary = active_effects[state_key]
		var definition := state.get("definition") as StatusEffectDefinition

		if definition != null and definition.effect_id == effect_id:
			matching_keys.append(state_key)

	return matching_keys


func _remove_state(state_key: String) -> void:
	if not active_effects.has(state_key):
		return

	var state: Dictionary = active_effects[state_key]
	var definition := state.get("definition") as StatusEffectDefinition
	var effect_id := state_key if definition == null else definition.effect_id

	active_effects.erase(state_key)
	_emit_event("status_removed", null, effect_id, 0)


func _update_periodic_damage(
	state: Dictionary,
	definition: StatusEffectDefinition,
	delta: float
) -> void:
	if definition.tick_interval <= 0.0 or definition.damage_per_tick <= 0:
		return

	state["tick_elapsed"] = float(state.get("tick_elapsed", 0.0)) + delta

	while float(state["tick_elapsed"]) >= definition.tick_interval:
		state["tick_elapsed"] = float(state["tick_elapsed"]) - definition.tick_interval

		if owner != null and owner.has_method("take_damage"):
			owner.take_damage(
				definition.damage_per_tick * int(state.get("stacks", 1)),
				state.get("source") as Node,
				definition.effect_id,
				{"periodic": true}
			)

		if not _owner_is_alive():
			return


func _owner_is_alive() -> bool:
	if owner == null or not is_instance_valid(owner):
		return false

	if owner.has_method("is_alive"):
		return bool(owner.is_alive())

	return true


func _emit_event(event_type: String, source: Node, ability_id: String, amount: int) -> void:
	if owner != null and owner.has_method("emit_combat_event"):
		owner.emit_combat_event(event_type, source, ability_id, amount)
