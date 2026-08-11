extends SceneTree

const TwinMaulersDefinitionScript := preload("res://scripts/data/twin_maulers_definition.gd")
const TwinMaulersRuntimeScript := preload("res://scripts/encounters/twin_maulers_runtime.gd")
const AttemptSummaryBuilderScript := preload("res://scripts/combat/attempt_summary_builder.gd")
const EncounterSessionScript := preload("res://scripts/combat/encounter_session.gd")


class DummyBoss:
	extends Node2D

	signal defeated

	var health: int = 60000
	var max_health: int = 60000
	var is_defeated: bool = false
	var mechanic_state: Dictionary = {}
	var combat_events: Array[Dictionary] = []
	var encounter_registry = null

	func is_alive() -> bool:
		return not is_defeated

	func get_current_health() -> int:
		return health

	func get_max_health() -> int:
		return max_health

	func get_current_target() -> Node:
		return null

	func get_encounter_target_registry() -> Node:
		return encounter_registry

	func set_mechanic_state(key: String, value: Variant) -> void:
		mechanic_state[key] = value

	func update_health_bar() -> void:
		pass

	func die() -> void:
		if is_defeated:
			return
		is_defeated = true
		health = 0
		defeated.emit()

	func register_encounter_object(object: Node) -> void:
		if object != null and object.has_signal("combat_event"):
			object.combat_event.connect(_on_encounter_event)

	func emit_combat_event(
		event_type: String,
		source: Node,
		ability_id: String,
		amount: int,
		metadata: Dictionary = {}
	) -> void:
		combat_events.append({
			"type": event_type,
			"source": source,
			"target": self,
			"ability_id": ability_id,
			"amount": amount,
			"metadata": metadata.duplicate(true)
		})

	func _on_encounter_event(event: Dictionary) -> void:
		combat_events.append(event.duplicate(true))


class DummyRaider:
	extends Node2D

	var health: int = 100
	var max_health: int = 100
	var roles: Array[String] = ["melee"]
	var active_target: Node = null
	var taunt_target: Node = null
	var damage_received: int = 0

	func is_alive() -> bool:
		return health > 0

	func get_max_health() -> int:
		return max_health

	func get_display_name() -> String:
		return name

	func has_role(role_name: String) -> bool:
		return roles.has(role_name)

	func get_active_attack_target() -> Node:
		if active_target == null or not is_instance_valid(active_target):
			return null
		if active_target.has_method("is_alive") and not active_target.is_alive():
			return null
		return active_target

	func command_attack(target: Node2D) -> void:
		active_target = target

	func command_taunt(target: Node2D) -> bool:
		taunt_target = target
		return true

	func stop_attack_only() -> void:
		active_target = null

	func take_damage(
		amount: int,
		_source: Node = null,
		_ability_id: String = "",
		_metadata: Dictionary = {}
	) -> void:
		var resolved_amount := maxi(amount, 0)
		health = maxi(health - resolved_amount, 0)
		damage_received += resolved_amount


var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := TwinMaulersDefinitionScript.new()
	definition.random_seed = 7
	definition.rampage_initial_delay_min = 999.0
	definition.rampage_initial_delay_max = 999.0
	definition.rampage_interval_min = 999.0
	definition.rampage_interval_max = 999.0

	_expect_close(definition.get_rage_rate(0), -18.0, "Zero attackers did not produce the expected Rage decay.")
	_expect_close(definition.get_rage_rate(5), -3.0, "Five attackers did not produce the expected Rage decay.")
	_expect_close(definition.get_rage_rate(6), 0.0, "The stable Rage band did not begin at six attackers.")
	_expect_close(definition.get_rage_rate(9), 0.0, "The stable Rage band did not end at nine attackers.")
	_expect_close(definition.get_rage_rate(10), 3.333333, "Ten attackers did not add one equal pressure step.")
	_expect_close(definition.get_rage_rate(15), 20.0, "Rage gain was not capped at the configured maximum.")

	var boss := DummyBoss.new()
	root.add_child(boss)
	var runtime := TwinMaulersRuntimeScript.new()
	boss.add_child(runtime)
	runtime.configure(boss, definition)
	var session := EncounterSessionScript.new()
	session.configure(boss, definition, runtime)
	boss.encounter_registry = runtime.get_target_registry()

	var raiders: Array = []
	for index in range(20):
		var raider := DummyRaider.new()
		raider.name = "Raider %02d" % (index + 1)
		if index < 2:
			raider.roles = ["tank"]
		root.add_child(raider)
		raiders.append(raider)

	runtime.set_party_members(raiders)
	runtime.set_encounter_active(true)

	var targets: Array[Node] = runtime.get_primary_encounter_targets()
	_expect(targets.size() == 2, "Twin Maulers did not expose two living primary targets.")
	var registry = runtime.get_target_registry()
	var west: Node = registry.resolve_selector({"kind": "twin_mauler", "side": "west"}).get("target", null)
	var east: Node = registry.resolve_selector({"kind": "twin_mauler", "side": "east"}).get("target", null)
	_expect(west != null and east != null, "Canonical west/east Mauler selectors did not resolve.")
	if west == null or east == null:
		_finish(boss, runtime, raiders)
		return

	for index in range(12):
		raiders[index].command_attack(west)
	for index in range(12, 20):
		raiders[index].command_attack(east)
	runtime.tick(1.0)
	_expect(int(west.active_attacker_count) == 12, "West pressure did not count active assigned attackers.")
	_expect(int(east.active_attacker_count) == 8, "East pressure did not count active assigned attackers.")
	_expect(float(west.rage) > float(east.rage), "Rage did not rise on the focused Mauler only.")
	_expect_close(float(east.rage), 0.0, "Stable-band pressure unexpectedly changed East Rage.")

	west.take_damage(15000)
	_expect_close(float(west.get_rage_floor()), 45.0, "Missing health did not raise the West Rage floor.")
	runtime.tick(0.1)
	_expect(float(west.rage) >= 45.0, "Rage was allowed below the missing-health floor.")

	east.exhaustion_level = 2
	east.rage = 80.0
	runtime.request_target_exhaustion(west)
	_expect(west.is_exhausted(), "West did not enter Exhaustion at the assigned threshold.")
	_expect(int(east.exhaustion_level) == 1, "Sibling Exhaustion threshold was not lowered by one step.")
	var west_health_before: int = west.health
	west.take_damage(10, raiders[0], "test_exhaustion_damage")
	_expect(west.health == west_health_before - 20, "Exhaustion did not apply the 2x incoming vulnerability.")
	west.rage = 90.0
	var west_rage_before: float = west.rage
	runtime.tick(1.0)
	_expect(float(west.rage) < west_rage_before, "Exhaustion did not rapidly decay Rage.")

	# A Rage-triggered Exhaustion cancels a Rampage warning/cast on that Mauler.
	east.clear_rampage_state()
	east.set_rampage_cast(2.0)
	runtime.set("active_rampage", east)
	runtime.request_target_exhaustion(east)
	_expect(not east.is_casting_ability(), "Exhaustion did not cancel the active Rampage cast.")
	_expect(east.is_exhausted(), "The reactive Exhaustion did not start on the casting Mauler.")

	# Resolve a Rampage once to verify the near-wipe payload and uninterruptible cast metadata.
	for raider in raiders:
		raider.health = raider.max_health
	west.exhausted_remaining = 0.0
	east.exhausted_remaining = 0.0
	west.rage = 0.0
	east.rage = 0.0
	runtime.set("active_rampage", null)
	runtime.set("rampage_timer", 0.0)
	runtime.tick(0.1)
	var rampage_target: Node = runtime.get("active_rampage")
	_expect(rampage_target != null, "The Rampage scheduler did not select a living Mauler.")
	if rampage_target != null:
		rampage_target.set_rampage_warning(0.1)
		runtime.tick(0.1)
		runtime.tick(2.1)
		var rampage_damage_total := 0
		var has_rampage_cast := false
		var rampage_cast_interruptible := true
		for event in boss.combat_events:
			if String(event.get("type", "")) == "twin_mauler_rampage_failed":
				rampage_damage_total = int(event.get("amount", 0))
			if (
				String(event.get("type", "")) == "cast_started"
				and String(event.get("ability_id", "")) == "twin_mauler_rampage"
			):
				has_rampage_cast = true
				rampage_cast_interruptible = bool(
					event.get("metadata", {}).get("interruptible", true)
				)
		_expect(rampage_damage_total == 1600, "Rampage did not deal 80% of each raider's maximum health.")
		_expect(has_rampage_cast, "Rampage did not emit a cast-start telemetry event.")
		if has_rampage_cast:
			_expect(
				not rampage_cast_interruptible,
				"Rampage was not marked uninterruptible."
			)

	# Kill West and verify the hard-burn survivor state and bare-command routing.
	var rampage_timer_before_survivor: float = runtime.get("rampage_timer")
	west.take_damage(100000, raiders[0], "test_west_defeat")
	_expect(runtime.get_primary_encounter_targets().size() == 1, "Defeated West Mauler remained a living primary target.")
	_expect(bool(runtime.get("survivor_enraged")), "The survivor enrage did not start after the first Mauler died.")
	_expect(bool(east.survivor_enraged), "East Mauler did not receive the survivor enrage state.")
	_expect_close(float(east.get_exhaustion_threshold()), 100.0, "Survivor Exhaustion threshold did not reset to 100.")
	_expect_close(float(east.get_rage_floor()), 40.0, "Survivor Rage floor bonus was not applied.")
	_expect_close(float(east.get_survivor_damage_multiplier()), 1.35, "Survivor damage bonus was not applied.")
	_expect_close(
		float(runtime.get("rampage_timer")),
		rampage_timer_before_survivor * definition.survivor_rampage_interval_multiplier,
		"The survivor Rampage timer did not immediately receive its interval reduction."
	)

	east.take_damage(100000, raiders[0], "test_east_defeat")
	await process_frame
	_expect(bool(boss.is_defeated), "The parent Boss coordinator did not die after both Maulers died.")
	_expect(int(boss.health) == 0, "The parent Boss aggregate health did not reach zero.")
	var summary := AttemptSummaryBuilderScript.build(
		"twin_maulers",
		"victory",
		boss.combat_events,
		boss.health,
		boss.max_health,
		"",
		""
	)
	summary["encounter_metrics"] = session.build_attempt_metrics(boss.combat_events)
	var metrics: Dictionary = summary.get("encounter_metrics", {}).get("twin_maulers", {})
	_expect(int(metrics.get("rampage_failure_count", 0)) == 1, "Twin Mauler summary did not record the Rampage failure.")
	_expect(not Array(metrics.get("rage_samples", [])).is_empty(), "Twin Mauler summary did not retain Rage telemetry.")
	_expect(
		String(summary.get("reliable_failures", []).front()) == "Rampage struck the raid for near-wipe damage.",
		"Twin Mauler summary did not expose a reliable Rampage failure."
	)

	_finish(boss, runtime, raiders)


func _finish(boss: Node, runtime: Node, raiders: Array) -> void:
	if runtime != null and is_instance_valid(runtime):
		runtime.cleanup_encounter()
	for raider in raiders:
		if raider != null and is_instance_valid(raider):
			raider.queue_free()
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
	await process_frame

	if failures.is_empty():
		print("RAID_TEST_PASS:twin_maulers_combat | Twin Maulers combat regressions passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _expect_close(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s Actual %.3f, expected %.3f." % [message, actual, expected])
