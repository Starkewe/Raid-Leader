extends Node2D
class_name CampAtmosphere

var redraw_timer: float = 0.0
var flicker_step: int = 0


func _ready() -> void:
	z_index = -450
	queue_redraw()


func _process(delta: float) -> void:
	redraw_timer -= delta

	if redraw_timer <= 0.0:
		redraw_timer = 0.12
		flicker_step = (flicker_step + 1) % 8
		queue_redraw()


func _draw() -> void:
	var fire_alpha := 0.11 + float(flicker_step % 3) * 0.015
	draw_circle(Vector2(1500, 1125), 255.0, Color(0.72, 0.31, 0.09, fire_alpha))
	draw_circle(Vector2(1500, 1125), 155.0, Color(0.95, 0.48, 0.12, fire_alpha))
	draw_circle(Vector2(1500, 520), 205.0, Color(0.55, 0.42, 0.18, 0.08))

	for lantern_position in [
		Vector2(1310, 610),
		Vector2(1690, 610),
		Vector2(2040, 880),
		Vector2(2300, 1190),
		Vector2(720, 1190),
		Vector2(1400, 1570)
	]:
		draw_circle(lantern_position, 64.0, Color(0.88, 0.48, 0.16, 0.055))

	var spark_offset := float((flicker_step * 7) % 19)
	draw_rect(Rect2(1491, 1080 - spark_offset, 4, 4), Color("e2a04f"))
	draw_rect(Rect2(1510, 1070 - fmod(spark_offset * 1.4, 24.0), 3, 3), Color("c76a32"))
