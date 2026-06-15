extends Node

@onready var raid_spawner: RaidSpawner = get_node_or_null("../RaidSpawner")
@onready var boss = get_node_or_null("../Boss")
@onready var ui = get_node_or_null("../UI")
@onready var player = get_node_or_null("../Player")

var boss_alive: bool = true
var fight_active: bool = false
var encounter_state: String = "idle"

var party_members: Array = []
var command_controller: RaidCommandController = null
var event_queue: Array = []
var processing_events: bool = false

var spawn_positions: Dictionary = {}

var status_refresh_timer: float = 0.0
var status_refresh_interval: float = 0.15

var temporary_statuses: Dictionary = {}

func _ready():
	print("CombatManager loaded")

	command_controller = RaidCommandController.new()
	connect_command_controller_signals()

	call_deferred("initialize_combat")
func connect_command_controller_signals() -> void:
	if command_controller == null:
		return

	if not command_controller.refresh_requested.is_connected(Callable(self, "refresh_all_statuses")):
		command_controller.refresh_requested.connect(Callable(self, "refresh_all_statuses"))

	if not command_controller.temporary_status_requested.is_connected(Callable(self, "set_temporary_status")):
		command_controller.temporary_status_requested.connect(Callable(self, "set_temporary_status"))
func initialize_combat():
	build_party_member_list()
	store_spawn_positions()

	if command_controller != null:
		command_controller.setup(party_members, boss, player)

	connect_unit_signals()
	connect_boss_signals()

	if ui != null and is_instance_valid(ui):
		if ui.has_method("setup_raid_frames"):
			ui.setup_raid_frames(party_members)

		if ui.has_method("setup_boss_frame"):
			ui.setup_boss_frame(boss)
		connect_ui_signals()
	
	initialize_ui()
	refresh_all_statuses()

func _process(delta):
	if Input.is_action_just_pressed("reset_encounter"):
		reset_encounter()
		return

	update_temporary_statuses(delta)
	update_status_refresh(delta)

	if Input.is_action_just_pressed("position_to_player"):
		command_hovered_unit_to_player()

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

	if ui.has_method("refresh_boss_frame"):
		ui.refresh_boss_frame(false)

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

func handle_unit_defeated(unit: Node) -> void:
	if unit == null:
		return

	if command_controller != null:
		command_controller.clear_hovered_unit_if_matches(unit)

	print("CombatManager handling death:", unit.name)

	temporary_statuses.erase(unit)

	var living_members: Array = []

	if command_controller != null:
		living_members = command_controller.get_living_party_members()

	if living_members.size() == 0:
		handle_party_wipe()
		return

	if command_controller == null:
		refresh_all_statuses()
		return

	var current_boss_target := command_controller.get_boss_target()

	if current_boss_target == null or not command_controller.is_unit_alive(current_boss_target):
		var new_target := command_controller.get_first_living_party_member()
		command_controller.assign_boss_target(new_target)
	else:
		if command_controller.is_following_boss_target():
			command_controller.assign_healers_to_target(current_boss_target)

	refresh_all_statuses()
func handle_boss_defeated():
	print("CombatManager handling boss defeated")

	boss_alive = false
	fight_active = false
	encounter_state = "victory"
	
	temporary_statuses.clear()

	if command_controller != null:
		command_controller.reset_commands()
		command_controller.stop_all_party_actions()

	refresh_all_statuses()

func handle_party_wipe():
	print("Party wiped.")

	fight_active = false
	encounter_state = "wipe"

	temporary_statuses.clear()

	if command_controller != null:
		command_controller.reset_commands()
		command_controller.clear_boss_target()

	refresh_all_statuses()

func reset_encounter():
	print("Resetting encounter")

	if command_controller != null:
		command_controller.reset_commands()

	boss_alive = true
	fight_active = false
	encounter_state = "idle"


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
func connect_ui_signals():
	if ui == null or not is_instance_valid(ui):
		return

	if ui.has_signal("raid_frame_hovered"):
		var hovered_callback := Callable(self, "_on_raid_frame_hovered")

		if not ui.is_connected("raid_frame_hovered", hovered_callback):
			ui.connect("raid_frame_hovered", hovered_callback)

	if ui.has_signal("raid_frame_unhovered"):
		var unhovered_callback := Callable(self, "_on_raid_frame_unhovered")

		if not ui.is_connected("raid_frame_unhovered", unhovered_callback):
			ui.connect("raid_frame_unhovered", unhovered_callback)
func _on_raid_frame_hovered(unit: Node) -> void:
	if command_controller == null:
		return

	if not command_controller.is_valid_node(unit):
		return

	if not command_controller.is_unit_alive(unit):
		return

	command_controller.set_hovered_unit(unit)

	print("Hovered unit:", command_controller.get_unit_debug_name(unit))
func _on_raid_frame_unhovered(unit: Node) -> void:
	if command_controller == null:
		return

	if unit == null:
		return

	if command_controller.is_hovered_unit(unit):
		print("Stopped hovering unit:", command_controller.get_unit_debug_name(unit))
		command_controller.clear_hovered_unit_if_matches(unit)
func command_party_attack() -> void:
	if command_controller == null:
		return

	var command_started := command_controller.command_party_attack(boss_alive)

	if command_started:
		fight_active = true
		encounter_state = "active"
		refresh_all_statuses()


func command_healers_to_heal_boss_target() -> void:
	if command_controller == null:
		return

	command_controller.command_healers_to_heal_boss_target()


func command_interrupt() -> void:
	if command_controller == null:
		return

	command_controller.command_interrupt(boss_alive)


func command_hovered_unit_to_player() -> void:
	if command_controller == null:
		return

	command_controller.command_hovered_unit_to_player()


func is_unit_alive(unit: Node) -> bool:
	if command_controller == null:
		return false

	return command_controller.is_unit_alive(unit)


func get_unit_debug_name(unit: Node) -> String:
	if command_controller == null:
		return "None"

	return command_controller.get_unit_debug_name(unit)
