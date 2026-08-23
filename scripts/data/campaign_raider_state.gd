extends RefCounted
class_name CampaignRaiderState

const RaiderClassCatalogScript := preload("res://scripts/data/raider_class_catalog.gd")
const TrainingProgressionCatalogScript := preload(
	"res://scripts/data/training_progression_catalog.gd"
)


static func create(
	raider_id: String,
	current_class: String,
	recruited: bool,
	active: bool,
	recruitment_source: String
) -> Dictionary:
	return {
		"raider_id": raider_id,
		"in_campaign_cast": true,
		"recruited": recruited,
		"active": active,
		"current_class": current_class,
		"assigned_roles": [],
		"specialization_unlocked": false,
		"lineage_token_spent": false,
		"secondary_lineage_id": "",
		"advanced_class_id": "",
		"advanced_class_completed_id": "",
		"specialization_id": "",
		"lineage_progress_by_id": {},
		"equipped_weapon_id": "",
		"major_trait_id": "",
		"minor_trait_ids": [],
		"doctrine_id": "",
		"recruitment_source": recruitment_source,
		"room_assignment_id": "",
		"last_camp_position": [],
		"combat_history": {"attempts": 0, "victories": 0, "defeats": 0},
		"permanent_milestone_ids": [],
		"descriptive_title": "",
	}


static func sanitize(source: Dictionary, raider_id: String, default_class: String) -> Dictionary:
	var state := source.duplicate(true)
	state["raider_id"] = raider_id
	state["in_campaign_cast"] = bool(state.get("in_campaign_cast", true))
	state["recruited"] = bool(state.get("recruited", false))
	state["active"] = bool(state.get("active", false))
	state["current_class"] = String(
		state.get("current_class", state.get("unit_class", default_class))
	)
	state["assigned_roles"] = _string_array(state.get("assigned_roles", []))
	var base_class_id := RaiderClassCatalogScript.normalize_class_id(
		String(state.get("current_class", default_class))
	)
	var advanced_class_id := RaiderClassCatalogScript.normalize_class_id(
		String(state.get("advanced_class_id", ""))
	)
	var lineage_id := RaiderClassCatalogScript.normalize_lineage_id(
		String(state.get("secondary_lineage_id", state.get("specialization_id", "")))
	)
	if lineage_id.is_empty() and not advanced_class_id.is_empty():
		var advanced_definition := RaiderClassCatalogScript.get_definition(advanced_class_id)
		if String(advanced_definition.get("parent_class_id", "")) == base_class_id:
			lineage_id = String(
				advanced_definition.get("secondary_lineage_id", advanced_class_id)
			)
	var lineage := RaiderClassCatalogScript.get_lineage_definition(lineage_id)
	if not lineage.is_empty() and String(lineage.get("base_class_id", "")) != base_class_id:
		lineage_id = ""
	if (
		not advanced_class_id.is_empty()
		and not lineage_id.is_empty()
		and RaiderClassCatalogScript.resolve_advanced_class_id(base_class_id, lineage_id)
		!= advanced_class_id
	):
		advanced_class_id = ""
	var lineage_progress := _sanitize_lineage_progress(
		state.get("lineage_progress_by_id", {}), base_class_id
	)
	# The discarded prototype granted advanced_class_id in one click. Preserve those
	# saves as fully acquired rather than silently taking identity or kit away.
	var stored_advanced_progress: Dictionary = Dictionary(
		lineage_progress.get(lineage_id, {})
	)
	if (
		not advanced_class_id.is_empty()
		and _string_array(stored_advanced_progress.get("completed_node_ids", [])).is_empty()
	):
		lineage_progress[lineage_id] = {
			"completed_node_ids": TrainingProgressionCatalogScript.ALL_NODE_IDS.duplicate(),
			"objective_progress": {},
		}
	var active_progress: Dictionary = Dictionary(
		lineage_progress.get(lineage_id, {"completed_node_ids": [], "objective_progress": {}})
	)
	var completed_nodes := _string_array(active_progress.get("completed_node_ids", []))
	advanced_class_id = (
		lineage_id
		if completed_nodes.has(TrainingProgressionCatalogScript.ENTRY_NODE_ID)
		else ""
	)
	var completed_advanced_id := (
		lineage_id
		if completed_nodes.has(TrainingProgressionCatalogScript.CAPSTONE_NODE_ID)
		else ""
	)
	var token_spent := bool(
		state.get("lineage_token_spent", state.get("specialization_unlocked", false))
	) or not lineage_id.is_empty() or not advanced_class_id.is_empty()
	state["specialization_unlocked"] = token_spent
	state["lineage_token_spent"] = token_spent
	state["secondary_lineage_id"] = lineage_id
	state["advanced_class_id"] = advanced_class_id
	state["advanced_class_completed_id"] = completed_advanced_id
	state["lineage_progress_by_id"] = lineage_progress
	# Compatibility alias for older readers and existing schema-11 saves.
	state["specialization_id"] = lineage_id
	state["equipped_weapon_id"] = String(state.get("equipped_weapon_id", ""))
	state["major_trait_id"] = String(state.get("major_trait_id", ""))
	state["minor_trait_ids"] = _string_array(state.get("minor_trait_ids", []))
	while state["minor_trait_ids"].size() > 2:
		state["minor_trait_ids"].pop_back()
	state["doctrine_id"] = String(state.get("doctrine_id", ""))
	state["recruitment_source"] = String(
		state.get("recruitment_source", state.get("source_id", "unknown"))
	)
	state["room_assignment_id"] = String(state.get("room_assignment_id", ""))
	state["last_camp_position"] = _sanitize_position(state.get("last_camp_position", []))
	state["combat_history"] = _sanitize_combat_history(state.get("combat_history", {}))
	state["permanent_milestone_ids"] = _string_array(
		state.get("permanent_milestone_ids", [])
	)
	state["descriptive_title"] = String(state.get("descriptive_title", ""))
	state.erase("unit_class")
	state.erase("source_id")
	return state


static func _sanitize_combat_history(value: Variant) -> Dictionary:
	var source: Dictionary = Dictionary(value) if value is Dictionary else {}
	return {
		"attempts": maxi(int(source.get("attempts", 0)), 0),
		"victories": maxi(int(source.get("victories", 0)), 0),
		"defeats": maxi(int(source.get("defeats", 0)), 0),
	}


static func _sanitize_position(value: Variant) -> Array:
	var source: Array = value if value is Array else []

	if source.size() < 2:
		return []

	var x := float(source[0])
	var y := float(source[1])

	if x != x or y != y or absf(x) > 100000.0 or absf(y) > 100000.0:
		return []

	return [x, y]


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()

			if not text.is_empty() and not result.has(text):
				result.append(text)

	return result


static func _sanitize_lineage_progress(value: Variant, base_class_id: String) -> Dictionary:
	var source: Dictionary = Dictionary(value) if value is Dictionary else {}
	var result: Dictionary = {}
	for lineage_id_value in source.keys():
		var lineage_id := RaiderClassCatalogScript.normalize_lineage_id(
			String(lineage_id_value)
		)
		var lineage := RaiderClassCatalogScript.get_lineage_definition(lineage_id)
		if String(lineage.get("base_class_id", "")) != base_class_id:
			continue
		var progress_value: Variant = source[lineage_id_value]
		var progress: Dictionary = (
			Dictionary(progress_value).duplicate(true)
			if progress_value is Dictionary else {}
		)
		var completed: Array[String] = []
		for node_id in _string_array(progress.get("completed_node_ids", [])):
			if TrainingProgressionCatalogScript.ALL_NODE_IDS.has(node_id):
				completed.append(node_id)
		var objective_value: Variant = progress.get("objective_progress", {})
		result[lineage_id] = {
			"completed_node_ids": completed,
			"objective_progress": (
				Dictionary(objective_value).duplicate(true)
				if objective_value is Dictionary else {}
			),
		}
	return result
