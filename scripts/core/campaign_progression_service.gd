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
		"migration_diagnostics": {
			"unknown_legacy_boss_resources": {},
			"duplicate_weapon_assignments": [],
		},
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
	var duplicate_assignments: Array[Dictionary] = []
	var duplicate_value: Variant = diagnostics.get("duplicate_weapon_assignments", [])
	if duplicate_value is Array:
		for entry_value in duplicate_value:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = Dictionary(entry_value).duplicate(true)
			entry["status"] = "duplicate_weapon_assignment_reconciled"
			entry["weapon_id"] = String(entry.get("weapon_id", entry.get("stable_id", "")))
			entry["stable_id"] = entry["weapon_id"]
			entry["kept_raider_id"] = String(entry.get("kept_raider_id", ""))
			entry["current_holder_id"] = entry["kept_raider_id"]
			entry["cleared_raider_ids"] = _unique_string_array(
				entry.get("cleared_raider_ids", [])
			)
			entry["message"] = String(entry.get("message", ""))
			duplicate_assignments.append(entry)
	diagnostics["duplicate_weapon_assignments"] = duplicate_assignments
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


func check_craft(campaign: Dictionary, recipe_id: String) -> Dictionary:
	var recipe := ProgressionCatalog.get_recipe(recipe_id)
	if recipe == null:
		return _result(
			false, "unknown_definition", "Unknown crafting recipe '%s'." % recipe_id
		)
	var progression := sanitize_progression(campaign.get("progression", {}))
	if not Array(progression.get("unlocked_recipe_ids", [])).has(recipe_id):
		return _result(
			false, "locked_recipe", "Recipe '%s' has not been unlocked." % recipe.display_name
		)
	if Array(progression.get("crafted_weapon_ids", [])).has(recipe.output_weapon_id):
		return _result(
			false, "already_owned", "Weapon '%s' has already been crafted." % recipe.output_weapon_id
		)
	var materials: Dictionary = progression.get("materials", {})
	var missing: Dictionary = {}
	var ingredient_status: Array[Dictionary] = []
	for ingredient in recipe.ingredients:
		if ingredient == null:
			continue
		var owned := int(materials.get(ingredient.material_id, 0))
		var required := ingredient.quantity
		ingredient_status.append({
			"material_id": ingredient.material_id,
			"owned": owned,
			"required": required,
			"missing": maxi(required - owned, 0),
		})
		if owned < required:
			missing[ingredient.material_id] = required - owned
	if not missing.is_empty():
		return {
			"ok": false,
			"status": "insufficient_materials",
			"message": "Missing materials for '%s'." % recipe.display_name,
			"recipe_id": recipe_id,
			"output_weapon_id": recipe.output_weapon_id,
			"ingredients": ingredient_status,
			"missing_materials": missing,
		}
	return {
		"ok": true,
		"status": "craftable",
		"message": "All materials are available for '%s'." % recipe.display_name,
		"recipe_id": recipe_id,
		"output_weapon_id": recipe.output_weapon_id,
		"ingredients": ingredient_status,
		"missing_materials": {},
	}


func craft(campaign: Dictionary, recipe_id: String) -> Dictionary:
	var validation := check_craft(campaign, recipe_id)
	if not bool(validation.get("ok", false)):
		return validation
	var recipe := ProgressionCatalog.get_recipe(recipe_id)
	if recipe == null:
		return _result(false, "unknown_definition", "Crafting recipe disappeared.")
	var progression := sanitize_progression(campaign.get("progression", {}))
	var materials: Dictionary = Dictionary(progression.get("materials", {})).duplicate(true)
	for ingredient in recipe.ingredients:
		if ingredient == null:
			continue
		var remaining := int(materials.get(ingredient.material_id, 0)) - ingredient.quantity
		if remaining > 0:
			materials[ingredient.material_id] = remaining
		else:
			materials.erase(ingredient.material_id)
	var crafted_ids: Array = Array(progression.get("crafted_weapon_ids", [])).duplicate()
	_append_unique_string(crafted_ids, recipe.output_weapon_id)
	progression["materials"] = materials
	progression["crafted_weapon_ids"] = crafted_ids
	campaign["progression"] = progression
	return {
		"ok": true,
		"status": "crafted",
		"message": "Crafted '%s'." % recipe.output_weapon_id,
		"recipe_id": recipe_id,
		"weapon_id": recipe.output_weapon_id,
		"consumed": Array(validation.get("ingredients", [])).duplicate(true),
	}


func check_equip(
	campaign: Dictionary, raider_id: String, weapon_id: String
) -> Dictionary:
	var state_result := _get_raider_state(campaign, raider_id)
	if not bool(state_result.get("ok", false)):
		return state_result
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	if weapon == null:
		return _result(
			false, "unknown_definition", "Unknown weapon definition '%s'." % weapon_id
		)
	var progression := sanitize_progression(campaign.get("progression", {}))
	if not Array(progression.get("crafted_weapon_ids", [])).has(weapon_id):
		return _result(
			false, "not_crafted", "Weapon '%s' has not been crafted." % weapon.display_name
		)
	var holder_id := get_weapon_holder_id(campaign, weapon_id)
	if holder_id == raider_id:
		return {
			"ok": false,
			"status": "already_equipped",
			"message": "Weapon is already equipped by this raider.",
			"raider_id": raider_id,
			"weapon_id": weapon_id,
			"holder_id": holder_id,
			"current_holder_id": holder_id,
		}
	if not holder_id.is_empty():
		return {
			"ok": false,
			"status": "assigned_elsewhere",
			"message": "Weapon is assigned to '%s'; unequip it there first." % holder_id,
			"raider_id": raider_id,
			"weapon_id": weapon_id,
			"holder_id": holder_id,
			"current_holder_id": holder_id,
		}
	if not Array(campaign.get("raid_plan", {}).get("active_member_ids", [])).has(raider_id):
		return {
			"ok": false,
			"status": "reserve_cannot_equip",
			"message": "Reserve raiders cannot receive weapon assignments.",
			"raider_id": raider_id,
			"weapon_id": weapon_id,
			"holder_id": "",
			"current_holder_id": "",
		}
	var state: Dictionary = state_result.get("state", {})
	var class_id := _effective_class_id(state)
	if not ProgressionCatalog.is_family_compatible(class_id, weapon.family_id):
		return {
			"ok": false,
			"status": "incompatible_family",
			"message": "Class '%s' cannot equip %s." % [class_id, weapon.family_id],
			"raider_id": raider_id,
			"weapon_id": weapon_id,
			"class_id": class_id,
			"family_id": weapon.family_id,
			"holder_id": "",
			"current_holder_id": "",
		}
	return {
		"ok": true,
		"status": "equippable",
		"message": "Weapon can be equipped.",
		"raider_id": raider_id,
		"weapon_id": weapon_id,
		"class_id": class_id,
		"family_id": weapon.family_id,
		"holder_id": "",
		"current_holder_id": "",
	}


func equip(campaign: Dictionary, raider_id: String, weapon_id: String) -> Dictionary:
	var validation := check_equip(campaign, raider_id, weapon_id)
	if not bool(validation.get("ok", false)):
		return validation
	var states: Dictionary = campaign.get("raider_states", {})
	var state: Dictionary = Dictionary(states[raider_id]).duplicate(true)
	var previous_weapon_id := String(state.get("equipped_weapon_id", ""))
	state["equipped_weapon_id"] = weapon_id
	states[raider_id] = state
	campaign["raider_states"] = states
	validation["ok"] = true
	validation["status"] = "equipped"
	validation["message"] = "Weapon equipped."
	validation["previous_weapon_id"] = previous_weapon_id
	return validation


func check_move_or_swap_equipped_weapon(
	campaign: Dictionary, source_raider_id: String, destination_raider_id: String
) -> Dictionary:
	if source_raider_id == destination_raider_id:
		return _result(false, "same_raider", "Choose a different raider as the destination.")
	var source_result := _get_raider_state(campaign, source_raider_id)
	if not bool(source_result.get("ok", false)):
		return source_result
	var destination_result := _get_raider_state(campaign, destination_raider_id)
	if not bool(destination_result.get("ok", false)):
		return destination_result
	var active_ids: Array = campaign.get("raid_plan", {}).get("active_member_ids", [])
	if not active_ids.has(source_raider_id):
		return _result(
			false, "source_not_active", "Reserve-held weapons may only be returned to the armory."
		)
	if not active_ids.has(destination_raider_id):
		return _result(
			false, "destination_not_active", "Reserve raiders cannot receive weapon assignments."
		)
	var source_state: Dictionary = source_result.get("state", {})
	var destination_state: Dictionary = destination_result.get("state", {})
	var source_weapon_id := String(source_state.get("equipped_weapon_id", ""))
	var destination_weapon_id := String(destination_state.get("equipped_weapon_id", ""))
	if source_weapon_id.is_empty():
		return _result(false, "source_unarmed", "Default weapons are not transferable inventory.")
	var source_weapon := ProgressionCatalog.get_weapon(source_weapon_id)
	if source_weapon == null:
		return _result(
			false, "source_weapon_missing",
			"The source weapon definition is missing; return it to the armory for recovery."
		)
	var progression := sanitize_progression(campaign.get("progression", {}))
	var crafted_ids: Array = progression.get("crafted_weapon_ids", [])
	if not crafted_ids.has(source_weapon_id):
		return _result(false, "source_not_crafted", "The source weapon is not in the crafted armory.")
	var destination_class_id := _effective_class_id(destination_state)
	if not ProgressionCatalog.is_family_compatible(
		destination_class_id, source_weapon.family_id
	):
		return {
			"ok": false,
			"status": "source_incompatible_with_destination",
			"message": "%s cannot use %s." % [destination_class_id, source_weapon.display_name],
			"source_raider_id": source_raider_id,
			"destination_raider_id": destination_raider_id,
			"source_weapon_id": source_weapon_id,
			"destination_weapon_id": destination_weapon_id,
		}
	if not destination_weapon_id.is_empty():
		var destination_weapon := ProgressionCatalog.get_weapon(destination_weapon_id)
		if destination_weapon == null:
			return _result(
				false, "destination_weapon_missing",
				"The destination weapon definition is missing; return it to the armory first."
			)
		if not crafted_ids.has(destination_weapon_id):
			return _result(
				false, "destination_not_crafted", "The destination weapon is not in the crafted armory."
			)
		var source_class_id := _effective_class_id(source_state)
		if not ProgressionCatalog.is_family_compatible(
			source_class_id, destination_weapon.family_id
		):
			return {
				"ok": false,
				"status": "destination_incompatible_with_source",
				"message": "%s cannot use %s." % [source_class_id, destination_weapon.display_name],
				"source_raider_id": source_raider_id,
				"destination_raider_id": destination_raider_id,
				"source_weapon_id": source_weapon_id,
				"destination_weapon_id": destination_weapon_id,
			}
	return {
		"ok": true,
		"status": "swappable" if not destination_weapon_id.is_empty() else "movable",
		"message": "Weapons can be swapped." if not destination_weapon_id.is_empty() else "Weapon can be moved.",
		"source_raider_id": source_raider_id,
		"destination_raider_id": destination_raider_id,
		"source_weapon_id": source_weapon_id,
		"destination_weapon_id": destination_weapon_id,
	}


func move_or_swap_equipped_weapon(
	campaign: Dictionary, source_raider_id: String, destination_raider_id: String
) -> Dictionary:
	var validation := check_move_or_swap_equipped_weapon(
		campaign, source_raider_id, destination_raider_id
	)
	if not bool(validation.get("ok", false)):
		return validation
	var states: Dictionary = campaign.get("raider_states", {})
	var source_state: Dictionary = Dictionary(states[source_raider_id]).duplicate(true)
	var destination_state: Dictionary = Dictionary(states[destination_raider_id]).duplicate(true)
	var source_weapon_id := String(validation.get("source_weapon_id", ""))
	var destination_weapon_id := String(validation.get("destination_weapon_id", ""))
	source_state["equipped_weapon_id"] = destination_weapon_id
	destination_state["equipped_weapon_id"] = source_weapon_id
	states[source_raider_id] = source_state
	states[destination_raider_id] = destination_state
	campaign["raider_states"] = states
	validation["status"] = "swapped" if not destination_weapon_id.is_empty() else "moved"
	validation["message"] = (
		"Weapons swapped." if not destination_weapon_id.is_empty() else "Weapon moved."
	)
	return validation


static func get_weapon_holder_id(campaign: Dictionary, weapon_id: String) -> String:
	if weapon_id.is_empty():
		return ""
	var states_value: Variant = campaign.get("raider_states", {})
	if not states_value is Dictionary:
		return ""
	var states: Dictionary = states_value
	for raider_id in _ordered_raider_ids(campaign, states):
		var state_value: Variant = states.get(raider_id, {})
		if (
			state_value is Dictionary
			and String(state_value.get("equipped_weapon_id", "")) == weapon_id
		):
			return raider_id
	return ""


static func reconcile_duplicate_weapon_assignments(
	campaign: Dictionary
) -> Array[Dictionary]:
	var reconciliations: Array[Dictionary] = []
	var states_value: Variant = campaign.get("raider_states", {})
	if not states_value is Dictionary:
		return reconciliations
	var states: Dictionary = states_value
	var kept_by_weapon: Dictionary = {}
	var cleared_by_weapon: Dictionary = {}
	for raider_id in _ordered_raider_ids(campaign, states):
		var state_value: Variant = states.get(raider_id, {})
		if not state_value is Dictionary:
			continue
		var weapon_id := String(state_value.get("equipped_weapon_id", ""))
		if weapon_id.is_empty():
			continue
		if not kept_by_weapon.has(weapon_id):
			kept_by_weapon[weapon_id] = raider_id
			continue
		var state: Dictionary = Dictionary(state_value).duplicate(true)
		state["equipped_weapon_id"] = ""
		states[raider_id] = state
		var cleared_ids: Array = cleared_by_weapon.get(weapon_id, [])
		cleared_ids.append(raider_id)
		cleared_by_weapon[weapon_id] = cleared_ids
	campaign["raider_states"] = states
	for weapon_id_value in cleared_by_weapon:
		var weapon_id := String(weapon_id_value)
		var kept_id := String(kept_by_weapon.get(weapon_id, ""))
		var cleared_ids: Array = Array(cleared_by_weapon[weapon_id_value]).duplicate()
		reconciliations.append({
			"status": "duplicate_weapon_assignment_reconciled",
			"weapon_id": weapon_id,
			"stable_id": weapon_id,
			"kept_raider_id": kept_id,
			"current_holder_id": kept_id,
			"cleared_raider_ids": cleared_ids,
			"message": "Kept '%s' as holder of '%s' and cleared: %s." % [
				kept_id, weapon_id, ", ".join(cleared_ids),
			],
		})
	if reconciliations.is_empty():
		return reconciliations
	var progression: Dictionary = sanitize_progression(campaign.get("progression", {}))
	var diagnostics: Dictionary = Dictionary(
		progression.get("migration_diagnostics", {})
	).duplicate(true)
	var stored: Array = Array(diagnostics.get("duplicate_weapon_assignments", [])).duplicate(true)
	stored.append_array(reconciliations)
	diagnostics["duplicate_weapon_assignments"] = stored
	progression["migration_diagnostics"] = diagnostics
	campaign["progression"] = progression
	return reconciliations


func unequip(campaign: Dictionary, raider_id: String) -> Dictionary:
	var state_result := _get_raider_state(campaign, raider_id)
	if not bool(state_result.get("ok", false)):
		return state_result
	var states: Dictionary = campaign.get("raider_states", {})
	var state: Dictionary = Dictionary(states[raider_id]).duplicate(true)
	var previous_weapon_id := String(state.get("equipped_weapon_id", ""))
	state["equipped_weapon_id"] = ""
	states[raider_id] = state
	campaign["raider_states"] = states
	return {
		"ok": true,
		"status": "unequipped",
		"message": "Weapon unequipped.",
		"raider_id": raider_id,
		"previous_weapon_id": previous_weapon_id,
	}


func get_raider_traits(campaign: Dictionary, raider_id: String) -> Dictionary:
	var state_result := _get_raider_state(campaign, raider_id)
	if not bool(state_result.get("ok", false)):
		return state_result
	var state: Dictionary = state_result.get("state", {})
	return {
		"ok": true,
		"status": "read",
		"message": "Trait slots read.",
		"raider_id": raider_id,
		"major_trait_id": String(state.get("major_trait_id", "")),
		"minor_trait_ids": _two_trait_slots(state.get("minor_trait_ids", [])),
		"doctrine_id": String(state.get("doctrine_id", "")),
	}


func assign_major_trait(
	campaign: Dictionary, raider_id: String, trait_id: String,
	catalog_override: ProgressionCatalogResource = null
) -> Dictionary:
	return _assign_trait(
		campaign, raider_id, "major", 0, trait_id, catalog_override
	)


func assign_minor_trait(
	campaign: Dictionary, raider_id: String, slot_index: int, trait_id: String,
	catalog_override: ProgressionCatalogResource = null
) -> Dictionary:
	if slot_index < 0 or slot_index > 1:
		return _result(false, "invalid_slot", "Minor trait slot must be 0 or 1.")
	return _assign_trait(
		campaign, raider_id, "minor", slot_index, trait_id, catalog_override
	)


func get_missing_content_diagnostics(campaign: Dictionary) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var progression := sanitize_progression(campaign.get("progression", {}))
	for token_id in progression.get("advancement_token_ids", []):
		if ProgressionCatalog.get_advancement_token(String(token_id)) == null:
			diagnostics.append(_missing("progression.advancement_token_ids", String(token_id)))
	for material_id_value in progression.get("materials", {}):
		if ProgressionCatalog.get_material(String(material_id_value)) == null:
			diagnostics.append(_missing("progression.materials", String(material_id_value)))
	for recipe_id in progression.get("unlocked_recipe_ids", []):
		if ProgressionCatalog.get_recipe(String(recipe_id)) == null:
			diagnostics.append(_missing("progression.unlocked_recipe_ids", String(recipe_id)))
	for weapon_id in progression.get("crafted_weapon_ids", []):
		if ProgressionCatalog.get_weapon(String(weapon_id)) == null:
			diagnostics.append(_missing("progression.crafted_weapon_ids", String(weapon_id)))
	for raider_id_value in campaign.get("raider_states", {}):
		var raider_id := String(raider_id_value)
		var state_value: Variant = campaign["raider_states"][raider_id_value]
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var weapon_id := String(state.get("equipped_weapon_id", ""))
		if not weapon_id.is_empty() and ProgressionCatalog.get_weapon(weapon_id) == null:
			diagnostics.append(_missing("raider_states.%s.equipped_weapon_id" % raider_id, weapon_id))
		var major_id := String(state.get("major_trait_id", ""))
		if not major_id.is_empty() and ProgressionCatalog.get_raider_trait(major_id) == null:
			diagnostics.append(_missing("raider_states.%s.major_trait_id" % raider_id, major_id))
		for minor_id in state.get("minor_trait_ids", []):
			if not String(minor_id).is_empty() and ProgressionCatalog.get_raider_trait(String(minor_id)) == null:
				diagnostics.append(_missing("raider_states.%s.minor_trait_ids" % raider_id, String(minor_id)))
	var migration_diagnostics: Dictionary = progression.get("migration_diagnostics", {})
	for reconciliation_value in migration_diagnostics.get("duplicate_weapon_assignments", []):
		if reconciliation_value is Dictionary:
			diagnostics.append(Dictionary(reconciliation_value).duplicate(true))
	return diagnostics


func debug_grant_materials(campaign: Dictionary, grants: Dictionary) -> Dictionary:
	var progression := sanitize_progression(campaign.get("progression", {}))
	var materials: Dictionary = Dictionary(progression.get("materials", {})).duplicate(true)
	for material_id_value in grants:
		var material_id := String(material_id_value)
		var quantity := int(grants[material_id_value])
		if ProgressionCatalog.get_material(material_id) == null:
			return _result(false, "unknown_definition", "Unknown material '%s'." % material_id)
		if quantity <= 0:
			return _result(false, "invalid_quantity", "Grant quantities must be positive.")
	for material_id_value in grants:
		var material_id := String(material_id_value)
		materials[material_id] = int(materials.get(material_id, 0)) + int(grants[material_id_value])
	progression["materials"] = materials
	campaign["progression"] = progression
	return {
		"ok": true, "status": "granted", "message": "Fixture materials granted.",
		"materials": grants.duplicate(true),
	}


func _assign_trait(
	campaign: Dictionary, raider_id: String, tier: String, slot_index: int,
	trait_id: String, catalog_override: ProgressionCatalogResource
) -> Dictionary:
	var state_result := _get_raider_state(campaign, raider_id)
	if not bool(state_result.get("ok", false)):
		return state_result
	var states: Dictionary = campaign.get("raider_states", {})
	var state: Dictionary = Dictionary(states[raider_id]).duplicate(true)
	var minor_slots := _two_trait_slots(state.get("minor_trait_ids", []))
	if trait_id.is_empty():
		if tier == "major":
			state["major_trait_id"] = ""
		else:
			minor_slots[slot_index] = ""
			state["minor_trait_ids"] = minor_slots
		states[raider_id] = state
		campaign["raider_states"] = states
		return {
			"ok": true, "status": "cleared", "message": "Trait slot cleared.",
			"raider_id": raider_id, "tier": tier, "slot_index": slot_index,
		}
	var raider_trait := _get_raider_trait_definition(trait_id, catalog_override)
	if raider_trait == null:
		return _result(false, "unknown_definition", "Unknown raider trait '%s'." % trait_id)
	if raider_trait.tier != tier:
		return _result(
			false, "incompatible_tier",
			"Trait '%s' belongs in a %s slot." % [trait_id, raider_trait.tier]
		)
	var assigned_ids: Array = [String(state.get("major_trait_id", ""))]
	assigned_ids.append_array(minor_slots)
	if assigned_ids.has(trait_id):
		return _result(false, "duplicate_trait", "A raider cannot assign the same trait twice.")
	if tier == "major":
		state["major_trait_id"] = trait_id
	else:
		minor_slots[slot_index] = trait_id
		state["minor_trait_ids"] = minor_slots
	states[raider_id] = state
	campaign["raider_states"] = states
	return {
		"ok": true, "status": "assigned", "message": "Trait assigned.",
		"raider_id": raider_id, "trait_id": trait_id,
		"tier": tier, "slot_index": slot_index,
	}


func _get_raider_trait_definition(
	trait_id: String, catalog_override: ProgressionCatalogResource
) -> RaiderTraitDefinition:
	if catalog_override == null:
		return ProgressionCatalog.get_raider_trait(trait_id)
	for raider_trait in catalog_override.raider_traits:
		if raider_trait != null and raider_trait.trait_id == trait_id:
			return raider_trait
	return null


func _get_raider_state(campaign: Dictionary, raider_id: String) -> Dictionary:
	var states_value: Variant = campaign.get("raider_states", {})
	if not states_value is Dictionary or not states_value.has(raider_id):
		return _result(false, "unknown_raider", "Unknown campaign raider '%s'." % raider_id)
	var state_value: Variant = states_value[raider_id]
	if not state_value is Dictionary:
		return _result(false, "unknown_raider", "Raider state is malformed.")
	return {"ok": true, "status": "found", "message": "", "state": state_value}


func _effective_class_id(state: Dictionary) -> String:
	var advanced_id := String(state.get("advanced_class_id", ""))
	return (
		RaiderClassCatalog.normalize_class_id(advanced_id)
		if not advanced_id.is_empty()
		else RaiderClassCatalog.normalize_class_id(String(state.get("current_class", "")))
	)


func _two_trait_slots(value: Variant) -> Array[String]:
	var result: Array[String] = ["", ""]
	if value is Array:
		for index in range(mini(2, value.size())):
			result[index] = String(value[index])
	return result


func _missing(path: String, stable_id: String) -> Dictionary:
	return {
		"status": "missing_content", "path": path, "stable_id": stable_id,
		"message": "Saved content '%s' is unavailable at %s." % [stable_id, path],
	}


func _result(ok: bool, status: String, message: String) -> Dictionary:
	return {"ok": ok, "status": status, "message": message}


static func _unique_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			_append_unique_string(result, String(entry).strip_edges())
	return result


static func _append_unique_string(values: Array, value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)


static func _ordered_raider_ids(
	campaign: Dictionary, states: Dictionary
) -> Array[String]:
	var result: Array[String] = []
	for raider_id_value in campaign.get("raid_plan", {}).get("active_member_ids", []):
		_append_unique_string(result, String(raider_id_value))
	for raider_id_value in campaign.get("campaign_cast", {}).get("selected_raider_ids", []):
		_append_unique_string(result, String(raider_id_value))
	var remaining: Array[String] = []
	for raider_id_value in states:
		var raider_id := String(raider_id_value)
		if not result.has(raider_id):
			remaining.append(raider_id)
	remaining.sort()
	result.append_array(remaining)
	return result


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
