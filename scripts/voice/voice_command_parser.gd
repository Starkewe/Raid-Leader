extends Node
class_name VoiceCommandParser


func parse(transcript: String) -> Dictionary:
	var text := _normalize(transcript)
	print("Voice normalized text: ", text)

	var who_result := _parse_who(text)

	if not bool(who_result.get("ok", false)):
		return _fail(
			"Could not determine target group or unit from: %s" % transcript,
			text,
			transcript
		)

	var action_result := _parse_action(text)

	if not bool(action_result.get("ok", false)):
		return _fail(
			"Could not determine command action from: %s" % transcript,
			text,
			transcript
		)

	var command_data := {
		"who_type": String(who_result.get("who_type", "everyone")),
		"who_value": who_result.get("who_value", ""),
		"unit": who_result.get("unit", null),
		"what": String(action_result.get("what", "")),
		"where": String(action_result.get("where", "none")),
		"when": "now"
	}

	var extra: Dictionary = action_result.get("extra", {})

	for key in extra.keys():
		command_data[key] = extra[key]

	return {
		"ok": true,
		"command_data": command_data,
		"reason": "",
		"transcript": transcript,
		"normalized_text": text
	}

func _normalize(text: String) -> String:
	var output := text.to_lower().strip_edges()

	var punctuation := [
		".",
		",",
		"!",
		"?",
		"'",
		"\"",
		":",
		";",
		"-",
		"_",
		"(",
		")",
		"[",
		"]",
		"{",
		"}",
		"/",
		"\\"
	]

	for mark in punctuation:
		output = output.replace(mark, " ")

	output = output.replace("every one", "everyone")
	output = output.replace("preached", "priest")
	output = output.replace("rouge", "rogue")
	output = output.replace("road", "rogue")

	while output.contains("  "):
		output = output.replace("  ", " ")

	return output.strip_edges()


func _parse_who(text: String) -> Dictionary:
	if _has_any_word(text, ["everyone", "everybody", "all"]):
		return _who("everyone", "", null)

	if _has_phrase(text, "group one") or _has_word(text, "group 1"):
		return _who("group", 1, null)

	if _has_phrase(text, "group two") or _has_word(text, "group 2"):
		return _who("group", 2, null)

	if _has_phrase(text, "group three") or _has_word(text, "group 3"):
		return _who("group", 3, null)

	if _has_phrase(text, "group four") or _has_word(text, "group 4"):
		return _who("group", 4, null)

	if _has_any_word(text, ["warrior", "warriors", "tank", "tanks"]):
		return _who("class", "Warrior", null)

	if _has_any_word(text, ["priest", "priests", "healer", "healers"]):
		return _who("class", "Priest", null)

	if _has_any_word(text, ["rogue", "rogues", "melee"]):
		return _who("class", "Rogue", null)

	if _has_any_word(text, ["mage", "mages", "ranged"]):
		return _who("class", "Mage", null)

	return {
		"ok": false,
		"who_type": "",
		"who_value": "",
		"unit": null
	}


func _parse_action(text: String) -> Dictionary:
	if _has_any_word(text, ["interrupt", "kick"]):
		return _action("interrupt", "boss", {})

	if _has_any_word(text, ["attack", "damage", "dps"]):
		return _action("attack", "boss", {})

	if _contains_movement_intent(text):
		return _parse_movement_action(text)

	if _has_any_word(text, ["heal", "healing"]):
		return _action("heal", "boss_target", {})

	return {
		"ok": false,
		"what": "",
		"where": "none",
		"extra": {}
	}


func _contains_movement_intent(text: String) -> bool:
	if _has_any_word(text, ["move", "moves", "moving", "go", "come", "rotate", "turn", "spread"]):
		return true

	if _has_any_word(text, ["closer", "away"]):
		return true

	if _has_phrase(text, "on me"):
		return true

	if _has_phrase(text, "to me"):
		return true

	return false


func _parse_movement_action(text: String) -> Dictionary:
	if _has_phrase(text, "come to me") or _has_phrase(text, "to me") or _has_phrase(text, "on me") or _has_phrase(text, "stack on me"):
		return _action("move", "me", {})

	if _has_phrase(text, "move out") or _has_phrase(text, "go out") or _has_phrase(text, "spread out") or _has_word(text, "away"):
		return _action("move", "movement_range_step", {
			"movement_direction": "out"
		})

	if _has_phrase(text, "move in") or _has_phrase(text, "go in") or _has_phrase(text, "come in") or _has_word(text, "closer"):
		return _action("move", "movement_range_step", {
			"movement_direction": "in"
		})

	if _has_word(text, "clockwise"):
		return _action("move", "movement_rotate_step", {
			"movement_direction": "clockwise"
		})

	if _has_word(text, "counterclockwise") or _has_phrase(text, "counter clockwise") or _has_word(text, "anticlockwise"):
		return _action("move", "movement_rotate_step", {
			"movement_direction": "counterclockwise"
		})

	var region := _parse_region(text)
	var range_name := _parse_range(text)

	if not region.is_empty() and not range_name.is_empty():
		return _action("move", "movement_slot", {
			"movement_region": region,
			"movement_range": range_name
		})

	if not region.is_empty() and (_has_word(text, "rotate") or _has_word(text, "turn")):
		return _action("move", "movement_rotate", {
			"movement_region": region
		})

	if not region.is_empty():
		return _action("move", "movement_region", {
			"movement_region": region
		})

	if not range_name.is_empty():
		return _action("move", "movement_range", {
			"movement_range": range_name
		})

	return _action("move", "me", {})


func _parse_region(text: String) -> String:
	if _has_word(text, "northeast") or _has_phrase(text, "north east"):
		return "northeast"

	if _has_word(text, "northwest") or _has_phrase(text, "north west"):
		return "northwest"

	if _has_word(text, "southeast") or _has_phrase(text, "south east"):
		return "southeast"

	if _has_word(text, "southwest") or _has_phrase(text, "south west"):
		return "southwest"

	if _has_word(text, "north"):
		return "north"

	if _has_word(text, "south"):
		return "south"

	if _has_word(text, "east"):
		return "east"

	if _has_word(text, "west"):
		return "west"

	return ""


func _parse_range(text: String) -> String:
	if _has_word(text, "close"):
		return "close"

	if _has_word(text, "mid") or _has_word(text, "middle"):
		return "mid"

	if _has_word(text, "far"):
		return "far"

	return ""


func _has_word(text: String, word: String) -> bool:
	var padded_text := " " + text + " "
	var padded_word := " " + word + " "

	return padded_text.contains(padded_word)


func _has_any_word(text: String, words: Array[String]) -> bool:
	for word in words:
		if _has_word(text, word):
			return true

	return false


func _has_phrase(text: String, phrase: String) -> bool:
	var padded_text := " " + text + " "
	var padded_phrase := " " + phrase + " "

	return padded_text.contains(padded_phrase)


func _who(who_type: String, who_value, unit) -> Dictionary:
	return {
		"ok": true,
		"who_type": who_type,
		"who_value": who_value,
		"unit": unit
	}


func _action(what: String, where: String, extra: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"what": what,
		"where": where,
		"extra": extra
	}


func _fail(reason: String, normalized_text: String = "", transcript: String = "") -> Dictionary:
	return {
		"ok": false,
		"command_data": {},
		"reason": reason,
		"transcript": transcript,
		"normalized_text": normalized_text
	}
