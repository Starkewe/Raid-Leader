extends Node
class_name VoiceCommandParser

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const JointCommandDecoderScript := preload("res://scripts/voice/joint_command_decoder.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const VocabularyScript := preload("res://scripts/voice/voice_command_vocabulary.gd")
const WhoTargetResolverScript := preload("res://scripts/voice/who_target_resolver.gd")

const ACTION_ALIASES := VocabularyScript.ACTION_ALIASES

const EXCEPTION_MARKERS: Array[String] = [
	" except ", " excluding ", " without ", " but not "
]

@export var debug_who_resolution: bool = false
@export var debug_command_decoding: bool = false

var who_resolver: WhoTargetResolver = WhoTargetResolverScript.new()
var joint_decoder: JointCommandDecoder = JointCommandDecoderScript.new()


func setup_roster_context(party_members: Array) -> void:
	who_resolver.debug_enabled = debug_who_resolution
	who_resolver.setup(party_members)
	joint_decoder.debug_enabled = debug_command_decoding
	joint_decoder.setup(who_resolver)


func rebuild_who_candidate_cache() -> void:
	who_resolver.rebuild_candidate_cache()
	joint_decoder.rebuild_vocabulary_cache()


func get_who_resolver() -> WhoTargetResolver:
	return who_resolver


func parse(transcript: String) -> Dictionary:
	var normalized_text := _normalize_text(transcript)
	var healing_input := _extract_healing_scope_suffix(normalized_text)
	var scope_found := bool(healing_input.get("found", false))
	var healing_scope: Dictionary = healing_input.get("scope", {})
	var command_text := (
		String(healing_input.get("command_text", normalized_text))
		if scope_found
		else normalized_text
	)
	var result := _parse_command_text(command_text, healing_scope)

	if (
		scope_found
		and bool(result.get("ok", false))
		and String(Dictionary(result.get("command_data", {})).get("what", ""))
			!= CommandSchemaScript.ACTION_HEAL
	):
		result = _parse_command_text(normalized_text, {})

	if not bool(result.get("ok", false)):
		if _contains_explicit_heal_action(command_text):
			var failure_reason := (
				"Everyone is not a valid healing target."
				if String(healing_scope.get("type", ""))
					== CommandSchemaScript.SELECTOR_EVERYONE
				else "Heal requires an explicit target."
			)
			return _fail(
				failure_reason,
				normalized_text,
				transcript,
				Dictionary(result.get("who_resolution", {}))
			)

		result["transcript"] = transcript
		result["normalized_text"] = normalized_text
		return result

	var command_data: Dictionary = result.get("command_data", {})

	if String(command_data.get("what", "")) == CommandSchemaScript.ACTION_HEAL:
		if not scope_found or healing_scope.is_empty():
			return _fail(
				"Heal requires an explicit target.",
				normalized_text,
				transcript,
				Dictionary(result.get("who_resolution", {}))
			)

		var target_validation := _validate_healing_scope_target(healing_scope)

		if not bool(target_validation.get("ok", false)):
			return _fail(
				String(target_validation.get("reason", "Invalid healing target.")),
				normalized_text,
				transcript,
				Dictionary(result.get("who_resolution", {}))
			)

	result["transcript"] = transcript
	result["normalized_text"] = normalized_text
	return result


func _parse_command_text(
	transcript: String,
	healing_scope: Dictionary = {}
) -> Dictionary:
	var deterministic_started := Time.get_ticks_usec()
	var deterministic_result := _parse_deterministic(transcript, healing_scope)
	var deterministic_duration := Time.get_ticks_usec() - deterministic_started
	var normalized_text := String(deterministic_result.get(
		"normalized_text",
		_normalize_text(transcript)
	))

	if bool(deterministic_result.get("ok", false)):
		var who_resolution: Dictionary = deterministic_result.get("who_resolution", {})
		var default_reason := ""

		if String(who_resolution.get("method", "")) == "deterministic_action_default":
			var action := String(
				Dictionary(deterministic_result.get("command_data", {})).get("what", "")
			)
			default_reason = String(
				VocabularyScript.get_default_selector_for_action(action).get("reason", "")
			)

		var command_resolution := joint_decoder.build_deterministic_resolution(
			transcript,
			normalized_text,
			Dictionary(deterministic_result.get("command_data", {})),
			who_resolution,
			deterministic_duration,
			default_reason
		)
		deterministic_result["command_resolution"] = command_resolution
		who_resolution["command_method"] = "deterministic"
		deterministic_result["who_resolution"] = who_resolution
		return deterministic_result

	return joint_decoder.decode(
		transcript,
		normalized_text,
		{
			"reason": String(deterministic_result.get("reason", "")),
			"duration_usec": deterministic_duration,
			"healing_scope": healing_scope.duplicate(true),
			"who_resolution": Dictionary(
				deterministic_result.get("who_resolution", {})
			).duplicate(true)
		}
	)


func _parse_deterministic(
	transcript: String,
	healing_scope: Dictionary = {}
) -> Dictionary:
	var normalized_text := _normalize_text(transcript)

	if normalized_text.is_empty():
		return _fail("Transcript is empty.", normalized_text, transcript)

	var action_result := _parse_action(normalized_text)

	if not bool(action_result.get("ok", false)):
		return _fail(String(action_result.get("reason", "No supported action was recognized.")), normalized_text, transcript)

	var action := String(action_result.get("what", ""))
	var subject_text := _get_subject_text(normalized_text, String(action_result.get("matched_alias", "")))
	var split_subject := _split_exception_text(subject_text)
	var include_text := String(split_subject.get("include_text", ""))
	var exclude_text := String(split_subject.get("exclude_text", ""))
	var who_started_usec := Time.get_ticks_usec()
	var include_selectors := _extract_selectors(include_text, true)
	var exclude_selectors := _extract_selectors(String(split_subject.get("exclude_text", "")), false)
	var who_resolution: Dictionary = {}

	if not include_selectors.is_empty():
		var selector_validation := who_resolver.validate_deterministic_selectors(include_selectors)

		if not bool(selector_validation.get("ok", false)):
			who_resolution = who_resolver.build_deterministic_result(
				transcript,
				normalized_text,
				include_text,
				include_selectors,
				Time.get_ticks_usec() - who_started_usec
			)
			who_resolution["ok"] = false
			who_resolution["reason"] = String(
				selector_validation.get("reason", "The requested Who target is not available.")
			)
			who_resolution["debug_text"] = who_resolver.format_diagnostics(who_resolution)
			return _fail(
				String(who_resolution["reason"]),
				normalized_text,
				transcript,
				who_resolution
			)

		who_resolution = who_resolver.build_deterministic_result(
			transcript,
			normalized_text,
			include_text,
			include_selectors,
			Time.get_ticks_usec() - who_started_usec
		)

	if include_selectors.is_empty() and not include_text.is_empty():
		return _fail(
			"The explicit Who span was not recognized deterministically.",
			normalized_text,
			transcript,
			who_resolution
		)

	if include_selectors.is_empty():
		include_selectors = _default_selectors_for_action(action)

		if not include_selectors.is_empty():
			who_resolution = who_resolver.build_deterministic_result(
				transcript,
				normalized_text,
				include_text,
				include_selectors,
				Time.get_ticks_usec() - who_started_usec,
				"deterministic_action_default"
			)

	if include_selectors.is_empty():
		include_selectors = _extract_fuzzy_subject_selector(include_text)

		if not include_selectors.is_empty():
			who_resolution = who_resolver.build_deterministic_result(
				transcript,
				normalized_text,
				include_text,
				include_selectors,
				Time.get_ticks_usec() - who_started_usec,
				"legacy_fuzzy_no_roster"
			)

	if include_selectors.is_empty():
		return _fail(
			"No raid member, class, group, or role was recognized.",
			normalized_text,
			transcript,
			who_resolution
		)

	var exclusion_validation := who_resolver.validate_deterministic_selectors(exclude_selectors)

	if not exclude_text.is_empty() and not bool(exclusion_validation.get("ok", false)):
		return _fail(
			String(exclusion_validation.get("reason", "An excluded Who target is not available.")),
			normalized_text,
			transcript,
			who_resolution
		)

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

	if action == CommandSchemaScript.ACTION_HEAL and not healing_scope.is_empty():
		command_data["healing_scope"] = healing_scope.duplicate(true)

	var validation_result := CommandSchemaScript.validate(command_data)

	if not bool(validation_result.get("ok", false)):
		return _fail(String(validation_result.get("reason", "Command validation failed.")), normalized_text, transcript)

	return {
		"ok": true,
		"command_data": command_data,
		"reason": "",
		"transcript": transcript,
		"normalized_text": normalized_text,
		"who_resolution": who_resolution
	}


func _normalize_text(text: String) -> String:
	var normalized := text.to_lower().strip_edges()
	var punctuation: Array[String] = [
		".", ",", "!", "?", ":", ";", "\"", "'", "(", ")", "[", "]",
		"-", "‐", "‑", "‒", "–", "—"
	]

	for character in punctuation:
		normalized = normalized.replace(character, " ")

	return _collapse_spaces(normalized)


func _extract_healing_scope_suffix(text: String) -> Dictionary:
	var working := text.strip_edges()
	var has_explicit_now := working.ends_with(" now")

	if has_explicit_now:
		working = working.trim_suffix(" now").strip_edges()

	for special in [
		{
			"phrases": ["the active tanks", "the active tank", "active tanks", "active tank"],
			"type": CommandSchemaScript.HEAL_SCOPE_ACTIVE_TANK
		},
		{
			"phrases": ["the raid", "raid"],
			"type": CommandSchemaScript.HEAL_SCOPE_RAID
		}
	]:
		for phrase_value in special.get("phrases", []):
			var special_result := _healing_scope_suffix_result(
				working,
				String(phrase_value),
				{"type": String(special.get("type", ""))},
				has_explicit_now
			)

			if bool(special_result.get("found", false)):
				return special_result

	for group_number in range(1, ceili(float(GameState.MAX_RAID_SIZE) / 5.0) + 1):
		for number_alias in _number_aliases(group_number):
			for group_word in ["group", "row"]:
				var group_result := _healing_scope_suffix_result(
					working,
					group_word + " " + number_alias,
					{
						"type": CommandSchemaScript.SELECTOR_GROUP,
						"value": group_number
					},
					has_explicit_now
				)

				if bool(group_result.get("found", false)):
					return group_result

	for class_entry in GameState.get_voice_class_entries():
		var unit_class := String(class_entry.get("unit_class", ""))

		for alias_value in class_entry.get("aliases", []):
			var alias := String(alias_value)

			for unit_number in range(1, GameState.MAX_RAID_SIZE + 1):
				for number_alias in _number_aliases(unit_number):
					var unit_result := _healing_scope_suffix_result(
						working,
						alias + " " + number_alias,
						{
							"type": CommandSchemaScript.SELECTOR_UNIT_IDENTITY,
							"value": unit_class + "_" + str(unit_number),
							"class": unit_class,
							"number": unit_number
						},
						has_explicit_now
					)

					if bool(unit_result.get("found", false)):
						return unit_result

	for class_entry in GameState.get_voice_class_entries():
		var unit_class := String(class_entry.get("unit_class", ""))

		for alias_value in class_entry.get("aliases", []):
			var class_result := _healing_scope_suffix_result(
				working,
				String(alias_value),
				{
					"type": CommandSchemaScript.SELECTOR_CLASS,
					"value": unit_class
				},
				has_explicit_now
			)

			if bool(class_result.get("found", false)):
				return class_result

	for invalid_everyone in ["everyone", "everybody", "all"]:
		var invalid_result := _healing_scope_suffix_result(
			working,
			invalid_everyone,
			{
				"type": CommandSchemaScript.SELECTOR_EVERYONE,
				"value": ""
			},
			has_explicit_now
		)

		if bool(invalid_result.get("found", false)):
			return invalid_result

	return {"found": false, "command_text": text, "scope": {}}


func _healing_scope_suffix_result(
	text: String,
	suffix: String,
	scope: Dictionary,
	has_explicit_now: bool
) -> Dictionary:
	if text != suffix and not text.ends_with(" " + suffix):
		return {"found": false}

	var command_text := text.trim_suffix(suffix).strip_edges()

	if has_explicit_now:
		command_text += " now"

	return {
		"found": true,
		"command_text": command_text.strip_edges(),
		"scope": scope.duplicate(true)
	}


func _validate_healing_scope_target(scope: Dictionary) -> Dictionary:
	var scope_type := String(scope.get("type", ""))

	if scope_type == CommandSchemaScript.SELECTOR_EVERYONE:
		return {
			"ok": false,
			"reason": "Everyone is not a valid healing target."
		}

	if scope_type in [
		CommandSchemaScript.HEAL_SCOPE_ACTIVE_TANK,
		CommandSchemaScript.HEAL_SCOPE_RAID
	]:
		return {"ok": true, "reason": ""}

	if not CommandSchemaScript.HEAL_SCOPE_SELECTOR_TYPES.has(scope_type):
		return {"ok": false, "reason": "Unsupported healing target."}

	return who_resolver.validate_deterministic_selectors([scope])


func _contains_explicit_heal_action(text: String) -> bool:
	return not _first_matching_alias(
		text,
		ACTION_ALIASES[CommandSchemaScript.ACTION_HEAL]
	).is_empty()


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
			if not _has_only_supported_when_after_action(text, matched_alias):
				return {
					"ok": false,
					"reason": "The action contains an unsupported destination or trailing phrase."
				}
			return _action(action, CommandSchemaScript.DESTINATION_BOSS, {}, matched_alias)

		CommandSchemaScript.ACTION_HEAL:
			if not _has_only_supported_when_after_action(text, matched_alias):
				return {
					"ok": false,
					"reason": "The action contains an unsupported destination or trailing phrase."
				}
			return _action(
				action,
				CommandSchemaScript.DESTINATION_HEALING_SCOPE,
				{},
				matched_alias
			)

		CommandSchemaScript.ACTION_CURE:
			if not _has_only_supported_when_after_action(text, matched_alias):
				return {
					"ok": false,
					"reason": "The action contains an unsupported destination or trailing phrase."
				}
			return _action(action, CommandSchemaScript.DESTINATION_CURABLE_ALLIES, {}, matched_alias)

		CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE:
			return _parse_movement_action(text, matched_alias, action)

	return {"ok": false, "reason": "Unsupported action: " + action}


func _has_only_supported_when_after_action(text: String, matched_alias: String) -> bool:
	var trailing := _text_after_alias(text, matched_alias)
	return trailing.is_empty() or trailing == "now"


func _parse_movement_action(
	text: String,
	matched_alias: String,
	movement_action: String = CommandSchemaScript.ACTION_MOVE
) -> Dictionary:
	var destination_text := _text_after_alias(text, matched_alias)

	if destination_text.ends_with(" now"):
		destination_text = destination_text.trim_suffix(" now").strip_edges()

	if _has_any_phrase(
		destination_text,
		["to me", "on me", "to player", "to the player"]
	):
		return _action(movement_action, "me", {}, matched_alias)

	if destination_text in ["out", "away"]:
		return _action(movement_action, "movement_range_step", {"movement_direction": "out"}, matched_alias)

	if destination_text in ["in", "closer"]:
		return _action(movement_action, "movement_range_step", {"movement_direction": "in"}, matched_alias)

	if destination_text in [
		"counterclockwise",
		"anticlockwise",
		"one step counterclockwise",
		"one step anticlockwise",
		"step counterclockwise",
		"step anticlockwise"
	]:
		return _action(movement_action, "movement_rotate_step", {"movement_direction": "counterclockwise"}, matched_alias)

	if destination_text in ["clockwise", "one step clockwise", "step clockwise"]:
		return _action(movement_action, "movement_rotate_step", {"movement_direction": "clockwise"}, matched_alias)

	var region := _parse_region(destination_text)
	var range_name := _parse_range(destination_text)

	if not region.is_empty() and not range_name.is_empty():
		if destination_text.split(" ", false).size() != 2:
			return {"ok": false, "reason": "Movement destination contains an unresolved span."}

		return _action(movement_action, "movement_slot", {
			"movement_region": region,
			"movement_range": range_name
		}, matched_alias)

	if not region.is_empty() and matched_alias in ["rotate", "turn"]:
		if destination_text.split(" ", false).size() != 1:
			return {"ok": false, "reason": "Rotation destination contains an unresolved span."}

		return _action(movement_action, "movement_rotate", {"movement_region": region}, matched_alias)

	if not region.is_empty():
		if destination_text.split(" ", false).size() != 1:
			return {"ok": false, "reason": "Movement destination contains an unresolved span."}

		return _action(movement_action, "movement_region", {"movement_region": region}, matched_alias)

	if not range_name.is_empty():
		if destination_text.split(" ", false).size() != 1:
			return {"ok": false, "reason": "Movement destination contains an unresolved span."}

		return _action(movement_action, "movement_range", {"movement_range": range_name}, matched_alias)

	return {"ok": false, "reason": "Movement command is missing a destination."}


func _get_subject_text(text: String, matched_alias: String) -> String:
	var padded := " " + text + " "
	var marker := " " + matched_alias + " "
	var action_index := padded.find(marker)

	if action_index == -1:
		return text

	return padded.substr(0, action_index).strip_edges()


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
			if (
				_has_phrase(working, "group " + number_alias)
				or _has_phrase(working, "row " + number_alias)
			):
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
	var default_data := VocabularyScript.get_default_selector_for_action(action)

	if default_data.is_empty():
		return []

	return [Dictionary(default_data.get("selector", {})).duplicate(true)]


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
	return VocabularyScript.get_target_number_aliases(value)


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


func _fail(
	reason: String,
	normalized_text: String,
	transcript: String,
	who_resolution: Dictionary = {}
) -> Dictionary:
	return {
		"ok": false,
		"command_data": {},
		"reason": reason,
		"transcript": transcript,
		"normalized_text": normalized_text,
		"who_resolution": who_resolution
	}
