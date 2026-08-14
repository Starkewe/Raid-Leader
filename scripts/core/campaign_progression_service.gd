extends RefCounted
class_name CampaignProgressionService

const LEGACY_BOSS_RESOURCE_MATERIALS := {
	"ogre": "shale_caked_hide",
	"chainmaster": "tempered_chainlink",
	"carrion_roc": "surgical_pinion",
	"twin_maulers": "rage_slick_hide",
}


static func create_empty_progression() -> Dictionary:
	return {
		"advancement_token_ids": [],
		"materials": {},
		"unlocked_recipe_ids": [],
		"crafted_weapon_ids": [],
		"first_clear_claims": [],
		"processed_attempt_ids": [],
		"reward_receipts": {},
		"migration_diagnostics": {"unknown_legacy_boss_resources": {}},
	}


static func sanitize_progression(value: Variant) -> Dictionary:
	var defaults := create_empty_progression()
	var source: Dictionary = Dictionary(value).duplicate(true) if value is Dictionary else {}
	var result := defaults.duplicate(true)
	for field_name in [
		"advancement_token_ids", "unlocked_recipe_ids", "crafted_weapon_ids",
		"first_clear_claims", "processed_attempt_ids",
	]:
		result[field_name] = _unique_string_array(source.get(field_name, []))
	var materials: Dictionary = {}
	var source_materials: Variant = source.get("materials", {})
	if source_materials is Dictionary:
		for material_id_value in source_materials:
			var material_id := String(material_id_value).strip_edges()
			var quantity := maxi(int(source_materials[material_id_value]), 0)
			if not material_id.is_empty() and quantity > 0:
				materials[material_id] = quantity
	result["materials"] = materials
	var receipts: Dictionary = {}
	var source_receipts: Variant = source.get("reward_receipts", {})
	if source_receipts is Dictionary:
		for attempt_id_value in source_receipts:
			if source_receipts[attempt_id_value] is Dictionary:
				receipts[String(attempt_id_value)] = _sanitize_reward_receipt(
					Dictionary(source_receipts[attempt_id_value])
				)
	result["reward_receipts"] = receipts
	var diagnostics: Dictionary = (
		Dictionary(source.get("migration_diagnostics", {})).duplicate(true)
		if source.get("migration_diagnostics", {}) is Dictionary else {}
	)
	var unknown_legacy: Dictionary = {}
	if diagnostics.get("unknown_legacy_boss_resources", {}) is Dictionary:
		for encounter_id_value in diagnostics["unknown_legacy_boss_resources"]:
			unknown_legacy[String(encounter_id_value)] = int(
				diagnostics["unknown_legacy_boss_resources"][encounter_id_value]
			)
	diagnostics["unknown_legacy_boss_resources"] = unknown_legacy
	if diagnostics.has("migrated_from_schema_version"):
		diagnostics["migrated_from_schema_version"] = int(
			diagnostics["migrated_from_schema_version"]
		)
	if diagnostics.has("historical_rolls_generated"):
		diagnostics["historical_rolls_generated"] = bool(
			diagnostics["historical_rolls_generated"]
		)
	result["migration_diagnostics"] = diagnostics
	return result


static func migrate_version_10_progression(source: Dictionary) -> Dictionary:
	var progression := create_empty_progression()
	var materials: Dictionary = {}
	var unknown: Dictionary = {}
	var legacy_value: Variant = source.get("boss_resources", {})
	if legacy_value is Dictionary:
		for encounter_id_value in legacy_value:
			var encounter_id := String(encounter_id_value)
			var count := maxi(int(legacy_value[encounter_id_value]), 0)
			if count <= 0:
				continue
			if LEGACY_BOSS_RESOURCE_MATERIALS.has(encounter_id):
				var material_id := String(LEGACY_BOSS_RESOURCE_MATERIALS[encounter_id])
				materials[material_id] = int(materials.get(material_id, 0)) + count
			else:
				unknown[encounter_id] = count

	var token_ids: Array = []
	var recipe_ids: Array = []
	var first_claims: Array = []
	var victories_value: Variant = source.get("victories", {})
	if victories_value is Dictionary:
		for encounter_id_value in victories_value:
			var encounter_id := String(encounter_id_value)
			if int(victories_value[encounter_id_value]) <= 0:
				continue
			var boss := ProgressionCatalog.get_boss_definition(encounter_id)
			if boss == null:
				continue
			_append_unique_string(first_claims, encounter_id)
			_append_unique_string(token_ids, boss.token_id)
			for recipe_id in ProgressionCatalog.get_recipe_ids_for_encounter(encounter_id):
				_append_unique_string(recipe_ids, recipe_id)

	var processed_ids: Array = []
	var history_value: Variant = source.get("attempt_history", {})
	if history_value is Dictionary:
		for encounter_history_value in history_value.values():
			if not encounter_history_value is Array:
				continue
			for summary_value in encounter_history_value:
				if not summary_value is Dictionary:
					continue
				if String(summary_value.get("outcome", "")) != "victory":
					continue
				_append_unique_string(
					processed_ids, String(summary_value.get("attempt_id", ""))
				)

	progression["materials"] = materials
	progression["advancement_token_ids"] = token_ids
	progression["unlocked_recipe_ids"] = recipe_ids
	progression["first_clear_claims"] = first_claims
	progression["processed_attempt_ids"] = processed_ids
	progression["migration_diagnostics"] = {
		"unknown_legacy_boss_resources": unknown,
		"migrated_from_schema_version": 10,
		"historical_rolls_generated": false,
	}
	return progression


func get_attempt_history(
	campaign: Dictionary, encounter_id: String, maximum_entries: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stored: Array = campaign.get("attempt_history", {}).get(encounter_id, [])
	for value in stored.slice(maxi(stored.size() - maximum_entries, 0)):
		if value is Dictionary:
			result.append(Dictionary(value).duplicate(true))
	return result


func get_victory_count(campaign: Dictionary, encounter_id: String) -> int:
	return int(campaign.get("victories", {}).get(encounter_id, 0))


func get_inventory(campaign: Dictionary) -> Dictionary:
	return sanitize_progression(campaign.get("progression", {})).duplicate(true)


func get_material_count(campaign: Dictionary, material_id: String) -> int:
	return int(
		sanitize_progression(campaign.get("progression", {}))
		.get("materials", {}).get(material_id, 0)
	)


static func _unique_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			_append_unique_string(result, String(entry).strip_edges())
	return result


static func _append_unique_string(values: Array, value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)


static func _sanitize_reward_receipt(source: Dictionary) -> Dictionary:
	var receipt := source.duplicate(true)
	for field_name in [
		"attempt_id", "encounter_id", "display_name", "reward_table_id",
		"reward_summary",
	]:
		receipt[field_name] = String(receipt.get(field_name, ""))
	receipt["rng_seed"] = String(receipt.get("rng_seed", ""))
	for field_name in [
		"reward_table_revision", "victory_count", "recorded_unix_time",
	]:
		receipt[field_name] = int(receipt.get(field_name, 0))
	receipt["first_victory"] = bool(receipt.get("first_victory", false))
	var materials: Dictionary = {}
	if receipt.get("materials", {}) is Dictionary:
		for material_id_value in receipt["materials"]:
			materials[String(material_id_value)] = int(receipt["materials"][material_id_value])
	receipt["materials"] = materials
	var first_clear: Dictionary = (
		Dictionary(receipt.get("first_clear", {})).duplicate(true)
		if receipt.get("first_clear", {}) is Dictionary else {}
	)
	first_clear["claimed"] = bool(first_clear.get("claimed", false))
	first_clear["token_id"] = String(first_clear.get("token_id", ""))
	first_clear["unlocked_recipe_ids"] = _unique_string_array(
		first_clear.get("unlocked_recipe_ids", [])
	)
	receipt["first_clear"] = first_clear
	var layers: Array[Dictionary] = []
	if receipt.get("layers", []) is Array:
		for layer_value in receipt["layers"]:
			if not layer_value is Dictionary:
				continue
			var layer: Dictionary = Dictionary(layer_value).duplicate(true)
			layer["layer_id"] = String(layer.get("layer_id", ""))
			layer["display_name"] = String(layer.get("display_name", ""))
			layer["roll_count"] = int(layer.get("roll_count", 0))
			var results: Array[Dictionary] = []
			if layer.get("results", []) is Array:
				for result_value in layer["results"]:
					if not result_value is Dictionary:
						continue
					var roll_result: Dictionary = Dictionary(result_value).duplicate(true)
					roll_result["material_id"] = String(roll_result.get("material_id", ""))
					roll_result["configured_weight_percent"] = float(
						roll_result.get("configured_weight_percent", 0.0)
					)
					roll_result["roll_index"] = int(roll_result.get("roll_index", 0))
					roll_result["roll_percent"] = float(roll_result.get("roll_percent", 0.0))
					roll_result["quantity"] = int(roll_result.get("quantity", 0))
					results.append(roll_result)
			layer["results"] = results
			layers.append(layer)
	receipt["layers"] = layers
	return receipt
