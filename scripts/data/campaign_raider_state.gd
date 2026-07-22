extends RefCounted
class_name CampaignRaiderState


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
		"advanced_class_id": "",
		"specialization_id": "",
		"recruitment_source": recruitment_source,
		"room_assignment_id": "",
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
	state["advanced_class_id"] = String(state.get("advanced_class_id", ""))
	state["specialization_id"] = String(state.get("specialization_id", ""))
	state["recruitment_source"] = String(
		state.get("recruitment_source", state.get("source_id", "unknown"))
	)
	state["room_assignment_id"] = String(state.get("room_assignment_id", ""))
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


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()

			if not text.is_empty() and not result.has(text):
				result.append(text)

	return result
