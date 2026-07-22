extends RefCounted
class_name CampV2EventSystem

const RaiderMemoryStoreScript := preload("res://scripts/data/raider_memory_store.gd")
const RaiderRelationshipStoreScript := preload(
	"res://scripts/data/raider_relationship_store.gd"
)
const RaiderLoreKnowledgeStoreScript := preload(
	"res://scripts/data/raider_lore_knowledge_store.gd"
)
const CampV2TuningScript := preload("res://scripts/core/camp_v2_tuning.gd")

const NOTABLE_EVENT_LIMIT: int = CampV2TuningScript.EVENT_LIMITS[
	"notable_event_records"
]
const RAID_CHRONICLE_LIMIT: int = CampV2TuningScript.EVENT_LIMITS["raid_chronicle"]

const EVENT_CATEGORIES := {
	"raider_recruited": "roster",
	"raider_added_to_active_roster": "roster",
	"raider_moved_to_reserve": "roster",
	"room_assignment_changed": "roster",
	"boss_attempt_completed": "combat",
	"boss_defeated": "combat",
	"raider_defeated": "combat",
	"mechanic_failed": "combat",
	"mechanic_successfully_resolved": "combat",
	"interrupt_succeeded": "combat",
	"exceptional_heal_or_rescue": "combat",
	"last_survivor": "combat",
	"class_advanced": "personal_reflection",
	"conversation_completed": "social",
	"meaningful_argument": "social",
	"mentorship_milestone": "social",
	"significant_shared_activity": "camp_life",
	"self_reflection": "personal_reflection",
	"memory_promoted": "personal_reflection",
	"relationship_threshold_reached": "social",
	"lore_learned": "personal_reflection",
	"lore_taught": "social",
	"lore_argument": "social",
}

const DEFAULT_ADMISSION_REASONS := {
	"raider_recruited": ["direct_consequence"],
	"raider_added_to_active_roster": ["direct_consequence"],
	"raider_moved_to_reserve": ["direct_consequence"],
	"room_assignment_changed": ["direct_consequence"],
	"raider_defeated": ["direct_consequence"],
	"mechanic_failed": ["unusual_for_raider", "direct_consequence"],
	"mechanic_successfully_resolved": ["meaningful_agency"],
	"interrupt_succeeded": ["meaningful_agency"],
	"exceptional_heal_or_rescue": ["meaningful_agency", "involved_specific_person"],
	"last_survivor": ["first_last_best_worst_or_milestone"],
	"class_advanced": ["first_last_best_worst_or_milestone"],
	"self_reflection": ["reinforces_existing_thread"],
}


static func create_memory_store() -> Dictionary:
	return RaiderMemoryStoreScript.create_store()


static func create_relationship_store() -> Dictionary:
	return RaiderRelationshipStoreScript.create_store()


static func create_lore_store() -> Dictionary:
	return RaiderLoreKnowledgeStoreScript.create_store()


static func sanitize_campaign_stores(
	campaign: Dictionary, valid_raider_ids: Array[String]
) -> void:
	campaign["memory_store"] = RaiderMemoryStoreScript.sanitize_store(
		campaign.get("memory_store", {}), valid_raider_ids
	)
	campaign["relationship_store"] = RaiderRelationshipStoreScript.sanitize_store(
		campaign.get("relationship_store", {}), valid_raider_ids
	)
	campaign["lore_knowledge_store"] = RaiderLoreKnowledgeStoreScript.sanitize_store(
		campaign.get("lore_knowledge_store", {}), valid_raider_ids
	)
	campaign["notable_event_records"] = _dictionary_array(
		campaign.get("notable_event_records", []), NOTABLE_EVENT_LIMIT
	)
	campaign["raid_chronicle"] = _dictionary_array(
		campaign.get("raid_chronicle", []), RAID_CHRONICLE_LIMIT
	)
	campaign["notable_event_sequence"] = maxi(
		int(campaign.get("notable_event_sequence", 0)),
		campaign["notable_event_records"].size()
	)


static func process_event(campaign: Dictionary, raw_event: Dictionary) -> Dictionary:
	var event := normalize_event(raw_event)

	if event.is_empty():
		return {"event": {}, "derived_events": []}

	var now := int(event.get("recorded_unix_time", Time.get_unix_time_from_system()))
	var memory_store: Dictionary = campaign.get("memory_store", create_memory_store())
	RaiderMemoryStoreScript.process_lifecycle(memory_store, now)
	var relationship_store: Dictionary = campaign.get(
		"relationship_store", create_relationship_store()
	)
	var participants := _string_array(event.get("participants", []))
	var derived_events: Array[Dictionary] = []
	var personal_candidates := _personal_candidates(event)

	if participants.size() == 2:
		for derived in RaiderRelationshipStoreScript.record_pair_event(
			relationship_store, event
		):
			derived_events.append(_normalize_derived_event(campaign, derived, now))

	if participants.size() >= 3:
		_append_chronicle(campaign, event)
	elif participants.is_empty() and bool(event.get("raid_chronicle", false)):
		_append_chronicle(campaign, event)

	if personal_candidates.is_empty() and participants.size() >= 2:
		_record_aggregate_rejection(memory_store, event, participants.size())

	for candidate in personal_candidates:
		var raider_id := String(candidate.get("raider_id", ""))

		if raider_id.is_empty():
			continue

		var personal_event := event.duplicate(true)
		personal_event["admission_reasons"] = _string_array(
			candidate.get("admission_reasons", event.get("admission_reasons", []))
		)

		for optional_key in [
			"promotion_reason",
			"permanent_eligible",
			"authored_significance",
			"memory_strength",
			"reinforcement_mode",
			"force_episode",
		]:
			if candidate.has(optional_key):
				personal_event[optional_key] = candidate[optional_key]

		var admission := RaiderMemoryStoreScript.admit_personal_event(
			memory_store, raider_id, personal_event, now
		)
		var promotion_value: Variant = admission.get("promotion_event", {})

		if promotion_value is Dictionary and not Dictionary(promotion_value).is_empty():
			derived_events.append(
				_normalize_derived_event(campaign, Dictionary(promotion_value), now)
			)

	campaign["memory_store"] = memory_store
	campaign["relationship_store"] = relationship_store
	_process_lore_event(campaign, event)
	_append_recent_event(campaign, event)

	for derived_event in derived_events:
		_append_recent_event(campaign, derived_event)

	return {"event": event, "derived_events": derived_events}


static func normalize_event(raw_event: Dictionary) -> Dictionary:
	var event_type := String(raw_event.get("event_type", raw_event.get("type", ""))).strip_edges()

	if event_type.is_empty():
		return {}

	var participants := _string_array(raw_event.get("participants", []))
	var category := String(
		raw_event.get("memory_category", EVENT_CATEGORIES.get(event_type, "personal_reflection"))
	)
	var reasons := _string_array(raw_event.get("admission_reasons", []))

	if reasons.is_empty() and DEFAULT_ADMISSION_REASONS.has(event_type):
		reasons = _string_array(DEFAULT_ADMISSION_REASONS[event_type])

	return {
		"event_id": String(raw_event.get("event_id", "")),
		"event_type": event_type,
		"source_system": String(raw_event.get("source_system", "campaign")),
		"recorded_unix_time": int(
			raw_event.get("recorded_unix_time", Time.get_unix_time_from_system())
		),
		"participants": participants,
		"scope": _scope_for_count(participants.size()),
		"memory_category": category,
		"subject_key": String(raw_event.get("subject_key", event_type)),
		"significance": clampi(int(raw_event.get("significance", 50)), 0, 100),
		"admission_reasons": reasons,
		"distinctive_participants": _dictionary_array(
			raw_event.get("distinctive_participants", []), 0
		),
		"personal_participants": _string_array(raw_event.get("personal_participants", [])),
		"memory_strength": clampf(float(raw_event.get("memory_strength", 0.45)), 0.05, 1.0),
		"reinforcement_mode": String(raw_event.get("reinforcement_mode", "external")),
		"promotion_reason": String(raw_event.get("promotion_reason", "")),
		"permanent_eligible": bool(raw_event.get("permanent_eligible", false)),
		"authored_significance": bool(raw_event.get("authored_significance", false)),
		"is_milestone": bool(raw_event.get("is_milestone", false)),
		"force_episode": bool(raw_event.get("force_episode", false)),
		"raid_chronicle": bool(raw_event.get("raid_chronicle", false)),
		"structured_data": (
			Dictionary(raw_event.get("structured_data", {})).duplicate(true)
			if raw_event.get("structured_data", {}) is Dictionary
			else {}
		),
		"prose_template_id": String(raw_event.get("prose_template_id", event_type)),
		"prose_parameters": (
			Dictionary(raw_event.get("prose_parameters", {})).duplicate(true)
			if raw_event.get("prose_parameters", {}) is Dictionary
			else {}
		),
		"life_prose_template_id": String(raw_event.get("life_prose_template_id", "")),
	}


static func advance_lifecycle(campaign: Dictionary, now: int) -> void:
	var memory_store: Dictionary = campaign.get("memory_store", create_memory_store())
	RaiderMemoryStoreScript.process_lifecycle(memory_store, now)
	campaign["memory_store"] = memory_store


static func learn_lore_topic(
	campaign: Dictionary,
	raider_id: String,
	topic_id: String,
	knowledge_state: String,
	interpretation: String,
	source_id: String,
	shared_with_raid: bool
) -> Dictionary:
	var store: Dictionary = campaign.get("lore_knowledge_store", create_lore_store())
	var topic := RaiderLoreKnowledgeStoreScript.learn_topic(
		store,
		raider_id,
		topic_id,
		knowledge_state,
		interpretation,
		source_id,
		shared_with_raid
	)
	campaign["lore_knowledge_store"] = store
	return topic


static func get_debug_report(campaign: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {
		"recent_notable_events": Array(campaign.get("notable_event_records", [])).duplicate(true),
		"memories": RaiderMemoryStoreScript.get_debug_report(
			Dictionary(campaign.get("memory_store", {})), now
		),
		"raid_chronicle": Array(campaign.get("raid_chronicle", [])).duplicate(true),
		"relationships": RaiderRelationshipStoreScript.get_debug_report(
			Dictionary(campaign.get("relationship_store", {}))
		),
		"lore_knowledge": RaiderLoreKnowledgeStoreScript.get_debug_report(
			Dictionary(campaign.get("lore_knowledge_store", {}))
		),
	}


static func _personal_candidates(event: Dictionary) -> Array[Dictionary]:
	var participants := _string_array(event.get("participants", []))
	var candidates: Array[Dictionary] = []

	if participants.size() == 1:
		candidates.append(
			{
				"raider_id": participants[0],
				"admission_reasons": _string_array(event.get("admission_reasons", [])),
			}
		)
	elif participants.size() == 2:
		for raider_id in _string_array(event.get("personal_participants", [])):
			if participants.has(raider_id):
				candidates.append(
					{
						"raider_id": raider_id,
						"admission_reasons": _string_array(event.get("admission_reasons", [])),
					}
				)

	for distinctive_value in event.get("distinctive_participants", []):
		if not distinctive_value is Dictionary:
			continue

		var distinctive: Dictionary = Dictionary(distinctive_value).duplicate(true)
		var raider_id := String(distinctive.get("raider_id", ""))

		if not participants.has(raider_id):
			continue

		var replaced := false

		for index in range(candidates.size()):
			if String(candidates[index].get("raider_id", "")) == raider_id:
				candidates[index] = distinctive
				replaced = true
				break

		if not replaced:
			candidates.append(distinctive)

	return candidates


static func _process_lore_event(campaign: Dictionary, event: Dictionary) -> void:
	if String(event.get("event_type", "")) not in ["lore_learned", "lore_taught", "lore_argument"]:
		return

	var data: Dictionary = Dictionary(event.get("structured_data", {}))

	for raider_id in _string_array(event.get("participants", [])):
		learn_lore_topic(
			campaign,
			raider_id,
			String(data.get("topic_id", "")),
			String(data.get("knowledge_state", "partial")),
			String(data.get("interpretation", "")),
			String(data.get("source_id", event.get("event_id", ""))),
			bool(data.get("shared_with_raid", false))
		)


static func _append_recent_event(campaign: Dictionary, event: Dictionary) -> void:
	var records: Array = campaign.get("notable_event_records", [])
	records.append(event.duplicate(true))

	if records.size() > NOTABLE_EVENT_LIMIT:
		records = records.slice(records.size() - NOTABLE_EVENT_LIMIT)

	campaign["notable_event_records"] = records


static func _append_chronicle(campaign: Dictionary, event: Dictionary) -> void:
	var chronicle: Array = campaign.get("raid_chronicle", [])
	chronicle.append(
		{
			"chronicle_id": "chronicle:%s" % String(event.get("event_id", "")),
			"event_id": String(event.get("event_id", "")),
			"event_type": String(event.get("event_type", "")),
			"recorded_unix_time": int(event.get("recorded_unix_time", 0)),
			"participant_count": event.get("participants", []).size(),
			"significance": int(event.get("significance", 0)),
			"subject_key": String(event.get("subject_key", "")),
			"structured_data": Dictionary(event.get("structured_data", {})).duplicate(true),
			"prose_template_id": String(event.get("prose_template_id", "")),
			"prose_parameters": Dictionary(event.get("prose_parameters", {})).duplicate(true),
		}
	)

	if chronicle.size() > RAID_CHRONICLE_LIMIT:
		chronicle = chronicle.slice(chronicle.size() - RAID_CHRONICLE_LIMIT)

	campaign["raid_chronicle"] = chronicle


static func _normalize_derived_event(
	campaign: Dictionary, raw_event: Dictionary, now: int
) -> Dictionary:
	campaign["notable_event_sequence"] = int(campaign.get("notable_event_sequence", 0)) + 1
	var prepared := raw_event.duplicate(true)
	prepared["event_id"] = "event_%08d" % int(campaign["notable_event_sequence"])
	prepared["recorded_unix_time"] = now
	prepared["source_system"] = "camp_v2_event_system"
	return normalize_event(prepared)


static func _record_aggregate_rejection(
	memory_store: Dictionary, event: Dictionary, participant_count: int
) -> void:
	var rejected: Array = memory_store.get("rejected_admissions", [])
	rejected.append(
		{
			"event_id": String(event.get("event_id", "")),
			"event_type": String(event.get("event_type", "")),
			"raider_id": "<group>",
			"reason": (
				"raid_event_stored_once_in_chronicle"
				if participant_count >= 3
				else "pair_context_stored_in_relationship_memory"
			),
			"participant_count": participant_count,
			"recorded_unix_time": int(event.get("recorded_unix_time", 0)),
		}
	)

	if rejected.size() > RaiderMemoryStoreScript.REJECTION_LIMIT:
		rejected = rejected.slice(rejected.size() - RaiderMemoryStoreScript.REJECTION_LIMIT)

	memory_store["rejected_admissions"] = rejected


static func _scope_for_count(participant_count: int) -> String:
	if participant_count == 1:
		return "personal"

	if participant_count == 2:
		return "pair"

	return "raid"


static func _dictionary_array(value: Variant, limit: int) -> Array:
	var result: Array = []

	if value is Array:
		for entry in value:
			if entry is Dictionary:
				result.append(Dictionary(entry).duplicate(true))

	if limit > 0 and result.size() > limit:
		result = result.slice(result.size() - limit)

	return result


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()

			if not text.is_empty() and not result.has(text):
				result.append(text)

	return result
