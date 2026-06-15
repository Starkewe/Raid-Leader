extends RefCounted

class_name RaidCommandController

signal refresh_requested
signal temporary_status_requested(unit: Node, text: String, duration: float)

var party_members: Array = []
var boss: Node = null
var player: Node = null

var priest_follow_boss_target: bool = false
var hovered_unit: Node = null


func setup(new_party_members: Array, new_boss: Node, new_player: Node) -> void:
	party_members = new_party_members
	boss = new_boss
	player = new_player


func reset_commands() -> void:
	priest_follow_boss_target = false
	hovered_unit = null


func is_following_boss_target() -> bool:
	return priest_follow_boss_target


# -------------------------------------------------------------------
# Main commands
# -------------------------------------------------------------------

func command_party_attack(boss_alive: bool) -> bool:
	if not boss_alive:
		print("Boss is already dead.")
		return false

	if not is_valid_node(boss):
		print("Boss is invalid.")
		return false

	print("Command: Party attack")

	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if unit.has_method("command_attack"):
			unit.command_attack(boss)

	var target := get_current_or_first_living_target()
	assign_boss_target(target)

	refresh_requested.emit()

	return true


func command_healers_to_heal_boss_target() -> void:
	print("Command: Healers heal boss target")

	priest_follow_boss_target = true

	var heal_target := get_boss_target()

	if heal_target == null or not is_unit_alive(heal_target):
		heal_target = get_first_living_party_member()

	assign_healers_to_target(heal_target)

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
			assign_healers_to_target(null)

		refresh_requested.emit()
		return

	if boss.has_method("set_target"):
		boss.set_target(new_target)

	if priest_follow_boss_target:
		assign_healers_to_target(new_target)

	refresh_requested.emit()


func clear_boss_target() -> void:
	if not is_valid_node(boss):
		return

	if boss.has_method("clear_target"):
		boss.clear_target()


func assign_healers_to_target(new_target: Node) -> void:
	for unit in party_members:
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


func get_first_living_interrupt_unit() -> Node:
	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if unit.has_method("command_interrupt"):
			return unit

	return null


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
