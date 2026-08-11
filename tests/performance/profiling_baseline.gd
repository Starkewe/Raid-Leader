extends Node

const CombatScene := preload("res://scenes/combat_scene.tscn")
const CampScene := preload("res://scenes/camp/camp_scene.tscn")
const TutorialSandboxConfigScript := preload(
	"res://scripts/data/tutorial_sandbox_config.gd"
)
const SAMPLE_FRAMES := 180


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var roster := TutorialSandboxConfigScript.get_roster()
	for unit_class in GameState.get_available_classes():
		GameState.set_class_count(unit_class, int(roster.get(unit_class, 0)))
	GameState.set_selected_normal_encounter(GameState.ENCOUNTER_OGRE)
	GameState.select_default_encounter()
	var combat := CombatScene.instantiate()
	add_child(combat)
	var combat_average := await _sample_frames()
	combat.queue_free()
	await get_tree().process_frame

	CampaignState.reset_campaign(false, 61059)
	var camp := CampScene.instantiate()
	add_child(camp)
	var camp_average := await _sample_frames()
	camp.queue_free()
	await get_tree().process_frame
	print("RAID_PROFILE_BASELINE:" + JSON.stringify({
		"godot": Engine.get_version_info().get("string", "unknown"),
		"sample_frames": SAMPLE_FRAMES,
		"combat_raiders": GameState.get_total_count(),
		"combat_average_frame_ms": snappedf(combat_average, 0.001),
		"camp_average_frame_ms": snappedf(camp_average, 0.001),
	}))
	print("RAID_TEST_PASS:profiling_baseline | Repeatable combat/camp profiling sample completed.")
	get_tree().quit(0)


func _sample_frames() -> float:
	var started := Time.get_ticks_usec()
	for _frame in range(SAMPLE_FRAMES):
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - started) / 1000.0 / float(SAMPLE_FRAMES)
