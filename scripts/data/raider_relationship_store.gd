extends RefCounted
class_name RaiderRelationshipStore

const CampV2TuningScript := preload("res://scripts/core/camp_v2_tuning.gd")
const TUNING := CampV2TuningScript.RELATIONSHIPS
const DIMENSIONS := ["affinity", "trust", "respect", "tension"]
const VALUE_MIN: int = TUNING["value_minimum"]
const VALUE_MAX: int = TUNING["value_maximum"]
const PAIR_MEMORY_LIMIT: int = TUNING["pair_memory_limit"]
const PERMANENT_PAIR_MEMORY_LIMIT: int = TUNING["permanent_pair_memory_limit"]
const RECENT_CONVERSATION_LIMIT: int = TUNING["recent_conversation_limit"]
const THRESHOLDS: Array = TUNING["thresholds"]


static func create_store() -> Dictionary:
	return {"pairs": {}}


static func sanitize_store(source: Variant, valid_raider_ids: Array[String]) -> Dictionary:
	var raw: Dictionary = Dictionary(source).duplicate(true) if source is Dictionary else {}
	var source_pairs: Dictionary = (
		Dictionary(raw.get("pairs", {})) if raw.get("pairs", {}) is Dictionary else {}
	)
	var pairs: Dictionary = {}

	for pair_value in source_pairs.values():
		if not pair_value is Dictionary:
			continue

		var source_pair: Dictionary = pair_value
		var first_id := String(source_pair.get("raider_a_id", ""))
		var second_id := String(source_pair.get("raider_b_id", ""))

		if (
			first_id.is_empty()
			or second_id.is_empty()
			or first_id == second_id
			or not valid_raider_ids.has(first_id)
			or not valid_raider_ids.has(second_id)
		):
			continue

		var key := pair_key(first_id, second_id)
		pairs[key] = _sanitize_pair(source_pair, first_id, second_id)

	return {"pairs": pairs}


static func record_pair_event(store: Dictionary, event: Dictionary) -> Array[Dictionary]:
	var participants := _string_array(event.get("participants", []))

	if participants.size() != 2:
		return []

	var first_id := participants[0]
	var second_id := participants[1]
	var pairs: Dictionary = store.get("pairs", {})
	var key := pair_key(first_id, second_id)
	var pair_value: Variant = pairs.get(key, {})
	var pair := (
		_sanitize_pair(Dictionary(pair_value), first_id, second_id)
		if pair_value is Dictionary and not Dictionary(pair_value).is_empty()
		else _create_pair(first_id, second_id)
	)
	_record_shared_context(pair, event)
	var derived_events := _apply_qualifying_changes(pair, event)
	pairs[key] = pair
	store["pairs"] = pairs
	return derived_events


static func get_pair(store: Dictionary, first_id: String, second_id: String) -> Dictionary:
	if first_id.is_empty() or second_id.is_empty() or first_id == second_id:
		return {}

	var value: Variant = store.get("pairs", {}).get(pair_key(first_id, second_id), {})
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


static func get_public_label(pair: Dictionary, viewer_id: String) -> String:
	if pair.is_empty():
		return "Familiar but distant"

	var other_id := _other_id(pair, viewer_id)
	var view := _direction(pair, viewer_id)
	var reciprocal := _direction(pair, other_id)
	var affinity := int(view.get("affinity", 0))
	var trust := int(view.get("trust", 0))
	var respect := int(view.get("respect", 0))
	var tension := int(view.get("tension", 0))

	if (
		affinity >= 60
		and trust >= 55
		and int(reciprocal.get("affinity", 0)) >= 45
		and int(reciprocal.get("trust", 0)) >= 40
	):
		return "Close friends"

	if trust >= 55 and respect >= 20:
		return "Trusted companion"

	if respect >= 50 and tension >= 20 and affinity < 40:
		return "Respectful rivals"

	if affinity >= 35 and trust < 20:
		return "Fond but unreliable"

	if tension >= 50 or affinity <= -30 or trust <= -35:
		return "Strained"

	if affinity >= 20 and trust >= 15:
		return "Becoming friends"

	return "Familiar but distant"


static func get_debug_report(store: Dictionary) -> Dictionary:
	var reports: Dictionary = {}

	for key in store.get("pairs", {}).keys():
		var pair: Dictionary = Dictionary(store["pairs"][key])
		var first_id := String(pair.get("raider_a_id", ""))
		var second_id := String(pair.get("raider_b_id", ""))
		reports[key] = {
			"raider_a_id": first_id,
			"raider_b_id": second_id,
			"a_views_b": Dictionary(pair.get("directional", {}).get(first_id, {})).duplicate(true),
			"b_views_a": Dictionary(pair.get("directional", {}).get(second_id, {})).duplicate(true),
			"a_label": get_public_label(pair, first_id),
			"b_label": get_public_label(pair, second_id),
			"shared_context": Dictionary(pair.get("shared_context", {})).duplicate(true),
			"shared_pair_memories": Array(pair.get("pair_memories", [])).duplicate(true),
			"permanent_relationship_memories": Array(
				pair.get("permanent_relationship_memories", [])
			).duplicate(true),
			"archived_permanent_relationship_summaries": Array(
				pair.get("archived_permanent_relationship_summaries", [])
			).duplicate(true),
			"relationship_threshold_progress": _threshold_progress(pair),
			"thresholds_reached": Array(pair.get("thresholds_reached", [])).duplicate(true),
		}

	return {"pairs": reports}


static func pair_key(first_id: String, second_id: String) -> String:
	var ids := [first_id, second_id]
	ids.sort()
	return "%s|%s" % ids


static func _record_shared_context(pair: Dictionary, event: Dictionary) -> void:
	var event_type := String(event.get("event_type", ""))
	var event_id := String(event.get("event_id", ""))
	var data: Dictionary = Dictionary(event.get("structured_data", {}))
	var context: Dictionary = pair.get("shared_context", {})
	var creates_pair_memory := false
	var pair_memory_kind := ""

	match event_type:
		"boss_defeated":
			_append_limited(context["shared_victories"], _context_entry(event), 16)
			creates_pair_memory = bool(data.get("pair_distinctive", false))
			pair_memory_kind = "shared_victory"
		"room_assignment_changed":
			_append_limited(
				context["roommate_history"],
				{
					"event_id": event_id,
					"room_assignment_id": String(data.get("room_assignment_id", "")),
					"recorded_unix_time": int(event.get("recorded_unix_time", 0)),
				},
				16
			)
			creates_pair_memory = bool(data.get("meaningful", false))
			pair_memory_kind = "roommate_history"
		"exceptional_heal_or_rescue":
			_append_limited(context["rescue_events"], _context_entry(event), 16)
			creates_pair_memory = true
			pair_memory_kind = "rescue"
		"meaningful_argument":
			_append_limited(context["meaningful_arguments"], _context_entry(event), 16)
			creates_pair_memory = true
			pair_memory_kind = "argument"
		"mentorship_milestone":
			_append_limited(context["mentorship"], _context_entry(event), 16)
			creates_pair_memory = true
			pair_memory_kind = "mentorship"
		"significant_shared_activity":
			var activity_id := String(data.get("activity_id", "unknown"))
			var counts: Dictionary = context.get("shared_activity_counts", {})
			counts[activity_id] = int(counts.get(activity_id, 0)) + 1
			context["shared_activity_counts"] = counts
			creates_pair_memory = bool(data.get("meaningful", false))
			pair_memory_kind = "shared_activity"
		"conversation_completed":
			var conversation_entry := _context_entry(event)
			conversation_entry["outcome_id"] = String(data.get("outcome_id", ""))
			conversation_entry["qualifies_for_relationship_change"] = bool(
				data.get("qualifies_for_relationship_change", false)
			)
			_append_limited(
				context["recent_completed_conversation_outcomes"],
				conversation_entry,
				RECENT_CONVERSATION_LIMIT
			)
			creates_pair_memory = bool(data.get("meaningful", true))
			pair_memory_kind = "conversation"

	pair["shared_context"] = context

	if creates_pair_memory:
		var pair_memories: Array = pair.get("pair_memories", [])
		_append_limited(
			pair_memories,
			{
				"pair_memory_id": "%s:%s" % [String(pair.get("pair_key", "")), event_id],
				"event_id": event_id,
				"kind": pair_memory_kind,
				"subject_key": String(event.get("subject_key", event_type)),
				"recorded_unix_time": int(event.get("recorded_unix_time", 0)),
				"prose_template_id": String(event.get("prose_template_id", "")),
				"prose_parameters": Dictionary(event.get("prose_parameters", {})).duplicate(true),
				"structured_data": data.duplicate(true),
			},
			PAIR_MEMORY_LIMIT
		)
		pair["pair_memories"] = pair_memories


static func _apply_qualifying_changes(
	pair: Dictionary, event: Dictionary
) -> Array[Dictionary]:
	var event_type := String(event.get("event_type", ""))
	var data: Dictionary = Dictionary(event.get("structured_data", {}))
	var qualifies := false

	if event_type == "conversation_completed":
		qualifies = (
			bool(data.get("controlled_outcome", false))
			and bool(data.get("qualifies_for_relationship_change", false))
		)
	else:
		qualifies = (
			bool(data.get("threshold_worthy", false))
			and int(event.get("significance", 0)) >= 60
			and event_type != "significant_shared_activity"
		)

	if not qualifies:
		return []

	var deltas_value: Variant = data.get("relationship_deltas", {})

	if not deltas_value is Dictionary:
		return []

	var deltas: Dictionary = deltas_value
	var directional: Dictionary = pair.get("directional", {})
	var reached: Array = pair.get("thresholds_reached", [])
	var derived_events: Array[Dictionary] = []

	for viewer_id in directional.keys():
		var viewer_delta_value: Variant = deltas.get(viewer_id, {})

		if not viewer_delta_value is Dictionary:
			continue

		var values: Dictionary = directional[viewer_id]
		var viewer_deltas: Dictionary = viewer_delta_value
		var other_id := _other_id(pair, String(viewer_id))

		for dimension in DIMENSIONS:
			if not viewer_deltas.has(dimension):
				continue

			var before := int(values.get(dimension, 0))
			var delta := int(viewer_deltas[dimension])
			if not bool(data.get("allow_large_relationship_delta", false)):
				var maximum_delta := int(TUNING.get("maximum_normal_dimension_delta", 8))
				delta = clampi(delta, -maximum_delta, maximum_delta)
			var after := clampi(before + delta, VALUE_MIN, VALUE_MAX)
			values[dimension] = after

			for threshold in THRESHOLDS:
				if not _crossed_threshold(before, after, threshold):
					continue

				var threshold_id := "%s:%s:%s:%d" % [
					String(pair.get("pair_key", "")), viewer_id, dimension, threshold
				]

				if _contains_threshold(reached, threshold_id):
					continue

				var threshold_entry := {
					"threshold_id": threshold_id,
					"viewer_id": String(viewer_id),
					"other_id": other_id,
					"dimension": dimension,
					"threshold": threshold,
					"source_event_id": String(event.get("event_id", "")),
					"recorded_unix_time": int(event.get("recorded_unix_time", 0)),
				}
				reached.append(threshold_entry)
				derived_events.append(
					{
						"event_type": "relationship_threshold_reached",
						"participants": [String(viewer_id), other_id],
						"memory_category": "social",
						"subject_key": "%s:%s" % [dimension, threshold],
						"significance": 75 if abs(threshold) >= 50 else 60,
						"structured_data": threshold_entry.duplicate(true),
						"prose_template_id": "relationship_threshold_reached",
						"prose_parameters": {
							"dimension": dimension, "threshold": threshold
						},
					}
				)

				if abs(threshold) >= 50:
					_record_permanent_relationship_memory(pair, threshold_entry, event)

		directional[viewer_id] = values

	pair["directional"] = directional
	pair["thresholds_reached"] = reached
	return derived_events


static func _record_permanent_relationship_memory(
	pair: Dictionary, threshold: Dictionary, source_event: Dictionary
) -> void:
	var permanent: Array = pair.get("permanent_relationship_memories", [])
	var threshold_id := String(threshold.get("threshold_id", ""))

	for existing in permanent:
		if existing is Dictionary and String(existing.get("threshold_id", "")) == threshold_id:
			return

	permanent.append(
		{
			"relationship_memory_id": "%s:permanent:%s" % [
				String(pair.get("pair_key", "")), threshold_id
			],
			"threshold_id": threshold_id,
			"source_event_id": String(source_event.get("event_id", "")),
			"dimension": String(threshold.get("dimension", "")),
			"threshold": int(threshold.get("threshold", 0)),
			"recorded_unix_time": int(source_event.get("recorded_unix_time", 0)),
			"prose_template_id": "lasting_relationship_milestone",
		}
	)
	pair["permanent_relationship_memories"] = permanent
	_archive_permanent_relationship_overflow(pair)


static func _threshold_progress(pair: Dictionary) -> Dictionary:
	var result: Dictionary = {}

	for viewer_id in pair.get("directional", {}).keys():
		var values: Dictionary = pair["directional"][viewer_id]
		var dimensions: Dictionary = {}

		for dimension in DIMENSIONS:
			var value := int(values.get(dimension, 0))
			var next_positive := 0
			var next_negative := 0

			for threshold in [25, 50, 75]:
				if value < threshold:
					next_positive = threshold
					break

			for threshold in [-25, -50, -75]:
				if value > threshold:
					next_negative = threshold
					break

			dimensions[dimension] = {
				"value": value,
				"next_positive_threshold": next_positive,
				"points_to_positive_threshold": maxi(next_positive - value, 0),
				"next_negative_threshold": next_negative,
				"points_to_negative_threshold": maxi(value - next_negative, 0),
			}

		result[viewer_id] = dimensions

	return result


static func _create_pair(first_id: String, second_id: String) -> Dictionary:
	var ids := [first_id, second_id]
	ids.sort()
	return {
		"pair_key": pair_key(first_id, second_id),
		"raider_a_id": ids[0],
		"raider_b_id": ids[1],
		"directional": {
			ids[0]: _empty_dimensions(),
			ids[1]: _empty_dimensions(),
		},
		"shared_context": _empty_shared_context(),
		"pair_memories": [],
		"permanent_relationship_memories": [],
		"archived_permanent_relationship_summaries": [],
		"thresholds_reached": [],
	}


static func _sanitize_pair(
	source: Dictionary, first_id: String, second_id: String
) -> Dictionary:
	var result := _create_pair(first_id, second_id)
	var source_directional: Dictionary = (
		Dictionary(source.get("directional", {}))
		if source.get("directional", {}) is Dictionary
		else {}
	)

	for viewer_id in result["directional"].keys():
		var source_values: Dictionary = (
			Dictionary(source_directional.get(viewer_id, {}))
			if source_directional.get(viewer_id, {}) is Dictionary
			else {}
		)
		var values := _empty_dimensions()

		for dimension in DIMENSIONS:
			values[dimension] = clampi(
				int(source_values.get(dimension, 0)), VALUE_MIN, VALUE_MAX
			)

		result["directional"][viewer_id] = values

	var context := _empty_shared_context()
	var source_context: Dictionary = (
		Dictionary(source.get("shared_context", {}))
		if source.get("shared_context", {}) is Dictionary
		else {}
	)

	for context_key in context.keys():
		if context_key == "shared_activity_counts":
			context[context_key] = (
				Dictionary(source_context.get(context_key, {})).duplicate(true)
				if source_context.get(context_key, {}) is Dictionary
				else {}
			)
		else:
			context[context_key] = _dictionary_array(source_context.get(context_key, []), 16)

	result["shared_context"] = context
	result["pair_memories"] = _dictionary_array(
		source.get("pair_memories", []), PAIR_MEMORY_LIMIT
	)
	result["permanent_relationship_memories"] = _dictionary_array(
		source.get("permanent_relationship_memories", []), 0
	)
	result["archived_permanent_relationship_summaries"] = _dictionary_array(
		source.get("archived_permanent_relationship_summaries", []), 0
	)
	result["thresholds_reached"] = _dictionary_array(source.get("thresholds_reached", []), 0)
	_archive_permanent_relationship_overflow(result)
	return result


static func _empty_dimensions() -> Dictionary:
	return {"affinity": 0, "trust": 0, "respect": 0, "tension": 0}


static func _archive_permanent_relationship_overflow(pair: Dictionary) -> void:
	var permanent: Array = pair.get("permanent_relationship_memories", [])
	var archive: Array = pair.get("archived_permanent_relationship_summaries", [])

	while permanent.size() > PERMANENT_PAIR_MEMORY_LIMIT:
		var oldest: Dictionary = Dictionary(permanent.pop_front())
		archive.append(
			{
				"relationship_memory_id": String(oldest.get("relationship_memory_id", "")),
				"dimension": String(oldest.get("dimension", "")),
				"threshold": int(oldest.get("threshold", 0)),
				"recorded_unix_time": int(oldest.get("recorded_unix_time", 0)),
			}
		)

	pair["permanent_relationship_memories"] = permanent
	pair["archived_permanent_relationship_summaries"] = archive


static func _empty_shared_context() -> Dictionary:
	return {
		"roommate_history": [],
		"shared_victories": [],
		"rescue_events": [],
		"meaningful_arguments": [],
		"mentorship": [],
		"shared_activity_counts": {},
		"recent_completed_conversation_outcomes": [],
	}


static func _direction(pair: Dictionary, viewer_id: String) -> Dictionary:
	var value: Variant = pair.get("directional", {}).get(viewer_id, {})
	return Dictionary(value) if value is Dictionary else _empty_dimensions()


static func _other_id(pair: Dictionary, viewer_id: String) -> String:
	var first_id := String(pair.get("raider_a_id", ""))
	var second_id := String(pair.get("raider_b_id", ""))
	return second_id if viewer_id == first_id else first_id


static func _crossed_threshold(before: int, after: int, threshold: int) -> bool:
	if threshold > 0:
		return before < threshold and after >= threshold

	return before > threshold and after <= threshold


static func _contains_threshold(entries: Array, threshold_id: String) -> bool:
	for entry in entries:
		if entry is Dictionary and String(entry.get("threshold_id", "")) == threshold_id:
			return true

	return false


static func _context_entry(event: Dictionary) -> Dictionary:
	return {
		"event_id": String(event.get("event_id", "")),
		"subject_key": String(event.get("subject_key", "")),
		"recorded_unix_time": int(event.get("recorded_unix_time", 0)),
		"structured_data": Dictionary(event.get("structured_data", {})).duplicate(true),
	}


static func _append_limited(target: Array, value: Dictionary, limit: int) -> void:
	target.append(value.duplicate(true))

	if limit > 0 and target.size() > limit:
		target.remove_at(0)


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
