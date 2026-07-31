extends SceneTree

const MovementCommandExecutorScript := preload(
	"res://scripts/commands/movement_command_executor.gd"
)
const MovementSlotResolverScript := preload(
	"res://scripts/combat/movement_slot_resolver.gd"
)

const EXPECTED_SPACING_PIXELS: float = 48.0
const TEST_RAIDER_COUNT: int = 20


class DummyBoss:
	extends Node2D

	var combat_radius: float = 128.0


	func get_combat_radius() -> float:
		return combat_radius


class DummyRaider:
	extends Node2D

	var manual_move_stop_distance: float = 12.0
	var mini_region_footprint_radius: float = 12.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not is_equal_approx(
		MovementSlotResolverScript.RAIDER_FORMATION_SPACING_PIXELS,
		EXPECTED_SPACING_PIXELS
	):
		_fail("The raider formation spacing target changed unexpectedly.")
		return

	if not _test_default_formation_spacing():
		return

	if not _test_crowded_destination_spacing():
		return

	print("Raider formation spacing regression test passed.")
	quit(0)


func _test_default_formation_spacing() -> bool:
	var positions := MovementSlotResolverScript.get_formation_positions(
		Vector2.ZERO,
		TEST_RAIDER_COUNT
	)

	return _positions_preserve_spacing(positions, "Default formation")


func _test_crowded_destination_spacing() -> bool:
	var boss := DummyBoss.new()
	var raider := DummyRaider.new()
	var stationary_raider := DummyRaider.new()
	root.add_child(boss)
	root.add_child(raider)
	root.add_child(stationary_raider)
	boss.global_position = Vector2.ZERO
	stationary_raider.global_position = Vector2(0.0, 520.0)
	stationary_raider.add_to_group("party_member")

	var executor := MovementCommandExecutorScript.new()
	executor.setup(boss, null, Callable())
	var source := Vector2(0.0, 520.0)
	var occupied_destinations := executor.build_occupied_destinations([raider])
	var positions: Array[Vector2] = []
	positions.append(stationary_raider.global_position)

	for _unit_index in range(TEST_RAIDER_COUNT):
		var destination: Vector2 = executor.get_nearest_available_mini_region_destination(
			raider,
			source,
			MovementSlotResolverScript.REGION_SOUTH,
			MovementSlotResolverScript.RANGE_MID,
			occupied_destinations
		)
		positions.append(destination)

		if not MovementSlotResolverScript.is_position_safely_inside_mini_region(
			boss,
			destination,
			MovementSlotResolverScript.REGION_SOUTH,
			MovementSlotResolverScript.RANGE_MID,
			raider.manual_move_stop_distance
			+ raider.mini_region_footprint_radius
			+ MovementCommandExecutorScript.MINI_REGION_SAFETY_BUFFER
		):
			_fail("A spread destination escaped the requested mini-region.")
			return false

	return _positions_preserve_spacing(positions, "Crowded destination allocation")


func _positions_preserve_spacing(positions: Array[Vector2], label: String) -> bool:
	for position_index in range(positions.size()):
		for other_index in range(position_index + 1, positions.size()):
			var distance := positions[position_index].distance_to(positions[other_index])

			if distance < EXPECTED_SPACING_PIXELS - 0.01:
				_fail(
					label
					+ " placed raiders only "
					+ str(snappedf(distance, 0.01))
					+ " pixels apart."
				)
				return false

	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
