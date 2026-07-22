extends RefCounted
class_name CampContentCatalog

const STATION_PATH := "res://data/camp/activity_stations.json"
const CONVERSATION_PATH := "res://data/camp/conversations/conversation_frames.json"
const LORE_PATH := "res://data/lore/camp_lore_topics.json"

static var _loaded: bool = false
static var _stations: Array[Dictionary] = []
static var _frames: Array[Dictionary] = []
static var _lore_by_id: Dictionary = {}
static var _warnings: Array[String] = []
static var _validation_report: Dictionary = {}


static func get_station_definitions() -> Array[Dictionary]:
	_ensure_loaded()
	return _stations.duplicate(true)


static func get_conversation_frames() -> Array[Dictionary]:
	_ensure_loaded()
	return _frames.duplicate(true)


static func get_lore_topic(topic_id: String) -> Dictionary:
	_ensure_loaded()
	return Dictionary(_lore_by_id.get(topic_id, {})).duplicate(true)


static func get_warnings() -> Array[String]:
	_ensure_loaded()
	return _warnings.duplicate()


static func get_validation_report() -> Dictionary:
	_ensure_loaded()
	return _validation_report.duplicate(true)


static func _ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	var station_root := _load_json(STATION_PATH)
	var frame_root := _load_json(CONVERSATION_PATH)
	var lore_root := _load_json(LORE_PATH)
	var station_ids: Dictionary = {}

	for value in station_root.get("stations", []):
		if not value is Dictionary:
			_warnings.append("Camp station catalog contains a non-object entry.")
			continue
		var station := Dictionary(value).duplicate(true)
		var station_id := String(station.get("station_id", "")).strip_edges()
		if station_id.is_empty() or station_ids.has(station_id):
			_warnings.append("Camp station has a missing or duplicate ID: " + station_id)
			continue
		if String(station.get("facility_id", "")).is_empty():
			_warnings.append("Camp station is missing facility_id: " + station_id)
			continue
		if int(station.get("capacity", 0)) <= 0:
			_warnings.append("Camp station has invalid capacity: " + station_id)
			continue
		if _string_array(station.get("supported_activity_ids", [])).is_empty():
			_warnings.append("Camp station supports no activities: " + station_id)
			continue
		station_ids[station_id] = true
		_stations.append(station)

	var frame_ids: Dictionary = {}

	for value in frame_root.get("frames", []):
		if not value is Dictionary:
			_warnings.append("Conversation catalog contains a non-object frame.")
			continue
		var frame := Dictionary(value).duplicate(true)
		var frame_id := String(frame.get("frame_id", "")).strip_edges()
		if frame_id.is_empty() or frame_ids.has(frame_id):
			_warnings.append("Conversation frame has a missing or duplicate ID: " + frame_id)
			continue
		var roles := _string_array(frame.get("roles", []))
		var beats: Array = frame.get("beats", []) if frame.get("beats", []) is Array else []
		if roles.size() < 2 or beats.size() < 3 or beats.size() > 5:
			_warnings.append("Conversation frame has invalid roles or beat count: " + frame_id)
			continue
		if not _has_alternating_valid_beats(beats, roles):
			_warnings.append("Conversation frame has non-alternating or invalid beats: " + frame_id)
			continue
		if not _frame_metadata_is_complete(frame):
			_warnings.append("Conversation frame is missing required metadata: " + frame_id)
			continue
		frame_ids[frame_id] = true
		_frames.append(frame)

	for value in lore_root.get("topics", []):
		if not value is Dictionary:
			continue
		var topic := Dictionary(value).duplicate(true)
		var topic_id := String(topic.get("topic_id", "")).strip_edges()
		if topic_id.is_empty() or _lore_by_id.has(topic_id):
			_warnings.append("Lore topic has a missing or duplicate ID: " + topic_id)
			continue
		var knowledge_type := String(topic.get("knowledge_type", "confirmed_fact"))
		if knowledge_type not in [
			"confirmed_fact", "common_belief", "disputed_account", "personal_theory", "misinformation"
		]:
			_warnings.append("Lore topic has an invalid knowledge type: " + topic_id)
			continue
		_lore_by_id[topic_id] = topic

	_validate_cross_references(station_ids, frame_ids)
	_validation_report = {
		"valid": _warnings.is_empty(),
		"station_count": _stations.size(),
		"conversation_frame_count": _frames.size(),
		"lore_topic_count": _lore_by_id.size(),
		"issues": _warnings.duplicate(),
	}


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_warnings.append("Camp content could not be opened: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_warnings.append("Camp content is not a JSON object: " + path)
		return {}
	return Dictionary(parsed)


static func _has_alternating_valid_beats(beats: Array, roles: Array[String]) -> bool:
	var previous_role := ""
	for value in beats:
		if not value is Dictionary:
			return false
		var beat: Dictionary = value
		var role := String(beat.get("speaker_role", ""))
		if role not in roles or role == previous_role or String(beat.get("text", "")).is_empty():
			return false
		previous_role = role
	return true


static func _frame_metadata_is_complete(frame: Dictionary) -> bool:
	for key in ["eligibility", "safe_fallback", "cooldowns", "summary_metadata", "outcome"]:
		if not frame.get(key, {}) is Dictionary or Dictionary(frame.get(key, {})).is_empty():
			return false
	var fallback: Dictionary = frame.get("safe_fallback", {})
	if String(fallback.get("text", "")).strip_edges().is_empty():
		return false
	var outcome: Dictionary = frame.get("outcome", {})
	if (
		String(outcome.get("type", "")).is_empty()
		or String(outcome.get("summary_template", "")).is_empty()
	):
		return false
	var cooldowns: Dictionary = frame.get("cooldowns", {})
	for key in ["frame", "topic", "pair", "speaker_role"]:
		if float(cooldowns.get(key, 0.0)) <= 0.0:
			return false
	return true


static func _validate_cross_references(
	station_ids: Dictionary, frame_ids: Dictionary
) -> void:
	for frame in _frames:
		var frame_id := String(frame.get("frame_id", ""))
		for station_id in _string_array(frame.get("required_station_ids", [])):
			if not station_ids.has(station_id):
				_warnings.append(
					"Conversation frame references missing station %s: %s"
					% [station_id, frame_id]
				)
		var lore_topic_id := String(frame.get("lore_topic_id", ""))
		if not lore_topic_id.is_empty() and not _lore_by_id.has(lore_topic_id):
			_warnings.append(
				"Conversation frame references missing lore topic %s: %s"
				% [lore_topic_id, frame_id]
			)

	for topic in _lore_by_id.values():
		var exchange_id := String(Dictionary(topic).get("authored_exchange_id", ""))
		if exchange_id.is_empty() or not frame_ids.has(exchange_id):
			_warnings.append(
				"Lore topic has no valid authored exchange: %s"
				% String(Dictionary(topic).get("topic_id", ""))
			)


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result
