extends Node

@onready var raid_spawner: RaidSpawner = get_node_or_null("../RaidSpawner")
@onready var boss = get_node_or_null("../Boss")
@onready var ui = get_node_or_null("../UI")

var boss_alive: bool = true
var fight_active: bool = false
var encounter_state: String = "idle"

var party_members: Array = []
var event_queue: Array = []
var processing_events: bool = false

var priest_follow_boss_target: bool = false
var spawn_positions: Dictionary = {}

var status_refresh_timer: float = 0.0
var status_refresh_interval: float = 0.15

var temporary_statuses: Dictionary = {}

func _ready():
	print("CombatManager loaded")
	call_deferred("initialize_combat")

func initialize_combat():
	build_party_member_list()
	store_spawn_positions()
	connect_unit_signals()
	connect_boss_signals()

	if ui != null and is_instance_valid(ui):
		if ui.has_method("setup_raid_frames"):
			ui.setup_raid_frames(party_members)

	initialize_ui()
	refresh_all_statuses()

func _process(delta):
	if Input.is_action_just_pressed("reset_encounter"):
		reset_encounter()
		return

	update_temporary_statuses(delta)
	update_status_refresh(delta)

	if Input.is_action_just_pressed("command_attack"):
		command_party_attack()

	if Input.is_action_just_pressed("command_heal"):
		command_healers_to_heal_boss_target()

	if Input.is_action_just_pressed("command_interrupt"):
		command_interrupt()

func build_party_member_list():
	party_members.clear()

	if raid_spawner != null and is_instance_valid(raid_spawner):
		party_members = raid_spawner.spawn_raid_from_roster()
		print("CombatManager received spawned party count:", party_members.size())
		return

	var grouped_members = get_tree().get_nodes_in_group("party_member")

	for unit in grouped_members:
		if unit != null and is_instance_valid(unit):
			party_members.append(unit)

	print("CombatManager loaded party from group. Count:", party_members.size())

func store_spawn_positions():
	spawn_positions.clear()

	for unit in party_members:
		if unit != null and is_instance_valid(unit):
			spawn_positions[unit] = unit.global_position

	if boss != null and is_instance_valid(boss):
		spawn_positions[boss] = boss.global_position

func connect_unit_signals():
	for unit in party_members:
		if unit == null or not is_instance_valid(unit):
			continue

		if unit.has_signal("defeated"):
			var callback := Callable(self, "_on_unit_defeated")

			if not unit.is_connected("defeated", callback):
				unit.connect("defeated", callback)

func connect_boss_signals():
	if boss == null or not is_instance_valid(boss):
		return

	if boss.has_signal("defeated"):
		var callback := Callable(self, "_on_boss_defeated")

		if not boss.is_connected("defeated", callback):
			boss.connect("defeated", callback)

func initialize_ui():
	encounter_state = "idle"

	if ui == null or not is_instance_valid(ui):
		return

	if ui.has_method("refresh_raid_frames"):
		ui.refresh_raid_frames({})

	if ui.has_method("set_boss_status"):
		ui.set_boss_status("Idle")

func update_status_refresh(delta):
	status_refresh_timer -= delta

	if status_refresh_timer <= 0:
		status_refresh_timer = status_refresh_interval
		refresh_all_statuses()

func refresh_all_statuses():
	if ui == null or not is_instance_valid(ui):
		return

	if ui.has_method("refresh_raid_frames"):
		ui.refresh_raid_frames(get_status_override_texts())

	if not ui.has_method("set_boss_status"):
		return

	if encounter_state == "victory":
		ui.set_boss_status("Defeated")
	elif encounter_state == "wipe":
		ui.set_boss_status("Party Wiped")
	elif boss != null and is_instance_valid(boss) and boss.has_method("get_status_text"):
		ui.set_boss_status(boss.get_status_text())
	else:
		ui.set_boss_status("Idle")

func set_temporary_status(unit: Node, text: String, duration: float):
	if unit == null or not is_instance_valid(unit):
		return

	temporary_statuses[unit] = {
		"text": text,
		"timer": duration
	}

	refresh_all_statuses()

func update_temporary_statuses(delta):
	if temporary_statuses.is_empty():
		return

	var expired_units: Array = []

	for unit in temporary_statuses.keys():
		if unit == null or not is_instance_valid(unit):
			expired_units.append(unit)
			continue

		var data: Dictionary = temporary_statuses[unit]
		data["timer"] = float(data["timer"]) - delta

		if float(data["timer"]) <= 0:
			expired_units.append(unit)
		else:
			temporary_statuses[unit] = data

	for unit in expired_units:
		temporary_statuses.erase(unit)

func get_status_override_texts() -> Dictionary:
	var overrides: Dictionary = {}

	for unit in temporary_statuses.keys():
		if unit == null or not is_instance_valid(unit):
			continue

		if not is_unit_alive(unit):
			continue

		var data: Dictionary = temporary_statuses[unit]
		overrides[unit] = String(data["text"])

	return overrides

func queue_combat_event(event_type: String, data: Dictionary = {}):
	event_queue.append({
		"type": event_type,
		"data": data
	})

	if not processing_events:
		call_deferred("process_combat_events")

func process_combat_events():
	processing_events = true

	while event_queue.size() > 0:
		var event = event_queue.pop_front()
		handle_combat_event(event)

	processing_events = false

func handle_combat_event(event: Dictionary):
	match event["type"]:
		"unit_defeated":
			handle_unit_defeated(event["data"]["unit"])
		"boss_defeated":
			handle_boss_defeated()

func _on_unit_defeated(unit: Node):
	queue_combat_event("unit_defeated", {
		"unit": unit
	})

func _on_boss_defeated():
	queue_combat_event("boss_defeated")

func command_party_attack():
	if not boss_alive:
		print("Boss is already dead.")
		return

	if boss == null or not is_instance_valid(boss):
		print("Boss is invalid.")
		return

	print("Command: Party attack")

	fight_active = true
	encounter_state = "active"

	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if unit.has_method("command_attack"):
			unit.command_attack(boss)

	var target = get_current_or_first_living_target()
	assign_boss_target(target)

	refresh_all_statuses()

func command_healers_to_heal_boss_target():
	print("Command: Healers heal boss target")

	priest_follow_boss_target = true

	var heal_target = get_boss_target()

	if heal_target == null or not is_unit_alive(heal_target):
		heal_target = get_first_living_party_member()

	assign_healers_to_target(heal_target)
	refresh_all_statuses()

func command_interrupt():
	print("Command: Interrupt")

	if not boss_alive:
		print("Boss is defeated. Cannot interrupt.")
		refresh_all_statuses()
		return

	if boss == null or not is_instance_valid(boss):
		print("Boss is invalid. Cannot interrupt.")
		refresh_all_statuses()
		return

	var interrupter = get_first_living_interrupt_unit()

	if interrupter == null:
		print("No living interrupter available.")
		return

	interrupter.command_interrupt(boss)
	set_temporary_status(interrupter, "Interrupt Command", 0.5)

func assign_boss_target(new_target: Node2D):
	if boss == null or not is_instance_valid(boss):
		return

	if new_target == null or not is_unit_alive(new_target):
		if boss.has_method("clear_target"):
			boss.clear_target()

		if priest_follow_boss_target:
			assign_healers_to_target(null)

		refresh_all_statuses()
		return

	if boss.has_method("set_target"):
		boss.set_target(new_target)

	if priest_follow_boss_target:
		assign_healers_to_target(new_target)

	refresh_all_statuses()

func assign_healers_to_target(new_target: Node2D):
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

func get_current_or_first_living_target() -> Node2D:
	var current_target = get_boss_target()

	if current_target != null and is_unit_alive(current_target):
		return current_target

	return get_first_living_party_member()

func get_boss_target() -> Node2D:
	if boss == null or not is_instance_valid(boss):
		return null

	if boss.has_method("get_current_target"):
		return boss.get_current_target()

	return null

func get_first_living_party_member() -> Node2D:
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

func handle_unit_defeated(unit: Node):
	if unit == null:
		return

	print("CombatManager handling death:", unit.name)

	temporary_statuses.erase(unit)

	var living_members = get_living_party_members()

	if living_members.size() == 0:
		handle_party_wipe()
		return

	var current_boss_target = get_boss_target()

	if current_boss_target == null or not is_unit_alive(current_boss_target):
		var new_target = get_first_living_party_member()
		assign_boss_target(new_target)
	else:
		if priest_follow_boss_target:
			assign_healers_to_target(current_boss_target)

	refresh_all_statuses()

func handle_boss_defeated():
	print("CombatManager handling boss defeated")

	boss_alive = false
	fight_active = false
	encounter_state = "victory"
	priest_follow_boss_target = false
	temporary_statuses.clear()

	for unit in party_members:
		if is_unit_alive(unit) and unit.has_method("stop_action"):
			unit.stop_action()

	refresh_all_statuses()

func handle_party_wipe():
	print("Party wiped.")

	fight_active = false
	encounter_state = "wipe"
	priest_follow_boss_target = false
	temporary_statuses.clear()

	if boss != null and is_instance_valid(boss):
		if boss.has_method("clear_target"):
			boss.clear_target()

	refresh_all_statuses()

func reset_encounter():
	print("Resetting encounter")

	boss_alive = true
	fight_active = false
	encounter_state = "idle"
	priest_follow_boss_target = false

	event_queue.clear()
	processing_events = false
	temporary_statuses.clear()
	status_refresh_timer = 0.0

	for unit in party_members:
		if unit == null or not is_instance_valid(unit):
			continue

		if spawn_positions.has(unit) and unit.has_method("reset_unit"):
			unit.reset_unit(spawn_positions[unit])

	if boss != null and is_instance_valid(boss):
		if spawn_positions.has(boss) and boss.has_method("reset_boss"):
			boss.reset_boss(spawn_positions[boss])

	initialize_ui()
	refresh_all_statuses()
