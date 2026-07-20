extends Node

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const CAMP_SCENE := "res://scenes/camp/camp_scene.tscn"

var mode: String = "menu"
var last_combat_outcome: String = ""


func enter_camp(context_type: String = "normal", details: Dictionary = {}) -> void:
	mode = "camp"
	CampaignState.begin_visit(context_type, details)
	_change_scene(CAMP_SCENE)


func launch_campaign_combat() -> bool:
	var validation := CampaignState.validate_raid_plan()

	if not bool(validation.get("valid", false)):
		return false

	var encounter_id := CampaignState.get_selected_encounter_id()
	GameState.set_selected_normal_encounter(encounter_id)
	GameState.select_default_encounter()
	mode = "campaign_combat"
	last_combat_outcome = ""
	_change_scene(GameState.get_selected_tutorial_scene_path())
	return true


func retry_campaign_combat() -> void:
	mode = "campaign_combat"
	last_combat_outcome = ""
	GameState.set_selected_normal_encounter(CampaignState.get_selected_encounter_id())
	GameState.select_default_encounter()
	_change_scene(GameState.get_selected_tutorial_scene_path())


func launch_tutorial(encounter_id: String) -> void:
	GameState.set_selected_tutorial_boss(encounter_id)
	mode = "tutorial_combat"
	last_combat_outcome = ""
	_change_scene(GameState.get_selected_tutorial_scene_path())


func return_from_combat(outcome: String) -> void:
	last_combat_outcome = outcome

	if mode != "campaign_combat":
		go_to_main_menu()
		return

	var context_type := "wipe"
	var details := {"encounter_id": CampaignState.get_selected_encounter_id()}

	if outcome == "victory":
		var latest_victory := CampaignState.get_latest_victory()
		context_type = (
			"first_victory"
			if bool(latest_victory.get("first_victory", false))
			else "repeat_victory"
		)
		details["victory"] = latest_victory

	enter_camp(context_type, details)


func go_to_main_menu() -> void:
	mode = "menu"
	_change_scene(MAIN_MENU_SCENE)


func is_campaign_combat() -> bool:
	return mode == "campaign_combat"


func is_tutorial_combat() -> bool:
	return mode == "tutorial_combat"


func _change_scene(scene_path: String) -> void:
	var result := get_tree().change_scene_to_file(scene_path)

	if result != OK:
		push_error("SceneFlow could not load scene: " + scene_path)
