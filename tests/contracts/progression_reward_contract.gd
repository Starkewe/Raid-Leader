extends Node

const RewardServiceScript := preload("res://scripts/core/campaign_reward_service.gd")


func _ready() -> void:
	var failures: Array[String] = []
	CampaignState.reset_campaign(false, 424242)
	var encounters := ["ogre", "chainmaster", "carrion_roc", "twin_maulers"]
	for encounter_id in encounters:
		_validate_first_clear(encounter_id, failures)
	_validate_repeat_and_duplicate(failures)
	_validate_roll_boundaries(failures)
	_validate_region_completion(failures)
	_finish(failures)


func _validate_first_clear(encounter_id: String, failures: Array[String]) -> void:
	var attempt_id := "contract_first_" + encounter_id
	var result := CampaignState.record_attempt({
		"attempt_id": attempt_id,
		"encounter_id": encounter_id,
		"outcome": "victory",
	})
	if not bool(result.get("ok", false)) or result.get("status") != "rewarded":
		failures.append("First clear failed for '%s': %s" % [encounter_id, result])
		return
	var receipt: Dictionary = result.get("receipt", {})
	var boss := ProgressionCatalog.get_boss_definition(encounter_id)
	if boss == null:
		failures.append("Missing boss definition for '%s'." % encounter_id)
		return
	if not bool(receipt.get("first_victory", false)):
		failures.append("First clear for '%s' was not marked first." % encounter_id)
	if not CampaignState.owns_advancement_token(boss.token_id):
		failures.append("First clear for '%s' did not grant its token." % encounter_id)
	var unlocked: Array = receipt.get("first_clear", {}).get("unlocked_recipe_ids", [])
	if unlocked.size() != 2:
		failures.append("First clear for '%s' did not unlock exactly two recipes." % encounter_id)
	var layer_by_id: Dictionary = {}
	var total_materials := 0
	for layer_value in receipt.get("layers", []):
		var layer: Dictionary = layer_value
		layer_by_id[String(layer.get("layer_id", ""))] = layer
		total_materials += int(layer.get("roll_count", 0))
	var basic_count := int(layer_by_id.get("basic", {}).get("roll_count", -1))
	if basic_count < 2 or basic_count > 4:
		failures.append("First clear for '%s' did not produce 2–4 Basic results." % encounter_id)
	if int(layer_by_id.get("valuable", {}).get("roll_count", -1)) != 1:
		failures.append("First clear for '%s' did not produce one Valuable result." % encounter_id)
	if int(layer_by_id.get("bonus", {}).get("roll_count", -1)) != 0:
		failures.append("First clear for '%s' produced a Bonus result." % encounter_id)
	var receipt_material_count := 0
	for quantity in receipt.get("materials", {}).values():
		receipt_material_count += int(quantity)
	if receipt_material_count != total_materials:
		failures.append("Receipt material totals do not explain every roll for '%s'." % encounter_id)
	if CampaignState.get_latest_reward_receipt() != receipt:
		failures.append("Latest reward receipt did not expose the full '%s' receipt." % encounter_id)


func _validate_repeat_and_duplicate(failures: Array[String]) -> void:
	var boss := ProgressionCatalog.get_boss_definition("ogre")
	var tokens_before := CampaignState.get_owned_advancement_token_ids()
	var recipes_before := CampaignState.get_unlocked_recipe_ids()
	var repeat := CampaignState.record_attempt({
		"attempt_id": "contract_repeat_ogre",
		"encounter_id": "ogre",
		"outcome": "victory",
	})
	if not bool(repeat.get("ok", false)):
		failures.append("Repeat victory failed: %s" % repeat)
	else:
		var receipt: Dictionary = repeat.get("receipt", {})
		if bool(receipt.get("first_victory", true)):
			failures.append("Repeat victory duplicated first-clear status.")
		if not String(receipt.get("first_clear", {}).get("token_id", "")).is_empty():
			failures.append("Repeat victory duplicated a token grant.")
		if not Array(receipt.get("first_clear", {}).get("unlocked_recipe_ids", [])).is_empty():
			failures.append("Repeat victory duplicated recipe unlocks.")
	if CampaignState.get_owned_advancement_token_ids() != tokens_before:
		failures.append("Repeat victory changed owned advancement tokens.")
	if CampaignState.get_unlocked_recipe_ids() != recipes_before:
		failures.append("Repeat victory changed unlocked recipes.")
	if boss == null or not CampaignState.owns_advancement_token(boss.token_id):
		failures.append("Earthgnasher token disappeared after repeat victory.")

	var snapshot_before := CampaignState.get_campaign_snapshot()
	var duplicate := CampaignState.record_attempt({
		"attempt_id": "contract_repeat_ogre",
		"encounter_id": "ogre",
		"outcome": "victory",
	})
	var snapshot_after := CampaignState.get_campaign_snapshot()
	if duplicate.get("status") != "duplicate":
		failures.append("Duplicate attempt did not return duplicate status: %s" % duplicate)
	if snapshot_after != snapshot_before:
		failures.append("Duplicate attempt mutated campaign state.")

	var invalid := CampaignState.record_attempt({
		"encounter_id": "ogre", "outcome": "victory",
	})
	if invalid.get("status") != "invalid_attempt_id":
		failures.append("Attempt without a stable ID entered the reward pipeline.")


func _validate_roll_boundaries(failures: Array[String]) -> void:
	var service = RewardServiceScript.new()
	var table := ProgressionCatalog.get_reward_table_for_encounter("ogre")
	if table == null:
		return
	var basic: RewardRollLayerDefinition = null
	var valuable: RewardRollLayerDefinition = null
	for layer in table.layers:
		if layer.layer_id == "basic":
			basic = layer
		elif layer.layer_id == "valuable":
			valuable = layer
	var boundary_materials := [
		service.select_material_for_roll(basic, 0.0).get("material_id", ""),
		service.select_material_for_roll(basic, 50.0).get("material_id", ""),
		service.select_material_for_roll(basic, 90.0).get("material_id", ""),
	]
	if boundary_materials != ["crucible_beastbone", "shale_caked_hide", "quake_marrow"]:
		failures.append("Fixed Basic RNG boundaries did not cover common/common/uncommon.")
	if service.select_material_for_roll(valuable, 75.0).get("material_id", "") != "earthgnasher_heartstone":
		failures.append("Fixed Valuable RNG boundary did not cover the rare outcome.")
	var first_roll := service.roll_reward_table(table, 99, "ogre", "deterministic")
	var second_roll := service.roll_reward_table(table, 99, "ogre", "deterministic")
	if first_roll != second_roll:
		failures.append("Campaign/encounter/attempt/revision seed was not deterministic.")


func _validate_region_completion(failures: Array[String]) -> void:
	var completion := CampaignState.get_region_progression("beast_crucible")
	if not bool(completion.get("complete", false)):
		failures.append("Four mandatory victories did not complete Beast Crucible.")
	if not Array(completion.get("optional", [])).is_empty():
		failures.append("Beast Crucible invented optional encounters.")
	if not Array(completion.get("apex", [])).is_empty():
		failures.append("Beast Crucible invented an apex encounter.")


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("RAID_TEST_PASS:progression_reward_contract | Progression reward contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
