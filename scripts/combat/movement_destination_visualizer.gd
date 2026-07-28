extends Node2D
class_name MovementDestinationVisualizer

const DodgeTuningScript := preload("res://scripts/combat/dodge_tuning.gd")

var tracked_units: Array = []
var redraw_timer: float = 0.0


func setup(units: Array) -> void:
	tracked_units = units.duplicate()
	queue_redraw()


func clear() -> void:
	tracked_units.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if DodgeTuningScript.DESTINATION_UPDATE_INTERVAL > 0.0:
		redraw_timer += delta

		if redraw_timer < DodgeTuningScript.DESTINATION_UPDATE_INTERVAL:
			return

		redraw_timer = 0.0

	queue_redraw()


func _draw() -> void:
	var flags_by_key: Dictionary = {}

	for unit in tracked_units:
		if not _is_valid_path_unit(unit):
			continue

		var path_points: Array = unit.get_command_path_points()
		var previous_point := to_local((unit as Node2D).global_position)
		_draw_path_origin(previous_point)

		for point_value in path_points:
			var world_point: Vector2 = point_value
			var next_point := to_local(world_point)
			_draw_dashed_segment(previous_point, next_point)
			previous_point = next_point

		if not path_points.is_empty():
			_draw_path_endpoint(previous_point)

		var destination_key := String(unit.get_command_destination_key())

		if destination_key.is_empty() or flags_by_key.has(destination_key):
			continue

		var flag_world_position: Vector2 = unit.get_command_destination_flag_position()
		flags_by_key[destination_key] = to_local(flag_world_position)

	for flag_position_value in flags_by_key.values():
		var flag_position: Vector2 = flag_position_value
		_draw_destination_flag(flag_position)


func _is_valid_path_unit(unit: Variant) -> bool:
	if unit == null or not is_instance_valid(unit) or not unit is Node2D:
		return false

	if not unit.has_method("has_active_command_path"):
		return false

	return bool(unit.has_active_command_path())


func _draw_dashed_segment(start: Vector2, finish: Vector2) -> void:
	var distance := start.distance_to(finish)

	if distance <= 0.01:
		return

	var direction := start.direction_to(finish)
	var dash_length := maxf(DodgeTuningScript.DESTINATION_LINE_DASH_LENGTH, 1.0)
	var gap_length := maxf(DodgeTuningScript.DESTINATION_LINE_GAP_LENGTH, 0.0)
	var step_length := dash_length + gap_length
	var traveled := 0.0
	var line_color := Color(1.0, 0.84, 0.26, DodgeTuningScript.DESTINATION_LINE_OPACITY)

	while traveled < distance:
		var dash_end := minf(traveled + dash_length, distance)
		draw_line(
			start + direction * traveled,
			start + direction * dash_end,
			line_color,
			DodgeTuningScript.DESTINATION_LINE_THICKNESS,
			true
		)
		traveled += step_length


func _draw_path_origin(position: Vector2) -> void:
	var color := Color(
		1.0,
		0.84,
		0.26,
		DodgeTuningScript.DESTINATION_ENDPOINT_OPACITY
	)
	draw_circle(position, DodgeTuningScript.DESTINATION_ENDPOINT_SIZE, color)


func _draw_path_endpoint(position: Vector2) -> void:
	var size := DodgeTuningScript.DESTINATION_ENDPOINT_SIZE
	var color := Color(
		1.0,
		0.84,
		0.26,
		DodgeTuningScript.DESTINATION_ENDPOINT_OPACITY
	)
	var outline := Color(
		0.12,
		0.10,
		0.05,
		DodgeTuningScript.DESTINATION_ENDPOINT_OPACITY
	)

	draw_circle(position, size, color)
	draw_arc(position, size, 0.0, TAU, 16, outline, 1.0, true)


func _draw_destination_flag(position: Vector2) -> void:
	var size := DodgeTuningScript.DESTINATION_FLAG_SIZE
	var color := Color(1.0, 0.78, 0.12, DodgeTuningScript.DESTINATION_FLAG_OPACITY)
	var outline := Color(0.12, 0.10, 0.05, DodgeTuningScript.DESTINATION_FLAG_OPACITY)
	var points := PackedVector2Array([
		position + Vector2(0.0, -size),
		position + Vector2(size, 0.0),
		position + Vector2(0.0, size),
		position + Vector2(-size, 0.0)
	])

	draw_colored_polygon(points, color)
	draw_polyline(PackedVector2Array([
		points[0], points[1], points[2], points[3], points[0]
	]), outline, 1.0, true)
