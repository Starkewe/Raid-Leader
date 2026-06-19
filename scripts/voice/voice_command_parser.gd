extends Node
class_name VoiceCommandParser


static func parse_transcript(transcript: String) -> Dictionary:
	var text := _normalize_text(transcript)

	var who_data := _parse_who_data(text)
	var what := _parse_what(text)

	if who_data.is_empty() or what.is_empty():
		return {}

	var command_data := {
		"who_type": String(who_data.get("who_type", "everyone")),
		"who_value": who_data.get("who_value", ""),
		"unit": null,
		"what": what,
		"where": "none",
		"when": "now",
		"raw_transcript": transcript
	}

	_apply_where_data(command_data, text, what)

	return command_data


static func _normalize_text(text: String) -> String:
	var normalized := text.to_lower().strip_edges()

	normalized = normalized.replace(".", "")
	normalized = normalized.replace(",", "")
	normalized = normalized.replace("!", "")
	normalized = normalized.replace("?", "")
	normalized = normalized.replace("'", "")

	return normalized


static func _parse_who_data(text: String) -> Dictionary:
	if text.contains("everyone") or text.contains("everybody") or text.contains("all"):
		return {
			"who_type": "everyone",
			"who_value": ""
		}

	if text.contains("group one") or text.contains("group 1"):
		return {
			"who_type": "group",
			"who_value": 1
		}

	if text.contains("group two") or text.contains("group 2"):
		return {
			"who_type": "group",
			"who_value": 2
		}

	if text.contains("group three") or text.contains("group 3"):
		return {
			"who_type": "group",
			"who_value": 3
		}

	if text.contains("group four") or text.contains("group 4"):
		return {
			"who_type": "group",
			"who_value": 4
		}

	if text.contains("tank") or text.contains("tanks") or text.contains("warrior") or text.contains("warriors"):
		return {
			"who_type": "class",
			"who_value": "Warrior"
		}

	if text.contains("healer") or text.contains("healers") or text.contains("priest") or text.contains("priests"):
		return {
			"who_type": "class",
			"who_value": "Priest"
		}

	if text.contains("rogue") or text.contains("rogues") or text.contains("melee"):
		return {
			"who_type": "class",
			"who_value": "Rogue"
		}

	if text.contains("mage") or text.contains("mages") or text.contains("ranged"):
		return {
			"who_type": "class",
			"who_value": "Mage"
		}

	return {}


static func _parse_what(text: String) -> String:
	if text.contains("attack"):
		return "attack"

	if text.contains("move") or text.contains("go") or text.contains("rotate") or text.contains("come"):
		return "move"

	if text.contains("interrupt") or text.contains("kick"):
		return "interrupt"

	if text.contains("heal"):
		return "heal"

	return ""


static func _apply_where_data(command_data: Dictionary, text: String, what: String) -> void:
	match what:
		"attack":
			command_data["where"] = "boss"

		"interrupt":
			command_data["where"] = "boss"

		"heal":
			command_data["where"] = "boss_target"

		"move":
			_apply_movement_where_data(command_data, text)

		_:
			command_data["where"] = "none"


static func _apply_movement_where_data(command_data: Dictionary, text: String) -> void:
	if text.contains("move in") or text.contains("go in") or text.contains("come in") or text.contains("closer"):
		command_data["where"] = "movement_range_step"
		command_data["movement_direction"] = "in"
		return

	if text.contains("move out") or text.contains("go out") or text.contains("spread out") or text.contains("away"):
		command_data["where"] = "movement_range_step"
		command_data["movement_direction"] = "out"
		return

	var region := _parse_region(text)

	if not region.is_empty():
		if text.contains("rotate") or text.contains("turn"):
			command_data["where"] = "movement_rotate"
			command_data["movement_region"] = region
			return

	if _has_range_word(text):
		command_data["where"] = "movement_slot"
		command_data["movement_region"] = region
		command_data["movement_range"] = _parse_range(text)
		return

	# Direction without rotate/range is ambiguous for now.
	command_data.clear()
	return

	if text.contains("close"):
		command_data["where"] = "movement_range"
		command_data["movement_range"] = "close"
		return

	if text.contains("mid") or text.contains("middle"):
		command_data["where"] = "movement_range"
		command_data["movement_range"] = "mid"
		return

	if text.contains("far"):
		command_data["where"] = "movement_range"
		command_data["movement_range"] = "far"
		return

	command_data["where"] = "me"
static func _has_range_word(text: String) -> bool:
	return text.contains("close") or text.contains("mid") or text.contains("middle") or text.contains("far")


static func _parse_range(text: String) -> String:
	if text.contains("close"):
		return "close"

	if text.contains("mid") or text.contains("middle"):
		return "mid"

	if text.contains("far"):
		return "far"

	return ""
static func _parse_region(text: String) -> String:
	if text.contains("northeast") or text.contains("north east"):
		return "northeast"

	if text.contains("northwest") or text.contains("north west"):
		return "northwest"

	if text.contains("southeast") or text.contains("south east"):
		return "southeast"

	if text.contains("southwest") or text.contains("south west"):
		return "southwest"

	if text.contains("north"):
		return "north"

	if text.contains("south"):
		return "south"

	if text.contains("east"):
		return "east"

	if text.contains("west"):
		return "west"

	return ""
