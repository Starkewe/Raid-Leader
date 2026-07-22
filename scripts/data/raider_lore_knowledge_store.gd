extends RefCounted
class_name RaiderLoreKnowledgeStore

const KNOWLEDGE_STATES := ["partial", "known"]


static func create_store() -> Dictionary:
	return {
		"raiders": {},
		"raid_shared_topics": [],
	}


static func sanitize_store(source: Variant, valid_raider_ids: Array[String]) -> Dictionary:
	var raw: Dictionary = Dictionary(source).duplicate(true) if source is Dictionary else {}
	var source_raiders: Dictionary = (
		Dictionary(raw.get("raiders", {})) if raw.get("raiders", {}) is Dictionary else {}
	)
	var raiders: Dictionary = {}

	for raider_id in valid_raider_ids:
		var value: Variant = source_raiders.get(raider_id, {})

		if value is Dictionary and not Dictionary(value).is_empty():
			raiders[raider_id] = _sanitize_raider_knowledge(Dictionary(value))

	return {
		"raiders": raiders,
		"raid_shared_topics": _string_array(raw.get("raid_shared_topics", [])),
	}


static func learn_topic(
	store: Dictionary,
	raider_id: String,
	topic_id: String,
	knowledge_state: String,
	interpretation: String,
	source_id: String,
	shared_with_raid: bool
) -> Dictionary:
	if raider_id.is_empty() or topic_id.is_empty():
		return {}

	var normalized_state := knowledge_state if knowledge_state in KNOWLEDGE_STATES else "partial"
	var raiders: Dictionary = store.get("raiders", {})
	var raider_value: Variant = raiders.get(raider_id, {})
	var raider: Dictionary = (
		_sanitize_raider_knowledge(Dictionary(raider_value))
		if raider_value is Dictionary
		else {"topics": {}}
	)
	var topics: Dictionary = raider.get("topics", {})
	var topic_value: Variant = topics.get(topic_id, {})
	var topic: Dictionary = (
		Dictionary(topic_value).duplicate(true) if topic_value is Dictionary else {}
	)
	var interpretations := _string_array(topic.get("believed_interpretations", []))
	var sources := _string_array(topic.get("source_ids", []))

	if not interpretation.is_empty() and not interpretations.has(interpretation):
		interpretations.append(interpretation)

	if not source_id.is_empty() and not sources.has(source_id):
		sources.append(source_id)

	topic["topic_id"] = topic_id
	var already_known := String(topic.get("knowledge_state", "")) == "known"
	topic["knowledge_state"] = "known" if normalized_state == "known" or already_known else "partial"
	topic["believed_interpretations"] = interpretations
	topic["source_ids"] = sources
	topic["shared_with_raid"] = (
		bool(topic.get("shared_with_raid", false)) or shared_with_raid
	)
	topics[topic_id] = topic
	raider["topics"] = topics
	raiders[raider_id] = raider
	store["raiders"] = raiders

	if shared_with_raid:
		var shared_topics := _string_array(store.get("raid_shared_topics", []))

		if not shared_topics.has(topic_id):
			shared_topics.append(topic_id)

		store["raid_shared_topics"] = shared_topics

	return topic.duplicate(true)


static func get_raider_knowledge(store: Dictionary, raider_id: String) -> Dictionary:
	var value: Variant = store.get("raiders", {}).get(raider_id, {})
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


static func get_debug_report(store: Dictionary) -> Dictionary:
	return store.duplicate(true)


static func _sanitize_raider_knowledge(source: Dictionary) -> Dictionary:
	var source_topics: Dictionary = (
		Dictionary(source.get("topics", {})) if source.get("topics", {}) is Dictionary else {}
	)
	var topics: Dictionary = {}

	for topic_id in source_topics.keys():
		if not source_topics[topic_id] is Dictionary:
			continue

		var source_topic: Dictionary = source_topics[topic_id]
		var state := String(source_topic.get("knowledge_state", "partial"))
		topics[String(topic_id)] = {
			"topic_id": String(topic_id),
			"knowledge_state": state if state in KNOWLEDGE_STATES else "partial",
			"believed_interpretations": _string_array(
				source_topic.get("believed_interpretations", [])
			),
			"source_ids": _string_array(source_topic.get("source_ids", [])),
			"shared_with_raid": bool(source_topic.get("shared_with_raid", false)),
		}

	return {"topics": topics}


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()

			if not text.is_empty() and not result.has(text):
				result.append(text)

	return result
