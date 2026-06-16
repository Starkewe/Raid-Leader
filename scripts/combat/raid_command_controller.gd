extends RefCounted
class_name RaidCommandController

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

signal refresh_requested
signal temporary_status_requested(unit: Node, text: String, duration: float)

const GROUP_SIZE: int = 5

var party_members: Array = []
var boss: Node = null
var player: Node = null

var priest_follow_boss_target: bool = false
var boss_target_healers: Array = []
var hovered_unit: Node = null


func setup(new_party_members: Array, new_boss: Node, new_player: Node) -> void:
	party_members = new_party_members
	boss = new_boss
	player = new_player


func reset_commands() -> void:
	priest_follow_boss_target = false
	boss_target_healers.clear()
	hovered_unit = null


func is_following_boss_target() -> bool:
	return priest_follow_boss_target


# -------------------------------------------------------------------
# Command panel entry point
# -------------------------------------------------------------------

func execute_panel_command(command_data: Dictionary, boss_alive: bool) -> bool:
	var selected_units: Array = get_units_for_command(command_data)
	var what: String = String(command_data.get("what", ""))
	var where: String = String(command_data.get("where", "none"))

	print("Executing panel command. What:", what, "Where:", where, "Selected units:", selected_units.size())

	match what:
		"attack":
			return execute_panel_attack(selected_units, where, boss_alive)

		"move":
			return execute_panel_move(selected_units, command_data)

		"interrupt":
			return execute_panel_interrupt(selected_units, where, boss_alive)

		"heal":
			return execute_panel_heal(selected_units, where)

		_:
			print("Unknown panel command:", what)
			return false


func get_units_for_command(command_data: Dictionary) -> Array:
	var who_type: String = String(command_data.get("who_type", "everyone"))
	var selected_units: Array = []

	match who_type:
		"everyone":
			selected_units = get_living_party_members()

		"class":
			var class_name_value: String = String(command_data.get("who_value", ""))
			selected_units = get_living_units_by_class(class_name_value)

		"group":
			var group_number: int = int(command_data.get("who_value", 0))
			selected_units = get_living_units_by_group(group_number)

		"unit":
			var unit_node: Node = command_data.get("unit", null) as Node

			if is_unit_alive(unit_node):
				selected_units.append(unit_node)

		_:
			print("Unknown who_type:", who_type)

	return selected_units


func execute_panel_attack(selected_units: Array, where: String, boss_alive: bool) -> bool:
	if where != "boss":
		print("Attack command only supports Where = Boss right now.")
		return false

	if not boss_alive:
		print("Boss is already dead.")
		return false

	if not is_valid_node(boss):
		print("Boss is invalid.")
		return false

	var issued_command: bool = false

	for unit in selected_units:
		if not is_unit_alive(unit):
			continue

		if unit.has_method("command_attack"):
			unit.command_attack(boss)
			issued_command = true

	if not issued_command:
		print("No selected units can attack.")
		return false

	var target := get_current_or_first_living_target()
	assign_boss_target(target)

	refresh_requested.emit()

	return true

func execute_panel_move(selected_units: Array, command_data: Dictionary) -> bool:
	var where: String = String(command_data.get("where", "none"))

	match where:
		"me":
			return execute_move_to_player(selected_units)

		"movement_slot":
			var region := String(command_data.get("movement_region", "north"))
			var range_name := String(command_data.get("movement_range", "mid"))
			return execute_move_to_slot(selected_units, region, range_name)

		"movement_rotate":
			var region := String(command_data.get("movement_region", "north"))
			return execute_rotate_to_region(selected_units, region)
			
		"movement_rotate_step":
			var direction := String(command_data.get("movement_direction", "clockwise"))
			return execute_rotate_step(selected_units, direction)

		"movement_range":
			var range_name := String(command_data.get("movement_range", "mid"))
			return execute_move_to_range(selected_units, range_name)

		_:
			print("Unsupported movement destination:", where)
			return false
func execute_rotate_step(selected_units: Array, rotation_direction: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot rotate movement.")
		return false

	var boss_2d := boss as Node2D
	var issued_command: bool = false
	var living_units: Array = get_living_movable_units(selected_units)

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

		var destination: Vector2 = MovementSlotResolverScript.get_slot_position(
			boss,
			next_region,
			current_range
		)

		unit.command_move_to_position(destination)
		temporary_status_requested.emit(unit, "Rotating " + rotation_direction.capitalize(), 0.75)
		issued_command = true

	if not issued_command:
		print("No selected units can rotate.")
		return false

	refresh_requested.emit()
	return false
func execute_move_to_player(selected_units: Array) -> bool:
	if not is_valid_node(player):
		print("Player node is missing.")
		return false

	if not player is Node2D:
		print("Player node is not a Node2D.")
		return false

	var player_2d := player as Node2D
	return command_units_to_shared_position(selected_units, player_2d.global_position, "Moving to Player")


func execute_move_to_slot(selected_units: Array, region: String, range_name: String) -> bool:
	if not is_valid_node(boss):
		print("Boss is missing. Cannot resolve movement slot.")
		return false

	var slot_position := MovementSlotResolverScript.get_slot_position(boss, region, range_name)

	return command_units_to_shared_position(
		selected_units,
		slot_position,
		"Moving " + region + " " + range_name
	)

func execute_rotate_to_region(selected_units: Array, region: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot rotate movement.")
		return false

	var boss_2d := boss as Node2D
	var issued_command: bool = false
	var living_units: Array = get_living_movable_units(selected_units)

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

		for path_region in region_path:
			var destination: Vector2 = MovementSlotResolverScript.get_slot_position(
				boss,
				path_region,
				current_range
			)

			destinations.append(destination)

		if destinations.is_empty():
			continue

		if unit.has_method("command_move_through_positions"):
			unit.command_move_through_positions(destinations)
		else:
			unit.command_move_to_position(destinations[destinations.size() - 1])

		temporary_status_requested.emit(unit, "Rotating " + region, 0.75)
		issued_command = true

	if not issued_command:
		print("No selected units can rotate.")
		return false

	refresh_requested.emit()
	return false

func execute_move_to_range(selected_units: Array, range_name: String) -> bool:
	if not is_valid_node(boss) or not boss is Node2D:
		print("Boss is missing. Cannot change movement range.")
		return false

	var boss_2d := boss as Node2D
	var issued_command := false
	var living_units := get_living_movable_units(selected_units)

	for unit in living_units:
		var unit_2d := unit as Node2D
		var current_region := MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var destination := MovementSlotResolverScript.get_slot_position(boss, current_region, range_name)

		unit.command_move_to_position(destination)
		temporary_status_requested.emit(unit, "Moving " + range_name, 0.75)
		issued_command = true

	if not issued_command:
		print("No selected units can change range.")
		return false

	refresh_requested.emit()
	return false


func command_units_to_shared_position(selected_units: Array, destination: Vector2, status_text: String) -> bool:
	var issued_command := false

	for unit in selected_units:
		if not is_unit_alive(unit):
			continue

		if not unit.has_method("command_move_to_position"):
			continue

		unit.command_move_to_position(destination)
		temporary_status_requested.emit(unit, status_text, 0.75)
		issued_command = true

	if not issued_command:
		print("No selected units can move.")
		return false

	refresh_requested.emit()
	return false

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
func execute_panel_interrupt(selected_units: Array, where: String, boss_alive: bool) -> bool:
	if where != "boss":
		print("Interrupt command only supports Where = Boss right now.")
		return false

	if not boss_alive:
		print("Boss is defeated. Cannot interrupt.")
		refresh_requested.emit()
		return false

	if not is_valid_node(boss):
		print("Boss is invalid. Cannot interrupt.")
		refresh_requested.emit()
		return false

	var interrupter := get_first_living_interrupt_unit_from_units(selected_units)

	if interrupter == null:
		print("No selected living interrupter available.")
		return false

	interrupter.command_interrupt(boss)
	temporary_status_requested.emit(interrupter, "Interrupt Command", 0.5)

	refresh_requested.emit()

	return false


func execute_panel_heal(selected_units: Array, where: String) -> bool:
	if where != "boss_target":
		print("Heal command only supports Where = Boss Target right now.")
		return false

	var heal_target := get_boss_target()

	if heal_target == null or not is_unit_alive(heal_target):
		heal_target = get_first_living_party_member()

	var selected_healers: Array = get_living_healer_units_from_units(selected_units)

	if selected_healers.size() == 0:
		print("No selected living healers available.")
		return false

	priest_follow_boss_target = true
	boss_target_healers = selected_healers

	assign_healers_to_target(heal_target, boss_target_healers)

	refresh_requested.emit()

	return false


# -------------------------------------------------------------------
# Existing keyboard / direct commands
# -------------------------------------------------------------------

func command_party_attack(boss_alive: bool) -> bool:
	if not boss_alive:
		print("Boss is already dead.")
		return false

	if not is_valid_node(boss):
		print("Boss is invalid.")
		return false

	print("Command: Party attack")

	var issued_command: bool = false

	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if unit.has_method("command_attack"):
			unit.command_attack(boss)
			issued_command = true

	var target := get_current_or_first_living_target()
	assign_boss_target(target)

	refresh_requested.emit()

	return issued_command


func command_healers_to_heal_boss_target() -> void:
	print("Command: Healers heal boss target")

	var heal_target := get_boss_target()

	if heal_target == null or not is_unit_alive(heal_target):
		heal_target = get_first_living_party_member()

	boss_target_healers = get_living_healer_units_from_units(party_members)
	priest_follow_boss_target = boss_target_healers.size() > 0

	assign_healers_to_target(heal_target, boss_target_healers)

	refresh_requested.emit()


func command_interrupt(boss_alive: bool) -> void:
	print("Command: Interrupt")

	if not boss_alive:
		print("Boss is defeated. Cannot interrupt.")
		refresh_requested.emit()
		return

	if not is_valid_node(boss):
		print("Boss is invalid. Cannot interrupt.")
		refresh_requested.emit()
		return

	var interrupter := get_first_living_interrupt_unit()

	if interrupter == null:
		print("No living interrupter available.")
		return

	interrupter.command_interrupt(boss)

	temporary_status_requested.emit(interrupter, "Interrupt Command", 0.5)


func command_hovered_unit_to_player() -> void:
	if not is_valid_node(hovered_unit):
		print("No raid member selected by mouseover.")
		return

	if not is_unit_alive(hovered_unit):
		print("Hovered unit is not alive.")
		hovered_unit = null
		return

	if not is_valid_node(player):
		print("Player node is missing.")
		return

	if not player is Node2D:
		print("Player node is not a Node2D.")
		return

	if not hovered_unit.has_method("command_move_to_position"):
		print(get_unit_debug_name(hovered_unit), "cannot receive movement commands.")
		return

	var player_2d := player as Node2D

	print("Command:", get_unit_debug_name(hovered_unit), "move to player position.")

	hovered_unit.command_move_to_position(player_2d.global_position)

	temporary_status_requested.emit(hovered_unit, "Moving to Player", 0.75)


# -------------------------------------------------------------------
# Hovered unit selection
# -------------------------------------------------------------------

func set_hovered_unit(unit: Node) -> void:
	if not is_valid_node(unit):
		return

	if not is_unit_alive(unit):
		return

	hovered_unit = unit


func clear_hovered_unit_if_matches(unit: Node) -> void:
	if hovered_unit == unit:
		hovered_unit = null


func is_hovered_unit(unit: Node) -> bool:
	return hovered_unit == unit


# -------------------------------------------------------------------
# Boss targeting / healer assignment
# -------------------------------------------------------------------

func assign_boss_target(new_target: Node) -> void:
	if not is_valid_node(boss):
		return

	if new_target == null or not is_unit_alive(new_target):
		clear_boss_target()

		if priest_follow_boss_target:
			assign_healers_to_target(null, boss_target_healers)

		refresh_requested.emit()
		return

	if boss.has_method("set_target"):
		boss.set_target(new_target)

	if priest_follow_boss_target:
		assign_healers_to_target(new_target, boss_target_healers)

	refresh_requested.emit()


func clear_boss_target() -> void:
	if not is_valid_node(boss):
		return

	if boss.has_method("clear_target"):
		boss.clear_target()


func assign_healers_to_target(new_target: Node, healer_units: Array = []) -> void:
	var units_to_check: Array = healer_units

	if units_to_check.size() == 0:
		units_to_check = party_members

	for unit in units_to_check:
		if not is_unit_alive(unit):
			continue

		if not unit.has_method("command_heal"):
			continue

		if new_target == null or not is_unit_alive(new_target):
			if unit.has_method("stop_action"):
				unit.stop_action()
		else:
			unit.command_heal(new_target)


func stop_all_party_actions() -> void:
	for unit in party_members:
		if is_unit_alive(unit) and unit.has_method("stop_action"):
			unit.stop_action()


# -------------------------------------------------------------------
# Unit lookup helpers
# -------------------------------------------------------------------

func get_current_or_first_living_target() -> Node:
	var current_target := get_boss_target()

	if current_target != null and is_unit_alive(current_target):
		return current_target

	return get_first_living_party_member()


func get_boss_target() -> Node:
	if not is_valid_node(boss):
		return null

	if boss.has_method("get_current_target"):
		return boss.get_current_target()

	return null


func get_first_living_party_member() -> Node:
	for unit in party_members:
		if is_unit_alive(unit):
			return unit

	return null


func get_living_party_members() -> Array:
	var living_members: Array = []

	for unit in party_members:
		if is_unit_alive(unit):
			living_members.append(unit)

	return living_members


func get_living_units_by_class(class_name_value: String) -> Array:
	var matching_units: Array = []

	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if get_unit_class_name(unit) == class_name_value:
			matching_units.append(unit)

	return matching_units


func get_living_units_by_group(group_number: int) -> Array:
	var matching_units: Array = []

	if group_number <= 0:
		return matching_units

	var start_index: int = (group_number - 1) * GROUP_SIZE
	var end_index: int = start_index + GROUP_SIZE

	for index in range(start_index, end_index):
		if index < 0 or index >= party_members.size():
			continue

		var unit = party_members[index]

		if is_unit_alive(unit):
			matching_units.append(unit)

	return matching_units


func get_living_healer_units_from_units(source_units: Array) -> Array:
	var healer_units: Array = []

	for unit in source_units:
		if not is_unit_alive(unit):
			continue

		if unit.has_method("command_heal"):
			healer_units.append(unit)

	return healer_units


func get_first_living_interrupt_unit() -> Node:
	return get_first_living_interrupt_unit_from_units(party_members)


func get_first_living_interrupt_unit_from_units(source_units: Array) -> Node:
	for unit in source_units:
		if not is_unit_alive(unit):
			continue

		if unit.has_method("command_interrupt"):
			return unit

	return null


func get_unit_class_name(unit: Node) -> String:
	if not is_valid_node(unit):
		return ""

	var unit_class_value = unit.get("unit_class")

	if unit_class_value != null and String(unit_class_value) != "":
		return String(unit_class_value)

	return unit.get_class()


func is_unit_alive(unit: Node) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if unit.has_method("is_alive"):
		return unit.is_alive()

	return true


func is_valid_node(node: Node) -> bool:
	return node != null and is_instance_valid(node)


func get_unit_debug_name(unit: Node) -> String:
	if not is_valid_node(unit):
		return "None"

	if unit.has_method("get_display_name"):
		return unit.get_display_name()

	return unit.name
