extends SceneTree

const CarrionRocDefinitionScript := preload("res://scripts/data/carrion_roc_definition.gd")
const CarrionRocRuntimeScript := preload("res://scripts/encounters/carrion_roc_runtime.gd")
const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")


class DummyBoss:
	extends Node2D

	var health: int = 50000
	var max_health: int = 50000
	var target: Node = null
	var mechanic_state: Dictionary = {}
	var combat_events: Array[Dictionary] = []

	func is_alive() -> bool:
		return health > 0

	func get_current_target() -> Node:
		return target

	func set_mechanic_state(key: String, value: Variant) -> void:
		mechanic_state[key] = value

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
			"ability_id": ability_id,
			"amount": amount,
			"metadata": metadata
		})

	func register_encounter_object(_object: Node) -> void:
		pass


class DummyRaider:
	extends Node2D

	var health: int = 100
	var max_health: int = 100
	var roles: Array[String] = ["melee"]
	var damage_received: int = 0

	func is_alive() -> bool:
		return health > 0

	func has_role(role_name: String) -> bool:
		return roles.has(role_name)

	func take_damage(amount: int, _source: Node = null, _ability_id: String = "", _metadata: Dictionary = {}) -> void:
		health = max(health - amount, 0)
		damage_received += amount

	func start_forced_movement(destination: Vector2, _duration: float) -> void:
		global_position = destination

	func get_member_id() -> String:
		return name

	func get_display_name() -> String:
		return name


var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var boss := DummyBoss.new()
	root.add_child(boss)

	var definition := CarrionRocDefinitionScript.new()
	definition.stagger_threshold = 100
	definition.cadence_interval = 100.0
	definition.initial_cadence_delay = 100.0
	definition.rupture_telegraph_duration = 6.5
	definition.rupture_delay_after_grounding = 2.5

	var runtime := CarrionRocRuntimeScript.new()
	boss.add_child(runtime)
	runtime.configure(boss, definition)

	var melee := DummyRaider.new()
	melee.name = "Warrior 1"
	melee.global_position = Vector2(500.0, 0.0)
	root.add_child(melee)
	var ranged := DummyRaider.new()
	ranged.name = "Mage 1"
	ranged.roles = ["ranged", "ranged_dps"]
	ranged.global_position = Vector2(-500.0, 0.0)
	root.add_child(ranged)
	boss.target = melee
	runtime.set_party_members([melee, ranged])
	runtime.set_encounter_active(true)

	runtime.before_boss_damage(100, melee, "test_melee", {})
	_expect(bool(runtime.get("grounded")), "Melee pressure did not break the Roc's Stagger.")
	_expect_close(float(runtime.get("stagger_pressure")), 0.0, "Stagger pressure did not reset on grounding.")

	runtime.tick(2.5)
	var ruptures: Array = runtime.get_active_ruptures()
	_expect(ruptures.size() == 2, "Grounding did not create one east and one west rupture.")
	var sides: Array[String] = []
	for rupture in ruptures:
		sides.append(String(rupture.get("side", "")))
	_expect(sides.has("east") and sides.has("west"), "Rupture sides were not paired east/west.")
	for rupture in ruptures:
		_expect(
			String(rupture.get("range", "")) in ["mid", "far"],
			"Rupture selected a close-range soak.")

	var dynamic_command := {
		"who_type": CommandSchemaScript.SELECTOR_EVERYONE,
		"who_value": "",
		"unit": null,
		"who_selectors": [{"type": CommandSchemaScript.SELECTOR_EVERYONE, "value": "", "unit": null}],
		"what": CommandSchemaScript.ACTION_ATTACK,
		"where": CommandSchemaScript.DESTINATION_ENCOUNTER_TARGET,
		"encounter_target": {"kind": "carrion_growth", "side": "east"},
		"when": "now"
	}
	_expect(bool(CommandSchemaScript.validate(dynamic_command).get("ok", false)), "Growth attack command failed schema validation.")

	var east_growth: Node = runtime.call("_spawn_growth", "east", "east", "mid")
	var west_growth: Node = runtime.call("_spawn_growth", "west", "west", "mid")
	var target_registry = runtime.get_target_registry()
	_expect(east_growth != null and west_growth != null, "Rupture failure could not create Growth targets.")
	_expect(
		not bool(target_registry.resolve_selector({"kind": "carrion_growth"}).get("ok", false)),
		"An unqualified Growth target did not reject an ambiguous east/west selection."
	)
	_expect(
		target_registry.resolve_selector({"kind": "carrion_growth", "side": "east"}).get("target", null) == east_growth,
		"The east Growth selector did not resolve the oldest east target."
	)
	if east_growth != null and east_growth.has_method("take_damage"):
		east_growth.take_damage(1000, melee, "test_growth_attack")
	_expect(
		target_registry.get_target_entries({"kind": "carrion_growth", "side": "east"}).is_empty(),
		"Defeated Growth targets were not removed from the live target registry."
	)

	if failures.is_empty():
		print("RAID_TEST_PASS:carrion_roc_combat | Carrion Roc combat regressions passed.")
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
