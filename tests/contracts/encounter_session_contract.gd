extends Node

const EncounterSessionScript := preload("res://scripts/combat/encounter_session.gd")
const FixtureRuntimeScript := preload(
	"res://tests/fixtures/multi_target_encounter_runtime_fixture.gd"
)


func _ready() -> void:
	var failures: Array[String] = []
	var boss := Node.new()
	boss.name = "FixtureBoss"
	add_child(boss)
	var session: EncounterSession = EncounterSessionScript.new()
	var runtime: EncounterRuntime = FixtureRuntimeScript.new()
	boss.add_child(runtime)
	runtime.configure(boss, null, session)
	session.configure(boss, null, runtime)

	if session.get_primary_targets().size() != 2:
		failures.append("The session did not expose both runtime-registered primary targets.")
	var ambiguous := session.resolve_target({"kind": "fixture_target"})
	if bool(ambiguous.get("ok", true)):
		failures.append("The session accepted an ambiguous multi-target selector.")
	var west := session.resolve_target({"kind": "fixture_target", "side": "west"})
	if not bool(west.get("ok", false)) or west.get("target") != runtime.get("west_target"):
		failures.append("The session did not resolve a qualified target selector.")

	session.record_command({"what": "attack"})
	session.record_telemetry({"event_type": "fixture"})
	var presentation := session.get_presentation_data()
	if int(runtime.get("command_count")) != 1:
		failures.append("The typed runtime command hook was not invoked.")
	if not bool(presentation.get("fixture_runtime", false)):
		failures.append("Runtime presentation state was not merged into the session.")
	if Array(presentation.get("telemetry", [])).size() != 1:
		failures.append("Session telemetry was not recorded.")

	# Ordinary single-target encounters need no specialized runtime or branch.
	var ordinary_boss := Node.new()
	ordinary_boss.name = "OrdinaryBoss"
	add_child(ordinary_boss)
	var ordinary: EncounterSession = EncounterSessionScript.new()
	ordinary.configure(ordinary_boss, null)
	if ordinary.get_primary_targets() != [ordinary_boss]:
		failures.append("The session did not provide the default single-boss target.")

	if failures.is_empty():
		print("RAID_TEST_PASS:encounter_session_contract | Encounter session contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
