extends Node
class_name VoiceCommandParser


func parse(transcript: String) -> Dictionary:
	var text := _normalize(transcript)

	var command_data := {
		"who_type": "",
		"who_value": null,
		"unit": null,
		"what": "",
		"where": "",
		"when": "now"
	}

	var who_result := _parse_who(text)
	if not who_result.ok:
		return _fail("Could not determine target group or unit from: %s" % transcript)

	command_data["who_type"] = who_result.who_type
	command_data["who_value"] = who_result.who_value
	command_data["unit"] = who_result.unit

	var what_result := _parse_what(text)
	if not what_result.ok:
		return _fail("Could not determine command action from: %s" % transcript)

	command_data["what"] = what_result.what
	command_data["where"] = what_result.where

	for key in what_result.extra.keys():
		command_data[key] = what_result.extra[key]

	return {
		"ok": true,
		"command_data": command_data,
		"reason": ""
	}


func _normalize(text: String) -> String:
	var output := text.to_lower().strip_edges()

	output = output.replace(".", "")
	output = output.replace(",", "")
	output = output.replace("!", "")
	output = output.replace("?", "")

	# Common Whisper cleanup.
	output = output.replace("every one", "everyone")
	output = output.replace("preached", "priest")
	output = output.replace("rouge", "rogue")

	return output


func _parse_who(text: String) -> Dictionary:
	if text.contains("everyone") or text.contains("everybody") or text.contains("all"):
		return _who("everyone", null, null)

	if text.contains("warrior") or text.contains("tank"):
		return _who("class", "warrior", null)

	if text.contains("priest") or text.contains("healer"):
		return _who("class", "priest", null)

	if text.contains("mage"):
		return _who("class", "mage", null)

	if text.contains("rogue"):
		return _who("class", "rogue", null)

	for i in range(1, 5):
		if text.contains("group %d" % i):
			return _who("group", i, null)

	return {
		"ok": false,
		"who_type": "",
		"who_value": null,
		"unit": null
	}


func _parse_what(text: String) -> Dictionary:
	if text.contains("interrupt"):
		return _what("interrupt", "", {})

	if text.contains("heal"):
		return _what("heal", "", {})

	if text.contains("move out") or text.contains("out"):
		return _what("movement", "out", {
			"movement_direction": "out",
			"movement_steps": 1
		})

	if text.contains("move in") or text.contains("in"):
		return _what("movement", "in", {
			"movement_direction": "in",
			"movement_steps": 1
		})

	if text.contains("come to me") or text.contains("to me") or text.contains("on me"):
		return _what("movement", "me", {
			"movement_direction": "toward_player",
			"movement_steps": 1
		})

	return {
		"ok": false,
		"what": "",
		"where": "",
		"extra": {}
	}


func _who(who_type: String, who_value, unit) -> Dictionary:
	return {
		"ok": true,
		"who_type": who_type,
		"who_value": who_value,
		"unit": unit
	}


func _what(what: String, where: String, extra: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"what": what,
		"where": where,
		"extra": extra
	}


func _fail(reason: String) -> Dictionary:
	return {
		"ok": false,
		"command_data": {},
		"reason": reason
	}
