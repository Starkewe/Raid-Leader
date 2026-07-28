extends Node2D
class_name BossTargetIndicator

@export var rotation_speed: float = 15.0
@export var ring_padding: float = 14.0

var boss: Node2D = null
var current_target: Node2D = null
var marker_angle: float = 0.0
var marker_initialized: bool = false
var visual_time: float = 0.0


func setup(new_boss: Node2D) -> void:
	boss = new_boss
	position = Vector2.ZERO
	queue_redraw()


func _process(delta: float) -> void:
	visual_time += delta

	if boss == null or not is_instance_valid(boss):
		visible = false
		return

	visible = true
	var next_target := get_boss_target()

	if next_target != null:
		var desired_angle := boss.global_position.direction_to(
			next_target.global_position
		).angle()

		if not marker_initialized:
			marker_angle = desired_angle
			marker_initialized = true
		else:
			marker_angle = get_smoothed_angle(
				marker_angle,
				desired_angle,
				delta
			)

	current_target = next_target
	queue_redraw()


func get_smoothed_angle(
	from_angle: float,
	to_angle: float,
	delta: float
) -> float:
	var weight := 1.0 - exp(-rotation_speed * maxf(delta, 0.0))
	return lerp_angle(from_angle, to_angle, clampf(weight, 0.0, 1.0))


func get_boss_target() -> Node2D:
	if boss == null or not is_instance_valid(boss):
		return null

	if not boss.has_method("get_current_target"):
		return null

	var target = boss.get_current_target()
	return target as Node2D if target is Node2D else null


func get_ring_radius() -> float:
	if boss != null and is_instance_valid(boss) and boss.has_method("get_combat_radius"):
		return maxf(float(boss.get_combat_radius()) + ring_padding, 18.0)

	return 34.0


func _draw() -> void:
	var radius := get_ring_radius()
	var has_target := current_target != null and is_instance_valid(current_target)
	var pulse := 0.5 + 0.5 * sin(visual_time * 6.0)
	var ring_color := (
		Color(0.92, 0.18, 0.12, 0.66 + pulse * 0.12)
		if has_target
		else Color(0.62, 0.20, 0.18, 0.34)
	)

	draw_arc(
		Vector2.ZERO,
		radius,
		0.0,
		TAU,
		64,
		ring_color,
		3.0,
		true
	)

	if not has_target or not marker_initialized:
		return

	var direction := Vector2.from_angle(marker_angle)
	var tangent := direction.orthogonal()
	var arrow_tip := direction * (radius + 9.0)
	var arrow_base := direction * (radius - 8.0)
	var points := PackedVector2Array([
		arrow_tip,
		arrow_base + tangent * 7.0,
		arrow_base - tangent * 7.0
	])
	draw_colored_polygon(points, Color(1.0, 0.24, 0.14, 0.90))
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]),
		Color(1.0, 0.72, 0.62, 0.92),
		1.2,
		true
	)
