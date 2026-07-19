extends Node2D
class_name CleaveImpactEffect

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

@export var duration: float = 0.35
@export var particle_count: int = 48
@export var fill_color: Color = Color(0.85, 0.95, 1.0, 0.20)
@export var edge_color: Color = Color(0.95, 1.0, 1.0, 0.75)
@export var particle_color: Color = Color(0.95, 1.0, 1.0, 0.90)

var elapsed: float = 0.0

var target_region: String = MovementSlotResolverScript.REGION_NORTH
var affected_ranges: Array[String] = [
	MovementSlotResolverScript.RANGE_CLOSE
]

var boss_radius: float = 128.0
var max_effect_range_units: float = 50.0

var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func setup(
	new_target_region: String,
	new_affected_ranges: Array[String],
	new_boss_radius: float,
	new_max_effect_range_units: float = 50.0
) -> void:
	target_region = new_target_region
	affected_ranges = new_affected_ranges.duplicate()
	boss_radius = new_boss_radius
	max_effect_range_units = new_max_effect_range_units

	generate_particles()
	queue_redraw()


func _ready() -> void:
	rng.randomize()

	if particles.is_empty():
		generate_particles()


func _process(delta: float) -> void:
	elapsed += delta

	if elapsed >= duration:
		queue_free()
		return

	queue_redraw()


func _draw() -> void:
	var progress: float = clamp(elapsed / duration, 0.0, 1.0)
	var fade: float = 1.0 - progress

	draw_region_flash(fade)
	draw_impact_particles(fade)


func draw_region_flash(fade: float) -> void:
	for range_name in affected_ranges:
		var polygon: PackedVector2Array = get_region_range_polygon(target_region, range_name)

		if polygon.size() < 3:
			continue

		draw_colored_polygon(
			polygon,
			Color(fill_color.r, fill_color.g, fill_color.b, fill_color.a * fade)
		)

		var closed_polygon := PackedVector2Array(polygon)
		closed_polygon.append(polygon[0])

		draw_polyline(
			closed_polygon,
			Color(edge_color.r, edge_color.g, edge_color.b, edge_color.a * fade),
			3.0,
			true
		)


func draw_impact_particles(fade: float) -> void:
	for particle in particles:
		var start_position: Vector2 = particle["position"]
		var velocity: Vector2 = particle["velocity"]
		var radius: float = float(particle["radius"])

		var position: Vector2 = start_position + velocity * elapsed
		var current_radius: float = radius * fade

		draw_circle(
			position,
			current_radius,
			Color(
				particle_color.r,
				particle_color.g,
				particle_color.b,
				particle_color.a * fade
			)
		)


func generate_particles() -> void:
	particles.clear()

	if affected_ranges.is_empty() or particle_count <= 0:
		return

	var particles_per_range: int = max(1, int(particle_count / affected_ranges.size()))

	for range_name in affected_ranges:
		for _i in range(particles_per_range):
			var start_position: Vector2 = get_random_point_in_region_range(target_region, range_name)
			var outward_direction: Vector2 = start_position.normalized()

			if outward_direction.length() <= 0.01:
				outward_direction = Vector2.UP

			var tangent_direction: Vector2 = outward_direction.rotated(PI / 2.0)
			var velocity: Vector2 = (
				outward_direction * rng.randf_range(140.0, 280.0)
				+ tangent_direction * rng.randf_range(-90.0, 90.0)
			)

			particles.append({
				"position": start_position,
				"velocity": velocity,
				"radius": rng.randf_range(3.0, 8.0)
			})


func get_region_range_polygon(region: String, range_name: String) -> PackedVector2Array:
	var band_apothems: Vector2 = get_range_band_apothems(range_name)
	var inner_circumradius: float = get_octagon_circumradius_from_apothem(band_apothems.x)
	var outer_circumradius: float = get_octagon_circumradius_from_apothem(band_apothems.y)

	var boundary_directions: Array[Vector2] = get_region_boundary_directions(region)
	var left_direction: Vector2 = boundary_directions[0]
	var right_direction: Vector2 = boundary_directions[1]

	var points := PackedVector2Array()
	points.append(left_direction * inner_circumradius)
	points.append(left_direction * outer_circumradius)
	points.append(right_direction * outer_circumradius)
	points.append(right_direction * inner_circumradius)

	return points


func get_random_point_in_region_range(region: String, range_name: String) -> Vector2:
	var band_apothems: Vector2 = get_range_band_apothems(range_name)
	var inner_circumradius: float = get_octagon_circumradius_from_apothem(band_apothems.x)
	var outer_circumradius: float = get_octagon_circumradius_from_apothem(band_apothems.y)

	var boundary_directions: Array[Vector2] = get_region_boundary_directions(region)
	var left_direction: Vector2 = boundary_directions[0]
	var right_direction: Vector2 = boundary_directions[1]

	var depth_t: float = rng.randf_range(0.0, 1.0)
	var side_t: float = rng.randf_range(0.0, 1.0)

	var distance: float = lerpf(inner_circumradius, outer_circumradius, depth_t)

	var left_point: Vector2 = left_direction * distance
	var right_point: Vector2 = right_direction * distance

	return left_point.lerp(right_point, side_t)


func get_range_band_apothems(range_name: String) -> Vector2:
	var close_mid_boundary: float = get_range_boundary_apothem(
		MovementSlotResolverScript.RANGE_CLOSE,
		MovementSlotResolverScript.RANGE_MID
	)

	var mid_far_boundary: float = get_range_boundary_apothem(
		MovementSlotResolverScript.RANGE_MID,
		MovementSlotResolverScript.RANGE_FAR
	)

	var max_outer_apothem: float = boss_radius + CombatMeasurementsScript.range_units_to_pixels(
		max_effect_range_units
	)

	match range_name:
		MovementSlotResolverScript.RANGE_CLOSE:
			return Vector2(boss_radius, close_mid_boundary)

		MovementSlotResolverScript.RANGE_MID:
			return Vector2(close_mid_boundary, mid_far_boundary)

		MovementSlotResolverScript.RANGE_FAR:
			return Vector2(mid_far_boundary, max_outer_apothem)

		_:
			return Vector2(boss_radius, close_mid_boundary)


func get_range_boundary_apothem(range_a: String, range_b: String) -> float:
	var offset_a_units: float = MovementSlotResolverScript.get_range_offset_units(range_a)
	var offset_b_units: float = MovementSlotResolverScript.get_range_offset_units(range_b)

	var boundary_offset_units: float = (offset_a_units + offset_b_units) * 0.5
	var boundary_offset_pixels: float = CombatMeasurementsScript.range_units_to_pixels(boundary_offset_units)

	return boss_radius + boundary_offset_pixels


func get_region_boundary_directions(region: String) -> Array[Vector2]:
	var center_direction: Vector2 = MovementSlotResolverScript.get_region_direction(region)
	var center_angle: float = center_direction.angle()

	var left_boundary_angle: float = center_angle - PI / 8.0
	var right_boundary_angle: float = center_angle + PI / 8.0

	return [
		Vector2.RIGHT.rotated(left_boundary_angle),
		Vector2.RIGHT.rotated(right_boundary_angle)
	]


func get_octagon_circumradius_from_apothem(apothem: float) -> float:
	return apothem / cos(PI / 8.0)
