extends Node2D
class_name CombatProjectileEffect

signal finished(effect: Node)

enum VisualStyle {
	PHYSICAL,
	MAGIC,
	HEAL
}

var visual_style: VisualStyle = VisualStyle.PHYSICAL
var active: bool = false
var elapsed: float = 0.0
var travel_duration: float = 0.25
var origin_position: Vector2 = Vector2.ZERO
var last_target_position: Vector2 = Vector2.ZERO
var target_offset: Vector2 = Vector2.ZERO
var target_reference: WeakRef = null
var travel_direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	visible = false
	set_process(false)


func activate(
	source_position: Vector2,
	target: Node2D,
	style: VisualStyle,
	duration: float,
	endpoint_offset: Vector2 = Vector2.ZERO
) -> void:
	visual_style = style
	active = true
	elapsed = 0.0
	travel_duration = maxf(duration, 0.05)
	origin_position = source_position
	target_offset = endpoint_offset
	target_reference = weakref(target)
	last_target_position = target.global_position + target_offset
	travel_direction = source_position.direction_to(last_target_position)
	global_position = source_position
	visible = true
	set_process(true)
	queue_redraw()


func cancel() -> void:
	if not active:
		return

	complete()


func _process(delta: float) -> void:
	if not active:
		return

	update_target_position()
	elapsed = minf(elapsed + delta, travel_duration)
	var progress := clampf(elapsed / travel_duration, 0.0, 1.0)
	var eased_progress := 1.0 - pow(1.0 - progress, 2.0)
	var next_position := origin_position.lerp(last_target_position, eased_progress)

	if visual_style == VisualStyle.HEAL:
		var perpendicular := travel_direction.orthogonal()
		next_position += perpendicular * sin(progress * PI) * 18.0

	global_position = next_position
	queue_redraw()

	if progress >= 1.0:
		complete()


func update_target_position() -> void:
	if target_reference == null:
		return

	var target: Variant = target_reference.get_ref()

	if target == null or not is_instance_valid(target) or not target is Node2D:
		target_reference = null
		return

	last_target_position = (target as Node2D).global_position + target_offset
	travel_direction = origin_position.direction_to(last_target_position)


func complete() -> void:
	active = false
	visible = false
	set_process(false)
	finished.emit(self)


func _draw() -> void:
	if not active:
		return

	var direction := travel_direction

	if direction.is_zero_approx():
		direction = Vector2.RIGHT

	var local_direction: Vector2 = direction.rotated(-global_rotation)
	var trail_start: Vector2 = -local_direction * 15.0

	match visual_style:
		VisualStyle.MAGIC:
			draw_line(
				trail_start,
				Vector2.ZERO,
				Color(0.34, 0.64, 1.0, 0.46),
				4.0,
				true
			)
			draw_circle(Vector2.ZERO, 6.0, Color(0.38, 0.62, 1.0, 0.34))
			draw_circle(Vector2.ZERO, 3.2, Color(0.78, 0.90, 1.0, 0.98))

		VisualStyle.HEAL:
			draw_line(
				trail_start,
				Vector2.ZERO,
				Color(0.32, 0.92, 0.52, 0.34),
				3.0,
				true
			)
			draw_circle(Vector2.ZERO, 5.5, Color(0.36, 0.94, 0.52, 0.34))
			draw_circle(Vector2.ZERO, 2.8, Color(0.82, 1.0, 0.86, 0.98))

		_:
			draw_line(
				trail_start,
				local_direction * 4.0,
				Color(0.95, 0.78, 0.38, 0.78),
				2.4,
				true
			)
			draw_circle(Vector2.ZERO, 2.6, Color(1.0, 0.92, 0.68, 0.96))
