extends Node2D
class_name CarrionRocVisuals

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var runtime: EncounterRuntime = null
var boss: Node2D = null


func setup(new_runtime: EncounterRuntime, new_boss: Node2D) -> void:
	runtime = new_runtime
	boss = new_boss
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_placeholder_roc()

	if runtime == null or not is_instance_valid(runtime) or boss == null:
		return

	var presentation := runtime.get_presentation_state()
	var rupture_data: Array = presentation.get("ruptures", [])
	for rupture_value in rupture_data:
		if not rupture_value is Dictionary:
			continue

		var rupture: Dictionary = rupture_value
		var region := String(rupture.get("region", "east"))
		var range_name := String(rupture.get("range", "mid"))
		var polygon := MovementSlotResolverScript.get_mini_region_polygon(
			MovementSlotResolverScript.get_boss_combat_radius(boss),
			region,
			range_name,
			50.0
		)
		var side := String(rupture.get("side", "east"))
		var color := Color(1.0, 0.55, 0.12, 0.28) if side == "east" else Color(0.3, 0.7, 1.0, 0.28)
		var edge := Color(1.0, 0.74, 0.24, 0.95) if side == "east" else Color(0.45, 0.85, 1.0, 0.95)
		draw_colored_polygon(polygon, color)
		draw_polyline(PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]]), edge, 3.0)

		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(
				font,
				polygon[0] + Vector2(4.0, -4.0),
				"%s rupture %.1f" % [side.capitalize(), float(rupture.get("remaining", 0.0))],
				HORIZONTAL_ALIGNMENT_LEFT,
				180.0,
				14,
				edge
			)

	var growth_data: Array = presentation.get("growths", [])
	for growth_value in growth_data:
		if not growth_value is Dictionary:
			continue

		var growth: Dictionary = growth_value
		var world_position: Vector2 = growth.get("position", boss.global_position)
		var local_position := to_local(world_position)
		draw_circle(local_position, 30.0, Color(0.32, 0.9, 0.22, 0.12))
		draw_arc(local_position, 30.0, 0.0, TAU, 32, Color(0.56, 1.0, 0.32, 0.5), 2.0)


func _draw_placeholder_roc() -> void:
	# Intentionally code-drawn until the final Roc art pass lands.
	draw_circle(Vector2.ZERO, 54.0, Color(0.16, 0.12, 0.10, 0.96))
	draw_circle(Vector2(0.0, -8.0), 35.0, Color(0.28, 0.23, 0.19, 1.0))
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-22.0, -18.0), Vector2(-128.0, -55.0), Vector2(-92.0, 8.0),
			Vector2(-35.0, 12.0)
		]),
		Color(0.22, 0.17, 0.14, 1.0)
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(22.0, -18.0), Vector2(128.0, -55.0), Vector2(92.0, 8.0),
			Vector2(35.0, 12.0)
		]),
		Color(0.22, 0.17, 0.14, 1.0)
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-10.0, 20.0), Vector2(-26.0, 85.0), Vector2(0.0, 48.0),
			Vector2(26.0, 85.0), Vector2(10.0, 20.0)
		]),
		Color(0.14, 0.10, 0.08, 1.0)
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(28.0, -10.0), Vector2(84.0, -4.0), Vector2(35.0, 12.0)
		]),
		Color(0.82, 0.48, 0.14, 1.0)
	)
	draw_circle(Vector2(10.0, -18.0), 5.0, Color(1.0, 0.78, 0.28, 1.0))
