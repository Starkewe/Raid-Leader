extends Node

@onready var warrior = $"../Warrior"
@onready var priest = $"../Priest"
@onready var rogue = $"../Rogue"
@onready var mage = $"../Mage"
@onready var boss = $"../Boss"
@onready var ui = $"../UI"

var encounter_state: String = "idle"
var status_refresh_timer: float = 0.0
var status_refresh_interval: float = 0.15

var boss_alive: bool = true
var fight_active: bool = false

var party_members: Array = []
var event_queue: Array = []
var processing_events: bool = false

var spawn_positions: Dictionary = {}

var priest_follow_boss_target: bool = false
var rogue_status_override_timer: float = 0.0

func _ready():
	print("CombatManager loaded")

	party_members = [
		warrior,
		rogue,
		mage,
		priest
	]
	
	spawn_positions = {
	warrior: warrior.global_position,
	priest: priest.global_position,
	rogue: rogue.global_position,
	mage: mage.global_position,
	boss: boss.global_position
}

	connect_unit_signals()
	connect_boss_signals()
	initialize_ui()

func _process(delta):
	if Input.is_action_just_pressed("reset_encounter"):
		reset_encounter()
		return

	update_temporary_statuses(delta)
	update_status_refresh(delta)
	
	if Input.is_action_just_pressed("command_attack"):
		command_party_attack()

	if Input.is_action_just_pressed("command_heal"):
		command_priest_heal_boss_target()

	if Input.is_action_just_pressed("command_interrupt"):
		command_rogue_interrupt()

func connect_unit_signals():
	for unit in party_members:
		if unit != null and unit.has_signal("defeated"):
			unit.defeated.connect(_on_unit_defeated)

func connect_boss_signals():
	if boss != null and boss.has_signal("defeated"):
		boss.defeated.connect(_on_boss_defeated)

func initialize_ui():
	ui.set_warrior_status("Idle")
	ui.set_priest_status("Idle")
	ui.set_rogue_status("Idle")
	ui.set_mage_status("Idle")
	ui.set_boss_status("Idle")

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

	if is_unit_alive(warrior):
		warrior.command_attack(boss)
		ui.set_warrior_status("Attacking Boss")
	else:
		ui.set_warrior_status("Dead")

	if is_unit_alive(rogue):
		rogue.command_attack(boss)
		ui.set_rogue_status("Attacking Boss")
	else:
		ui.set_rogue_status("Dead")

	if is_unit_alive(mage):
		mage.command_attack(boss)
		ui.set_mage_status("Casting at Boss")
	else:
		ui.set_mage_status("Dead")

	var target = get_current_or_first_living_target()
	assign_boss_target(target)

func command_priest_heal_boss_target():
	print("Command: Priest heal boss target")

	if not is_unit_alive(priest):
		print("Priest is dead and cannot heal.")
		ui.set_priest_status("Dead")
		return

	priest_follow_boss_target = true

	var target = get_boss_target()

	if target == null or not is_unit_alive(target):
		target = get_first_living_party_member()

	assign_priest_heal_target(target)

func command_rogue_interrupt():
	print("Command: Rogue interrupt")

	if not boss_alive:
		print("Boss is defeated. Cannot interrupt.")
		ui.set_boss_status("Defeated")
		return

	if boss == null or not is_instance_valid(boss):
		print("Boss is invalid. Cannot interrupt.")
		ui.set_boss_status("Defeated")
		return

	if not is_unit_alive(rogue):
		print("Rogue is dead and cannot interrupt.")
		ui.set_rogue_status("Dead")
		return

	rogue.command_interrupt(boss)
	ui.set_rogue_status("Interrupt Command")
	rogue_status_override_timer = 0.5

func assign_boss_target(new_target: Node2D):
	if boss == null or not is_instance_valid(boss):
		return

	if new_target == null or not is_unit_alive(new_target):
		boss.clear_target()
		ui.set_boss_status("No Targets")

		if priest_follow_boss_target:
			assign_priest_heal_target(null)

		return

	boss.set_target(new_target)
	ui.set_boss_status("Attacking " + new_target.name)

	if priest_follow_boss_target:
		assign_priest_heal_target(new_target)

func assign_priest_heal_target(new_target: Node2D):
	if not is_unit_alive(priest):
		ui.set_priest_status("Dead")
		return

	if new_target == null or not is_unit_alive(new_target):
		priest.stop_action()
		ui.set_priest_status("Idle")
		return

	priest.command_heal(new_target)

	if new_target == priest:
		ui.set_priest_status("Healing Self")
	else:
		ui.set_priest_status("Healing " + new_target.name)

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

func is_unit_alive(unit: Node) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if unit.has_method("is_alive"):
		return unit.is_alive()

	return true

func get_first_living_party_member() -> Node2D:
	if is_unit_alive(warrior):
		return warrior

	if is_unit_alive(rogue):
		return rogue

	if is_unit_alive(mage):
		return mage

	if is_unit_alive(priest):
		return priest

	return null

func get_living_party_members() -> Array:
	var living_members: Array = []

	for unit in party_members:
		if is_unit_alive(unit):
			living_members.append(unit)

	return living_members

func handle_unit_defeated(unit: Node):
	if unit == null:
		return

	print("CombatManager handling death:", unit.name)

	if unit == warrior:
		ui.set_warrior_status("Dead")
	elif unit == priest:
		ui.set_priest_status("Dead")
	elif unit == rogue:
		ui.set_rogue_status("Dead")
	elif unit == mage:
		ui.set_mage_status("Dead")

	var living_members = get_living_party_members()

	if living_members.size() == 0:
		handle_party_wipe()
		return

	var new_target = get_first_living_party_member()
	assign_boss_target(new_target)

func handle_boss_defeated():
	print("CombatManager handling boss defeated")

	boss_alive = false
	fight_active = false
	encounter_state = "victory"
	
	for unit in party_members:
		if is_unit_alive(unit) and unit.has_method("stop_action"):
			unit.stop_action()

	if is_unit_alive(warrior):
		ui.set_warrior_status("Idle")
	else:
		ui.set_warrior_status("Dead")

	if is_unit_alive(priest):
		ui.set_priest_status("Idle")
	else:
		ui.set_priest_status("Dead")

	if is_unit_alive(rogue):
		ui.set_rogue_status("Idle")
	else:
		ui.set_rogue_status("Dead")

	if is_unit_alive(mage):
		ui.set_mage_status("Idle")
	else:
		ui.set_mage_status("Dead")

	ui.set_boss_status("Defeated")

func handle_party_wipe():
	print("Party wiped.")

	fight_active = false
	priest_follow_boss_target = false
	encounter_state = "wipe"
	
	if boss != null and is_instance_valid(boss):
		boss.clear_target()

	ui.set_warrior_status("Dead")
	ui.set_priest_status("Dead")
	ui.set_rogue_status("Dead")
	ui.set_mage_status("Dead")
	ui.set_boss_status("Victory")
func reset_encounter():
	print("Resetting encounter")

	boss_alive = true
	fight_active = false
	priest_follow_boss_target = false
	rogue_status_override_timer = 0.0
	encounter_state = "idle"
	status_refresh_timer = 0.0

	warrior.reset_unit(spawn_positions[warrior])
	priest.reset_unit(spawn_positions[priest])
	rogue.reset_unit(spawn_positions[rogue])
	mage.reset_unit(spawn_positions[mage])
	boss.reset_boss(spawn_positions[boss])

	initialize_ui()
func update_temporary_statuses(delta):
	if rogue_status_override_timer > 0:
		rogue_status_override_timer -= delta

		if rogue_status_override_timer <= 0:
			rogue_status_override_timer = 0
			refresh_rogue_status()
func refresh_rogue_status():
	if not is_unit_alive(rogue):
		ui.set_rogue_status("Dead")
		return

	if not boss_alive:
		ui.set_rogue_status("Idle")
		return

	if rogue.has_method("get_status_text"):
		ui.set_rogue_status(rogue.get_status_text())
	else:
		ui.set_rogue_status("Idle")
		
func update_status_refresh(delta):
	status_refresh_timer -= delta

	if status_refresh_timer <= 0:
		status_refresh_timer = status_refresh_interval
		refresh_all_statuses()

func refresh_all_statuses():
	if ui == null or not is_instance_valid(ui):
		return

	if warrior != null and is_instance_valid(warrior) and warrior.has_method("get_status_text"):
		ui.set_warrior_status(warrior.get_status_text())

	if priest != null and is_instance_valid(priest) and priest.has_method("get_status_text"):
		ui.set_priest_status(priest.get_status_text())

	if rogue != null and is_instance_valid(rogue) and rogue.has_method("get_status_text"):
		if rogue_status_override_timer <= 0:
			ui.set_rogue_status(rogue.get_status_text())

	if mage != null and is_instance_valid(mage) and mage.has_method("get_status_text"):
		ui.set_mage_status(mage.get_status_text())

	if encounter_state == "victory":
		ui.set_boss_status("Defeated")
	elif encounter_state == "wipe":
		ui.set_boss_status("Victory")
	elif boss != null and is_instance_valid(boss) and boss.has_method("get_status_text"):
		ui.set_boss_status(boss.get_status_text())
