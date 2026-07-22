extends RefCounted
class_name CampConversationState

const CampV2TuningScript := preload("res://scripts/core/camp_v2_tuning.gd")
const TUNING := CampV2TuningScript.CONVERSATIONS


static func create_store() -> Dictionary:
	return {
		"camp_time_seconds": 0.0,
		"pressure": float(TUNING.get("initial_pressure", 18.0)),
		"next_ordinary_conversation_at": float(
			TUNING.get("first_conversation_delay_seconds", 14.0)
		),
		"cooldowns": {},
		"recent_summaries": [],
		"summary_sequence": 0,
		"completed_conversation_count": 0,
		"pressure_sources": [],
		"last_schedule_miss_at": -999.0,
	}


static func sanitize_store(source: Variant, valid_raider_ids: Array[String]) -> Dictionary:
	var store := create_store()
	var raw: Dictionary = Dictionary(source).duplicate(true) if source is Dictionary else {}
	store["camp_time_seconds"] = maxf(float(raw.get("camp_time_seconds", 0.0)), 0.0)
	store["pressure"] = clampf(
		float(raw.get("pressure", TUNING.get("initial_pressure", 18.0))), 0.0, 100.0
	)
	store["next_ordinary_conversation_at"] = maxf(
		float(
			raw.get(
				"next_ordinary_conversation_at",
				TUNING.get("first_conversation_delay_seconds", 14.0)
			)
		),
		float(store["camp_time_seconds"])
	)
	store["summary_sequence"] = maxi(int(raw.get("summary_sequence", 0)), 0)
	store["completed_conversation_count"] = maxi(
		int(raw.get("completed_conversation_count", 0)), 0
	)
	store["last_schedule_miss_at"] = float(raw.get("last_schedule_miss_at", -999.0))

	var cooldowns: Dictionary = {}
	var raw_cooldowns: Dictionary = Dictionary(raw.get("cooldowns", {})) if raw.get("cooldowns", {}) is Dictionary else {}

	for key in raw_cooldowns.keys():
		var expires_at := float(raw_cooldowns[key])
		if expires_at > float(store["camp_time_seconds"]):
			cooldowns[String(key)] = expires_at

	store["cooldowns"] = cooldowns
	var summaries: Array = []

	for value in raw.get("recent_summaries", []):
		if not value is Dictionary:
			continue
		var summary := Dictionary(value).duplicate(true)
		var participants: Array[String] = []
		for participant_id in _string_array(summary.get("participant_ids", [])):
			if valid_raider_ids.has(participant_id):
				participants.append(participant_id)
		if participants.size() < 2:
			continue
		summary["participant_ids"] = participants
		summaries.append(summary)

	var summary_limit := int(TUNING.get("summary_limit", 160))
	if summaries.size() > summary_limit:
		summaries = summaries.slice(summaries.size() - summary_limit)

	store["recent_summaries"] = summaries
	var sources: Array = []

	for value in raw.get("pressure_sources", []):
		if value is Dictionary:
			sources.append(Dictionary(value).duplicate(true))

	var pressure_source_limit := int(TUNING.get("pressure_source_limit", 40))
	if sources.size() > pressure_source_limit:
		sources = sources.slice(sources.size() - pressure_source_limit)

	store["pressure_sources"] = sources
	return store


static func advance(store: Dictionary, delta: float, concurrent_conversations: int) -> void:
	if delta <= 0.0:
		return

	store["camp_time_seconds"] = float(store.get("camp_time_seconds", 0.0)) + delta
	var extra_decay := maxf(float(concurrent_conversations - 1), 0.0) * 0.03
	store["pressure"] = clampf(
		float(store.get("pressure", 0.0))
		- delta * (float(TUNING.get("pressure_decay_per_second", 0.065)) + extra_decay),
		0.0,
		100.0
	)
	_prune_cooldowns(store)


static func apply_event_pressure(store: Dictionary, event: Dictionary) -> void:
	var event_type := String(event.get("event_type", ""))
	var amount := float(Dictionary(TUNING.get("pressure_by_event", {})).get(event_type, 0.0))

	if event_type == "conversation_completed":
		var data: Dictionary = Dictionary(event.get("structured_data", {}))
		amount = (
			-float(TUNING.get("focused_completion_pressure_reduction", 13.0))
			if String(data.get("delivery", "embedded")) == "focused"
			else -float(TUNING.get("embedded_completion_pressure_reduction", 7.0))
		)

	if not is_zero_approx(amount):
		adjust_pressure(store, amount, event_type)


static func apply_visit_pressure(store: Dictionary, visit_type: String) -> void:
	var amount := float(Dictionary(TUNING.get("pressure_by_visit", {})).get(visit_type, 0.0))
	if not is_zero_approx(amount):
		adjust_pressure(store, amount, "visit:%s" % visit_type)


static func get_next_cooldown(store: Dictionary, variance: float = 0.0) -> float:
	var normalized := clampf(float(store.get("pressure", 0.0)) / 100.0, 0.0, 1.0)
	var minimum := float(TUNING.get("minimum_cooldown_seconds", 14.0))
	var baseline := float(TUNING.get("baseline_cooldown_seconds", 50.0))
	var maximum := float(TUNING.get("maximum_cooldown_seconds", 80.0))
	var result := lerpf(baseline, minimum, normalized) + variance
	return clampf(result, minimum, maximum)


static func schedule_next(store: Dictionary, cooldown: float) -> void:
	var minimum := float(TUNING.get("minimum_cooldown_seconds", 14.0))
	var maximum := float(TUNING.get("maximum_cooldown_seconds", 80.0))
	store["next_ordinary_conversation_at"] = float(store.get("camp_time_seconds", 0.0)) + clampf(
		cooldown, minimum, maximum
	)


static func is_due(store: Dictionary) -> bool:
	return float(store.get("camp_time_seconds", 0.0)) >= float(
		store.get("next_ordinary_conversation_at", 0.0)
	)


static func set_cooldowns(store: Dictionary, cooldown_durations: Dictionary) -> void:
	var cooldowns: Dictionary = store.get("cooldowns", {})
	var now := float(store.get("camp_time_seconds", 0.0))

	for key in cooldown_durations.keys():
		var duration := maxf(float(cooldown_durations[key]), 0.0)
		if duration > 0.0:
			cooldowns[String(key)] = maxf(float(cooldowns.get(key, 0.0)), now + duration)

	store["cooldowns"] = cooldowns


static func cooldown_remaining(store: Dictionary, key: String) -> float:
	return maxf(
		float(store.get("cooldowns", {}).get(key, 0.0))
		- float(store.get("camp_time_seconds", 0.0)),
		0.0
	)


static func get_active_cooldowns(store: Dictionary) -> Dictionary:
	_prune_cooldowns(store)
	var result: Dictionary = {}

	for key in store.get("cooldowns", {}).keys():
		result[String(key)] = cooldown_remaining(store, String(key))

	return result


static func add_summary(store: Dictionary, source: Dictionary) -> Dictionary:
	store["summary_sequence"] = int(store.get("summary_sequence", 0)) + 1
	var summary := source.duplicate(true)
	summary["summary_id"] = "conversation_summary_%06d" % int(store["summary_sequence"])
	summary.erase("beats")
	summary.erase("transcript")
	var summaries: Array = store.get("recent_summaries", [])
	summaries.append(summary)

	var summary_limit := int(TUNING.get("summary_limit", 160))
	if summaries.size() > summary_limit:
		summaries = summaries.slice(summaries.size() - summary_limit)

	store["recent_summaries"] = summaries
	store["completed_conversation_count"] = int(
		store.get("completed_conversation_count", 0)
	) + 1
	return summary.duplicate(true)


static func note_schedule_miss(store: Dictionary, reason: String) -> void:
	var now := float(store.get("camp_time_seconds", 0.0))
	if now - float(store.get("last_schedule_miss_at", -999.0)) >= 5.0:
		adjust_pressure(
			store,
			-float(TUNING.get("schedule_miss_pressure_reduction", 0.5)),
			"schedule_miss:%s" % reason
		)
		store["last_schedule_miss_at"] = now
	store["next_ordinary_conversation_at"] = now + float(
		TUNING.get("schedule_miss_retry_seconds", 7.0)
	)


static func get_debug_report(store: Dictionary) -> Dictionary:
	return {
		"camp_time_seconds": float(store.get("camp_time_seconds", 0.0)),
		"conversation_pressure": float(store.get("pressure", 0.0)),
		"bounded_cooldown_seconds": {
			"minimum": float(TUNING.get("minimum_cooldown_seconds", 14.0)),
			"baseline": float(TUNING.get("baseline_cooldown_seconds", 50.0)),
			"maximum": float(TUNING.get("maximum_cooldown_seconds", 80.0)),
			"next_computed": get_next_cooldown(store),
		},
		"next_ordinary_conversation_in": maxf(
			float(store.get("next_ordinary_conversation_at", 0.0))
			- float(store.get("camp_time_seconds", 0.0)),
			0.0
		),
		"active_cooldowns": get_active_cooldowns(store),
		"completed_conversation_count": int(store.get("completed_conversation_count", 0)),
		"recent_structured_summaries": Array(store.get("recent_summaries", [])).duplicate(true),
		"recent_pressure_sources": Array(store.get("pressure_sources", [])).duplicate(true),
	}


static func adjust_pressure(store: Dictionary, amount: float, source: String) -> void:
	store["pressure"] = clampf(float(store.get("pressure", 0.0)) + amount, 0.0, 100.0)
	var sources: Array = store.get("pressure_sources", [])
	sources.append(
		{
			"source": source,
			"amount": amount,
			"camp_time_seconds": float(store.get("camp_time_seconds", 0.0)),
			"resulting_pressure": float(store["pressure"]),
		}
	)
	if sources.size() > int(TUNING.get("pressure_source_limit", 40)):
		sources.remove_at(0)
	store["pressure_sources"] = sources


static func _prune_cooldowns(store: Dictionary) -> void:
	var cooldowns: Dictionary = store.get("cooldowns", {})
	var now := float(store.get("camp_time_seconds", 0.0))

	for key in cooldowns.keys():
		if float(cooldowns[key]) <= now:
			cooldowns.erase(key)

	store["cooldowns"] = cooldowns


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result
