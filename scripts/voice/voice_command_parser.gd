extends Node
class_name VoiceCommandParser

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

const NUMBER_WORDS := {
	"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
	"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
	"eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
	"fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
	"nineteen": 19, "twenty": 20
}

const ACTION_ALIASES := {
	CommandSchemaScript.ACTION_INTERRUPT: ["interrupt", "kick"],
	CommandSchemaScript.ACTION_TAUNT: ["taunt", "provoke"],
	CommandSchemaScript.ACTION_ATTACK: ["attack", "damage", "burn", "focus", "engage"],
	CommandSchemaScript.ACTION_HEAL: ["heal", "healing"],
	CommandSchemaScript.ACTION_MOVE: ["move", "moves", "moving", "go", "come", "rotate", "turn", "spread", "stack"]
}

const EXCEPTION_MARKERS: Array[String] = [
	" except ", " excluding ", " without ", " but not "
]


func parse(transcript: String) -> Dictionary:
	var normalized_text := _normalize_text(transcript)

	if normalized_text.is_empty():
		return _fail("Transcript is empty.", normalized_text, transcript)

	var action_result := _parse_action(normalized_text)

	if not bool(action_result.get("ok", false)):
		return _fail(String(action_result.get("reason", "No supported action was recognized.")), normalized_text, transcript)

	var action := String(action_result.get("what", ""))
	var subject_text := _get_subject_text(normalized_text, String(action_result.get("matched_alias", "")))
	var split_subject := _split_exception_text(subject_text)
	var include_selectors := _extract_selectors(String(split_subject.get("include_text", "")), true)
	var exclude_selectors := _extract_selectors(String(split_subject.get("exclude_text", "")), false)

	if include_selectors.is_empty():
		include_selectors = _default_selectors_for_action(action)

	if include_selectors.is_empty():
		include_selectors = _extract_fuzzy_subject_selector(String(split_subject.get("include_text", "")))

	if include_selectors.is_empty():
		return _fail("No raid member, class, group, or role was recognized.", normalized_text, transcript)

	var primary_selector: Dictionary = include_selectors[0]
	var command_data := {
		"who_type": String(primary_selector.get("type", CommandSchemaScript.SELECTOR_EVERYONE)),
		"who_value": primary_selector.get("value", ""),
		"unit": null,
		"who_selectors": include_selectors,
		"who_exclude_selectors": exclude_selectors,
		"what": action,
		"where": String(action_result.get("where", "")),
		"when": "now"
	}

	var extra: Dictionary = action_result.get("extra", {})

	for key in extra.keys():
		command_data[key] = extra[key]

	var validation_result := CommandSchemaScript.validate(command_data)

	if not bool(validation_result.get("ok", false)):
		return _fail(String(validation_result.get("reason", "Command validation failed.")), normalized_text, transcript)

	return {
		"ok": true,
		"command_data": command_data,
		"reason": "",
		"transcript": transcript,
		"normalized_text": normalized_text
	}


func _normalize_text(text: String) -> String:
	var normalized := text.to_lower().strip_edges()
	var punctuation: Array[String] = [".", ",", "!", "?", ":", ";", "\"", "'", "(", ")", "[", "]"]

	for character in punctuation:
		normalized = normalized.replace(character, " ")

	return _collapse_spaces(normalized)


func _parse_action(text: String) -> Dictionary:
	var matched_actions: Array[Dictionary] = []

	for action_value in ACTION_ALIASES.keys():
		var action := String(action_value)
		var matched_alias := _first_matching_alias(text, ACTION_ALIASES[action])

		if not matched_alias.is_empty():
			matched_actions.append({"action": action, "alias": matched_alias})

	if matched_actions.is_empty():
		return {"ok": false, "reason": "No supported action was recognized."}

	if matched_actions.size() > 1:
		return {"ok": false, "reason": "The transcript contains more than one action."}

	var match_data: Dictionary = matched_actions[0]
	var action := String(match_data.get("action", ""))
	var matched_alias := String(match_data.get("alias", ""))

	match action:
		CommandSchemaScript.ACTION_ATTACK, CommandSchemaScript.ACTION_INTERRUPT, CommandSchemaScript.ACTION_TAUNT:
			return _action(action, CommandSchemaScript.DESTINATION_BOSS, {}, matched_alias)

		CommandSchemaScript.ACTION_HEAL:
			return _action(action, CommandSchemaScript.DESTINATION_BOSS_TARGET, {}, matched_alias)

		CommandSchemaScript.ACTION_MOVE:
			return _parse_movement_action(text, matched_alias)

	return {"ok": false, "reason": "Unsupported action: " + action}


func _parse_movement_action(text: String, matched_alias: String) -> Dictionary:
	if _has_any_phrase(text, ["come to me", "to me", "on me", "stack on me"]):
		return _action("move", "me", {}, matched_alias)

	if _has_any_phrase(text, ["move out", "go out", "spread out"]) or _has_word(text, "away"):
		return _action("move", "movement_range_step", {"movement_direction": "out"}, matched_alias)

	if _has_any_phrase(text, ["move in", "go in", "come in"]) or _has_word(text, "closer"):
		return _action("move", "movement_range_step", {"movement_direction": "in"}, matched_alias)

	if _has_word(text, "counterclockwise") or _has_word(text, "anticlockwise"):
		return _action("move", "movement_rotate_step", {"movement_direction": "counterclockwise"}, matched_alias)

	if _has_word(text, "clockwise"):
		return _action("move", "movement_rotate_step", {"movement_direction": "clockwise"}, matched_alias)

	var destination_text := _text_after_alias(text, matched_alias)
	var region := _parse_region(destination_text)
	var range_name := _parse_range(destination_text)

	if not region.is_empty() and not range_name.is_empty():
		return _action("move", "movement_slot", {
			"movement_region": region,
			"movement_range": range_name
		}, matched_alias)

	if not region.is_empty() and matched_alias in ["rotate", "turn"]:
		return _action("move", "movement_rotate", {"movement_region": region}, matched_alias)

	if not region.is_empty():
		return _action("move", "movement_region", {"movement_region": region}, matched_alias)

	if not range_name.is_empty():
		return _action("move", "movement_range", {"movement_range": range_name}, matched_alias)

	return {"ok": false, "reason": "Movement command is missing a destination."}


func _get_subject_text(text: String, matched_alias: String) -> String:
	var padded := " " + text + " "
	var marker := " " + matched_alias + " "
	var action_index := padded.find(marker)

	if action_index == -1:
		return text

	var before_action := padded.substr(0, action_index).strip_edges()

	if not before_action.is_empty():
		return before_action

	var after_start := action_index + marker.length()
	return padded.substr(after_start).strip_edges()


func _split_exception_text(text: String) -> Dictionary:
	var padded := " " + text.strip_edges() + " "
	var best_index := -1
	var best_marker := ""

	for marker in EXCEPTION_MARKERS:
		var marker_index := padded.find(marker)

		if marker_index >= 0 and (best_index == -1 or marker_index < best_index):
			best_index = marker_index
			best_marker = marker

	if best_index == -1:
		return {"include_text": text, "exclude_text": ""}

	return {
		"include_text": padded.substr(0, best_index).strip_edges(),
		"exclude_text": padded.substr(best_index + best_marker.length()).strip_edges()
	}


func _extract_selectors(text: String, allow_everyone: bool) -> Array:
	var selectors: Array = []
	var working := " " + text.strip_edges() + " "

	if allow_everyone and _has_any_word(working, ["everyone", "everybody", "all", "raid"]):
		_add_selector(selectors, CommandSchemaScript.SELECTOR_EVERYONE, "")

	for group_number in range(1, ceili(float(GameState.MAX_RAID_SIZE) / 5.0) + 1):
		for number_alias in _number_aliases(group_number):
			if _has_phrase(working, "group " + number_alias):
				_add_selector(selectors, CommandSchemaScript.SELECTOR_GROUP, group_number)

	working = _extract_unit_identities(working, selectors)
	working = _extract_roles(working, selectors)
	_extract_classes(working, selectors)
	return selectors


func _extract_unit_identities(working: String, selectors: Array) -> String:
	for class_entry in GameState.get_voice_class_entries():
		var unit_class := String(class_entry.get("unit_class", ""))

		for alias_value in class_entry.get("aliases", []):
			var alias := String(alias_value)

			for unit_number in range(1, GameState.MAX_RAID_SIZE + 1):
				for number_alias in _number_aliases(unit_number):
					var phrase := alias + " " + number_alias

					if _has_phrase(working, phrase):
						_add_unit_identity_selector(selectors, unit_class, unit_number)
						working = _remove_phrase(working, phrase)

	return working


func _extract_roles(working: String, selectors: Array) -> String:
	var candidates: Array[Dictionary] = []

	for role_data in GameState.get_role_options():
		var role_name := String(role_data.get("role", ""))

		for alias_value in role_data.get("aliases", []):
			candidates.append({"alias": String(alias_value), "role": role_name})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		return String(a.get("alias", "")).length() > String(b.get("alias", "")).length()
	)

	for candidate in candidates:
		var alias := String(candidate.get("alias", ""))

		if _has_phrase(working, alias):
			_add_selector(
				selectors,
				CommandSchemaScript.SELECTOR_ROLE,
				String(candidate.get("role", ""))
			)
			working = _remove_phrase(working, alias)

	return working


func _extract_classes(working: String, selectors: Array) -> void:
	for class_entry in GameState.get_voice_class_entries():
		for alias_value in class_entry.get("aliases", []):
			if _has_word(working, String(alias_value)):
				_add_selector(
					selectors,
					CommandSchemaScript.SELECTOR_CLASS,
					String(class_entry.get("unit_class", ""))
				)
				break


func _default_selectors_for_action(action: String) -> Array:
	if action == CommandSchemaScript.ACTION_INTERRUPT:
		return [{"type": CommandSchemaScript.SELECTOR_EVERYONE, "value": ""}]

	if action == CommandSchemaScript.ACTION_TAUNT:
		return [{"type": CommandSchemaScript.SELECTOR_ROLE, "value": "tank"}]

	return []


func _extract_fuzzy_subject_selector(text: String) -> Array:
	var candidates: Array[Dictionary] = []

	for class_entry in GameState.get_voice_class_entries():
		for alias_value in class_entry.get("aliases", []):
			candidates.append({
				"word": String(alias_value),
				"type": CommandSchemaScript.SELECTOR_CLASS,
				"value": String(class_entry.get("unit_class", ""))
			})

	for role_data in GameState.get_role_options():
		for alias_value in role_data.get("aliases", []):
			candidates.append({
				"word": String(alias_value),
				"type": CommandSchemaScript.SELECTOR_ROLE,
				"value": String(role_data.get("role", ""))
			})

	for token_value in text.split(" ", false):
		var match_data := _best_fuzzy_match(String(token_value), candidates, 2)

		if not match_data.is_empty():
			return [{"type": match_data["type"], "value": match_data["value"]}]

	return []


func _parse_region(text: String) -> String:
	var candidates: Array[Dictionary] = []

	for region_value in MovementSlotResolverScript.REGION_ORDER:
		var region := String(region_value)

		if _has_word(text, region):
			return region

		candidates.append({"word": region, "value": region})

	for token_value in text.split(" ", false):
		var match_data := _best_fuzzy_match(String(token_value), candidates, 1)

		if not match_data.is_empty():
			return String(match_data.get("value", ""))

	return ""


func _parse_range(text: String) -> String:
	if _has_word(text, "close"):
		return MovementSlotResolverScript.RANGE_CLOSE

	if _has_any_word(text, ["mid", "middle", "midrange"]):
		return MovementSlotResolverScript.RANGE_MID

	if _has_word(text, "far"):
		return MovementSlotResolverScript.RANGE_FAR

	return ""


func _best_fuzzy_match(token: String, candidates: Array[Dictionary], max_distance: int) -> Dictionary:
	if token.length() < 4:
		return {}

	var best: Dictionary = {}
	var best_distance := 999
	var second_distance := 999

	for candidate in candidates:
		var word := String(candidate.get("word", ""))

		if word.contains(" ") or abs(word.length() - token.length()) > max_distance:
			continue

		var distance := _levenshtein_distance(token, word)

		if distance < best_distance:
			second_distance = best_distance
			best_distance = distance
			best = candidate
		elif distance < second_distance:
			second_distance = distance

	if best_distance > max_distance or best_distance == second_distance:
		return {}

	return best


func _add_selector(selectors: Array, selector_type: String, selector_value: Variant) -> void:
	var selector := {"type": selector_type, "value": selector_value}
	var key := selector_type + ":" + str(selector_value)

	for existing in selectors:
		if String(existing.get("type", "")) + ":" + str(existing.get("value", "")) == key:
			return

	selectors.append(selector)


func _add_unit_identity_selector(selectors: Array, unit_class: String, unit_number: int) -> void:
	var key := "unit_identity:" + unit_class + ":" + str(unit_number)

	for existing in selectors:
		if (
			String(existing.get("type", ""))
			+ ":" + String(existing.get("class", ""))
			+ ":" + str(existing.get("number", 0))
		) == key:
			return

	selectors.append({
		"type": CommandSchemaScript.SELECTOR_UNIT_IDENTITY,
		"value": unit_class + "_" + str(unit_number),
		"class": unit_class,
		"number": unit_number
	})


func _number_aliases(value: int) -> Array[String]:
	var aliases: Array[String] = [str(value)]

	for word_value in NUMBER_WORDS.keys():
		if int(NUMBER_WORDS[word_value]) == value:
			aliases.append(String(word_value))

	return aliases


func _first_matching_alias(text: String, aliases: Array) -> String:
	for alias_value in aliases:
		var alias := String(alias_value)

		if _has_word(text, alias):
			return alias

	return ""


func _text_after_alias(text: String, alias: String) -> String:
	var padded := " " + text + " "
	var marker := " " + alias + " "
	var index := padded.find(marker)

	if index == -1:
		return text

	return padded.substr(index + marker.length()).strip_edges()


func _has_word(text: String, word: String) -> bool:
	return (" " + text.strip_edges() + " ").contains(" " + word.strip_edges() + " ")


func _has_any_word(text: String, words: Array) -> bool:
	for word_value in words:
		if _has_word(text, String(word_value)):
			return true

	return false


func _has_phrase(text: String, phrase: String) -> bool:
	return (" " + text.strip_edges() + " ").contains(" " + phrase.strip_edges() + " ")


func _has_any_phrase(text: String, phrases: Array) -> bool:
	for phrase_value in phrases:
		if _has_phrase(text, String(phrase_value)):
			return true

	return false


func _remove_phrase(text: String, phrase: String) -> String:
	return _collapse_spaces((" " + text.strip_edges() + " ").replace(" " + phrase.strip_edges() + " ", " "))


func _collapse_spaces(text: String) -> String:
	var output := text.strip_edges()

	while output.contains("  "):
		output = output.replace("  ", " ")

	return output


func _levenshtein_distance(a: String, b: String) -> int:
	var previous_row: Array[int] = []
	var current_row: Array[int] = []

	for column in range(b.length() + 1):
		previous_row.append(column)

	for row in range(1, a.length() + 1):
		current_row.clear()
		current_row.append(row)

		for column in range(1, b.length() + 1):
			var insertion := current_row[column - 1] + 1
			var deletion := previous_row[column] + 1
			var substitution := previous_row[column - 1]

			if a[row - 1] != b[column - 1]:
				substitution += 1

			current_row.append(mini(insertion, mini(deletion, substitution)))

		previous_row = current_row.duplicate()

	return previous_row[b.length()]


func _action(
	what: String,
	where: String,
	extra: Dictionary,
	matched_alias: String
) -> Dictionary:
	return {
		"ok": true,
		"what": what,
		"where": where,
		"extra": extra,
		"matched_alias": matched_alias
	}


func _fail(reason: String, normalized_text: String, transcript: String) -> Dictionary:
	return {
		"ok": false,
		"command_data": {},
		"reason": reason,
		"transcript": transcript,
		"normalized_text": normalized_text
	}
