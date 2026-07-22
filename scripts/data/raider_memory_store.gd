extends RefCounted
class_name RaiderMemoryStore

const CampV2TuningScript := preload("res://scripts/core/camp_v2_tuning.gd")
const TUNING := CampV2TuningScript.MEMORY
const DAY_SECONDS: int = TUNING["day_seconds"]
const NORMAL_REINFORCEMENT_CEILING_DAYS: int = TUNING[
	"normal_reinforcement_ceiling_days"
]
const SELF_REINFORCEMENT_LIMIT: int = TUNING["self_reinforcement_limit"]
const REJECTION_LIMIT: int = TUNING["rejection_limit"]
const LIFE_MEMORY_CAPACITY: int = TUNING["life_memory_capacity"]
const LATENT_MULTIPLIER: int = TUNING["latent_multiplier"]
const CATEGORY_CAPACITIES: Dictionary = TUNING["category_capacities"]
const CATEGORY_ACTIVE_DAYS: Dictionary = TUNING["category_active_days"]
const CATEGORY_LATENT_DAYS: Dictionary = TUNING["category_latent_days"]


static func create_store() -> Dictionary:
	return {
		"raiders": {},
		"rejected_admissions": [],
		"last_lifecycle_unix_time": 0,
	}


static func sanitize_store(source: Variant, valid_raider_ids: Array[String]) -> Dictionary:
	var raw: Dictionary = Dictionary(source).duplicate(true) if source is Dictionary else {}
	var result := create_store()
	var source_raiders: Dictionary = (
		Dictionary(raw.get("raiders", {})) if raw.get("raiders", {}) is Dictionary else {}
	)
	var sanitized_raiders: Dictionary = {}

	for raider_id in valid_raider_ids:
		var raider_value: Variant = source_raiders.get(raider_id, {})

		if raider_value is Dictionary and not Dictionary(raider_value).is_empty():
			sanitized_raiders[raider_id] = _sanitize_raider_memory(Dictionary(raider_value))

	result["raiders"] = sanitized_raiders
	result["rejected_admissions"] = _dictionary_array(
		raw.get("rejected_admissions", []), REJECTION_LIMIT
	)
	result["last_lifecycle_unix_time"] = maxi(
		int(raw.get("last_lifecycle_unix_time", 0)), 0
	)
	return result


static func process_lifecycle(store: Dictionary, now: int) -> void:
	var raiders: Dictionary = store.get("raiders", {})

	for raider_id in raiders.keys():
		var memory: Dictionary = _sanitize_raider_memory(Dictionary(raiders[raider_id]))
		_expire_active_episodes(memory, now)
		_expire_latent_episodes(memory, now)
		_expire_threads(memory, now)
		raiders[raider_id] = memory

	store["raiders"] = raiders
	store["last_lifecycle_unix_time"] = now


static func admit_personal_event(
	store: Dictionary, raider_id: String, event: Dictionary, now: int
) -> Dictionary:
	var admission_reasons := _string_array(event.get("admission_reasons", []))

	if admission_reasons.is_empty():
		_record_rejection(store, event, raider_id, "no_personal_admission_criterion")
		return {"admitted": false, "reason": "no_personal_admission_criterion"}

	var category := _normalize_category(String(event.get("memory_category", "combat")))
	var subject_key := String(event.get("subject_key", event.get("event_type", "event")))
	var raiders: Dictionary = store.get("raiders", {})
	var memory := _ensure_raider_memory(raiders, raider_id)
	var threads: Dictionary = memory.get("threads", {})
	var thread_id := "%s|%s" % [category, subject_key]
	var existing_thread_value: Variant = threads.get(thread_id, {})
	var thread: Dictionary = (
		Dictionary(existing_thread_value).duplicate(true)
		if existing_thread_value is Dictionary
		else {}
	)
	var reinforcement_mode := String(event.get("reinforcement_mode", "external"))
	var had_thread := not thread.is_empty()

	if thread.is_empty():
		if reinforcement_mode == "self":
			_record_rejection(
				store, event, raider_id, "self_reinforcement_requires_existing_thread"
			)
			return {"admitted": false, "reason": "self_reinforcement_requires_existing_thread"}

		thread = _create_thread(thread_id, category, subject_key, event, now)

	if (
		reinforcement_mode == "self"
		and int(thread.get("self_reinforcement_count", 0)) >= SELF_REINFORCEMENT_LIMIT
	):
		_record_rejection(store, event, raider_id, "self_reinforcement_limit_reached")
		return {"admitted": false, "reason": "self_reinforcement_limit_reached"}

	var reactivated := String(thread.get("state", "active")) == "latent"
	_reinforce_thread(thread, event, now, reinforcement_mode)
	threads[thread_id] = thread
	memory["threads"] = threads

	var duplicate_suppressed := had_thread and _should_suppress_duplicate_episode(
		memory, thread_id, event, now
	)
	var episode_id := ""

	if not duplicate_suppressed:
		var episode := _create_episode(raider_id, thread_id, category, subject_key, event, now)
		episode_id = String(episode.get("episode_id", ""))
		var active: Dictionary = memory.get("active_episodes", {})
		var category_episodes: Array = active.get(category, [])
		category_episodes.append(episode)
		active[category] = category_episodes
		memory["active_episodes"] = active
		_enforce_active_capacity(memory, category, now)

	var promotion := _promotion_reason(thread, event)
	var promotion_event: Dictionary = {}

	if not promotion.is_empty():
		promotion_event = _promote_thread(memory, raider_id, thread_id, event, promotion, now)

	raiders[raider_id] = memory
	store["raiders"] = raiders
	return {
		"admitted": true,
		"reason": (
			"latent_thread_reactivated"
			if reactivated
			else (
				"thread_reinforced_without_duplicate_episode"
				if duplicate_suppressed
				else "episode_created"
			)
		),
		"episode_id": episode_id,
		"thread_id": thread_id,
		"promotion_event": promotion_event,
	}


static func get_raider_memory(store: Dictionary, raider_id: String) -> Dictionary:
	var raiders: Dictionary = store.get("raiders", {})
	var value: Variant = raiders.get(raider_id, {})
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


static func select_relevant_thread(
	store: Dictionary, raider_id: String, criteria: Dictionary, now: int
) -> Dictionary:
	var memory := get_raider_memory(store, raider_id)
	var category := String(criteria.get("category", ""))
	var subject_prefix := String(criteria.get("subject_prefix", ""))
	var allowed_states := _string_array(
		criteria.get("states", ["active", "latent", "permanent"])
	)
	var state_weights: Dictionary = Dictionary(
		TUNING.get("selection_state_weights", {})
	)
	var best: Dictionary = {}
	var best_score := -1.0
	for value in Dictionary(memory.get("threads", {})).values():
		if not value is Dictionary:
			continue
		var thread: Dictionary = value
		var state := String(thread.get("state", "active"))
		if not allowed_states.is_empty() and state not in allowed_states:
			continue
		if not category.is_empty() and String(thread.get("category", "")) != category:
			continue
		if (
			not subject_prefix.is_empty()
			and not String(thread.get("subject_key", "")).begins_with(subject_prefix)
		):
			continue
		var age_days := maxf(
			float(now - int(thread.get("last_reinforced_at", now))) / float(DAY_SECONDS),
			0.0
		)
		var recency_window := maxf(
			float(TUNING.get("selection_recency_window_days", 90.0)), 1.0
		)
		var score := float(state_weights.get(state, 0.25))
		score += float(thread.get("strength", 0.0)) * float(
			TUNING.get("selection_strength_weight", 1.4)
		)
		score += minf(
			float(thread.get("reinforcement_count", 0))
			* float(TUNING.get("selection_reinforcement_weight", 0.12)),
			0.8
		)
		score += maxf(1.0 - age_days / recency_window, 0.0)
		if score > best_score:
			best = thread.duplicate(true)
			best["selection_score"] = score
			best_score = score
	return best


static func get_debug_report(store: Dictionary, now: int) -> Dictionary:
	var raider_reports: Dictionary = {}
	var raiders: Dictionary = store.get("raiders", {})

	for raider_id in raiders.keys():
		var memory: Dictionary = Dictionary(raiders[raider_id])
		var thread_report: Array[Dictionary] = []

		for thread_value in memory.get("threads", {}).values():
			if not thread_value is Dictionary:
				continue

			var thread: Dictionary = thread_value
			thread_report.append(
				{
					"thread_id": String(thread.get("thread_id", "")),
					"category": String(thread.get("category", "")),
					"state": String(thread.get("state", "")),
					"reinforcement_count": int(thread.get("reinforcement_count", 0)),
					"external_reinforcement_count": int(
						thread.get("external_reinforcement_count", 0)
					),
					"social_reinforcement_count": int(
						thread.get("social_reinforcement_count", 0)
					),
					"self_reinforcement_count": int(
						thread.get("self_reinforcement_count", 0)
					),
					"expires_in_days": _days_until(int(thread.get("expires_at", 0)), now),
					"latent_expires_in_days": _days_until(
						int(thread.get("latent_expires_at", 0)), now
					),
					"normal_ceiling_in_days": _days_until(
						int(thread.get("normal_ceiling_at", 0)), now
					),
					"promotion_reason": String(thread.get("promotion_reason", "")),
				}
			)

		raider_reports[raider_id] = {
			"active_episodes": Dictionary(memory.get("active_episodes", {})).duplicate(true),
			"latent_episodes": Dictionary(memory.get("latent_episodes", {})).duplicate(true),
			"threads": thread_report,
			"life_memories": Array(memory.get("life_memories", [])).duplicate(true),
			"archived_life_memory_summaries": Array(
				memory.get("archived_life_memory_summaries", [])
			).duplicate(true),
		}

	return {
		"category_active_capacities": CATEGORY_CAPACITIES.duplicate(true),
		"normal_reinforcement_ceiling_days": NORMAL_REINFORCEMENT_CEILING_DAYS,
		"self_reinforcement_limit": SELF_REINFORCEMENT_LIMIT,
		"raiders": raider_reports,
		"rejected_personal_memories": Array(store.get("rejected_admissions", [])).duplicate(true),
	}


static func _create_thread(
	thread_id: String, category: String, subject_key: String, _event: Dictionary, now: int
) -> Dictionary:
	var active_duration := _active_duration_seconds(category)
	return {
		"thread_id": thread_id,
		"category": category,
		"subject_key": subject_key,
		"state": "active",
		"created_at": now,
		"last_reinforced_at": now,
		"expires_at": now,
		"latent_expires_at": now + active_duration + _latent_duration_seconds(category),
		"normal_ceiling_at": now + NORMAL_REINFORCEMENT_CEILING_DAYS * DAY_SECONDS,
		"strength": 0.0,
		"reinforcement_count": 0,
		"external_reinforcement_count": 0,
		"social_reinforcement_count": 0,
		"self_reinforcement_count": 0,
		"source_event_ids": [],
		"promotion_reason": "",
	}


static func _reinforce_thread(
	thread: Dictionary, event: Dictionary, now: int, mode: String
) -> void:
	var reinforcement_count := int(thread.get("reinforcement_count", 0))
	var active_duration := _active_duration_seconds(String(thread.get("category", "combat")))
	var diminishing_extension := int(
		float(active_duration)
		/ (
			1.0
			+ float(reinforcement_count)
			* float(TUNING.get("diminishing_extension_rate", 0.85))
		)
	)
	var ceiling := int(thread.get("normal_ceiling_at", now))

	if mode != "self":
		ceiling = max(
			ceiling, now + NORMAL_REINFORCEMENT_CEILING_DAYS * DAY_SECONDS
		)
		thread["normal_ceiling_at"] = ceiling

	thread["state"] = "active"
	thread["last_reinforced_at"] = now
	thread["reinforcement_count"] = reinforcement_count + 1
	thread["expires_at"] = mini(
		maxi(int(thread.get("expires_at", now)), now) + diminishing_extension,
		ceiling
	)
	thread["latent_expires_at"] = int(thread["expires_at"]) + _latent_duration_seconds(
		String(thread.get("category", "combat"))
	)
	thread["strength"] = clampf(
		float(thread.get("strength", 0.25))
		+ float(event.get("memory_strength", 0.35)) / (1.0 + reinforcement_count * 0.5),
		0.0,
		1.0
	)

	match mode:
		"self":
			thread["self_reinforcement_count"] = int(
				thread.get("self_reinforcement_count", 0)
			) + 1
		"social":
			thread["social_reinforcement_count"] = int(
				thread.get("social_reinforcement_count", 0)
			) + 1
		_:
			thread["external_reinforcement_count"] = int(
				thread.get("external_reinforcement_count", 0)
			) + 1

	var source_ids := _string_array(thread.get("source_event_ids", []))
	var event_id := String(event.get("event_id", ""))

	if not event_id.is_empty() and not source_ids.has(event_id):
		source_ids.append(event_id)

	if source_ids.size() > 12:
		source_ids = source_ids.slice(source_ids.size() - 12)

	thread["source_event_ids"] = source_ids


static func _create_episode(
	raider_id: String,
	thread_id: String,
	category: String,
	subject_key: String,
	event: Dictionary,
	now: int
) -> Dictionary:
	return {
		"episode_id": "%s:%s" % [raider_id, String(event.get("event_id", "event"))],
		"event_id": String(event.get("event_id", "")),
		"event_type": String(event.get("event_type", "")),
		"thread_id": thread_id,
		"category": category,
		"subject_key": subject_key,
		"state": "active",
		"occurred_at": now,
		"expires_at": now + _active_duration_seconds(category),
		"strength": clampf(float(event.get("memory_strength", 0.45)), 0.05, 1.0),
		"admission_reasons": _string_array(event.get("admission_reasons", [])),
		"prose_template_id": String(event.get("prose_template_id", "")),
		"prose_parameters": Dictionary(event.get("prose_parameters", {})).duplicate(true),
		"structured_data": Dictionary(event.get("structured_data", {})).duplicate(true),
	}


static func _should_suppress_duplicate_episode(
	memory: Dictionary, thread_id: String, event: Dictionary, now: int
) -> bool:
	if bool(event.get("force_episode", false)):
		return false

	if (
		String(event.get("promotion_reason", "")) != ""
		or bool(event.get("is_milestone", false))
		or bool(event.get("structured_data", {}).get("resolves_thread", false))
	):
		return false

	for episode_value in memory.get("active_episodes", {}).get(
		_normalize_category(String(event.get("memory_category", "combat"))), []
	):
		if not episode_value is Dictionary:
			continue

		var episode: Dictionary = episode_value

		if (
			String(episode.get("thread_id", "")) == thread_id
			and String(episode.get("event_type", "")) == String(event.get("event_type", ""))
			and now - int(episode.get("occurred_at", 0))
			<= int(TUNING.get("duplicate_episode_window_days", 10)) * DAY_SECONDS
		):
			return true

	return false


static func _promotion_reason(thread: Dictionary, event: Dictionary) -> String:
	var explicit_reason := String(event.get("promotion_reason", ""))

	if bool(event.get("permanent_eligible", false)) and not explicit_reason.is_empty():
		return explicit_reason

	if (
		bool(event.get("structured_data", {}).get("resolves_thread", false))
		and int(thread.get("external_reinforcement_count", 0))
		>= int(TUNING.get("resolution_external_reinforcements", 4))
	):
		return "repeated_pattern_resolved"

	if (
		int(thread.get("self_reinforcement_count", 0)) >= SELF_REINFORCEMENT_LIMIT
		and bool(event.get("authored_significance", false))
		and float(thread.get("strength", 0.0))
		>= float(TUNING.get("identity_promotion_strength", 0.88))
	):
		return "repeated_reflection_became_identity"

	return ""


static func _promote_thread(
	memory: Dictionary,
	raider_id: String,
	thread_id: String,
	event: Dictionary,
	reason: String,
	now: int
) -> Dictionary:
	var threads: Dictionary = memory.get("threads", {})
	var thread: Dictionary = Dictionary(threads.get(thread_id, {}))
	thread["state"] = "permanent"
	thread["promotion_reason"] = reason
	thread["promoted_at"] = now
	threads[thread_id] = thread
	memory["threads"] = threads
	var source_episode_ids: Array[String] = []

	for store_name in ["active_episodes", "latent_episodes"]:
		var episode_store: Dictionary = memory.get(store_name, {})

		for category in episode_store.keys():
			var retained: Array = []

			for episode_value in episode_store[category]:
				if not episode_value is Dictionary:
					continue

				var episode: Dictionary = episode_value

				if String(episode.get("thread_id", "")) == thread_id:
					source_episode_ids.append(String(episode.get("episode_id", "")))
				else:
					retained.append(episode)

			episode_store[category] = retained

		memory[store_name] = episode_store

	var life_memories: Array = memory.get("life_memories", [])
	var existing_index := -1

	for index in range(life_memories.size()):
		if (
			life_memories[index] is Dictionary
			and String(life_memories[index].get("thread_id", "")) == thread_id
		):
			existing_index = index
			break

	var life_memory := {
		"life_memory_id": "%s:life:%s" % [raider_id, thread_id],
		"thread_id": thread_id,
		"category": "permanent_life_memory",
		"source_category": String(thread.get("category", "")),
		"subject_key": String(thread.get("subject_key", "")),
		"promotion_reason": reason,
		"promoted_at": now,
		"source_episode_ids": source_episode_ids,
		"source_event_ids": _string_array(thread.get("source_event_ids", [])),
		"prose_template_id": String(event.get("life_prose_template_id", "life_memory_arc")),
		"prose_parameters": Dictionary(event.get("prose_parameters", {})).duplicate(true),
		"structured_arc": Dictionary(event.get("structured_data", {})).duplicate(true),
	}

	if existing_index >= 0:
		var existing: Dictionary = Dictionary(life_memories[existing_index])
		life_memory["source_episode_ids"] = _merge_strings(
			existing.get("source_episode_ids", []), source_episode_ids
		)
		life_memory["source_event_ids"] = _merge_strings(
			existing.get("source_event_ids", []), life_memory["source_event_ids"]
		)
		life_memories[existing_index] = life_memory
	else:
		life_memories.append(life_memory)

	memory["life_memories"] = life_memories
	_archive_life_memory_overflow(memory)
	return {
		"event_type": "memory_promoted",
		"participants": [raider_id],
		"memory_category": "personal_reflection",
		"subject_key": thread_id,
		"significance": 85,
		"structured_data": {
			"life_memory_id": String(life_memory.get("life_memory_id", "")),
			"promotion_reason": reason,
			"source_episode_count": source_episode_ids.size(),
		},
		"prose_template_id": "memory_promoted",
		"prose_parameters": {"promotion_reason": reason},
	}


static func _enforce_active_capacity(memory: Dictionary, category: String, now: int) -> void:
	var active: Dictionary = memory.get("active_episodes", {})
	var episodes: Array = active.get(category, [])
	var capacity := int(CATEGORY_CAPACITIES.get(category, 3))

	while episodes.size() > capacity:
		var weakest_index := _weakest_episode_index(episodes)
		var compressed := _compress_episode(Dictionary(episodes[weakest_index]), category, now)
		episodes.remove_at(weakest_index)
		var latent: Dictionary = memory.get("latent_episodes", {})
		var latent_category: Array = latent.get(category, [])
		latent_category.append(compressed)

		while latent_category.size() > capacity * LATENT_MULTIPLIER:
			latent_category.remove_at(_weakest_episode_index(latent_category))

		latent[category] = latent_category
		memory["latent_episodes"] = latent

	active[category] = episodes
	memory["active_episodes"] = active


static func _expire_active_episodes(memory: Dictionary, now: int) -> void:
	var active: Dictionary = memory.get("active_episodes", {})
	var latent: Dictionary = memory.get("latent_episodes", {})

	for category in CATEGORY_CAPACITIES.keys():
		var retained: Array = []
		var latent_category: Array = latent.get(category, [])

		for episode_value in active.get(category, []):
			if not episode_value is Dictionary:
				continue

			var episode: Dictionary = episode_value

			if int(episode.get("expires_at", now + 1)) <= now:
				var compressed := _compress_episode(episode, String(category), now)
				compressed["latent_expires_at"] = (
					int(episode.get("expires_at", now))
					+ _latent_duration_seconds(String(category))
				)

				if int(compressed["latent_expires_at"]) > now:
					latent_category.append(compressed)
			else:
				retained.append(episode)

		active[category] = retained
		latent[category] = latent_category

	memory["active_episodes"] = active
	memory["latent_episodes"] = latent


static func _expire_latent_episodes(memory: Dictionary, now: int) -> void:
	var latent: Dictionary = memory.get("latent_episodes", {})

	for category in CATEGORY_CAPACITIES.keys():
		var retained: Array = []

		for episode_value in latent.get(category, []):
			if (
				episode_value is Dictionary
				and int(episode_value.get("latent_expires_at", 0)) > now
			):
				retained.append(episode_value)

		latent[category] = retained

	memory["latent_episodes"] = latent


static func _expire_threads(memory: Dictionary, now: int) -> void:
	var threads: Dictionary = memory.get("threads", {})

	for thread_id in threads.keys():
		var thread_value: Variant = threads[thread_id]

		if not thread_value is Dictionary:
			threads.erase(thread_id)
			continue

		var thread: Dictionary = thread_value
		var state := String(thread.get("state", "active"))

		if state == "permanent":
			continue

		if state == "active" and int(thread.get("expires_at", 0)) <= now:
			if int(thread.get("latent_expires_at", 0)) <= now:
				threads.erase(thread_id)
			else:
				thread["state"] = "latent"
				threads[thread_id] = thread
		elif state == "latent" and int(thread.get("latent_expires_at", 0)) <= now:
			threads.erase(thread_id)

	memory["threads"] = threads


static func _compress_episode(episode: Dictionary, category: String, now: int) -> Dictionary:
	return {
		"episode_id": String(episode.get("episode_id", "")),
		"event_id": String(episode.get("event_id", "")),
		"event_type": String(episode.get("event_type", "")),
		"thread_id": String(episode.get("thread_id", "")),
		"category": category,
		"subject_key": String(episode.get("subject_key", "")),
		"state": "latent",
		"occurred_at": int(episode.get("occurred_at", now)),
		"compressed_at": now,
		"latent_expires_at": now + _latent_duration_seconds(category),
		"strength": clampf(float(episode.get("strength", 0.25)) * 0.75, 0.05, 1.0),
		"prose_template_id": String(episode.get("prose_template_id", "")),
		"prose_parameters": Dictionary(episode.get("prose_parameters", {})).duplicate(true),
	}


static func _archive_life_memory_overflow(memory: Dictionary) -> void:
	var life_memories: Array = memory.get("life_memories", [])
	var archive: Array = memory.get("archived_life_memory_summaries", [])

	while life_memories.size() > LIFE_MEMORY_CAPACITY:
		var oldest: Dictionary = Dictionary(life_memories.pop_front())
		archive.append(
			{
				"life_memory_id": String(oldest.get("life_memory_id", "")),
				"subject_key": String(oldest.get("subject_key", "")),
				"promotion_reason": String(oldest.get("promotion_reason", "")),
				"promoted_at": int(oldest.get("promoted_at", 0)),
				"source_event_count": oldest.get("source_event_ids", []).size(),
			}
		)

	memory["life_memories"] = life_memories
	memory["archived_life_memory_summaries"] = archive


static func _record_rejection(
	store: Dictionary, event: Dictionary, raider_id: String, reason: String
) -> void:
	var rejected: Array = store.get("rejected_admissions", [])
	rejected.append(
		{
			"event_id": String(event.get("event_id", "")),
			"event_type": String(event.get("event_type", "")),
			"raider_id": raider_id,
			"reason": reason,
			"recorded_unix_time": int(event.get("recorded_unix_time", 0)),
		}
	)

	if rejected.size() > REJECTION_LIMIT:
		rejected = rejected.slice(rejected.size() - REJECTION_LIMIT)

	store["rejected_admissions"] = rejected


static func _ensure_raider_memory(raiders: Dictionary, raider_id: String) -> Dictionary:
	var value: Variant = raiders.get(raider_id, {})

	if value is Dictionary and not Dictionary(value).is_empty():
		return _sanitize_raider_memory(Dictionary(value))

	return _empty_raider_memory()


static func _empty_raider_memory() -> Dictionary:
	var active: Dictionary = {}
	var latent: Dictionary = {}

	for category in CATEGORY_CAPACITIES.keys():
		active[category] = []
		latent[category] = []

	return {
		"active_episodes": active,
		"latent_episodes": latent,
		"threads": {},
		"life_memories": [],
		"archived_life_memory_summaries": [],
	}


static func _sanitize_raider_memory(source: Dictionary) -> Dictionary:
	var result := _empty_raider_memory()
	var source_active: Dictionary = (
		Dictionary(source.get("active_episodes", {}))
		if source.get("active_episodes", {}) is Dictionary
		else {}
	)
	var source_latent: Dictionary = (
		Dictionary(source.get("latent_episodes", {}))
		if source.get("latent_episodes", {}) is Dictionary
		else {}
	)

	for category in CATEGORY_CAPACITIES.keys():
		result["active_episodes"][category] = _dictionary_array(
			source_active.get(category, []), int(CATEGORY_CAPACITIES[category])
		)
		result["latent_episodes"][category] = _dictionary_array(
			source_latent.get(category, []), int(CATEGORY_CAPACITIES[category]) * LATENT_MULTIPLIER
		)

	var threads: Dictionary = {}
	var source_threads: Dictionary = (
		Dictionary(source.get("threads", {})) if source.get("threads", {}) is Dictionary else {}
	)

	for thread_id in source_threads.keys():
		if source_threads[thread_id] is Dictionary:
			threads[String(thread_id)] = Dictionary(source_threads[thread_id]).duplicate(true)

	result["threads"] = threads
	result["life_memories"] = _dictionary_array(
		source.get("life_memories", []), LIFE_MEMORY_CAPACITY
	)
	result["archived_life_memory_summaries"] = _dictionary_array(
		source.get("archived_life_memory_summaries", []), 0
	)
	return result


static func _weakest_episode_index(episodes: Array) -> int:
	var weakest_index := 0
	var weakest_strength := INF
	var oldest_time := 9223372036854775807

	for index in range(episodes.size()):
		if not episodes[index] is Dictionary:
			return index

		var episode: Dictionary = episodes[index]
		var strength := float(episode.get("strength", 0.0))
		var occurred_at := int(episode.get("occurred_at", 0))

		if strength < weakest_strength or (
			is_equal_approx(strength, weakest_strength) and occurred_at < oldest_time
		):
			weakest_index = index
			weakest_strength = strength
			oldest_time = occurred_at

	return weakest_index


static func _normalize_category(category: String) -> String:
	return category if CATEGORY_CAPACITIES.has(category) else "personal_reflection"


static func _active_duration_seconds(category: String) -> int:
	return int(CATEGORY_ACTIVE_DAYS.get(category, 35)) * DAY_SECONDS


static func _latent_duration_seconds(category: String) -> int:
	return int(CATEGORY_LATENT_DAYS.get(category, 100)) * DAY_SECONDS


static func _days_until(timestamp: int, now: int) -> float:
	if timestamp <= 0:
		return -1.0

	return snappedf(float(timestamp - now) / float(DAY_SECONDS), 0.1)


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


static func _merge_strings(first: Variant, second: Variant) -> Array[String]:
	var result := _string_array(first)

	for value in _string_array(second):
		if not result.has(value):
			result.append(value)

	return result
