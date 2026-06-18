extends RefCounted
class_name VoiceCommandParser


static func parse_transcript(transcript: String) -> Dictionary:
	var text := normalize_text(transcript)

	if text.is_empty():
		return {}

	var command_data := parse_who(text)

	if has_any(text, ["attack", "start attack", "hit boss", "attack boss", "dps boss"]):
		command_data["what"] = "attack"
		command_data["where"] = "boss"
		return command_data

	if has_any(text, ["interrupt", "kick", "stop cast", "stop casting"]):
		command_data["what"] = "interrupt"
		command_data["where"] = "boss"
		return command_data

	if has_any(text, ["heal", "heal target", "heal boss target", "heal the target"]):
		command_data["what"] = "heal"
		command_data["where"] = "boss_target"
		return command_data

	if has_any(text, ["move", "go", "rotate", "step", "come", "spread"]):
		return parse_move_command(text, command_data)

	return {}


static func parse_move_command(text: String, command_data: Dictionary) -> Dictionary:
	command_data["what"] = "move"

	if has_any(text, ["move in", "come in", "step in", "closer", "move closer"]):
		command_data["where"] = "movement_range_step"
		command_data["movement_direction"] = "in"
		return command_data

	if has_any(text, ["move out", "go out", "step out", "back out", "farther", "move farther"]):
		command_data["where"] = "movement_range_step"
		command_data["movement_direction"] = "out"
		return command_data

	var range_name := parse_range(text)
	var region_name := parse_region(text)

	if region_name != "" and range_name != "":
		command_data["where"] = "movement_slot"
		command_data["movement_region"] = region_name
		command_data["movement_range"] = range_name
		return command_data

	if region_name != "":
		command_data["where"] = "movement_rotate"
		command_data["movement_region"] = region_name
		return command_data

	if range_name != "":
		command_data["where"] = "movement_range"
		command_data["movement_range"] = range_name
		return command_data

	if has_any(text, ["to me", "on me", "come to me", "stack on me"]):
		command_data["where"] = "me"
		return command_data

	return {}


static func parse_who(text: String) -> Dictionary:
	if has_any(text, ["group one", "group 1"]):
		return {
			"who_type": "group",
			"who_value": 1
		}

	if has_any(text, ["group two", "group 2"]):
		return {
			"who_type": "group",
			"who_value": 2
		}

	if has_any(text, ["group three", "group 3"]):
		return {
			"who_type": "group",
			"who_value": 3
		}

	if has_any(text, ["group four", "group 4"]):
		return {
			"who_type": "group",
			"who_value": 4
		}

	if has_any(text, ["warrior", "warriors", "tank", "tanks"]):
		return {
			"who_type": "class",
			"who_value": "Warrior"
		}

	if has_any(text, ["rogue", "rogues"]):
		return {
			"who_type": "class",
			"who_value": "Rogue"
		}

	if has_any(text, ["mage", "mages", "caster", "casters"]):
		return {
			"who_type": "class",
			"who_value": "Mage"
		}

	if has_any(text, ["priest", "priests", "healer", "healers"]):
		return {
			"who_type": "class",
			"who_value": "Priest"
		}

	return {
		"who_type": "everyone",
		"who_value": ""
	}


static func parse_region(text: String) -> String:
	var region_terms := [
		["north east", "northeast", "north-east"],
		["south east", "southeast", "south-east"],
		["south west", "southwest", "south-west"],
		["north west", "northwest", "north-west"],
		["north"],
		["east"],
		["south"],
		["west"]
	]

	var region_values := [
		"northeast",
		"southeast",
		"southwest",
		"northwest",
		"north",
		"east",
		"south",
		"west"
	]

	for i in range(region_terms.size()):
		if has_any(text, region_terms[i]):
			return region_values[i]

	return ""


static func parse_range(text: String) -> String:
	if has_any(text, ["close", "melee"]):
		return "close"

	if has_any(text, ["mid", "middle"]):
		return "mid"

	if has_any(text, ["far", "long", "ranged"]):
		return "far"

	return ""


static func normalize_text(transcript: String) -> String:
	var text := transcript.to_lower().strip_edges()

	for symbol in [".", ",", "!", "?", ";", ":"]:
		text = text.replace(symbol, "")

	return text


static func has_any(text: String, terms: Array) -> bool:
	for term in terms:
		if text.contains(String(term)):
			return true

	return false
