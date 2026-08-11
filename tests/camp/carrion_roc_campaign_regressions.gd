extends Node

const GameStateScript := preload("res://scripts/core/game_state.gd")
const CampaignStateScript := preload("res://scripts/core/campaign_state.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := get_tree().root
	var game_state := scene_root.get_node_or_null("GameState")
	if game_state == null:
		game_state = GameStateScript.new()
		scene_root.add_child(game_state)

	var campaign_state := scene_root.get_node_or_null("CampaignState")
	if campaign_state == null:
		campaign_state = CampaignStateScript.new()
		scene_root.add_child(campaign_state)

	var normal_ids: Array = game_state.get_normal_encounter_ids()
	if normal_ids != [
		GameStateScript.ENCOUNTER_OGRE,
		GameStateScript.ENCOUNTER_CHAINMASTER,
		GameStateScript.ENCOUNTER_CARRION_ROC,
		GameStateScript.ENCOUNTER_TWIN_MAULERS
	]:
		push_error("The normal Beast Crucible encounter order is incorrect after adding the Twin Maulers.")
		get_tree().quit(1)
		return

	var available: Array = campaign_state.get_available_encounter_ids()
	if not available.has(GameStateScript.ENCOUNTER_CARRION_ROC):
		push_error("Carrion Roc is not immediately available in the Beast Crucible.")
		get_tree().quit(1)
		return

	if String(game_state.get_encounter_definition(GameStateScript.ENCOUNTER_CARRION_ROC).encounter_id) != "carrion_roc":
		push_error("Carrion Roc catalog definition has the wrong encounter id.")
		get_tree().quit(1)
		return

	print("RAID_TEST_PASS:carrion_roc_campaign | Carrion Roc campaign regressions passed.")
	get_tree().quit(0)
