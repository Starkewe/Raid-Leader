extends Area2D
class_name CombatHazard

signal expired(hazard: CombatHazard)

var definition: HazardDefinition = null
var source: Node = null
var elapsed: float = 0.0
var tick_elapsed: float = 0.0
var candidate_targets: Array = []
var tracked_targets: Array[Node] = []
var cleaned_up: bool = false


func _ready() -> void:
	# Keep collision-driven hazards compatible while allowing mechanics to supply
	# explicit candidates when they do not need a dedicated collision shape.
	body_entered.connect(register_target)
	body_exited.connect(unregister_target)


func configure(
	new_definition: HazardDefinition,
	new_source: Node = null,
	new_candidate_targets: Array = []
) -> void:
	definition = new_definition
	source = new_source
	candidate_targets = new_candidate_targets.duplicate()
	elapsed = 0.0
	tick_elapsed = 0.0
	cleaned_up = false
	queue_redraw()
	_refresh_tracked_targets()


func _process(delta: float) -> void:
	if definition == null or cleaned_up:
		return

	elapsed += delta
	tick_elapsed += delta
	_refresh_tracked_targets()

	var interval := maxf(definition.tick_interval, 0.01)

	while tick_elapsed >= interval:
		tick_elapsed -= interval
		apply_tick()

	if definition.duration > 0.0 and elapsed >= definition.duration:
		cleanup()


func _draw() -> void:
	if definition == null or not definition.show_visual:
		return

	var radius := maxf(definition.affected_radius, 1.0)
	draw_circle(Vector2.ZERO, radius, definition.fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, definition.edge_color, 3.0, true)

	for branch_index in range(7):
		var angle := (TAU / 7.0) * float(branch_index) + 0.17
		var tangent := Vector2(-sin(angle), cos(angle))
		var direction := Vector2(cos(angle), sin(angle))
		var points := PackedVector2Array([
			Vector2.ZERO,
			direction * radius * 0.34 + tangent * (6.0 if branch_index % 2 == 0 else -6.0),
			direction * radius * 0.68 - tangent * 4.0,
			direction * radius * 0.94
		])
		draw_polyline(points, definition.edge_color, 2.0, true)


func apply_tick() -> void:
	if definition == null:
		return

	for target in tracked_targets.duplicate():
		if not _is_valid_living_target(target):
			_unregister_target(target)
			continue

		if definition.damage_per_tick > 0 and target.has_method("take_damage"):
			target.take_damage(
				definition.damage_per_tick,
				source,
				definition.hazard_id,
				{"hazard": true, "hazard_position": global_position}
			)


func cleanup() -> void:
	if cleaned_up:
		return

	cleaned_up = true

	for target in tracked_targets.duplicate():
		_unregister_target(target)

	tracked_targets.clear()
	expired.emit(self)
	queue_free()


func _exit_tree() -> void:
	if cleaned_up:
		return

	for target in tracked_targets.duplicate():
		_remove_hazard_status(target)

	tracked_targets.clear()
	cleaned_up = true


func _refresh_tracked_targets() -> void:
	if definition == null:
		return

	var currently_inside: Array[Node] = []
	var radius := maxf(definition.affected_radius, 0.0)

	for target_value in candidate_targets:
		var target := target_value as Node

		if not _is_valid_living_target(target) or not target is Node2D:
			continue

		var target_2d := target as Node2D

		if global_position.distance_to(target_2d.global_position) <= radius:
			currently_inside.append(target)

	for target in currently_inside:
		if not tracked_targets.has(target):
			_register_target(target)

	for target in tracked_targets.duplicate():
		if not currently_inside.has(target):
			_unregister_target(target)


func _register_target(target: Node) -> void:
	if tracked_targets.has(target):
		return

	tracked_targets.append(target)

	if definition.status_effect != null and target.has_method("apply_status_effect"):
		target.apply_status_effect(definition.status_effect, self)

	_debug_log(_get_target_name(target) + " entered " + definition.display_name + ".")


func register_target(target: Node) -> void:
	if definition != null and _is_valid_living_target(target):
		_register_target(target)


func _unregister_target(target: Node) -> void:
	var was_tracked := tracked_targets.has(target)
	tracked_targets.erase(target)
	_remove_hazard_status(target)

	if was_tracked and definition != null:
		_debug_log(_get_target_name(target) + " left " + definition.display_name + ".")


func unregister_target(target: Node) -> void:
	_unregister_target(target)


func _remove_hazard_status(target: Node) -> void:
	if target == null or not is_instance_valid(target) or definition == null:
		return

	if definition.status_effect == null:
		return

	if target.has_method("clear_status_effect_from_source"):
		target.clear_status_effect_from_source(definition.status_effect.effect_id, self)


func _is_valid_living_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if target.has_method("is_alive"):
		return bool(target.is_alive())

	return true


func _get_target_name(target: Node) -> String:
	if target == null or not is_instance_valid(target):
		return "Invalid target"

	if target.has_method("get_display_name"):
		return String(target.get_display_name())

	return String(target.name)


func _debug_log(message: String) -> void:
	if source != null and is_instance_valid(source) and source.has_method("debug_log"):
		source.debug_log(message)
