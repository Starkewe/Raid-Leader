extends Node2D
class_name BossDebugVisuals

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var boss: Node = null
var combat_radius: float = 128.0
var max_range_units: float = 50.0
var show_regions: bool = false
var show_ranges: bool = false


func setup(
	new_boss: Node,
	new_combat_radius: float,
	new_max_range_units: float,
	new_show_regions: bool,
	new_show_ranges: bool
) -> void:
	boss = new_boss
	combat_radius = new_combat_radius
	max_range_units = new_max_range_units
	show_regions = new_show_regions
	show_ranges = new_show_ranges
	queue_redraw()


func _draw() -> void:
	if show_ranges:
		draw_range_boundaries()

	if show_regions:
		draw_region_boundaries()


func draw_region_boundaries() -> void:
	var extended_apothem := get_max_range_apothem() + 80.0
	var max_circumradius := get_octagon_circumradius_from_apothem(extended_apothem)

	for boundary_index in range(8):
		var direction := get_region_boundary_direction(boundary_index)
		draw_line(Vector2.ZERO, direction * max_circumradius, Color(1, 1, 1, 0.55), 2.0)


func draw_range_boundaries() -> void:
	draw_octagon_outline(combat_radius, Color(1, 1, 1, 0.45))
	draw_octagon_outline(
		get_range_boundary_apothem(
			MovementSlotResolverScript.RANGE_CLOSE,
			MovementSlotResolverScript.RANGE_MID
		),
		Color(0.2, 1.0, 0.2, 0.55)
	)
	draw_octagon_outline(
		get_range_boundary_apothem(
			MovementSlotResolverScript.RANGE_MID,
			MovementSlotResolverScript.RANGE_FAR
		),
		Color(1.0, 1.0, 0.2, 0.55)
	)
	draw_octagon_outline(get_max_range_apothem(), Color(0.2, 0.6, 1.0, 0.65))


func get_range_boundary_apothem(range_a: String, range_b: String) -> float:
	var offset_units := (
		MovementSlotResolverScript.get_range_offset_units(range_a)
		+ MovementSlotResolverScript.get_range_offset_units(range_b)
	) * 0.5
	return combat_radius + CombatMeasurementsScript.range_units_to_pixels(offset_units)


func draw_octagon_outline(apothem: float, color: Color, width: float = 2.0) -> void:
	var points := get_octagon_points_from_apothem(apothem)

	if points.size() < 2:
		return

	points.append(points[0])
	draw_polyline(points, color, width, true)


func get_octagon_points_from_apothem(apothem: float) -> PackedVector2Array:
	var points := PackedVector2Array()

	if apothem <= 0.0:
		return points

	var circumradius := get_octagon_circumradius_from_apothem(apothem)

	for boundary_index in range(8):
		points.append(get_region_boundary_direction(boundary_index) * circumradius)

	return points


func get_octagon_circumradius_from_apothem(apothem: float) -> float:
	return apothem / cos(PI / 8.0)


func get_region_boundary_direction(index: int) -> Vector2:
	var angle := -PI / 2.0 - PI / 8.0 + (TAU / 8.0) * float(index)
	return Vector2.RIGHT.rotated(angle)


func get_max_range_apothem() -> float:
	return combat_radius + CombatMeasurementsScript.range_units_to_pixels(max_range_units)
