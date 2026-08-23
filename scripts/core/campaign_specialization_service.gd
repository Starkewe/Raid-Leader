extends RefCounted
class_name CampaignSpecializationService

const RaiderClassCatalogScript := preload("res://scripts/data/raider_class_catalog.gd")
const TrainingProgressionCatalogScript := preload(
	"res://scripts/data/training_progression_catalog.gd"
)


func get_status(
	campaign: Dictionary, raider_id: String, preview_lineage_id: String = ""
) -> Dictionary:
	var lookup := _get_raider_state(campaign, raider_id)
	if not bool(lookup.get("ok", false)):
		return lookup
	var state: Dictionary = lookup["state"]
	var base_class_id := RaiderClassCatalogScript.normalize_class_id(
		String(state.get("current_class", ""))
	)
	var eligible := RaiderClassCatalogScript.get_lineages_for_base_class(base_class_id)
	var active_lineage_id := _valid_lineage_for_base(
		String(state.get("secondary_lineage_id", state.get("specialization_id", ""))),
		base_class_id
	)
	var preview_id := _valid_lineage_for_base(preview_lineage_id, base_class_id)
	if preview_id.is_empty():
		preview_id = active_lineage_id
	if preview_id.is_empty() and not eligible.is_empty():
		preview_id = String(eligible[0].get("lineage_id", ""))
	var preview_lineage := RaiderClassCatalogScript.get_lineage_definition(preview_id)
	var active_lineage := RaiderClassCatalogScript.get_lineage_definition(active_lineage_id)
	var token_spent := bool(
		state.get("lineage_token_spent", state.get("specialization_unlocked", false))
	)
	var preview_progress := _progress_for_lineage(state, preview_id)
	var completed_ids: Array[String] = _string_array(
		preview_progress.get("completed_node_ids", [])
	)
	var advanced_id := String(state.get("advanced_class_id", ""))
	var full_id := String(state.get("advanced_class_completed_id", ""))
	var token := _matching_owned_token(campaign, base_class_id)
	return {
		"ok": true,
		"status": "found",
		"raider_id": raider_id,
		"base_class_id": base_class_id,
		"lineage_token_spent": token_spent,
		"specialization_unlocked": token_spent,
		"secondary_lineage_id": active_lineage_id,
		"lineage": active_lineage,
		"active_lineage": active_lineage,
		"eligible_lineages": eligible,
		"preview_lineage_id": preview_id,
		"preview_lineage": preview_lineage,
		"preview_is_active": not preview_id.is_empty() and preview_id == active_lineage_id,
		"preview_progress": preview_progress,
		"node_statuses": _build_node_statuses(preview_id, preview_progress),
		"available_node_ids": TrainingProgressionCatalogScript.get_available_node_ids(
			completed_ids
		),
		"candidate_advanced_class_id": preview_id,
		"candidate_advanced_class": RaiderClassCatalogScript.get_definition(preview_id),
		"advanced_class_id": advanced_id,
		"advanced_class": RaiderClassCatalogScript.get_definition(advanced_id),
		"advanced_class_completed_id": full_id,
		"full_advanced_class": RaiderClassCatalogScript.get_definition(full_id),
		"active_raid_roles": Array(active_lineage.get("raid_roles", [])).duplicate(),
		"matching_token_id": String(token.get("token_id", "")),
		"matching_token_name": String(token.get("display_name", "")),
		"free_for_testing": true,
		"unlock_costs": [],
		"stage": _stage_for(active_lineage_id, advanced_id, full_id),
	}


func check_lock_lineage(
	campaign: Dictionary, raider_id: String, lineage_id: String
) -> Dictionary:
	var status := get_status(campaign, raider_id, lineage_id)
	if not bool(status.get("ok", false)):
		return status
	var canonical := String(status.get("preview_lineage_id", ""))
	if canonical.is_empty() or canonical != RaiderClassCatalogScript.normalize_lineage_id(lineage_id):
		return _result(false, "ineligible_lineage", "That lineage is unavailable to this raider.")
	var current_id := String(status.get("secondary_lineage_id", ""))
	if canonical == current_id:
		return _result(false, "already_active", "This lineage is already active.")
	var first_lock := not bool(status.get("lineage_token_spent", false))
	var token_id := String(status.get("matching_token_id", ""))
	if first_lock and token_id.is_empty():
		return _result(
			false,
			"no_matching_token",
			"No owned %s class token is available." % String(status.get("base_class_id", "")).capitalize()
		)
	var state: Dictionary = campaign.get("raider_states", {}).get(raider_id, {})
	var target_progress := _progress_for_lineage(state, canonical)
	var target_completed: Array[String] = _string_array(
		target_progress.get("completed_node_ids", [])
	)
	var target_identity_active := target_completed.has(
		TrainingProgressionCatalogScript.ENTRY_NODE_ID
	)
	var target_effective_class := (
		canonical if target_identity_active else String(status.get("base_class_id", ""))
	)
	var weapon_return := _weapon_return_preview(state, target_effective_class)
	var old_progress := _progress_for_lineage(state, current_id)
	var old_completed: Array[String] = _string_array(old_progress.get("completed_node_ids", []))
	return {
		"ok": true,
		"status": "lockable",
		"message": "",
		"raider_id": raider_id,
		"lineage_id": canonical,
		"lineage": status.get("preview_lineage", {}),
		"advanced_class": status.get("candidate_advanced_class", {}),
		"first_lock": first_lock,
		"switching": not current_id.is_empty(),
		"previous_lineage_id": current_id,
		"previous_lineage": status.get("active_lineage", {}),
		"previous_completed_node_ids": old_completed,
		"previous_partial_progress_resets": _has_partial_progress(old_progress),
		"restored_completed_node_ids": target_completed,
		"incoming_roles": Array(status.get("preview_lineage", {}).get("raid_roles", [])).duplicate(),
		"token_id": token_id,
		"token_name": String(status.get("matching_token_name", token_id)),
		"weapon_return": weapon_return,
		"free_for_testing": true,
	}


func lock_lineage(
	campaign: Dictionary, raider_id: String, lineage_id: String
) -> Dictionary:
	var check := check_lock_lineage(campaign, raider_id, lineage_id)
	if not bool(check.get("ok", false)):
		return check
	var first_lock := bool(check.get("first_lock", false))
	var token_id := String(check.get("token_id", ""))
	if first_lock:
		var progression: Dictionary = Dictionary(campaign.get("progression", {})).duplicate(true)
		var token_ids: Array = Array(progression.get("advancement_token_ids", [])).duplicate()
		if not token_ids.has(token_id):
			return _result(false, "no_matching_token", "The selected token is no longer available.")
		token_ids.erase(token_id)
		progression["advancement_token_ids"] = token_ids
		campaign["progression"] = progression

	var states: Dictionary = Dictionary(campaign.get("raider_states", {})).duplicate(true)
	var state: Dictionary = Dictionary(states.get(raider_id, {})).duplicate(true)
	var previous_id := String(state.get("secondary_lineage_id", ""))
	var all_progress := _all_progress(state)
	if not previous_id.is_empty() and all_progress.has(previous_id):
		all_progress[previous_id] = _reset_partial_progress(
			Dictionary(all_progress[previous_id])
		)
	var canonical := String(check.get("lineage_id", ""))
	if not all_progress.has(canonical):
		all_progress[canonical] = _empty_progress()
	var target_progress: Dictionary = Dictionary(all_progress[canonical])
	var completed: Array[String] = _string_array(target_progress.get("completed_node_ids", []))
	state["lineage_token_spent"] = true
	state["specialization_unlocked"] = true
	state["secondary_lineage_id"] = canonical
	state["specialization_id"] = canonical
	state["lineage_progress_by_id"] = all_progress
	state["assigned_roles"] = []
	state["advanced_class_id"] = (
		canonical if completed.has(TrainingProgressionCatalogScript.ENTRY_NODE_ID) else ""
	)
	state["advanced_class_completed_id"] = (
		canonical if completed.has(TrainingProgressionCatalogScript.CAPSTONE_NODE_ID) else ""
	)
	var returned_weapon_id := ""
	var weapon_return: Dictionary = check.get("weapon_return", {})
	if bool(weapon_return.get("required", false)):
		returned_weapon_id = String(state.get("equipped_weapon_id", ""))
		state["equipped_weapon_id"] = ""
	states[raider_id] = state
	campaign["raider_states"] = states
	var default_class_id := String(state.get("advanced_class_id", ""))
	if default_class_id.is_empty():
		default_class_id = String(state.get("current_class", ""))
	return {
		"ok": true,
		"status": "lineage_locked" if first_lock else "lineage_changed",
		"message": (
			"Lineage begun. Its role and minor benefits are active."
			if first_lock
			else "Lineage changed. Completed milestones were restored; partial abandoned quests were reset."
		),
		"raider_id": raider_id,
		"lineage_id": canonical,
		"previous_lineage_id": previous_id,
		"consumed_token_id": token_id if first_lock else "",
		"returned_weapon_id": returned_weapon_id,
		"default_weapon_family_id": RaiderClassCatalogScript.get_default_weapon_family_id(
			default_class_id
		),
		"restored_completed_node_ids": completed,
		"free_for_testing": true,
	}


func clear_lineage(campaign: Dictionary, raider_id: String) -> Dictionary:
	var status := get_status(campaign, raider_id)
	if not bool(status.get("ok", false)):
		return status
	var lineage_id := String(status.get("secondary_lineage_id", ""))
	if lineage_id.is_empty():
		return _result(false, "no_lineage", "This raider has no active lineage.")
	var states: Dictionary = Dictionary(campaign.get("raider_states", {})).duplicate(true)
	var state: Dictionary = Dictionary(states.get(raider_id, {})).duplicate(true)
	var all_progress := _all_progress(state)
	all_progress[lineage_id] = _reset_partial_progress(
		Dictionary(all_progress.get(lineage_id, _empty_progress()))
	)
	state["lineage_progress_by_id"] = all_progress
	state["secondary_lineage_id"] = ""
	state["specialization_id"] = ""
	state["advanced_class_id"] = ""
	state["advanced_class_completed_id"] = ""
	state["assigned_roles"] = []
	states[raider_id] = state
	campaign["raider_states"] = states
	return {
		"ok": true,
		"status": "lineage_cleared",
		"message": "Lineage removed. Completed milestones remain dormant and partial quests were reset.",
		"raider_id": raider_id,
		"previous_lineage_id": lineage_id,
	}


func apply_victory_summary(campaign: Dictionary, summary: Dictionary) -> Dictionary:
	if String(summary.get("outcome", "")) != "victory":
		return {"ok": true, "status": "discarded_non_victory", "updates": []}
	var encounter_id := String(summary.get("encounter_id", "")).strip_edges()
	if encounter_id.is_empty():
		return _result(false, "missing_encounter", "Training credit requires an encounter ID.")
	var credits_value: Variant = summary.get("training_quest_credit", {})
	var credits_by_raider: Dictionary = (
		Dictionary(credits_value) if credits_value is Dictionary else {}
	)
	var active_ids: Array[String] = _string_array(
		campaign.get("raid_plan", {}).get("active_member_ids", [])
	)
	var states: Dictionary = Dictionary(campaign.get("raider_states", {})).duplicate(true)
	var updates: Array[Dictionary] = []
	for raider_id in active_ids:
		if not states.get(raider_id) is Dictionary:
			continue
		var state: Dictionary = Dictionary(states[raider_id]).duplicate(true)
		var lineage_id := String(state.get("secondary_lineage_id", ""))
		if lineage_id.is_empty():
			continue
		var all_progress := _all_progress(state)
		var progress: Dictionary = Dictionary(
			all_progress.get(lineage_id, _empty_progress())
		).duplicate(true)
		var progress_before := progress.duplicate(true)
		var completed_before: Array[String] = _string_array(
			progress.get("completed_node_ids", [])
		)
		var available_before := TrainingProgressionCatalogScript.get_available_node_ids(
			completed_before
		)
		var raider_credits: Dictionary = {}
		if credits_by_raider.get(raider_id) is Dictionary:
			raider_credits = Dictionary(credits_by_raider[raider_id])
		var completed_now: Array[String] = []
		for node_id in available_before:
			_apply_node_credit(
				progress, lineage_id, node_id, encounter_id, raider_credits
			)
			if _is_node_complete(lineage_id, node_id, progress):
				var completed: Array[String] = _string_array(progress.get("completed_node_ids", []))
				if not completed.has(node_id):
					completed.append(node_id)
					completed_now.append(node_id)
				progress["completed_node_ids"] = completed
		all_progress[lineage_id] = progress
		state["lineage_progress_by_id"] = all_progress
		var returned_weapon_id := ""
		if completed_now.has(TrainingProgressionCatalogScript.ENTRY_NODE_ID):
			state["advanced_class_id"] = lineage_id
			var weapon_return := _weapon_return_preview(state, lineage_id)
			if bool(weapon_return.get("required", false)):
				returned_weapon_id = String(state.get("equipped_weapon_id", ""))
				state["equipped_weapon_id"] = ""
		if completed_now.has(TrainingProgressionCatalogScript.CAPSTONE_NODE_ID):
			state["advanced_class_completed_id"] = lineage_id
		states[raider_id] = state
		if progress != progress_before:
			updates.append({
				"raider_id": raider_id,
				"lineage_id": lineage_id,
				"completed_node_ids": completed_now,
				"returned_weapon_id": returned_weapon_id,
			})
	campaign["raider_states"] = states
	return {
		"ok": true,
		"status": "training_progress_applied",
		"message": "Victory-backed training credit applied.",
		"updates": updates,
	}


# Compatibility aliases retained for older callers while the UI uses lock_lineage.
func check_unlock_specialization(campaign: Dictionary, raider_id: String) -> Dictionary:
	var status := get_status(campaign, raider_id)
	if not bool(status.get("ok", false)):
		return status
	return _result(
		false,
		"lineage_required",
		"Choose a lineage first; the matching token is consumed when that lineage begins."
	)


func unlock_specialization(campaign: Dictionary, raider_id: String) -> Dictionary:
	return check_unlock_specialization(campaign, raider_id)


func check_select_lineage(
	campaign: Dictionary, raider_id: String, lineage_id: String
) -> Dictionary:
	return check_lock_lineage(campaign, raider_id, lineage_id)


func select_lineage(
	campaign: Dictionary, raider_id: String, lineage_id: String
) -> Dictionary:
	return lock_lineage(campaign, raider_id, lineage_id)


func check_commit_advanced_class(campaign: Dictionary, raider_id: String) -> Dictionary:
	var status := get_status(campaign, raider_id)
	if not bool(status.get("ok", false)):
		return status
	return _result(
		false,
		"quest_progression_required",
		"Complete the entry, three talent tiers, and capstone to acquire this advanced class."
	)


func commit_advanced_class(campaign: Dictionary, raider_id: String) -> Dictionary:
	return check_commit_advanced_class(campaign, raider_id)


func _apply_node_credit(
	progress: Dictionary, lineage_id: String, node_id: String,
	encounter_id: String, credits: Dictionary
) -> void:
	var node := TrainingProgressionCatalogScript.get_node(lineage_id, node_id)
	var all_objectives: Dictionary = Dictionary(
		progress.get("objective_progress", {})
	).duplicate(true)
	var node_progress: Dictionary = Dictionary(
		all_objectives.get(node_id, {})
	).duplicate(true)
	for objective_value in node.get("objectives", []):
		var objective: Dictionary = objective_value
		var objective_id := String(objective.get("objective_id", ""))
		var kind := String(objective.get("kind", "counter"))
		if kind == "unique_set":
			var seen := _string_array(node_progress.get(objective_id, []))
			if not seen.has(encounter_id):
				seen.append(encounter_id)
			node_progress[objective_id] = seen
			continue
		var credit_key := String(objective.get("credit_key", ""))
		var delta := maxi(int(credits.get(credit_key, 0)), 0)
		if delta <= 0:
			continue
		var target := maxi(int(objective.get("target", 1)), 1)
		node_progress[objective_id] = mini(
			int(node_progress.get(objective_id, 0)) + delta, target
		)
	all_objectives[node_id] = node_progress
	progress["objective_progress"] = all_objectives


func _is_node_complete(lineage_id: String, node_id: String, progress: Dictionary) -> bool:
	var node := TrainingProgressionCatalogScript.get_node(lineage_id, node_id)
	var all_objectives: Dictionary = progress.get("objective_progress", {})
	var node_progress: Dictionary = all_objectives.get(node_id, {})
	for objective_value in node.get("objectives", []):
		var objective: Dictionary = objective_value
		var current := _objective_count(
			node_progress.get(String(objective.get("objective_id", "")), 0)
		)
		if current < int(objective.get("target", 1)):
			return false
	return not Array(node.get("objectives", [])).is_empty()


func _build_node_statuses(lineage_id: String, progress: Dictionary) -> Array[Dictionary]:
	if lineage_id.is_empty():
		return []
	var result: Array[Dictionary] = []
	var completed: Array[String] = _string_array(progress.get("completed_node_ids", []))
	var available := TrainingProgressionCatalogScript.get_available_node_ids(completed)
	var all_objectives: Dictionary = progress.get("objective_progress", {})
	for node_value in TrainingProgressionCatalogScript.get_definition(lineage_id).get("nodes", []):
		var node: Dictionary = node_value
		var node_id := String(node.get("node_id", ""))
		var node_progress: Dictionary = all_objectives.get(node_id, {})
		var objectives: Array[Dictionary] = []
		for objective_value in node.get("objectives", []):
			var objective: Dictionary = Dictionary(objective_value).duplicate(true)
			var objective_id := String(objective.get("objective_id", ""))
			objective["current"] = (
				int(objective.get("target", 1))
				if completed.has(node_id)
				else _objective_count(node_progress.get(objective_id, 0))
			)
			objective["complete"] = int(objective["current"]) >= int(objective.get("target", 1))
			objectives.append(objective)
		var status := "locked"
		if completed.has(node_id):
			status = "completed"
		elif available.has(node_id):
			status = "available"
		var enriched := node.duplicate(true)
		enriched["status"] = status
		enriched["objectives"] = objectives
		result.append(enriched)
	return result


func _reset_partial_progress(progress: Dictionary) -> Dictionary:
	var result := progress.duplicate(true)
	var completed: Array[String] = _string_array(result.get("completed_node_ids", []))
	var objective_progress: Dictionary = Dictionary(
		result.get("objective_progress", {})
	).duplicate(true)
	for node_id in objective_progress.keys():
		if not completed.has(String(node_id)):
			objective_progress.erase(node_id)
	result["objective_progress"] = objective_progress
	result["completed_node_ids"] = completed
	return result


func _progress_for_lineage(state: Dictionary, lineage_id: String) -> Dictionary:
	if lineage_id.is_empty():
		return _empty_progress()
	return Dictionary(_all_progress(state).get(lineage_id, _empty_progress())).duplicate(true)


func _all_progress(state: Dictionary) -> Dictionary:
	var source: Variant = state.get("lineage_progress_by_id", {})
	var result: Dictionary = Dictionary(source).duplicate(true) if source is Dictionary else {}
	for lineage_id in result.keys():
		if not result[lineage_id] is Dictionary:
			result[lineage_id] = _empty_progress()
			continue
		var progress: Dictionary = Dictionary(result[lineage_id]).duplicate(true)
		progress["completed_node_ids"] = _string_array(progress.get("completed_node_ids", []))
		if not progress.get("objective_progress", {}) is Dictionary:
			progress["objective_progress"] = {}
		result[lineage_id] = progress
	return result


func _empty_progress() -> Dictionary:
	return {"completed_node_ids": [], "objective_progress": {}}


func _has_partial_progress(progress: Dictionary) -> bool:
	var completed: Array[String] = _string_array(progress.get("completed_node_ids", []))
	for node_id in Dictionary(progress.get("objective_progress", {})).keys():
		if not completed.has(String(node_id)):
			return true
	return false


func _weapon_return_preview(state: Dictionary, target_class_id: String) -> Dictionary:
	var weapon_id := String(state.get("equipped_weapon_id", ""))
	if weapon_id.is_empty():
		return {"required": false}
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	if weapon == null:
		return {
			"required": true,
			"weapon_id": weapon_id,
			"weapon_name": weapon_id.replace("_", " ").capitalize(),
			"reason": "The equipped weapon definition is unavailable.",
		}
	if ProgressionCatalog.is_family_compatible(target_class_id, weapon.family_id):
		return {"required": false}
	return {
		"required": true,
		"weapon_id": weapon_id,
		"weapon_name": weapon.display_name,
		"family_id": weapon.family_id,
		"target_class_id": target_class_id,
		"reason": "The weapon is incompatible with the incoming class identity.",
	}


func _matching_owned_token(campaign: Dictionary, base_class_id: String) -> Dictionary:
	for token_id_value in campaign.get("progression", {}).get("advancement_token_ids", []):
		var token_id := String(token_id_value)
		var token := ProgressionCatalog.get_advancement_token(token_id)
		if token == null:
			continue
		if RaiderClassCatalogScript.normalize_class_id(token.archetype_class_id) == base_class_id:
			return {"token_id": token.token_id, "display_name": token.display_name}
	return {}


func _valid_lineage_for_base(lineage_id: String, base_class_id: String) -> String:
	var canonical := RaiderClassCatalogScript.normalize_lineage_id(lineage_id)
	var lineage := RaiderClassCatalogScript.get_lineage_definition(canonical)
	return canonical if String(lineage.get("base_class_id", "")) == base_class_id else ""


func _stage_for(active_id: String, advanced_id: String, full_id: String) -> String:
	if active_id.is_empty():
		return "uncommitted"
	if full_id == active_id:
		return "advanced_class_complete"
	if advanced_id == active_id:
		return "class_identity"
	return "lineage"


func _objective_count(value: Variant) -> int:
	return value.size() if value is Array else maxi(int(value), 0)


func _get_raider_state(campaign: Dictionary, raider_id: String) -> Dictionary:
	var states_value: Variant = campaign.get("raider_states", {})
	if not states_value is Dictionary or not states_value.has(raider_id):
		return _result(false, "unknown_raider", "Unknown campaign raider '%s'." % raider_id)
	var state_value: Variant = states_value[raider_id]
	if not state_value is Dictionary:
		return _result(false, "unknown_raider", "Raider state is malformed.")
	if not bool(state_value.get("recruited", false)):
		return _result(false, "not_recruited", "Only recruited raiders can begin a lineage.")
	return {"ok": true, "status": "found", "message": "", "state": state_value}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry)
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result


func _result(ok: bool, status: String, message: String) -> Dictionary:
	return {"ok": ok, "status": status, "message": message}
