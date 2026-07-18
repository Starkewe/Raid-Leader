extends RefCounted
class_name MovementCommandExecutor

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

signal refresh_requested
signal temporary_status_requested(unit: Node, text: String, duration: float)

var boss: Node = null
var player: Node = null
var is_unit_alive_callable: Callable = Callable()


func setup(new_boss: Node, new_player: Node, new_is_unit_alive_callable: Callable) -> void:
	boss = new_boss
	player = new_player
	is_unit_alive_callable = new_is_unit_alive_callable


func execute_move(selected_units: Array, command_data: Dictionary) -> bool:
	var where: String = String(command_data.get("where", "none"))

	match where:
		"me":
			return execute_move_to_player(selected_units)

		"movement_slot":
			var region := String(command_data.get("movement_region", "north"))
			var range_name := String(command_data.get("movement_range", "mid"))
			return execute_move_to_slot(selected_units, region, range_name)

		"movement_region":
			var region := String(command_data.get("movement_region", "north"))
			return execute_move_to_region(selected_units, region)

		"movement_rotate":
			var region := String(command_data.get("movement_region", "north"))
			return execute_rotate_to_region(selected_units, region)

		"movement_rotate_step":
			var direction := String(command_data.get("movement_direction", "clockwise"))
			return execute_rotate_step(selected_units, direction)

		"movement_range":
			var range_name := String(command_data.get("movement_range", "mid"))
			return execute_move_to_range(selected_units, range_name)

		"movement_range_step":
			var direction := String(command_data.get("movement_direction", "out"))
			return execute_range_step(selected_units, direction)

		_:
			print("Unsupported movement destination:", where)
			return false


func execute_move_to_player(selected_units: Array) -> bool:
	if not is_valid_node(player):
		print("Player node is missing.")
		return false

	if not player is Node2D:
		print("Player node is not a Node2D.")
		return false

	var player_2d := player as Node2D

	return command_units_to_shared_position(
		selected_units,
		player_2d.global_position,
		"Moving to Player"
	)


func execute_move_to_slot(selected_units: Array, region: String, range_name: String) -> bool:
	if not is_valid_node(boss):
		print("Boss is missing. Cannot resolve movement slot.")
		return false

	var living_units := get_living_movable_units(selected_units)
	var destinations := MovementSlotResolverScript.get_slot_formation_positions(
		boss,
		region,
		range_name,
		living_units.size()
	)

	return command_units_to_positions(
		living_units,
		destinations,
		"Moving " + region.capitalize() + " " + range_name.capitalize()
	)


func execute_move_to_region(selected_units: Array, region: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot move to region.")
		return false

	var boss_2d := boss as Node2D
	var issued_command := false
	var living_units := get_living_movable_units(selected_units)

	for unit_index in range(living_units.size()):
		var unit = living_units[unit_index]
		var unit_2d := unit as Node2D

		var current_range: String = MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		var slot_center: Vector2 = MovementSlotResolverScript.get_slot_position(
			boss,
			region,
			current_range
		)
		var destination := get_formation_destination(
			slot_center,
			unit_index,
			living_units.size(),
			region
		)

		unit.command_move_to_position(destination)

		temporary_status_requested.emit(
			unit,
			"Moving " + region.capitalize(),
			0.75
		)

		issued_command = true

	if not issued_command:
		print("No selected units can move to region.")
		return false

	refresh_requested.emit()
	return true


func execute_rotate_step(selected_units: Array, rotation_direction: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot rotate movement.")
		return false

	var boss_2d := boss as Node2D
	var issued_command := false
	var living_units := get_living_movable_units(selected_units)

	for unit_index in range(living_units.size()):
		var unit = living_units[unit_index]
		var unit_2d := unit as Node2D

		var current_region: String = MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var current_range: String = MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		var next_region: String = MovementSlotResolverScript.get_adjacent_region(
			current_region,
			rotation_direction
		)

		var slot_center: Vector2 = MovementSlotResolverScript.get_slot_position(
			boss,
			next_region,
			current_range
		)
		var destination := get_formation_destination(
			slot_center,
			unit_index,
			living_units.size(),
			next_region
		)

		unit.command_move_to_position(destination)

		temporary_status_requested.emit(
			unit,
			"Rotating " + rotation_direction.capitalize(),
			0.75
		)

		issued_command = true

	if not issued_command:
		print("No selected units can rotate.")
		return false

	refresh_requested.emit()
	return true


func execute_rotate_to_region(selected_units: Array, region: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot rotate movement.")
		return false

	var boss_2d := boss as Node2D
	var issued_command := false
	var living_units := get_living_movable_units(selected_units)

	for unit_index in range(living_units.size()):
		var unit = living_units[unit_index]
		var unit_2d := unit as Node2D

		var current_region: String = MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var current_range: String = MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		var region_path: Array[String] = MovementSlotResolverScript.get_region_rotation_path(
			current_region,
			region
		)

		var destinations: Array[Vector2] = []

		for path_region in region_path:
			var slot_center: Vector2 = MovementSlotResolverScript.get_slot_position(
				boss,
				path_region,
				current_range
			)
			var destination := get_formation_destination(
				slot_center,
				unit_index,
				living_units.size(),
				path_region
			)

			destinations.append(destination)

		if destinations.is_empty():
			continue

		if unit.has_method("command_move_through_positions"):
			unit.command_move_through_positions(destinations)
		else:
			unit.command_move_to_position(destinations[destinations.size() - 1])

		temporary_status_requested.emit(
			unit,
			"Rotating " + region.capitalize(),
			0.75
		)

		issued_command = true

	if not issued_command:
		print("No selected units can rotate.")
		return false

	refresh_requested.emit()
	return true


func execute_move_to_range(selected_units: Array, range_name: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot change movement range.")
		return false

	var boss_2d := boss as Node2D
	var issued_command := false
	var living_units := get_living_movable_units(selected_units)

	for unit_index in range(living_units.size()):
		var unit = living_units[unit_index]
		var unit_2d := unit as Node2D

		var current_region: String = MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var slot_center: Vector2 = MovementSlotResolverScript.get_slot_position(
			boss,
			current_region,
			range_name
		)
		var destination := get_formation_destination(
			slot_center,
			unit_index,
			living_units.size(),
			current_region
		)

		unit.command_move_to_position(destination)

		temporary_status_requested.emit(
			unit,
			"Moving " + range_name.capitalize(),
			0.75
		)

		issued_command = true

	if not issued_command:
		print("No selected units can change range.")
		return false

	refresh_requested.emit()
	return true


func execute_range_step(selected_units: Array, range_direction: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot step range.")
		return false

	var boss_2d := boss as Node2D
	var issued_command := false
	var living_units := get_living_movable_units(selected_units)

	for unit_index in range(living_units.size()):
		var unit = living_units[unit_index]
		var unit_2d := unit as Node2D

		var current_region: String = MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var current_range: String = MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		var next_range: String = MovementSlotResolverScript.get_adjacent_range(
			current_range,
			range_direction
		)

		if next_range == current_range:
			var boundary_text := "Already " + current_range

			if range_direction == MovementSlotResolverScript.RANGE_DIRECTION_IN:
				boundary_text = "Already close"
			elif range_direction == MovementSlotResolverScript.RANGE_DIRECTION_OUT:
				boundary_text = "Already far"

			temporary_status_requested.emit(unit, boundary_text, 0.75)
			continue

		var slot_center: Vector2 = MovementSlotResolverScript.get_slot_position(
			boss,
			current_region,
			next_range
		)
		var destination := get_formation_destination(
			slot_center,
			unit_index,
			living_units.size(),
			current_region
		)

		unit.command_move_to_position(destination)

		var status_text := "Moving " + range_direction

		if range_direction == MovementSlotResolverScript.RANGE_DIRECTION_IN:
			status_text = "Moving in"
		elif range_direction == MovementSlotResolverScript.RANGE_DIRECTION_OUT:
			status_text = "Moving out"

		temporary_status_requested.emit(unit, status_text, 0.75)
		issued_command = true

	if not issued_command:
		print("No selected units can step range.")
		refresh_requested.emit()
		return false

	refresh_requested.emit()
	return true


func command_units_to_shared_position(selected_units: Array, destination: Vector2, status_text: String) -> bool:
	var living_units := get_living_movable_units(selected_units)
	var outward_direction := Vector2.DOWN

	if is_valid_node(boss) and boss is Node2D:
		outward_direction = (destination - (boss as Node2D).global_position).normalized()

	var destinations := MovementSlotResolverScript.get_formation_positions(
		destination,
		living_units.size(),
		outward_direction
	)

	return command_units_to_positions(living_units, destinations, status_text)


func command_units_to_positions(
	selected_units: Array,
	destinations: Array[Vector2],
	status_text: String
) -> bool:
	var issued_command := false

	for unit_index in range(selected_units.size()):
		var unit = selected_units[unit_index]

		if not is_unit_alive(unit):
			continue

		if not unit.has_method("command_move_to_position"):
			continue

		if unit_index >= destinations.size():
			continue

		unit.command_move_to_position(destinations[unit_index])
		temporary_status_requested.emit(unit, status_text, 0.75)
		issued_command = true

	if not issued_command:
		print("No selected units can move.")
		return false

	refresh_requested.emit()
	return true


func get_formation_destination(
	center: Vector2,
	unit_index: int,
	unit_count: int,
	region: String
) -> Vector2:
	var positions := MovementSlotResolverScript.get_formation_positions(
		center,
		unit_count,
		MovementSlotResolverScript.get_region_direction(region)
	)

	if unit_index < 0 or unit_index >= positions.size():
		return center

	return positions[unit_index]


func get_living_movable_units(source_units: Array) -> Array:
	var movable_units: Array = []

	for unit in source_units:
		if not is_unit_alive(unit):
			continue

		if not unit is Node2D:
			continue

		if not unit.has_method("command_move_to_position"):
			continue

		movable_units.append(unit)

	return movable_units


func is_unit_alive(unit: Node) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if not is_unit_alive_callable.is_null():
		return bool(is_unit_alive_callable.call(unit))

	if unit.has_method("is_alive"):
		return unit.is_alive()

	return true


func is_valid_node(node: Node) -> bool:
	return node != null and is_instance_valid(node)
