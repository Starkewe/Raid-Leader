extends SceneTree


class DummyBoss:
	extends Node2D

	var combat_radius: float = 128.0
	var current_target: Node2D = null

	func get_combat_radius() -> float:
		return combat_radius

	func get_current_target() -> Node2D:
		return current_target


class DummyRaider:
	extends Node2D

	var manual_move_stop_distance: float = 12.0
	var mini_region_footprint_radius: float = 12.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var boss := DummyBoss.new()
	var tank := Node2D.new()
	root.add_child(boss)
	root.add_child(tank)

	boss.global_position = Vector2.ZERO
	var source := Vector2.from_angle(PI / 4.0) * 500.0
	var destination := MovementSlotResolver.get_closest_point_in_mini_region(
		boss,
		source,
		MovementSlotResolver.REGION_SOUTH,
		MovementSlotResolver.RANGE_MID,
		28.0
	)

	if not MovementSlotResolver.is_position_safely_inside_mini_region(
		boss,
		destination,
		MovementSlotResolver.REGION_SOUTH,
		MovementSlotResolver.RANGE_MID,
		28.0
	):
		_fail("The nearest destination did not preserve the requested safe inset.")
		return

	var early_stop := destination.move_toward(source, 12.0)

	if not MovementSlotResolver.is_position_safely_inside_mini_region(
		boss,
		early_stop,
		MovementSlotResolver.REGION_SOUTH,
		MovementSlotResolver.RANGE_MID,
		12.0
	):
		_fail("Stopping tolerance left part of the raider outside the mini-region.")
		return

	var boundary_position := Vector2.from_angle(3.0 * PI / 8.0) * 500.0
	var reclamped := MovementSlotResolver.get_closest_point_in_mini_region(
		boss,
		boundary_position,
		MovementSlotResolver.REGION_SOUTH,
		MovementSlotResolver.RANGE_MID,
		28.0
	)

	if reclamped.is_equal_approx(boundary_position):
		_fail("A point-classified destination on the boundary was not moved inward.")
		return

	tank.global_position = destination
	boss.current_target = tank
	var cleave := DirectionalRegionCleave.new()

	if cleave.get_target_region_from_boss(boss) != MovementSlotResolver.REGION_SOUTH:
		_fail("A tank safely positioned south still aimed the cone southeast.")
		return

	if not _test_octagonal_range_geometry(boss):
		return

	if not _test_bounded_local_destination_allocation(boss):
		return

	print("Mini-region safe entry regression test passed.")
	quit(0)


func _test_octagonal_range_geometry(boss: DummyBoss) -> bool:
	var region_direction := MovementSlotResolver.get_region_direction(
		MovementSlotResolver.REGION_SOUTH
	)
	var mid_far_boundary_apothem := (
		boss.combat_radius
		+ CombatMeasurements.range_units_to_pixels(30.0)
	)
	var corner_angle := 3.0 * PI / 8.0 + 0.01
	var relative_angle := absf(
		wrapf(corner_angle - region_direction.angle(), -PI, PI)
	)
	var visibly_mid_position := (
		Vector2.from_angle(corner_angle)
		* ((mid_far_boundary_apothem - 10.0) / cos(relative_angle))
	)

	if MovementSlotResolver.get_nearest_range_from_position(
		boss,
		visibly_mid_position
	) != MovementSlotResolver.RANGE_MID:
		_fail(
			"A position inside the visible mid octagon was incorrectly "
			+ "classified as far."
		)
		return false

	var far_destination := MovementSlotResolver.get_closest_point_in_mini_region(
		boss,
		visibly_mid_position,
		MovementSlotResolver.REGION_SOUTH,
		MovementSlotResolver.RANGE_FAR,
		28.0
	)

	if far_destination.dot(region_direction) < mid_far_boundary_apothem + 27.99:
		_fail("The far destination stopped before crossing the visible far boundary.")
		return false

	if not MovementSlotResolver.is_position_safely_inside_mini_region(
		boss,
		far_destination,
		MovementSlotResolver.REGION_SOUTH,
		MovementSlotResolver.RANGE_FAR,
		28.0
	):
		_fail("The far destination was not safely inside the visible far region.")
		return false

	return true


func _test_bounded_local_destination_allocation(boss: DummyBoss) -> bool:
	var executor := MovementCommandExecutor.new()
	executor.setup(boss, null, Callable())
	var raider := DummyRaider.new()
	root.add_child(raider)
	var source := Vector2.from_angle(PI / 4.0) * 500.0
	var safety_inset := (
		raider.manual_move_stop_distance
		+ raider.mini_region_footprint_radius
		+ 4.0
	)
	var nearest_destination := MovementSlotResolver.get_closest_point_in_mini_region(
		boss,
		source,
		MovementSlotResolver.REGION_SOUTH,
		MovementSlotResolver.RANGE_MID,
		safety_inset
	)
	var occupied_destinations: Dictionary = {}
	var maximum_adjustment := MovementCommandExecutor.LOCAL_DESTINATION_MAX_ADJUSTMENT

	for _unit_index in range(20):
		var allocated_destination := (
			executor.get_nearest_available_mini_region_destination(
				raider,
				source,
				MovementSlotResolver.REGION_SOUTH,
				MovementSlotResolver.RANGE_MID,
				occupied_destinations
			)
		)

		if _unit_index == 0 and not allocated_destination.is_equal_approx(
			nearest_destination
		):
			_fail("An unoccupied destination did not use the nearest safe point.")
			return false

		if allocated_destination.distance_to(nearest_destination) > (
			maximum_adjustment + 0.01
		):
			_fail(
				"Local spacing moved a crowded destination farther than the "
				+ str(maximum_adjustment)
				+ "-pixel allocation limit."
			)
			return false

		if source.distance_to(allocated_destination) > (
			source.distance_to(nearest_destination) + maximum_adjustment + 0.01
		):
			_fail(
				"Local spacing created an unnecessarily long movement path."
			)
			return false

		if not MovementSlotResolver.is_position_safely_inside_mini_region(
			boss,
			allocated_destination,
			MovementSlotResolver.REGION_SOUTH,
			MovementSlotResolver.RANGE_MID,
			safety_inset
		):
			_fail("A locally adjusted destination escaped the safe interior.")
			return false

	raider.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
