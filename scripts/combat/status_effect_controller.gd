extends RefCounted
class_name StatusEffectController

var owner: Node = null
var active_effects: Dictionary = {}


func setup(new_owner: Node) -> void:
	owner = new_owner


func apply(definition: StatusEffectDefinition, source: Node = null) -> void:
	if definition == null or definition.effect_id.is_empty() or not _owner_is_alive():
		return

	var state: Dictionary = active_effects.get(definition.effect_id, {})
	var stacks := mini(int(state.get("stacks", 0)) + 1, maxi(definition.max_stacks, 1))
	var remaining := float(state.get("remaining", definition.duration))

	if state.is_empty() or definition.refresh_duration_on_stack:
		remaining = maxf(definition.duration, 0.0)

	active_effects[definition.effect_id] = {
		"definition": definition,
		"source": source,
		"stacks": stacks,
		"remaining": remaining,
		"tick_elapsed": float(state.get("tick_elapsed", 0.0))
	}

	_emit_event("status_applied", source, definition.effect_id, stacks)


func clear(effect_id: String) -> void:
	if not active_effects.has(effect_id):
		return

	active_effects.erase(effect_id)
	_emit_event("status_removed", null, effect_id, 0)


func clear_all() -> void:
	active_effects.clear()


func get_stacks(effect_id: String) -> int:
	return int(active_effects.get(effect_id, {}).get("stacks", 0))


func update(delta: float) -> void:
	if not _owner_is_alive() or active_effects.is_empty():
		return

	var expired_ids: Array[String] = []

	for effect_id_value in active_effects.keys():
		var effect_id := String(effect_id_value)
		var state: Dictionary = active_effects[effect_id]
		var definition := state.get("definition") as StatusEffectDefinition

		if definition == null:
			expired_ids.append(effect_id)
			continue

		state["remaining"] = maxf(float(state.get("remaining", 0.0)) - delta, 0.0)
		_update_periodic_damage(state, definition, delta)

		if not _owner_is_alive():
			return

		active_effects[effect_id] = state

		if float(state.get("remaining", 0.0)) <= 0.0:
			expired_ids.append(effect_id)

	for effect_id in expired_ids:
		clear(effect_id)


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
