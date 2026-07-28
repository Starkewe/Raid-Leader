extends Node2D
class_name CombatImpactEffect

signal finished(effect: Node)

enum VisualStyle {
	MELEE,
	PHYSICAL,
	MAGIC,
	HEAL
}

var visual_style: VisualStyle = VisualStyle.MELEE
var active: bool = false
var elapsed: float = 0.0
var effect_duration: float = 0.20


func _ready() -> void:
	visible = false
	set_process(false)


func activate(
	impact_position: Vector2,
	direction: Vector2,
	style: VisualStyle
) -> void:
	global_position = impact_position
	rotation = direction.angle() if not direction.is_zero_approx() else 0.0
	visual_style = style
	active = true
	elapsed = 0.0
	effect_duration = 0.28 if style == VisualStyle.HEAL else 0.20
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

	elapsed = minf(elapsed + delta, effect_duration)
	queue_redraw()

	if elapsed >= effect_duration:
		complete()


func complete() -> void:
	active = false
	visible = false
	set_process(false)
	finished.emit(self)


func _draw() -> void:
	if not active:
		return

	var progress := clampf(elapsed / effect_duration, 0.0, 1.0)
	var fade := 1.0 - progress

	match visual_style:
		VisualStyle.HEAL:
			var radius := 7.0 + progress * 20.0
			draw_arc(
				Vector2.ZERO,
				radius,
				0.0,
				TAU,
				24,
				Color(0.50, 1.0, 0.62, 0.68 * fade),
				2.4,
				true
			)
			draw_circle(
				Vector2.ZERO,
				5.0 * fade,
				Color(0.76, 1.0, 0.80, 0.28 * fade)
			)

		VisualStyle.MAGIC:
			var radius := 5.0 + progress * 15.0
			draw_arc(
				Vector2.ZERO,
				radius,
				0.0,
				TAU,
				20,
				Color(0.42, 0.70, 1.0, 0.76 * fade),
				2.0,
				true
			)

		VisualStyle.PHYSICAL:
			draw_line(
				Vector2(-10.0, 0.0),
				Vector2(10.0 + progress * 8.0, 0.0),
				Color(1.0, 0.84, 0.48, 0.78 * fade),
				2.5,
				true
			)

		_:
			var arc_points := PackedVector2Array()
			var radius := 16.0 + progress * 7.0

			for point_index in range(10):
				var point_progress := float(point_index) / 9.0
				var angle := lerpf(-0.85, 0.85, point_progress)
				arc_points.append(Vector2.from_angle(angle) * radius)

			draw_polyline(
				arc_points,
				Color(1.0, 0.78, 0.34, 0.88 * fade),
				3.0,
				true
			)
