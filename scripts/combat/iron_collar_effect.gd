extends Node
class_name IronCollarEffect

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var definition: IronCollarDefinition = null
var boss: Node = null
var target: Node2D = null
var elapsed: float = 0.0
var starting_range_index: int = 0
var cleaned_up: bool = false


func configure(
	new_definition: IronCollarDefinition,
	new_boss: Node,
	new_target: Node2D
) -> void:
	definition = new_definition
	boss = new_boss
	target = new_target
	elapsed = 0.0
	cleaned_up = false
	starting_range_index = _get_target_range_index()

	if definition != null and definition.status_effect != null:
		if _target_is_living() and target.has_method("apply_status_effect"):
			target.apply_status_effect(definition.status_effect, self)

	_debug_log(
		_get_target_name() + " received Iron Collar at "
		+ _get_range_name(starting_range_index) + " range."
	)


func _process(delta: float) -> void:
	if cleaned_up:
		return

	if definition == null or not _target_is_living() or not _boss_is_valid():
		cleanup()
		return

	elapsed += delta
	var current_range_index := _get_target_range_index()

	if current_range_index >= starting_range_index + maxi(definition.required_outward_steps, 1):
		_debug_log(_get_target_name() + " broke Iron Collar by moving outward.")
		cleanup()
		return

	if elapsed >= maxf(definition.collar_duration, 0.01):
		_tighten_collar()


func _tighten_collar() -> void:
	if not _target_is_living() or definition == null:
		cleanup()
		return

	var resolved_damage := definition.damage

	if boss.has_method("get_ability_damage_multiplier"):
		resolved_damage = maxi(
			int(round(float(definition.damage) * float(boss.get_ability_damage_multiplier()))),
			0
		)

	if resolved_damage > 0 and target.has_method("take_damage"):
		target.take_damage(
			resolved_damage,
			boss,
			definition.ability_id,
			{"damage_type": definition.damage_type, "iron_collar_failure": true}
		)

	if _target_is_living() and target.has_method("start_forced_movement"):
		var region := MovementSlotResolverScript.get_nearest_region_from_position(
			(boss as Node2D).global_position,
			target.global_position
		)
		var destination := MovementSlotResolverScript.get_slot_position(
			boss,
			region,
			definition.failure_destination_range
		)
		target.start_forced_movement(destination, definition.failure_pull_duration)

	_debug_log(
		"Iron Collar tightened on " + _get_target_name() + " for "
		+ str(resolved_damage) + " damage."
	)
	cleanup()


func cleanup() -> void:
	if cleaned_up:
		return

	cleaned_up = true

	if definition != null and definition.status_effect != null:
		if target != null and is_instance_valid(target):
			if target.has_method("clear_status_effect_from_source"):
				target.clear_status_effect_from_source(
					definition.status_effect.effect_id,
					self
				)

	queue_free()


func _exit_tree() -> void:
	if cleaned_up:
		return

	if definition != null and definition.status_effect != null:
		if target != null and is_instance_valid(target):
			if target.has_method("clear_status_effect_from_source"):
				target.clear_status_effect_from_source(
					definition.status_effect.effect_id,
					self
				)

	cleaned_up = true


func _get_target_range_index() -> int:
	if not _target_is_living() or not _boss_is_valid():
		return 0

	var range_name := MovementSlotResolverScript.get_nearest_range_from_position(
		boss,
		target.global_position
	)
	return maxi(MovementSlotResolverScript.RANGE_ORDER.find(range_name), 0)


func _get_range_name(range_index: int) -> String:
	if range_index < 0 or range_index >= MovementSlotResolverScript.RANGE_ORDER.size():
		return "unknown"

	return String(MovementSlotResolverScript.RANGE_ORDER[range_index])


func _target_is_living() -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if target.has_method("is_alive"):
		return bool(target.is_alive())

	return true


func _boss_is_valid() -> bool:
	return boss != null and is_instance_valid(boss) and boss is Node2D


func _get_target_name() -> String:
	if target == null or not is_instance_valid(target):
		return "Invalid target"

	if target.has_method("get_display_name"):
		return String(target.get_display_name())

	return String(target.name)


func _debug_log(message: String) -> void:
	if boss != null and is_instance_valid(boss) and boss.has_method("debug_log"):
		boss.debug_log(message)
