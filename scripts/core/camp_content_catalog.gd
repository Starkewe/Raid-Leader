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


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result
