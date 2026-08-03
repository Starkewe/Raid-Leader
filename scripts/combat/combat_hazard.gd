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
var coverage_polygon: PackedVector2Array = PackedVector2Array()
var coverage_region: String = ""
var coverage_range: String = ""


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
	coverage_polygon = PackedVector2Array()
	coverage_region = ""
	coverage_range = ""
	queue_redraw()
	_refresh_tracked_targets()


func configure_polygon_coverage(
	world_polygon: PackedVector2Array,
	region: String = "",
	range_name: String = ""
) -> void:
	coverage_polygon = PackedVector2Array()

	for point in world_polygon:
		coverage_polygon.append(to_local(point))

	coverage_region = region
	coverage_range = range_name
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

	if coverage_polygon.size() >= 3:
		draw_colored_polygon(coverage_polygon, definition.fill_color)
		var closed_polygon := PackedVector2Array(coverage_polygon)
		closed_polygon.append(coverage_polygon[0])
		draw_polyline(closed_polygon, definition.edge_color, 3.0, true)
		_draw_polygon_cracks()
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


func _draw_polygon_cracks() -> void:
	var center := Vector2.ZERO

	for point in coverage_polygon:
		center += point

	center /= float(coverage_polygon.size())

	for edge_index in range(coverage_polygon.size()):
		var edge_start: Vector2 = coverage_polygon[edge_index]
		var edge_end: Vector2 = coverage_polygon[(edge_index + 1) % coverage_polygon.size()]
		var edge_midpoint := edge_start.lerp(edge_end, 0.5)
		var tangent := (edge_end - edge_start).normalized()
		var bend := center.lerp(edge_midpoint, 0.58)
		bend += tangent * (4.0 if edge_index % 2 == 0 else -4.0)
		draw_polyline(
			PackedVector2Array([center, bend, edge_midpoint]),
			definition.edge_color,
			2.0,
			true
		)


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

	for target_value in candidate_targets:
		var target := target_value as Node

		if not _is_valid_living_target(target) or not target is Node2D:
			continue

		var target_2d := target as Node2D

		if contains_world_position(target_2d.global_position):
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


func contains_world_position(world_position: Vector2, clearance_pixels: float = 0.0) -> bool:
	if definition == null:
		return false

	var clearance := maxf(clearance_pixels, 0.0)

	if coverage_polygon.size() < 3:
		return global_position.distance_to(world_position) <= (
			maxf(definition.affected_radius, 0.0) + clearance
		)

	var local_position := to_local(world_position)

	if _is_point_in_polygon(local_position, coverage_polygon):
		return true

	if clearance <= 0.0:
		return false

	for edge_index in range(coverage_polygon.size()):
		var edge_start: Vector2 = coverage_polygon[edge_index]
		var edge_end: Vector2 = coverage_polygon[(edge_index + 1) % coverage_polygon.size()]

		if _distance_from_point_to_segment(local_position, edge_start, edge_end) <= clearance:
			return true

	return false


func intersects_world_segment(
	world_start: Vector2,
	world_finish: Vector2,
	clearance_pixels: float = 0.0
) -> bool:
	if definition == null:
		return false

	var clearance := maxf(clearance_pixels, 0.0)

	if coverage_polygon.size() < 3:
		return _distance_from_point_to_segment(
			global_position,
			world_start,
			world_finish
		) <= maxf(definition.affected_radius, 0.0) + clearance

	var local_start := to_local(world_start)
	var local_finish := to_local(world_finish)

	if (
		_is_point_in_polygon(local_start, coverage_polygon)
		or _is_point_in_polygon(local_finish, coverage_polygon)
	):
		return true

	for edge_index in range(coverage_polygon.size()):
		var edge_start: Vector2 = coverage_polygon[edge_index]
		var edge_end: Vector2 = coverage_polygon[(edge_index + 1) % coverage_polygon.size()]

		if _distance_between_segments(
			local_start,
			local_finish,
			edge_start,
			edge_end
		) <= clearance:
			return true

	return false


func is_world_segment_safe(
	world_start: Vector2,
	world_finish: Vector2,
	clearance_pixels: float = 0.0,
	allow_escape_from_source: bool = false
) -> bool:
	if (
		allow_escape_from_source
		and contains_world_position(world_start, clearance_pixels)
		and not contains_world_position(world_finish, clearance_pixels)
	):
		if coverage_polygon.size() >= 3:
			return true

		var radius := maxf(definition.affected_radius, 0.0) + maxf(clearance_pixels, 0.0)
		var outward := world_start - global_position
		var travel := world_finish - world_start

		if (
			world_start.distance_to(global_position) <= radius
			and world_finish.distance_to(global_position) >= radius
			and (outward.is_zero_approx() or outward.dot(travel) >= -0.001)
		):
			return true

	return not intersects_world_segment(world_start, world_finish, clearance_pixels)


func get_coverage_bounds_radius() -> float:
	if coverage_polygon.size() < 3:
		return 0.0 if definition == null else maxf(definition.affected_radius, 0.0)

	var maximum_radius := 0.0

	for point in coverage_polygon:
		maximum_radius = maxf(maximum_radius, point.length())

	return maximum_radius


func get_coverage_signature() -> String:
	return "%s:%s:%s" % [coverage_region, coverage_range, str(coverage_polygon)]


func get_coverage_mini_region_key() -> String:
	if coverage_region.is_empty() or coverage_range.is_empty():
		return ""

	return coverage_region + ":" + coverage_range


func _is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var has_positive_cross := false
	var has_negative_cross := false

	for edge_index in range(polygon.size()):
		var edge_start: Vector2 = polygon[edge_index]
		var edge_end: Vector2 = polygon[(edge_index + 1) % polygon.size()]
		var cross := (edge_end - edge_start).cross(point - edge_start)

		if absf(cross) <= 0.001:
			continue

		if cross > 0.0:
			has_positive_cross = true
		else:
			has_negative_cross = true

		if has_positive_cross and has_negative_cross:
			return false

	return true


func _is_point_on_segment(point: Vector2, start: Vector2, finish: Vector2) -> bool:
	var segment := finish - start
	return (
		absf(segment.cross(point - start)) <= 0.001
		and (point - start).dot(point - finish) <= 0.001
	)


func _segments_intersect(
	first_start: Vector2,
	first_finish: Vector2,
	second_start: Vector2,
	second_finish: Vector2
) -> bool:
	var first_segment := first_finish - first_start
	var second_segment := second_finish - second_start
	var first_cross_a := first_segment.cross(second_start - first_start)
	var first_cross_b := first_segment.cross(second_finish - first_start)
	var second_cross_a := second_segment.cross(first_start - second_start)
	var second_cross_b := second_segment.cross(first_finish - second_start)

	if (
		absf(first_cross_a) <= 0.001
		and _is_point_on_segment(second_start, first_start, first_finish)
	):
		return true

	if (
		absf(first_cross_b) <= 0.001
		and _is_point_on_segment(second_finish, first_start, first_finish)
	):
		return true

	if (
		absf(second_cross_a) <= 0.001
		and _is_point_on_segment(first_start, second_start, second_finish)
	):
		return true

	if (
		absf(second_cross_b) <= 0.001
		and _is_point_on_segment(first_finish, second_start, second_finish)
	):
		return true

	return (
		((first_cross_a > 0.0) != (first_cross_b > 0.0))
		and ((second_cross_a > 0.0) != (second_cross_b > 0.0))
	)


func _distance_from_point_to_segment(
	point: Vector2,
	start: Vector2,
	finish: Vector2
) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()

	if length_squared <= 0.0001:
		return point.distance_to(start)

	var projection := clampf(
		(point - start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(start + segment * projection)


func _distance_between_segments(
	first_start: Vector2,
	first_finish: Vector2,
	second_start: Vector2,
	second_finish: Vector2
) -> float:
	if _segments_intersect(first_start, first_finish, second_start, second_finish):
		return 0.0

	return minf(
		minf(
			_distance_from_point_to_segment(first_start, second_start, second_finish),
			_distance_from_point_to_segment(first_finish, second_start, second_finish)
		),
		minf(
			_distance_from_point_to_segment(second_start, first_start, first_finish),
			_distance_from_point_to_segment(second_finish, first_start, first_finish)
		)
	)


func _debug_log(message: String) -> void:
	if source != null and is_instance_valid(source) and source.has_method("debug_log"):
		source.debug_log(message)
