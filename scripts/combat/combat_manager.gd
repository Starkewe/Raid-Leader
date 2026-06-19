extends Node

const CombatEventQueueScript := preload("res://scripts/combat/combat_event_queue.gd")
const CombatStatusPresenterScript := preload("res://scripts/combat/combat_status_presenter.gd")
const VoiceTranscriberClientScript := preload("res://scripts/voice/voice_transcriber_client.gd")
const VoiceCommandParserScript := preload("res://scripts/voice/voice_command_parser.gd")

@onready var raid_spawner: RaidSpawner = get_node_or_null("../RaidSpawner")
@onready var boss = get_node_or_null("../Boss")
@onready var ui = get_node_or_null("../UI")
@onready var player = get_node_or_null("../Player")

@export var voice_transcriber_path: NodePath
@export var voice_command_parser_path: NodePath

var voice_transcriber: VoiceTranscriberClient = null
var voice_command_parser: VoiceCommandParser = null

var boss_alive: bool = true
var fight_active: bool = false
var encounter_state: String = "idle"

var party_members: Array = []

var command_controller: RaidCommandController = null
var combat_event_queue = null
var status_presenter = null

var spawn_positions: Dictionary = {}

func _ready():
	print("CombatManager loaded")

	command_controller = RaidCommandController.new()
	connect_command_controller_signals()
	
	combat_event_queue = CombatEventQueueScript.new()
	combat_event_queue.setup(Callable(self, "handle_combat_event"))
	
	status_presenter = CombatStatusPresenterScript.new()
	setup_voice_commands()
	
	call_deferred("initialize_combat")
func _on_command_panel_submitted(command_data: Dictionary) -> void:
	submit_command_data(command_data, "command_panel")
func submit_command_data(command_data: Dictionary, source: String = "unknown") -> bool:
	if command_controller == null:
		push_warning("CombatManager cannot execute command because command_controller is missing.")
		return false

	if command_data.is_empty():
		push_warning("CombatManager rejected empty command_data from " + source + ".")
		return false

	var validation_result := validate_command_data(command_data)

	if not bool(validation_result.get("ok", false)):
		var reason := String(validation_result.get("reason", "Unknown validation failure."))
		push_warning("CombatManager rejected command_data from " + source + ": " + reason)
		return false

	print("CombatManager executing command from ", source, ": ", command_data)

	var command_started: bool = command_controller.execute_panel_command(command_data, boss_alive)

	if command_started:
		fight_active = true
		encounter_state = "active"

	refresh_all_statuses()

	return command_started


func validate_command_data(command_data: Dictionary) -> Dictionary:
	var required_keys := [
		"who_type",
		"who_value",
		"unit",
		"what",
		"where",
		"when"
	]

	for key in required_keys:
		if not command_data.has(key):
			return {
				"ok": false,
				"reason": "Missing required key: " + key
			}

	var what := String(command_data.get("what", "")).strip_edges()
	var where := String(command_data.get("where", "")).strip_edges()

	if what.is_empty():
		return {
			"ok": false,
			"reason": "Command action is empty."
		}

	if where.is_empty():
		return {
			"ok": false,
			"reason": "Command destination is empty."
		}

	return {
		"ok": true,
		"reason": ""
	}
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

	if boss != null and is_instance_valid(boss):
		if boss.has_method("set_party_members"):
			boss.set_party_members(party_members)

	if command_controller != null:
		command_controller.setup(party_members, boss, player)
	
	if status_presenter != null:
		status_presenter.setup(ui, boss, Callable(self, "is_unit_alive"))
	
	connect_unit_signals()
	connect_boss_signals()

	if ui != null and is_instance_valid(ui):
		if ui.has_method("setup_raid_frames"):
			ui.setup_raid_frames(party_members)

		if ui.has_method("setup_boss_frame"):
			ui.setup_boss_frame(boss)

		if ui.has_method("setup_command_panel"):
			ui.setup_command_panel(party_members)

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

func initialize_ui() -> void:
	encounter_state = "idle"

	if status_presenter == null:
		return

	status_presenter.initialize_ui()

func update_status_refresh(delta: float) -> void:
	if status_presenter == null:
		return

	if status_presenter.should_refresh_statuses(delta):
		refresh_all_statuses()

func refresh_all_statuses() -> void:
	if status_presenter == null:
		return

	status_presenter.refresh_all_statuses(encounter_state)

func set_temporary_status(unit: Node, text: String, duration: float) -> void:
	if status_presenter == null:
		return

	status_presenter.set_temporary_status(unit, text, duration)
	refresh_all_statuses()

func update_temporary_statuses(delta: float) -> void:
	if status_presenter == null:
		return

	var changed: bool = status_presenter.update_temporary_statuses(delta)

	if changed:
		refresh_all_statuses()

func queue_combat_event(event_type: String, data: Dictionary = {}) -> void:
	if combat_event_queue == null:
		print("Combat event queue is missing.")
		return

	combat_event_queue.queue_event(event_type, data)


func handle_combat_event(event: Dictionary) -> void:
	if event.is_empty():
		return

	var event_type: String = String(event.get("type", ""))
	var event_data: Dictionary = event.get("data", {})

	match event_type:
		"unit_defeated":
			if event_data.has("unit"):
				handle_unit_defeated(event_data["unit"])

		"boss_defeated":
			handle_boss_defeated()

		_:
			print("Unknown combat event type:", event_type)
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

	if status_presenter != null:
		status_presenter.clear_temporary_status(unit)

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
	
	if status_presenter != null:
		status_presenter.clear_all_temporary_statuses()

	if command_controller != null:
		command_controller.reset_commands()
		command_controller.stop_all_party_actions()

	refresh_all_statuses()

func handle_party_wipe():
	print("Party wiped.")

	fight_active = false
	encounter_state = "wipe"

	if status_presenter != null:
		status_presenter.clear_all_temporary_statuses()

	if command_controller != null:
		command_controller.reset_commands()
		command_controller.clear_boss_target()

	refresh_all_statuses()

func reset_encounter():
	print("Resetting encounter")

	if command_controller != null:
		command_controller.reset_commands()
	if combat_event_queue != null:
		combat_event_queue.clear()
		
	boss_alive = true
	fight_active = false
	encounter_state = "idle"

	if status_presenter != null:
		status_presenter.clear_all_temporary_statuses()
		status_presenter.reset_status_refresh_timer()

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
	if ui.has_signal("command_panel_submitted"):
		var command_panel_callback := Callable(self, "_on_command_panel_submitted")

		if not ui.is_connected("command_panel_submitted", command_panel_callback):
			ui.connect("command_panel_submitted", command_panel_callback)
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
	
func setup_voice_commands() -> void:
	setup_voice_transcriber()
	setup_voice_command_parser()

	if voice_transcriber == null:
		push_warning("CombatManager could not find VoiceTranscriberClient. Voice commands disabled.")
		return

	if voice_command_parser == null:
		push_warning("CombatManager could not find or create VoiceCommandParser. Voice commands disabled.")
		return

	if not voice_transcriber.transcript_received.is_connected(_on_voice_transcript_received):
		voice_transcriber.transcript_received.connect(_on_voice_transcript_received)

	if not voice_transcriber.transcription_failed.is_connected(_on_voice_transcription_failed):
		voice_transcriber.transcription_failed.connect(_on_voice_transcription_failed)


func setup_voice_transcriber() -> void:
	voice_transcriber = null

	if not voice_transcriber_path.is_empty():
		voice_transcriber = get_node_or_null(voice_transcriber_path) as VoiceTranscriberClient

	if voice_transcriber != null:
		return

	voice_transcriber = get_node_or_null("../VoicePipeline/VoiceTranscriberClient") as VoiceTranscriberClient

	if voice_transcriber != null:
		return

	voice_transcriber = get_node_or_null("../VoiceTranscriberClient") as VoiceTranscriberClient


func setup_voice_command_parser() -> void:
	voice_command_parser = null

	if not voice_command_parser_path.is_empty():
		voice_command_parser = get_node_or_null(voice_command_parser_path) as VoiceCommandParser

	if voice_command_parser != null:
		return

	voice_command_parser = get_node_or_null("../VoicePipeline/VoiceCommandParser") as VoiceCommandParser

	if voice_command_parser != null:
		return

	voice_command_parser = get_node_or_null("../VoiceCommandParser") as VoiceCommandParser

	if voice_command_parser != null:
		return

	voice_command_parser = VoiceCommandParserScript.new()


func _on_voice_transcript_received(transcript: String) -> void:
	if voice_command_parser == null:
		push_warning("Voice transcript received, but VoiceCommandParser is missing.")
		return

	print("Voice transcript received by CombatManager: ", transcript)

	var parse_result: Dictionary = voice_command_parser.parse(transcript)

	if not bool(parse_result.get("ok", false)):
		var reason := String(parse_result.get("reason", "Could not parse voice command."))
		push_warning("Voice command rejected: " + reason)
		return

	var command_data: Dictionary = parse_result.get("command_data", {})

	submit_command_data(command_data, "voice")


func _on_voice_transcription_failed(reason: String) -> void:
	push_warning("Voice transcription failed: " + reason)
