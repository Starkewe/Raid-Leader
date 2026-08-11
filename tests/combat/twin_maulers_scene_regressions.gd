extends Node

const CombatScene := preload("res://scenes/combat_scene.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_default_roster()
	GameState.set_class_count("Warrior", 2)
	GameState.set_class_count("Priest", 5)
	GameState.set_class_count("Rogue", 6)
	GameState.set_class_count("Mage", 7)
	GameState.set_selected_normal_encounter(GameState.ENCOUNTER_TWIN_MAULERS)
	GameState.select_default_encounter()
	GameState.set_raid_debug_context(GameState.RAID_DEBUG_CONTEXT_COMBAT)
	GameState.set_raid_debug_mode(GameState.RAID_DEBUG_MODE_OFF)

	var combat := CombatScene.instantiate()
	get_tree().root.add_child(combat)
	await _wait_frames(6)

	var boss := combat.get_node_or_null("Boss") as Node
	var manager := combat.get_node_or_null("CombatManager") as Node
	var ui := combat.get_node_or_null("UI") as Node
	_expect(boss != null, "The combat scene did not create the Twin Maulers Boss coordinator.")
	_expect(manager != null, "The combat scene did not create a CombatManager.")
	_expect(ui != null, "The combat scene did not create the combat UI.")
	if boss == null or manager == null or ui == null:
		_finish(combat)
		return

	var definition = boss.get("encounter_definition")
	_expect(
		definition != null and String(definition.encounter_id) == GameState.ENCOUNTER_TWIN_MAULERS,
		"The Boss did not load the Twin Maulers encounter definition."
	)
	var runtime := boss.get("encounter_runtime") as Node
	_expect(runtime != null, "The Twin Maulers runtime was not attached to the Boss.")
	var boss_sprite := boss.get_node_or_null("Sprite2D") as CanvasItem
	_expect(boss_sprite == null or not boss_sprite.visible, "The canonical Boss sprite was not replaced by the procedural Maulers.")
	var targets: Array[Node] = boss.get_primary_encounter_targets()
	_expect(targets.size() == 2, "The live encounter did not expose two primary Mauler targets.")
	if targets.size() < 2:
		_finish(combat)
		return

	var west := runtime.get_target_registry().resolve_selector(
		{"kind": "twin_mauler", "side": "west"}
	).get("target", null) as Node
	var east := runtime.get_target_registry().resolve_selector(
		{"kind": "twin_mauler", "side": "east"}
	).get("target", null) as Node
	_expect(west != null and east != null, "The live West/East Mauler selectors did not resolve.")
	_expect(String(west.get_display_name()) == "West Mauler", "The West Mauler canonical label is wrong.")
	_expect(String(east.get_display_name()) == "East Mauler", "The East Mauler canonical label is wrong.")

	await _wait_frames(2)
	var extra_frames: Array = ui.get("extra_boss_frames")
	_expect(extra_frames.size() == 1, "The combat UI did not create a second boss frame for the two targets.")
	ui.refresh_boss_frame()
	var first_name := ui.get_node_or_null("BossFramePanel/VBoxContainer/BossNameLabel") as Label
	_expect(first_name != null and first_name.text.contains("West Mauler"), "The first boss frame did not show the West Mauler.")
	if extra_frames.size() == 1 and extra_frames[0] != null and is_instance_valid(extra_frames[0]):
		var second_name := extra_frames[0].get_node_or_null("VBoxContainer/BossNameLabel") as Label
		_expect(second_name != null and second_name.text.contains("East Mauler"), "The second boss frame did not show the East Mauler.")
		var second_rage_bar := extra_frames[0].get_node_or_null("VBoxContainer/BossRageBar") as ProgressBar
		_expect(second_rage_bar != null and second_rage_bar.visible, "The East boss frame did not expose Rage.")

	var party: Array = manager.get("party_members")
	_expect(party.size() == 20, "The Twin Maulers scene did not spawn the expected raid.")
	if party.is_empty():
		_finish(combat)
		return

	var unqualified_attack := {
		"who_type": "everyone",
		"who_value": "",
		"unit": null,
		"what": "attack",
		"where": "boss",
		"when": "now"
	}
	_expect(
		not bool(manager.submit_command_data(unqualified_attack, "twin_maulers_regression")),
		"An unqualified Boss attack was accepted while both Maulers were alive."
	)

	var west_attack := {
		"who_type": "everyone",
		"who_value": "",
		"unit": null,
		"what": "attack",
		"where": "encounter_target",
		"encounter_target": {"kind": "twin_mauler", "side": "west"},
		"when": "now"
	}
	_expect(
		bool(manager.submit_command_data(west_attack, "twin_maulers_regression")),
		"An explicit West Mauler attack was rejected."
	)

	var east_taunt := {
		"who_type": "everyone",
		"who_value": "",
		"unit": null,
		"what": "taunt",
		"where": "encounter_target",
		"encounter_target": {"kind": "twin_mauler", "side": "east"},
		"when": "now"
	}
	_expect(
		bool(manager.submit_command_data(east_taunt, "twin_maulers_regression")),
		"An explicit East Mauler taunt was rejected."
	)
	_expect(
		int(runtime.get("command_assignment_count")) >= 2,
		"Encounter target reassignment telemetry did not record the explicit commands."
	)

	var health_before: int = boss.get_current_health()
	boss.take_damage(1000, party[0], "test_parent_damage")
	_expect(boss.get_current_health() == health_before, "The aggregate Boss coordinator accepted direct damage.")

	await _wait_frames(2)
	_expect(bool(runtime.get("encounter_active")), "The Twin Maulers runtime did not become active after an attack command.")
	west.take_damage(100000, party[0], "test_west_defeat")
	await _wait_frames(3)
	_expect(boss.get_primary_encounter_targets().size() == 1, "The defeated West Mauler remained a live primary target.")

	var survivor_attack := {
		"who_type": "everyone",
		"who_value": "",
		"unit": null,
		"what": "attack",
		"where": "boss",
		"when": "now"
	}
	_expect(
		bool(manager.submit_command_data(survivor_attack, "twin_maulers_regression")),
		"A bare Boss attack did not route to the surviving East Mauler."
	)
	var first_party_unit := party[0] as Node
	if first_party_unit != null and first_party_unit.has_method("get_active_attack_target"):
		_expect(first_party_unit.get_active_attack_target() == east, "Bare survivor routing selected the wrong Mauler.")

	east.take_damage(100000, party[0], "test_east_defeat")
	await _wait_frames(4)
	_expect(not bool(boss.is_alive()), "The aggregate Boss coordinator did not die after both Maulers were defeated.")
	_expect(int(boss.get_current_health()) == 0, "The aggregate Boss health did not reach zero.")

	_finish(combat)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _finish(combat: Node) -> void:
	if combat != null and is_instance_valid(combat):
		combat.queue_free()
	await _wait_frames(2)
	GameState.set_selected_normal_encounter(GameState.ENCOUNTER_OGRE)
	GameState.select_default_encounter()
	GameState.set_raid_debug_mode(GameState.RAID_DEBUG_MODE_OFF)

	if failures.is_empty():
		print("RAID_TEST_PASS:twin_maulers_scene | Twin Maulers scene regressions passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
