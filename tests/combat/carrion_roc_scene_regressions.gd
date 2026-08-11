extends Node

const CombatScene := preload("res://scenes/combat_scene.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.set_selected_normal_encounter(GameState.ENCOUNTER_CARRION_ROC)
	GameState.select_default_encounter()
	GameState.set_raid_debug_context(GameState.RAID_DEBUG_CONTEXT_COMBAT)
	GameState.set_raid_debug_mode(GameState.RAID_DEBUG_MODE_OFF)

	var combat := CombatScene.instantiate()
	get_tree().root.add_child(combat)
	await _wait_frames(5)

	var boss := combat.get_node_or_null("Boss") as Node
	var manager := combat.get_node_or_null("CombatManager") as Node
	_expect(boss != null, "The combat scene did not create a Boss node.")
	_expect(manager != null, "The combat scene did not create a CombatManager node.")
	if boss == null or manager == null:
		_finish(combat)
		return

	var definition = boss.get("encounter_definition")
	_expect(
		definition != null and String(definition.encounter_id) == GameState.ENCOUNTER_CARRION_ROC,
		"The Boss did not load the Carrion Roc encounter definition."
	)
	var runtime := boss.get("encounter_runtime") as Node
	_expect(runtime != null, "The Carrion Roc runtime was not attached to the Boss.")
	_expect(
		boss.get_node_or_null("CarrionRocVisuals") != null,
		"The Carrion Roc placeholder visuals were not attached to the Boss."
	)
	var boss_sprite := boss.get_node_or_null("Sprite2D") as CanvasItem
	_expect(boss_sprite == null or not boss_sprite.visible, "The placeholder Roc did not replace the boss sprite.")

	var attack_command := {
		"who_type": "everyone",
		"who_value": "",
		"unit": null,
		"what": "attack",
		"where": "boss",
		"when": "now"
	}
	_expect(
		bool(manager.submit_command_data(attack_command, "carrion_roc_regression")),
		"The actual CombatManager rejected a normal Carrion Roc attack command."
	)
	await _wait_frames(2)
	_expect(bool(runtime.get("encounter_active")), "The Carrion Roc runtime did not start with combat.")

	var party: Array = manager.get("party_members")
	if runtime != null and not party.is_empty():
		boss.take_damage(2800, party[0], "regression_stagger")
		_expect(bool(runtime.get("grounded")), "Boss damage did not break the live Carrion Roc Stagger.")

		var growth: Node = runtime.call("_spawn_growth", "east", "east", "mid")
		_expect(growth != null, "The live Carrion Roc runtime could not spawn a Growth target.")
		if growth != null:
			var growth_command := {
				"who_type": "everyone",
				"who_value": "",
				"unit": null,
				"what": "attack",
				"where": "encounter_target",
				"encounter_target": {"kind": "carrion_growth", "side": "east"},
				"when": "now"
			}
			_expect(
				bool(manager.submit_command_data(growth_command, "carrion_roc_regression")),
				"The live CombatManager rejected an east Growth attack command."
			)
			growth.take_damage(1000, party[0], "regression_growth_attack")
			_expect(
				runtime.get_target_registry().get_target_entries({"kind": "carrion_growth"}).is_empty(),
				"The live target registry retained a defeated Growth."
			)

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
		print("RAID_TEST_PASS:carrion_roc_scene | Carrion Roc scene regressions passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
