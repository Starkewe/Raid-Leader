extends RefCounted
class_name MovementCommandExecutor

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const LOCAL_DESTINATION_SPACING: float = 28.0
const LOCAL_SEPARATION_ITERATIONS: int = 8

signal refresh_requested
signal temporary_status_requested(unit: Node, text: String, duration: float)

var boss: Node = null
var player: Node = null
var is_unit_alive_callable: Callable = Callable()
var execute_as_dodge: bool = false


func setup(new_boss: Node, new_player: Node, new_is_unit_alive_callable: Callable) -> void:
	boss = new_boss
	player = new_player
	is_unit_alive_callable = new_is_unit_alive_callable


func execute_move(selected_units: Array, command_data: Dictionary) -> bool:
	return execute_movement_action(selected_units, command_data, false)


func execute_dodge(selected_units: Array, command_data: Dictionary) -> bool:
	return execute_movement_action(selected_units, command_data, true)


func execute_movement_action(
	selected_units: Array,
	command_data: Dictionary,
	as_dodge: bool
) -> bool:
	execute_as_dodge = as_dodge
	var where: String = String(command_data.get("where", "none"))
	var issued := false

	match where:
		"me":
			issued = execute_move_to_player(selected_units)

		"movement_slot":
			var region := String(command_data.get("movement_region", "north"))
			var range_name := String(command_data.get("movement_range", "mid"))
			issued = execute_move_to_slot(selected_units, region, range_name)

		"movement_region":
			var region := String(command_data.get("movement_region", "north"))
			issued = execute_move_to_region(selected_units, region)

		"movement_rotate":
			var region := String(command_data.get("movement_region", "north"))
			issued = execute_rotate_to_region(selected_units, region)

		"movement_rotate_step":
			var direction := String(command_data.get("movement_direction", "clockwise"))
			issued = execute_rotate_step(selected_units, direction)

		"movement_range":
			var range_name := String(command_data.get("movement_range", "mid"))
			issued = execute_move_to_range(selected_units, range_name)

		"movement_range_step":
			var direction := String(command_data.get("movement_direction", "out"))
			issued = execute_range_step(selected_units, direction)

		_:
			print("Unsupported movement destination:", where)

	execute_as_dodge = false
	return issued


func execute_move_to_player(selected_units: Array) -> bool:
	if not is_valid_node(player):
		print("Player node is missing.")
		return false

	if not player is Node2D:
		print("Player node is not a Node2D.")
		return false

	var player_2d := player as Node2D
	var destination_context := build_destination_context_from_position(
		player_2d.global_position
	)

	return command_units_to_shared_position(
		selected_units,
		player_2d.global_position,
		"Moving to Player",
		destination_context
	)


func execute_move_to_slot(selected_units: Array, region: String, range_name: String) -> bool:
	if not is_valid_node(boss):
		print("Boss is missing. Cannot resolve movement slot.")
		return false

	var living_units := get_living_movable_units(selected_units)
	var destinations: Array[Vector2] = []
	var occupied_destinations: Dictionary = {}

	for unit in living_units:
		destinations.append(
			get_nearest_available_mini_region_destination(
				(unit as Node2D).global_position,
				region,
				range_name,
				occupied_destinations
			)
		)

	return command_units_to_positions(
		living_units,
		destinations,
		"Moving " + region.capitalize() + " " + range_name.capitalize(),
		build_destination_context(region, range_name)
	)


func execute_move_to_region(selected_units: Array, region: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot move to region.")
		return false

	var issued_command := false
	var living_units := get_living_movable_units(selected_units)
	var occupied_destinations: Dictionary = {}

	for unit in living_units:
		var unit_2d := unit as Node2D

		var current_range: String = MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		var destination := get_nearest_available_mini_region_destination(
			unit_2d.global_position,
			region,
			current_range,
			occupied_destinations
		)

		issue_position_command(
			unit,
			destination,
			build_destination_context(region, current_range)
		)

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
	var occupied_destinations: Dictionary = {}

	for unit in living_units:
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

		var destination := get_nearest_available_mini_region_destination(
			unit_2d.global_position,
			next_region,
			current_range,
			occupied_destinations
		)

		issue_position_command(
			unit,
			destination,
			build_destination_context(next_region, current_range)
		)

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
	var occupied_destinations: Dictionary = {}

	for unit in living_units:
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
		var waypoint_origin := unit_2d.global_position

		for path_region in region_path:
			var destination := get_nearest_available_mini_region_destination(
				waypoint_origin,
				path_region,
				current_range,
				occupied_destinations
			)

			destinations.append(destination)
			waypoint_origin = destination

		if destinations.is_empty():
			continue

		var destination_context := build_destination_context(region, current_range)

		if execute_as_dodge and unit.has_method("command_dodge_through_positions"):
			unit.command_dodge_through_positions(destinations, destination_context)
		elif unit.has_method("command_move_through_positions"):
			unit.command_move_through_positions(destinations, destination_context)
		else:
			issue_position_command(
				unit,
				destinations[destinations.size() - 1],
				destination_context
			)

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
	var occupied_destinations: Dictionary = {}

	for unit in living_units:
		var unit_2d := unit as Node2D

		var current_region: String = MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var destination := get_nearest_available_mini_region_destination(
			unit_2d.global_position,
			current_region,
			range_name,
			occupied_destinations
		)

		issue_position_command(
			unit,
			destination,
			build_destination_context(current_region, range_name)
		)

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
	var occupied_destinations: Dictionary = {}

	for unit in living_units:
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

		var destination := get_nearest_available_mini_region_destination(
			unit_2d.global_position,
			current_region,
			next_range,
			occupied_destinations
		)

		issue_position_command(
			unit,
			destination,
			build_destination_context(current_region, next_range)
		)

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


func command_units_to_shared_position(
	selected_units: Array,
	destination: Vector2,
	status_text: String,
	command_context: Dictionary = {}
) -> bool:
	var living_units := get_living_movable_units(selected_units)
	var outward_direction := Vector2.DOWN

	if is_valid_node(boss) and boss is Node2D:
		outward_direction = (destination - (boss as Node2D).global_position).normalized()

	var destinations := MovementSlotResolverScript.get_formation_positions(
		destination,
		living_units.size(),
		outward_direction
	)

	return command_units_to_positions(
		living_units,
		destinations,
		status_text,
		command_context
	)


func command_units_to_positions(
	selected_units: Array,
	destinations: Array[Vector2],
	status_text: String,
	command_context: Dictionary = {}
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

		issue_position_command(unit, destinations[unit_index], command_context)
		temporary_status_requested.emit(unit, status_text, 0.75)
		issued_command = true

	if not issued_command:
		print("No selected units can move.")
		return false

	refresh_requested.emit()
	return true


func issue_position_command(
	unit: Node,
	destination: Vector2,
	command_context: Dictionary
) -> void:
	if execute_as_dodge and unit.has_method("command_dodge_to_position"):
		unit.command_dodge_to_position(destination, command_context)
	else:
		unit.command_move_to_position(destination, command_context)


func build_destination_context(region: String, range_name: String) -> Dictionary:
	var flag_position := Vector2.ZERO

	if is_valid_node(boss):
		flag_position = MovementSlotResolverScript.get_slot_position(
			boss,
			region,
			range_name
		)

	return {
		"boss": boss,
		"destination_region": region,
		"destination_range": range_name,
		"destination_key": MovementSlotResolverScript.get_mini_region_key(
			region,
			range_name
		),
		"flag_position": flag_position,
		"complete_on_mini_region_entry": true
	}


func build_destination_context_from_position(destination: Vector2) -> Dictionary:
	if not is_valid_node(boss):
		return {}

	var mini_region := MovementSlotResolverScript.get_mini_region_from_position(
		boss,
		destination
	)

	return {
		"boss": boss,
		"destination_region": String(mini_region.get("region", "")),
		"destination_range": String(mini_region.get("range", "")),
		"destination_key": String(mini_region.get("key", "")),
		"flag_position": destination
	}


func get_nearest_available_mini_region_destination(
	source_position: Vector2,
	region: String,
	range_name: String,
	occupied_destinations: Dictionary
) -> Vector2:
	var destination := MovementSlotResolverScript.get_closest_point_in_mini_region(
		boss,
		source_position,
		region,
		range_name
	)
	var destination_key := MovementSlotResolverScript.get_mini_region_key(
		region,
		range_name
	)
	var occupied: Array = occupied_destinations.get(destination_key, [])
	var interior_anchor := MovementSlotResolverScript.get_slot_position(
		boss,
		region,
		range_name
	)

	for _iteration in range(LOCAL_SEPARATION_ITERATIONS):
		var separation_motion := Vector2.ZERO

		for occupied_value in occupied:
			var occupied_position := occupied_value as Vector2
			var offset := destination - occupied_position
			var distance := offset.length()

			if distance >= LOCAL_DESTINATION_SPACING:
				continue

			if offset.is_zero_approx():
				offset = interior_anchor - destination

			if offset.is_zero_approx():
				var outward := MovementSlotResolverScript.get_region_direction(region)
				offset = Vector2(-outward.y, outward.x)

			separation_motion += (
				offset.normalized()
				* (LOCAL_DESTINATION_SPACING - distance)
			)

		if separation_motion.is_zero_approx():
			break

		destination += separation_motion
		destination = MovementSlotResolverScript.get_closest_point_in_mini_region(
			boss,
			destination,
			region,
			range_name
		)

	occupied.append(destination)
	occupied_destinations[destination_key] = occupied
	return destination


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
