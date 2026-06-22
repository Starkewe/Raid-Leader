extends Node
class_name VoiceCommandParser

const SELECTOR_EVERYONE := "everyone"
const SELECTOR_CLASS := "class"
const SELECTOR_GROUP := "group"
const SELECTOR_UNIT_IDENTITY := "unit_identity"
const SELECTOR_ROLE := "role"

const CLASS_WARRIOR := "Warrior"
const CLASS_ROGUE := "Rogue"
const CLASS_MAGE := "Mage"
const CLASS_PRIEST := "Priest"

const ROLE_TANK := "tank"
const ROLE_OFFTANK := "offtank"
const ROLE_TANK_GROUP := "tank_group"
const ROLE_MELEE := "melee"
const ROLE_MELEE_DPS := "melee_dps"
const ROLE_DPS := "dps"
const ROLE_RANGED_DPS := "ranged_dps"
const ROLE_CASTER := "caster"
const ROLE_HEALER := "healer"

const NUMBER_WORDS := {
	"one": 1,
	"two": 2,
	"three": 3,
	"four": 4,
	"five": 5,
	"six": 6,
	"seven": 7,
	"eight": 8,
	"nine": 9,
	"ten": 10,
	"i": 1,
	"ii": 2,
	"iii": 3,
	"iv": 4,
	"v": 5,
	"vi": 6,
	"vii": 7,
	"viii": 8,
	"ix": 9,
	"x": 10
}

const COMMAND_VOCABULARY := [
	"everyone", "everybody", "all", "raid",
	"except", "excluding", "without", "but", "not",
	"group", "one", "two", "three", "four", "five",
	"warrior", "warriors", "rogue", "rogues", "mage", "mages", "priest", "priests",
	"tank", "tanks", "offtank",
	"healer", "healers", "melee", "dps", "ranged", "range", "caster", "casters",
	"move", "moves", "moving", "go", "come", "rotate", "turn", "spread", "stack",
	"attack", "damage", "burn", "focus", "engage",
	"interrupt", "kick",
	"heal", "healing",
	"north", "south", "east", "west",
	"northeast", "northwest", "southeast", "southwest",
	"close", "mid", "middle", "midrange", "far",
	"out", "in", "away", "closer",
	"clockwise", "counterclockwise", "anticlockwise",
	"on", "to", "me", "with"
]


func parse(transcript: String) -> Dictionary:
	var raw_normalized_text := _normalize_basic(transcript)
	var text := _normalize_command_text(raw_normalized_text)

	print("Voice raw normalized text: ", raw_normalized_text)
	print("Voice command normalized text: ", text)

	var action_result := _parse_action(text)

	if not bool(action_result.get("ok", false)):
		return _fail(
			"Could not determine command action from: %s" % transcript,
			text,
			transcript
		)

	var who_result := _parse_who(text)

	if not bool(who_result.get("ok", false)):
		if _can_action_auto_select_subject(action_result):
			who_result = _default_auto_interrupt_who_result()
		else:
			return _fail(
				"Could not determine target group or unit from: %s" % transcript,
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

	var include_selectors: Array = who_result.get("who_selectors", [])
	var exclude_selectors: Array = who_result.get("who_exclude_selectors", [])

	if not include_selectors.is_empty():
		command_data["who_selectors"] = include_selectors

	if not exclude_selectors.is_empty():
		command_data["who_exclude_selectors"] = exclude_selectors

	if bool(who_result.get("auto_selected_subject", false)):
		command_data["auto_selected_subject"] = true

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


func _normalize_basic(text: String) -> String:
	var output := text.to_lower().strip_edges()

	var punctuation := [
		".", ",", "!", "?", "'", "\"", ":", ";", "-", "_",
		"(", ")", "[", "]", "{", "}", "/", "\\"
	]

	for mark in punctuation:
		output = output.replace(mark, " ")

	output = output.replace("every one", "everyone")
	output = output.replace("off tank", "offtank")
	output = output.replace("main tank", "tank")
	output = output.replace("counter clockwise", "counterclockwise")
	
	output = output.replace("north east", "northeast")
	output = output.replace("north west", "northwest")
	output = output.replace("north with", "northwest")
	output = output.replace("south east", "southeast")
	output = output.replace("south west", "southwest")
	output = output.replace("south with", "southwest")
	
	output = output.replace("mid range", "midrange")
	output = output.replace("close range", "close")
	output = output.replace("far range", "far")
	output = _apply_voice_phrase_repairs(output)
	
	return _collapse_spaces(output)

func _apply_voice_phrase_repairs(text: String) -> String:
	var output := " " + _collapse_spaces(text) + " "

	var repairs := [
		[" may just ", " mages "],
		[" may jest ", " mages "],
		[" my vault ", " move out "],
		[" movie s ", " move east "],
		[" movies ", " move east "],
		[" movie east ", " move east "],
		[" accepts ", " except "],
		[" accept ", " except "],
		[" excepts ", " except "]
	]

	for repair in repairs:
		var from_text := String(repair[0])
		var to_text := String(repair[1])
		output = output.replace(from_text, to_text)

	return _collapse_spaces(output)

func _normalize_command_text(text: String) -> String:
	var compound_repaired_text := _repair_compound_command_tokens(text)
	var tokens := compound_repaired_text.split(" ", false)
	var corrected_tokens: Array[String] = []

	for token in tokens:
		var corrected_token := _correct_token_against_command_vocabulary(String(token))
		corrected_tokens.append(corrected_token)

	return _collapse_spaces(" ".join(corrected_tokens))
func _repair_compound_command_tokens(text: String) -> String:
	var tokens := text.split(" ", false)
	var repaired_tokens: Array[String] = []

	for token in tokens:
		var repaired := _split_compound_subject_action_token(String(token))

		if repaired.is_empty():
			repaired_tokens.append(String(token))
		else:
			for repaired_token in repaired.split(" ", false):
				repaired_tokens.append(String(repaired_token))

	return _collapse_spaces(" ".join(repaired_tokens))


func _split_compound_subject_action_token(token: String) -> String:
	if token.length() < 6:
		return ""

	var subject_aliases := [
		"row",
		"rows",
		"road",
		"roads",
		"rose",
		"roses",
		"work",
		"works",
		"roke",
		"rokes",
		"rogue",
		"rogues",
		"rouge",
		"rouges"
	]

	for subject_alias in subject_aliases:
		if not token.begins_with(subject_alias):
			continue

		var tail := token.substr(String(subject_alias).length()).strip_edges()

		if _is_move_like_token(tail):
			return String(subject_alias) + " move"

	return ""

func _is_move_like_token(token: String) -> bool:
	if token.is_empty():
		return false

	var move_aliases := [
		"move",
		"moves",
		"moving",
		"moved",
		"smooth",
		"smoove",
		"mary"
	]

	if move_aliases.has(token):
		return true

	var best_distance := 999

	for move_word in ["move", "moves", "moving"]:
		var distance := _levenshtein_distance(token, String(move_word))

		if distance < best_distance:
			best_distance = distance

	return best_distance <= 2

func _correct_token_against_command_vocabulary(token: String) -> String:
	if token.is_empty():
		return token

	if token.is_valid_int():
		return token

	if COMMAND_VOCABULARY.has(token):
		return token

	if token.length() <= 3:
		return token

	var best_word := token
	var best_distance := 999

	for vocabulary_word in COMMAND_VOCABULARY:
		var candidate := String(vocabulary_word)

		if abs(candidate.length() - token.length()) > 2:
			continue

		var distance := _levenshtein_distance(token, candidate)

		if distance < best_distance:
			best_distance = distance
			best_word = candidate

	var allowed_distance := 1

	if token.length() >= 6:
		allowed_distance = 2

	if best_distance <= allowed_distance:
		return best_word

	return token


func _parse_who(text: String) -> Dictionary:
	var split_result := _split_exception_text(text)
	var include_text := String(split_result.get("include_text", text))
	var exclude_text := String(split_result.get("exclude_text", ""))
	var has_exception := bool(split_result.get("has_exception", false))

	var include_selectors := _extract_selectors(include_text, true)
	var exclude_selectors := _extract_selectors(exclude_text, false)

	if include_selectors.is_empty() and not has_exception:
		include_selectors = _extract_selectors(text, true)

	if include_selectors.is_empty():
		include_selectors = _extract_fuzzy_subject_selector(text)

	if include_selectors.is_empty():
		return {
			"ok": false,
			"who_type": "",
			"who_value": "",
			"unit": null,
			"who_selectors": [],
			"who_exclude_selectors": []
		}

	var primary_selector: Dictionary = include_selectors[0]

	return {
		"ok": true,
		"who_type": String(primary_selector.get("type", SELECTOR_EVERYONE)),
		"who_value": primary_selector.get("value", ""),
		"unit": null,
		"who_selectors": include_selectors,
		"who_exclude_selectors": exclude_selectors
	}
func _can_action_auto_select_subject(action_result: Dictionary) -> bool:
	return String(action_result.get("what", "")) == "interrupt"

func _default_auto_interrupt_who_result() -> Dictionary:
	var selectors: Array = [
		{
			"type": SELECTOR_EVERYONE,
			"value": ""
		}
	]

	return {
		"ok": true,
		"who_type": SELECTOR_EVERYONE,
		"who_value": "",
		"unit": null,
		"who_selectors": selectors,
		"who_exclude_selectors": [],
		"auto_selected_subject": true
	}
func _extract_fuzzy_subject_selector(text: String) -> Array:
	var subject_text := _get_subject_text_before_action(text)

	if subject_text.is_empty():
		return []

	var tokens := subject_text.split(" ", false)

	for token in tokens:
		var selector := _get_fuzzy_selector_for_subject_token(String(token))

		if not selector.is_empty():
			return [selector]

	return []


func _get_subject_text_before_action(text: String) -> String:
	var action_words := [
		"move", "moves", "moving", "go", "come", "rotate", "turn", "spread", "stack",
		"attack", "damage", "burn", "focus", "engage",
		"interrupt", "kick",
		"heal", "healing"
	]

	var best_index := -1
	var padded_text := " " + text.strip_edges() + " "

	for action_word in action_words:
		var action_word_text := String(action_word)
		var marker := " " + action_word_text + " "
		var index := padded_text.find(marker)

		if index == -1:
			continue

		if best_index == -1 or index < best_index:
			best_index = index

	if best_index == -1:
		return ""

	return padded_text.substr(0, best_index).strip_edges()
func _get_fuzzy_selector_for_subject_token(token: String) -> Dictionary:
	token = token.strip_edges()

	if token.is_empty():
		return {}
	if _is_range_like_token(token):
		return {}
	var healer_subject_aliases := [
		"dealer",
		"dealers",
		"steeler",
		"steelers",
		"pillar",
		"pillars",
		"killer",
		"killers"
	]

	if healer_subject_aliases.has(token):
		return {
			"type": SELECTOR_ROLE,
			"value": ROLE_HEALER
		}

	if healer_subject_aliases.has(token):
		return {
			"type": SELECTOR_ROLE,
			"value": ROLE_HEALER
		}

	var melee_subject_aliases := [
		"merely",
		"mainly",
		"mealy"
	]

	if melee_subject_aliases.has(token):
		return {
			"type": SELECTOR_ROLE,
			"value": ROLE_MELEE
		}

	var mage_subject_aliases := [
		"may",
		"maze",
		"maize",
		"mayes",
		"maids",
		"major",
		"majors"
	]

	if mage_subject_aliases.has(token):
		return {
			"type": SELECTOR_CLASS,
			"value": CLASS_MAGE
		}

	# selector_candidates continues below...
	var selector_candidates := [
		{"word": "warrior", "type": SELECTOR_CLASS, "value": CLASS_WARRIOR},
		{"word": "warriors", "type": SELECTOR_CLASS, "value": CLASS_WARRIOR},
		{"word": "rogue", "type": SELECTOR_CLASS, "value": CLASS_ROGUE},
		{"word": "rogues", "type": SELECTOR_CLASS, "value": CLASS_ROGUE},
		{"word": "mage", "type": SELECTOR_CLASS, "value": CLASS_MAGE},
		{"word": "mages", "type": SELECTOR_CLASS, "value": CLASS_MAGE},
		{"word": "priest", "type": SELECTOR_CLASS, "value": CLASS_PRIEST},
		{"word": "priests", "type": SELECTOR_CLASS, "value": CLASS_PRIEST},
		{"word": "healer", "type": SELECTOR_ROLE, "value": ROLE_HEALER},
		{"word": "healers", "type": SELECTOR_ROLE, "value": ROLE_HEALER},
		{"word": "caster", "type": SELECTOR_ROLE, "value": ROLE_CASTER},
		{"word": "casters", "type": SELECTOR_ROLE, "value": ROLE_CASTER},
		{"word": "melee", "type": SELECTOR_ROLE, "value": ROLE_MELEE},
		{"word": "ranged", "type": SELECTOR_ROLE, "value": ROLE_RANGED_DPS},
		{"word": "tank", "type": SELECTOR_ROLE, "value": ROLE_TANK},
		{"word": "tanks", "type": SELECTOR_ROLE, "value": ROLE_TANK_GROUP}
	]

	var best_candidate := {}
	var best_distance := 999

	for candidate in selector_candidates:
		var candidate_word := String(candidate["word"])

		if abs(candidate_word.length() - token.length()) > 3:
			continue

		var distance := _levenshtein_distance(token, candidate_word)

		if distance < best_distance:
			best_distance = distance
			best_candidate = candidate

	if best_candidate.is_empty():
		return {}

	var allowed_distance := 1

	if token.length() >= 5:
		allowed_distance = 2

	if best_distance > allowed_distance:
		return {}

	return {
		"type": String(best_candidate["type"]),
		"value": best_candidate["value"]
	}
func _is_range_like_token(token: String) -> bool:
	token = token.strip_edges()

	if token.is_empty():
		return false

	var range_aliases := [
		"close",
		"coast",
		"closed",
		"closer",
		"mid",
		"middle",
		"midrange",
		"far"
	]

	if range_aliases.has(token):
		return true

	var range_words := [
		"close",
		"mid",
		"middle",
		"far"
	]

	for range_word in range_words:
		if _levenshtein_distance(token, String(range_word)) <= 2:
			return true

	return false
func _split_exception_text(text: String) -> Dictionary:
	var markers := [
	" except ",
	" accepts ",
	" accept ",
	" excepts ",
	" excluding ",
	" without ",
	" but not "
	]

	var padded_text := " " + text.strip_edges() + " "
	var best_index := -1
	var best_marker := ""

	for marker in markers:
		var marker_index := padded_text.find(marker)

		if marker_index == -1:
			continue

		if best_index == -1 or marker_index < best_index:
			best_index = marker_index
			best_marker = marker

	if best_index == -1:
		return {
			"include_text": text,
			"exclude_text": "",
			"has_exception": false
		}

	return {
		"include_text": padded_text.substr(0, best_index).strip_edges(),
		"exclude_text": padded_text.substr(best_index + best_marker.length()).strip_edges(),
		"has_exception": true
	}


func _extract_selectors(text: String, allow_everyone: bool) -> Array:
	var selectors: Array = []
	var working := " " + text.strip_edges() + " "

	if allow_everyone:
		if _has_any_word(working, ["everyone", "everybody", "all", "raid"]):
			_add_selector(selectors, SELECTOR_EVERYONE, "")
			working = _remove_words(working, ["everyone", "everybody", "all", "raid"])

	working = _extract_group_selectors(working, selectors)
	working = _extract_unit_identity_selectors(working, selectors)
	working = _extract_role_and_class_selectors(working, selectors)

	return selectors


func _extract_group_selectors(working: String, selectors: Array) -> String:
	for group_number in range(1, 5):
		for number_alias in _number_aliases(group_number):
			var phrase := "group " + number_alias

			if _has_phrase(working, phrase):
				_add_selector(selectors, SELECTOR_GROUP, group_number)
				working = _remove_phrase(working, phrase)

	return working

func _extract_unit_identity_selectors(working: String, selectors: Array) -> String:
	var class_entries := [
		{"word": "warrior", "unit_class": CLASS_WARRIOR},
		{"word": "rogue", "unit_class": CLASS_ROGUE},
		{"word": "mage", "unit_class": CLASS_MAGE},
		{"word": "priest", "unit_class": CLASS_PRIEST}
	]

	for class_entry in class_entries:
		var class_word := String(class_entry["word"])
		var unit_class_name := String(class_entry["unit_class"])

		for unit_number in range(1, 11):
			for number_alias in _number_aliases(unit_number):
				var phrase := class_word + " " + number_alias

				if _has_phrase(working, phrase):
					_add_unit_identity_selector(selectors, unit_class_name, unit_number)
					working = _remove_phrase(working, phrase)

	return working

func _extract_role_and_class_selectors(working: String, selectors: Array) -> String:
	if _has_phrase(working, "melee dps"):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_MELEE_DPS)
		working = _remove_phrase(working, "melee dps")

	if _has_phrase(working, "ranged dps") or _has_phrase(working, "range dps"):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_RANGED_DPS)
		working = _remove_phrases(working, ["ranged dps", "range dps"])

	if _has_any_word(working, ["warrior", "warriors"]):
		_add_selector(selectors, SELECTOR_CLASS, CLASS_WARRIOR)
		working = _remove_words(working, ["warrior", "warriors"])

	if _has_any_word(working, ["rogue", "rogues"]):
		_add_selector(selectors, SELECTOR_CLASS, CLASS_ROGUE)
		working = _remove_words(working, ["rogue", "rogues"])

	if _has_any_word(working, ["mage", "mages"]):
		_add_selector(selectors, SELECTOR_CLASS, CLASS_MAGE)
		working = _remove_words(working, ["mage", "mages"])

	if _has_any_word(working, ["priest", "priests"]):
		_add_selector(selectors, SELECTOR_CLASS, CLASS_PRIEST)
		working = _remove_words(working, ["priest", "priests"])

	if _has_word(working, "offtank"):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_OFFTANK)
		working = _remove_word(working, "offtank")

	if _has_word(working, "tanks"):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_TANK_GROUP)
		working = _remove_word(working, "tanks")

	if _has_word(working, "tank"):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_TANK)
		working = _remove_word(working, "tank")

	if _has_any_word(working, ["healers", "healer"]):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_HEALER)
		working = _remove_words(working, ["healers", "healer"])

	if _has_word(working, "melee"):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_MELEE)
		working = _remove_word(working, "melee")

	if _has_word(working, "dps"):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_DPS)
		working = _remove_word(working, "dps")

	if _has_any_word(working, ["ranged", "range"]):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_RANGED_DPS)
		working = _remove_words(working, ["ranged", "range"])

	if _has_any_word(working, ["casters", "caster"]):
		_add_selector(selectors, SELECTOR_ROLE, ROLE_CASTER)
		working = _remove_words(working, ["casters", "caster"])

	return working


func _parse_action(text: String) -> Dictionary:
	if _contains_movement_intent(text):
		return _parse_movement_action(text)

	if _has_any_word(text, ["interrupt", "kick"]):
		return _action("interrupt", "boss", {})

	if _has_any_word(text, ["attack", "damage", "burn", "focus", "engage"]):
		return _action("attack", "boss", {})

	if _has_any_word(text, ["heal", "healing", "hill", "hills"]):
		return _action("heal", "boss_target", {})

	return {
		"ok": false,
		"what": "",
		"where": "none",
		"extra": {}
	}


func _contains_movement_intent(text: String) -> bool:
	if _has_any_word(text, ["move", "moves", "moving", "go", "come", "rotate", "turn", "spread", "stack"]):
		return true

	if _has_any_word(text, ["closer", "away", "clockwise", "counterclockwise", "anticlockwise"]):
		return true

	if _has_phrase(text, "on me") or _has_phrase(text, "to me"):
		return true

	if not _parse_region(text).is_empty():
		return true

	if not _parse_range(text).is_empty():
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

	if _has_word(text, "counterclockwise") or _has_word(text, "anticlockwise"):
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

	if _has_word(text, "moving"):
		return _action("move", "movement_range_step", {
			"movement_direction": "in"
		})

	return {
		"ok": false,
		"what": "",
		"where": "none",
		"extra": {}
	}


func _parse_region(text: String) -> String:
	var destination_text := _get_destination_text_after_action(text)

	if destination_text.is_empty():
		destination_text = text

	var tokens := destination_text.split(" ", false)

	for token_value in tokens:
		var token := String(token_value).strip_edges()

		if token.is_empty():
			continue

		if _is_range_like_token(token):
			continue

		if token == "northeast":
			return "northeast"

		if token == "northwest":
			return "northwest"

		if token == "southeast":
			return "southeast"

		if token == "southwest":
			return "southwest"

		if token == "north":
			return "north"

		if token == "south":
			return "south"

		if token == "east":
			return "east"

		if token == "west":
			return "west"

		var fuzzy_region := _get_fuzzy_region_for_token(token)

		if not fuzzy_region.is_empty():
			return fuzzy_region

	return ""
func _get_destination_text_after_action(text: String) -> String:
	var action_words: Array[String] = [
		"move", "moves", "moving", "go", "come", "rotate", "turn", "spread", "stack"
	]

	var padded_text := " " + text.strip_edges() + " "
	var best_index := -1
	var best_action_word := ""

	for action_word: String in action_words:
		var marker := " " + action_word + " "
		var index := padded_text.find(marker)

		if index == -1:
			continue

		if best_index == -1 or index < best_index:
			best_index = index
			best_action_word = action_word

	if best_index == -1:
		return ""

	var start_index := best_index + best_action_word.length() + 2

	if start_index >= padded_text.length():
		return ""

	return padded_text.substr(start_index).strip_edges()


func _parse_fuzzy_region(destination_text: String) -> String:
	var tokens := destination_text.split(" ", false)

	for token in tokens:
		var region := _get_fuzzy_region_for_token(String(token))

		if not region.is_empty():
			return region

	return ""


func _get_fuzzy_region_for_token(token: String) -> String:
	token = token.strip_edges()

	if token.is_empty():
		return ""

	if _is_range_like_token(token):
		return ""

	if token == "lust" or token == "list" or token == "less" or token == "lest":
		return "west"

	if token == "least":
		return "east"

	var region_words := [
		"north",
		"south",
		"east",
		"west",
		"northeast",
		"northwest",
		"southeast",
		"southwest"
	]

	var best_region := ""
	var best_distance := 999

	for region_word in region_words:
		var candidate := String(region_word)

		if abs(candidate.length() - token.length()) > 2:
			continue

		var distance := _levenshtein_distance(token, candidate)

		if distance < best_distance:
			best_distance = distance
			best_region = candidate

	if best_region.is_empty():
		return ""

	var allowed_distance := 1

	if token.length() >= 5:
		allowed_distance = 2

	if best_distance <= allowed_distance:
		return best_region

	return ""

func _parse_range(text: String) -> String:
	if _has_word(text, "close") or _has_word(text, "coast"):
		return "close"

	if _has_word(text, "mid") or _has_word(text, "middle") or _has_word(text, "midrange"):
		return "mid"

	if _has_word(text, "far"):
		return "far"

	return ""


func _add_selector(selectors: Array, selector_type: String, selector_value) -> void:
	var new_selector := {
		"type": selector_type,
		"value": selector_value
	}

	var new_key := _get_selector_key(new_selector)

	for selector in selectors:
		if selector is Dictionary and _get_selector_key(selector) == new_key:
			return

	selectors.append(new_selector)


func _add_unit_identity_selector(selectors: Array, unit_class_name: String, unit_number: int) -> void:
	var new_selector := {
		"type": SELECTOR_UNIT_IDENTITY,
		"value": unit_class_name + "_" + str(unit_number),
		"class": unit_class_name,
		"number": unit_number
	}

	var new_key := _get_selector_key(new_selector)

	for selector in selectors:
		if selector is Dictionary and _get_selector_key(selector) == new_key:
			return

	selectors.append(new_selector)


func _get_selector_key(selector: Dictionary) -> String:
	var selector_type := String(selector.get("type", ""))
	var selector_value := str(selector.get("value", ""))

	if selector_type == SELECTOR_UNIT_IDENTITY:
		return selector_type + ":" + String(selector.get("class", "")) + ":" + str(selector.get("number", 0))

	return selector_type + ":" + selector_value

func _number_aliases(value: int) -> Array[String]:
	var aliases: Array[String] = [str(value)]

	for word in NUMBER_WORDS.keys():
		if int(NUMBER_WORDS[word]) == value:
			aliases.append(String(word))

	return aliases


func _number_to_word(value: int) -> String:
	for word in NUMBER_WORDS.keys():
		if int(NUMBER_WORDS[word]) == value and not String(word).is_valid_int():
			return String(word)

	return str(value)

func _has_word(text: String, word: String) -> bool:
	var padded_text := " " + text.strip_edges() + " "
	var padded_word := " " + word.strip_edges() + " "

	return padded_text.contains(padded_word)


func _has_any_word(text: String, words: Array) -> bool:
	for word in words:
		if _has_word(text, String(word)):
			return true

	return false


func _has_phrase(text: String, phrase: String) -> bool:
	var padded_text := " " + text.strip_edges() + " "
	var padded_phrase := " " + phrase.strip_edges() + " "

	return padded_text.contains(padded_phrase)


func _remove_word(text: String, word: String) -> String:
	return _collapse_spaces((" " + text.strip_edges() + " ").replace(" " + word.strip_edges() + " ", " "))


func _remove_words(text: String, words: Array) -> String:
	var output := text

	for word in words:
		output = _remove_word(output, String(word))

	return output


func _remove_phrase(text: String, phrase: String) -> String:
	return _collapse_spaces((" " + text.strip_edges() + " ").replace(" " + phrase.strip_edges() + " ", " "))


func _remove_phrases(text: String, phrases: Array) -> String:
	var output := text

	for phrase in phrases:
		output = _remove_phrase(output, String(phrase))

	return output


func _collapse_spaces(text: String) -> String:
	var output := text.strip_edges()

	while output.contains("  "):
		output = output.replace("  ", " ")

	return output


func _levenshtein_distance(a: String, b: String) -> int:
	var previous_row: Array[int] = []
	var current_row: Array[int] = []

	for j in range(b.length() + 1):
		previous_row.append(j)

	for i in range(1, a.length() + 1):
		current_row.clear()
		current_row.append(i)

		for j in range(1, b.length() + 1):
			var insertion_cost := current_row[j - 1] + 1
			var deletion_cost := previous_row[j] + 1
			var substitution_cost := previous_row[j - 1]

			if a[i - 1] != b[j - 1]:
				substitution_cost += 1

			current_row.append(min(insertion_cost, min(deletion_cost, substitution_cost)))

		previous_row = current_row.duplicate()

	return previous_row[b.length()]


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
