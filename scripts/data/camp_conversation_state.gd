extends RefCounted
class_name CampConversationState

const SUMMARY_LIMIT := 160
const PRESSURE_SOURCE_LIMIT := 32
const MIN_COOLDOWN := 12.0
const BASELINE_COOLDOWN := 46.0
const MAX_COOLDOWN := 75.0
const PRESSURE_DECAY_PER_SECOND := 0.055

const PRESSURE_BY_EVENT := {
	"raider_recruited": 22.0,
	"raider_added_to_active_roster": 9.0,
	"raider_moved_to_reserve": 9.0,
	"boss_attempt_completed": 12.0,
	"boss_defeated": 24.0,
	"class_advanced": 18.0,
	"memory_promoted": 12.0,
	"relationship_threshold_reached": 16.0,
	"lore_learned": 14.0,
}

const PRESSURE_BY_VISIT := {
	"normal": 0.0,
	"wipe": 20.0,
	"first_victory": 30.0,
	"repeat_victory": 18.0,
	"recruitment": 24.0,
	"roster_change": 12.0,
	"apex_victory": 36.0,
}


static func create_store() -> Dictionary:
	return {
		"camp_time_seconds": 0.0,
		"pressure": 18.0,
		"next_ordinary_conversation_at": 14.0,
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
	store["pressure"] = clampf(float(raw.get("pressure", 18.0)), 0.0, 100.0)
	store["next_ordinary_conversation_at"] = maxf(
		float(raw.get("next_ordinary_conversation_at", 14.0)),
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

	if summaries.size() > SUMMARY_LIMIT:
		summaries = summaries.slice(summaries.size() - SUMMARY_LIMIT)

	store["recent_summaries"] = summaries
	var sources: Array = []

	for value in raw.get("pressure_sources", []):
		if value is Dictionary:
			sources.append(Dictionary(value).duplicate(true))

	if sources.size() > PRESSURE_SOURCE_LIMIT:
		sources = sources.slice(sources.size() - PRESSURE_SOURCE_LIMIT)

	store["pressure_sources"] = sources
	return store


static func advance(store: Dictionary, delta: float, concurrent_conversations: int) -> void:
	if delta <= 0.0:
		return

	store["camp_time_seconds"] = float(store.get("camp_time_seconds", 0.0)) + delta
	var extra_decay := maxf(float(concurrent_conversations - 1), 0.0) * 0.03
	store["pressure"] = clampf(
		float(store.get("pressure", 0.0)) - delta * (PRESSURE_DECAY_PER_SECOND + extra_decay),
		0.0,
		100.0
	)
	_prune_cooldowns(store)


static func apply_event_pressure(store: Dictionary, event: Dictionary) -> void:
	var event_type := String(event.get("event_type", ""))
	var amount := float(PRESSURE_BY_EVENT.get(event_type, 0.0))

	if event_type == "conversation_completed":
		var data: Dictionary = Dictionary(event.get("structured_data", {}))
		amount = -14.0 if String(data.get("delivery", "embedded")) == "focused" else -8.0

	if not is_zero_approx(amount):
		_adjust_pressure(store, amount, event_type)


static func apply_visit_pressure(store: Dictionary, visit_type: String) -> void:
	var amount := float(PRESSURE_BY_VISIT.get(visit_type, 0.0))
	if not is_zero_approx(amount):
		_adjust_pressure(store, amount, "visit:%s" % visit_type)


static func get_next_cooldown(store: Dictionary, variance: float = 0.0) -> float:
	var normalized := clampf(float(store.get("pressure", 0.0)) / 100.0, 0.0, 1.0)
	var result := lerpf(BASELINE_COOLDOWN, MIN_COOLDOWN, normalized) + variance
	return clampf(result, MIN_COOLDOWN, MAX_COOLDOWN)


static func schedule_next(store: Dictionary, cooldown: float) -> void:
	store["next_ordinary_conversation_at"] = float(store.get("camp_time_seconds", 0.0)) + clampf(
		cooldown, MIN_COOLDOWN, MAX_COOLDOWN
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

	if summaries.size() > SUMMARY_LIMIT:
		summaries = summaries.slice(summaries.size() - SUMMARY_LIMIT)

	store["recent_summaries"] = summaries
	store["completed_conversation_count"] = int(
		store.get("completed_conversation_count", 0)
	) + 1
	return summary.duplicate(true)


static func note_schedule_miss(store: Dictionary, reason: String) -> void:
	var now := float(store.get("camp_time_seconds", 0.0))
	if now - float(store.get("last_schedule_miss_at", -999.0)) >= 5.0:
		_adjust_pressure(store, -1.0, "schedule_miss:%s" % reason)
		store["last_schedule_miss_at"] = now
	store["next_ordinary_conversation_at"] = now + 6.0


static func get_debug_report(store: Dictionary) -> Dictionary:
	return {
		"camp_time_seconds": float(store.get("camp_time_seconds", 0.0)),
		"conversation_pressure": float(store.get("pressure", 0.0)),
		"bounded_cooldown_seconds": {
			"minimum": MIN_COOLDOWN,
			"baseline": BASELINE_COOLDOWN,
			"maximum": MAX_COOLDOWN,
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


static func _adjust_pressure(store: Dictionary, amount: float, source: String) -> void:
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
	if sources.size() > PRESSURE_SOURCE_LIMIT:
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
