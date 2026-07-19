extends RefCounted
class_name RaidCommandController

const CommandTargetResolverScript := preload("res://scripts/commands/command_target_resolver.gd")
const MovementCommandExecutorScript := preload("res://scripts/commands/movement_command_executor.gd")

signal refresh_requested
signal temporary_status_requested(unit: Node, text: String, duration: float)

var party_members: Array = []
var boss: Node = null
var player: Node = null

var healers_follow_boss_target: bool = false
var boss_target_healers: Array = []
var hovered_unit: Node = null

var target_resolver = null
var movement_executor = null


func setup(new_party_members: Array, new_boss: Node, new_player: Node) -> void:
	party_members = new_party_members
	boss = new_boss
	player = new_player

	target_resolver = CommandTargetResolverScript.new()
	target_resolver.setup(party_members)

	movement_executor = MovementCommandExecutorScript.new()
	movement_executor.setup(
		boss,
		player,
		Callable(self, "is_unit_alive")
	)

	connect_movement_executor_signals()


func connect_movement_executor_signals() -> void:
	if movement_executor == null:
		return

	var refresh_callback := Callable(self, "_on_movement_refresh_requested")

	if not movement_executor.refresh_requested.is_connected(refresh_callback):
		movement_executor.refresh_requested.connect(refresh_callback)

	var temporary_status_callback := Callable(self, "_on_movement_temporary_status_requested")

	if not movement_executor.temporary_status_requested.is_connected(temporary_status_callback):
		movement_executor.temporary_status_requested.connect(temporary_status_callback)


func _on_movement_refresh_requested() -> void:
	refresh_requested.emit()


func _on_movement_temporary_status_requested(unit: Node, text: String, duration: float) -> void:
	temporary_status_requested.emit(unit, text, duration)


func reset_commands() -> void:
	healers_follow_boss_target = false
	boss_target_healers.clear()
	hovered_unit = null


func is_following_boss_target() -> bool:
	return healers_follow_boss_target


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

		"taunt":
			return execute_panel_taunt(selected_units, where, boss_alive)

		"cure":
			return execute_panel_cure(selected_units, where)

		_:
			print("Unknown panel command:", what)
			return false


func get_units_for_command(command_data: Dictionary) -> Array:
	if target_resolver == null:
		return []

	return target_resolver.get_units_for_command(command_data)


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

	return true


func execute_panel_move(selected_units: Array, command_data: Dictionary) -> bool:
	if movement_executor == null:
		print("Movement executor is missing.")
		return false

	return movement_executor.execute_move(selected_units, command_data)


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

	return true


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

	healers_follow_boss_target = true
	boss_target_healers = selected_healers

	assign_healers_to_target(heal_target, boss_target_healers)
	refresh_requested.emit()

	return true


func execute_panel_taunt(selected_units: Array, where: String, boss_alive: bool) -> bool:
	if where != "boss" or not boss_alive or not is_valid_node(boss):
		print("Taunt requires a living boss target.")
		return false

	for unit in selected_units:
		if not is_unit_alive(unit) or not unit.has_method("command_taunt"):
			continue

		if bool(unit.command_taunt(boss)):
			if healers_follow_boss_target:
				assign_healers_to_target(unit, boss_target_healers)

			temporary_status_requested.emit(unit, "Taunted Boss", 0.75)
			refresh_requested.emit()
			return true

	print("No selected living unit can taunt.")
	return false


func execute_panel_cure(selected_units: Array, where: String) -> bool:
	if where != "curable_allies":
		print("Cure requires Where = Curable Allies.")
		return false

	var curers: Array = []

	for unit in selected_units:
		if is_unit_alive(unit) and unit.has_method("command_cure"):
			curers.append(unit)

	if curers.is_empty():
		print("No selected living unit can cure.")
		return false

	var curable_targets: Array = []

	for party_member in party_members:
		if not is_unit_alive(party_member):
			continue

		if party_member.has_method("has_dispellable_status"):
			if bool(party_member.has_dispellable_status("cure")):
				curable_targets.append(party_member)

	if curable_targets.is_empty():
		print("No living ally has a curable status.")
		return false

	var issued_count := 0

	for curer_index in range(mini(curers.size(), curable_targets.size())):
		var curer = curers[curer_index]
		var cure_target = curable_targets[curer_index]

		if bool(curer.command_cure(cure_target)):
			temporary_status_requested.emit(curer, "Curing " + get_unit_debug_name(cure_target), 0.75)
			issued_count += 1

	refresh_requested.emit()
	print("Cure assigned", issued_count, "curer(s) to slowed allies.")
	return issued_count > 0


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

	if not issued_command:
		print("No living party members can attack.")
		return false

	var target := get_current_or_first_living_target()
	assign_boss_target(target)

	return true


func command_healers_to_heal_boss_target() -> void:
	print("Command: Healers heal boss target")

	var heal_target := get_boss_target()

	if heal_target == null or not is_unit_alive(heal_target):
		heal_target = get_first_living_party_member()

	boss_target_healers = get_living_healer_units_from_units(party_members)
	healers_follow_boss_target = boss_target_healers.size() > 0

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
	refresh_requested.emit()


func command_hovered_unit_to_player() -> void:
	if not is_valid_node(hovered_unit):
		print("No raid member selected by mouseover.")
		return

	if not is_unit_alive(hovered_unit):
		print("Hovered unit is not alive.")
		hovered_unit = null
		return

	if movement_executor == null:
		print("Movement executor is missing.")
		return

	print("Command:", get_unit_debug_name(hovered_unit), "move to player position.")

	movement_executor.execute_move(
		[hovered_unit],
		{
			"where": "me"
		}
	)


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


func assign_boss_target(new_target: Node) -> void:
	if not is_valid_node(boss):
		return

	if new_target == null or not is_unit_alive(new_target):
		clear_boss_target()

		if healers_follow_boss_target:
			assign_healers_to_target(null, boss_target_healers)

		refresh_requested.emit()
		return

	if boss.has_method("set_target"):
		boss.set_target(new_target)

	if healers_follow_boss_target:
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
	if target_resolver == null:
		var living_members: Array = []

		for unit in party_members:
			if is_unit_alive(unit):
				living_members.append(unit)

		return living_members

	return target_resolver.get_living_party_members()


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
		if is_valid_interrupt_candidate(unit):
			return unit

	return null
func is_valid_interrupt_candidate(unit: Node) -> bool:
	if not is_unit_alive(unit):
		return false

	if not unit.has_method("command_interrupt"):
		return false

	if not is_valid_node(boss):
		return false

	if not can_unit_interrupt_target(unit, boss):
		return false

	if not is_interrupt_ready(unit):
		return false

	if not is_unit_in_interrupt_range(unit, boss):
		return false

	return true


func can_unit_interrupt_target(unit: Node, target_node: Node) -> bool:
	if unit.has_method("can_interrupt_target"):
		return bool(unit.can_interrupt_target(target_node))

	if target_node == null or not is_instance_valid(target_node):
		return false

	return target_node.has_method("interrupt_cast")


func is_interrupt_ready(unit: Node) -> bool:
	var interrupt_timer_value = unit.get("interrupt_timer")

	if interrupt_timer_value != null:
		if float(interrupt_timer_value) > 0.0:
			return false

	return true


func is_unit_in_interrupt_range(unit: Node, target_node: Node) -> bool:
	if not is_valid_node(unit):
		return false

	if not is_valid_node(target_node):
		return false

	if not unit is Node2D:
		return false

	if not target_node is Node2D:
		return false

	var interrupt_range_units := get_interrupt_range_units_for_unit(unit)

	if unit.has_method("is_node_in_range_units"):
		return bool(unit.is_node_in_range_units(target_node, interrupt_range_units))

	var unit_2d := unit as Node2D
	var target_2d := target_node as Node2D

	return unit_2d.global_position.distance_to(target_2d.global_position) <= interrupt_range_units


func get_interrupt_range_units_for_unit(unit: Node) -> float:
	var interrupt_range_value = unit.get("interrupt_range_units")

	if interrupt_range_value != null:
		return float(interrupt_range_value)

	return 5.0

func get_unit_class_name(unit: Node) -> String:
	if target_resolver != null:
		return target_resolver.get_unit_class_name(unit)

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
