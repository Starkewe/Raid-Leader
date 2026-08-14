extends RefCounted
class_name CampaignRewardService


func process_victory(campaign: Dictionary, summary: Dictionary) -> Dictionary:
	var attempt_id := String(summary.get("attempt_id", "")).strip_edges()
	var encounter_id := String(summary.get("encounter_id", "")).strip_edges()
	if attempt_id.is_empty():
		return _result(false, "invalid_attempt_id", "Victory rewards require a stable attempt ID.")
	if String(summary.get("outcome", "")) != "victory":
		return _result(false, "invalid_outcome", "Only victories can enter the reward pipeline.")

	var progression := CampaignProgressionService.sanitize_progression(
		campaign.get("progression", {})
	)
	var receipts: Dictionary = progression.get("reward_receipts", {})
	if receipts.has(attempt_id):
		return {
			"ok": true,
			"status": "duplicate",
			"message": "This attempt was already rewarded.",
			"receipt": Dictionary(receipts[attempt_id]).duplicate(true),
		}
	if Array(progression.get("processed_attempt_ids", [])).has(attempt_id):
		return {
			"ok": true,
			"status": "duplicate_historical",
			"message": "This historical attempt was already processed before reward receipts existed.",
			"receipt": {},
		}

	var boss := ProgressionCatalog.get_boss_definition(encounter_id)
	var table := ProgressionCatalog.get_reward_table_for_encounter(encounter_id)
	if boss == null or table == null:
		return _result(
			false, "unknown_definition",
			"No progression reward definition exists for encounter '%s'." % encounter_id
		)

	var campaign_seed := int(campaign.get("campaign_seed", 0))
	var rolled := roll_reward_table(table, campaign_seed, encounter_id, attempt_id)
	if not bool(rolled.get("ok", false)):
		return rolled

	var first_claims: Array = Array(progression.get("first_clear_claims", [])).duplicate()
	var token_ids: Array = Array(progression.get("advancement_token_ids", [])).duplicate()
	var unlocked_ids: Array = Array(progression.get("unlocked_recipe_ids", [])).duplicate()
	var processed_ids: Array = Array(progression.get("processed_attempt_ids", [])).duplicate()
	var material_inventory: Dictionary = Dictionary(
		progression.get("materials", {})
	).duplicate(true)
	var first_clear := not first_claims.has(encounter_id)
	var newly_unlocked: Array[String] = []
	var granted_token_id := ""
	if first_clear:
		first_claims.append(encounter_id)
		granted_token_id = boss.token_id
		_append_unique(token_ids, boss.token_id)
		for recipe_id in ProgressionCatalog.get_recipe_ids_for_encounter(encounter_id):
			if not unlocked_ids.has(recipe_id):
				unlocked_ids.append(recipe_id)
				newly_unlocked.append(recipe_id)

	var dropped_materials: Dictionary = rolled.get("materials", {})
	for material_id_value in dropped_materials:
		var material_id := String(material_id_value)
		material_inventory[material_id] = (
			int(material_inventory.get(material_id, 0))
			+ int(dropped_materials[material_id_value])
		)
	_append_unique(processed_ids, attempt_id)

	var victories: Dictionary = Dictionary(campaign.get("victories", {})).duplicate(true)
	var victory_count := int(victories.get(encounter_id, 0)) + 1
	victories[encounter_id] = victory_count
	var receipt := {
		"attempt_id": attempt_id,
		"encounter_id": encounter_id,
		"display_name": boss.display_name,
		"reward_table_id": table.reward_table_id,
		"reward_table_revision": table.revision,
		"rng_seed": String(rolled.get("rng_seed", "")),
		"victory_count": victory_count,
		"first_victory": first_clear,
		"first_clear": {
			"claimed": first_clear,
			"token_id": granted_token_id,
			"unlocked_recipe_ids": newly_unlocked,
		},
		"layers": Array(rolled.get("layers", [])).duplicate(true),
		"materials": dropped_materials.duplicate(true),
		"reward_summary": _build_reward_summary(
			first_clear, granted_token_id, newly_unlocked, dropped_materials
		),
		"recorded_unix_time": int(Time.get_unix_time_from_system()),
	}
	receipts[attempt_id] = receipt.duplicate(true)
	progression["first_clear_claims"] = first_claims
	progression["advancement_token_ids"] = token_ids
	progression["unlocked_recipe_ids"] = unlocked_ids
	progression["processed_attempt_ids"] = processed_ids
	progression["materials"] = material_inventory
	progression["reward_receipts"] = receipts
	campaign["progression"] = progression
	campaign["victories"] = victories
	campaign["latest_victory"] = receipt.duplicate(true)
	return {
		"ok": true,
		"status": "rewarded",
		"message": "Victory rewards were applied.",
		"receipt": receipt.duplicate(true),
	}


func roll_reward_table(
	table: BossRewardTableDefinition, campaign_seed: int,
	encounter_id: String, attempt_id: String
) -> Dictionary:
	if table == null:
		return _result(false, "unknown_definition", "Reward table is missing.")
	var seed_value := _stable_reward_seed(
		campaign_seed, encounter_id, attempt_id, table.revision
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layer_receipts: Array[Dictionary] = []
	var material_totals: Dictionary = {}
	for layer in table.layers:
		if layer == null:
			continue
		var roll_count := layer.minimum_rolls
		if layer.maximum_rolls > layer.minimum_rolls:
			roll_count = rng.randi_range(layer.minimum_rolls, layer.maximum_rolls)
		var results: Array[Dictionary] = []
		for roll_index in range(roll_count):
			var roll_percent := rng.randf_range(0.0, 100.0)
			var selected := select_material_for_roll(layer, roll_percent)
			if selected.is_empty():
				return _result(
					false, "invalid_reward_table",
					"Reward layer '%s' could not resolve roll %.4f."
					% [layer.layer_id, roll_percent]
				)
			selected["roll_index"] = roll_index
			selected["roll_percent"] = roll_percent
			selected["quantity"] = 1
			results.append(selected)
			var material_id := String(selected.get("material_id", ""))
			material_totals[material_id] = int(material_totals.get(material_id, 0)) + 1
		layer_receipts.append({
			"layer_id": layer.layer_id,
			"display_name": layer.display_name,
			"roll_count": roll_count,
			"results": results,
		})
	return {
		"ok": true,
		"status": "rolled",
		"message": "Reward table rolled successfully.",
		"rng_seed": str(seed_value),
		"layers": layer_receipts,
		"materials": material_totals,
	}


func select_material_for_roll(
	layer: RewardRollLayerDefinition, roll_percent: float
) -> Dictionary:
	if layer == null or layer.entries.is_empty():
		return {}
	var normalized := clampf(roll_percent, 0.0, 99.999999)
	var cumulative := 0.0
	for entry in layer.entries:
		if entry == null:
			continue
		cumulative += entry.weight_percent
		if normalized < cumulative:
			return {
				"material_id": entry.material_id,
				"configured_weight_percent": entry.weight_percent,
			}
	return {}


func _stable_reward_seed(
	campaign_seed: int, encounter_id: String, attempt_id: String, revision: int
) -> int:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(
		("%d|%s|%s|%d" % [campaign_seed, encounter_id, attempt_id, revision]).to_utf8_buffer()
	)
	var digest := context.finish()
	var result := 0
	for index in range(mini(8, digest.size())):
		result = (result << 8) | int(digest[index])
	return result


func _build_reward_summary(
	first_clear: bool, token_id: String, recipe_ids: Array[String], materials: Dictionary
) -> String:
	var material_count := 0
	for quantity in materials.values():
		material_count += int(quantity)
	if first_clear:
		return (
			"%d materials secured; token '%s' and %d recipes unlocked."
			% [material_count, token_id, recipe_ids.size()]
		)
	return "%d materials secured from a repeat victory." % material_count


func _append_unique(values: Array, value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)


func _result(ok: bool, status: String, message: String) -> Dictionary:
	return {"ok": ok, "status": status, "message": message, "receipt": {}}
