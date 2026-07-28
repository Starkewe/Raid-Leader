extends RefCounted
class_name WhoTargetResolver

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const TuningScript := preload("res://scripts/voice/who_resolver_tuning.gd")

const GROUP_SIZE: int = 5
const NUMBER_WORDS := {
	"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
	"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
	"eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
	"fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
	"nineteen": 19, "twenty": 20
}
const FILLER_WORDS: Array[String] = [
	"a", "an", "can", "could", "hey", "please", "the", "you"
]

var debug_enabled: bool = false
var party_members: Array = []
var candidate_cache: Array[Dictionary] = []
var cache_generation: int = 0
var recent_target_keys: Array[String] = []


func setup(new_party_members: Array) -> void:
	party_members = new_party_members.duplicate()
	rebuild_candidate_cache()


func has_roster_context() -> bool:
	return not party_members.is_empty()


func rebuild_candidate_cache() -> void:
	candidate_cache.clear()
	cache_generation += 1

	if party_members.is_empty():
		return

	_add_everyone_candidate()
	_add_class_candidates()
	_add_role_candidates()
	_add_row_candidates()
	_add_numbered_individual_candidates()


func resolve_who(
	raw_transcript: String,
	normalized_transcript: String,
	who_text: String,
	command_context: Dictionary = {}
) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var normalized_who := _normalize_text(who_text)
	var number_result := _extract_requested_number(normalized_who)
	var inferred_structure := _infer_structure(normalized_who, number_result)

	if bool(number_result.get("ambiguous", false)):
		return _failure_result(
			raw_transcript,
			normalized_transcript,
			normalized_who,
			inferred_structure,
			"Who contains conflicting target numbers.",
			started_usec
		)

	var valid_candidates: Array[Dictionary] = []

	for cached_candidate in candidate_cache:
		var candidate: Dictionary = cached_candidate

		if _candidate_is_commandable(candidate):
			valid_candidates.append(candidate)

	if valid_candidates.is_empty():
		return _failure_result(
			raw_transcript,
			normalized_transcript,
			normalized_who,
			inferred_structure,
			"No valid current Who targets are available.",
			started_usec
		)

	var requested_number := int(number_result.get("value", 0))

	if inferred_structure == "row":
		var row_candidates: Array[Dictionary] = []

		for candidate in valid_candidates:
			if String(candidate.get("target_type", "")) == "row":
				row_candidates.append(candidate)

		if requested_number > 0 and not _has_numbered_candidate(row_candidates, requested_number):
			return _failure_result(
				raw_transcript,
				normalized_transcript,
				normalized_who,
				inferred_structure,
				"No current raid-frame row matches %d." % requested_number,
				started_usec
			)

		valid_candidates = row_candidates

	if requested_number > 0 and not _has_numbered_candidate(valid_candidates, requested_number):
		return _failure_result(
			raw_transcript,
			normalized_transcript,
			normalized_who,
			inferred_structure,
			"No current numbered individual or row matches %d." % requested_number,
			started_usec
		)

	var lexical_text := _get_lexical_text(normalized_who, number_result)
	var plural_evidence := _has_plural_evidence(lexical_text)
	var scored_candidates: Array[Dictionary] = []

	for candidate in valid_candidates:
		var candidate_number := int(candidate.get("number", 0))

		if requested_number > 0 and candidate_number > 0 and candidate_number != requested_number:
			continue

		scored_candidates.append(
			_score_candidate(
				candidate,
				lexical_text,
				inferred_structure,
				requested_number,
				plural_evidence,
				command_context
			)
		)

	if scored_candidates.is_empty():
		return _failure_result(
			raw_transcript,
			normalized_transcript,
			normalized_who,
			inferred_structure,
			"No valid Who candidates remained after structural filtering.",
			started_usec
		)

	scored_candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_score := float(a.get("final_score", 0.0))
		var b_score := float(b.get("final_score", 0.0))

		if is_equal_approx(a_score, b_score):
			return String(a.get("canonical_id", "")) < String(b.get("canonical_id", ""))

		return a_score > b_score
	)

	var selected: Dictionary = scored_candidates[0]
	var duration_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var result := {
		"ok": true,
		"method": "weighted_phonetic",
		"raw_transcript": raw_transcript,
		"normalized_transcript": normalized_transcript,
		"who_text": normalized_who,
		"inferred_structure": inferred_structure,
		"selector": Dictionary(selected.get("selector", {})).duplicate(true),
		"canonical_id": String(selected.get("canonical_id", "")),
		"canonical_target_ids": Array(selected.get("canonical_target_ids", [])).duplicate(),
		"display_label": String(selected.get("display_label", "")),
		"final_score": float(selected.get("final_score", 0.0)),
		"candidate_scores": scored_candidates,
		"duration_ms": duration_ms,
		"cache_generation": cache_generation,
		"reason": ""
	}
	result["debug_text"] = format_diagnostics(result)
	_record_target_key(String(selected.get("key", "")))

	if debug_enabled:
		print(String(result["debug_text"]))

	return result


func build_deterministic_result(
	raw_transcript: String,
	normalized_transcript: String,
	who_text: String,
	selectors: Array,
	duration_usec: int,
	method: String = "deterministic"
) -> Dictionary:
	var selected_candidate: Dictionary = {}

	if not selectors.is_empty() and selectors[0] is Dictionary:
		selected_candidate = _find_candidate_for_selector(selectors[0])

	var canonical_id := (
		String(selected_candidate.get("canonical_id", ""))
		if not selected_candidate.is_empty()
		else _canonical_id_for_selector(selectors[0] if not selectors.is_empty() else {})
	)
	var display_label := (
		String(selected_candidate.get("display_label", ""))
		if not selected_candidate.is_empty()
		else canonical_id
	)
	var target_ids: Array = (
		Array(selected_candidate.get("canonical_target_ids", [])).duplicate()
		if not selected_candidate.is_empty()
		else []
	)
	var result := {
		"ok": not selectors.is_empty(),
		"method": method,
		"raw_transcript": raw_transcript,
		"normalized_transcript": normalized_transcript,
		"who_text": _normalize_text(who_text),
		"inferred_structure": _infer_structure(
			_normalize_text(who_text),
			_extract_requested_number(_normalize_text(who_text))
		),
		"selector": Dictionary(selectors[0]).duplicate(true) if not selectors.is_empty() else {},
		"canonical_id": canonical_id,
		"canonical_target_ids": target_ids,
		"display_label": display_label,
		"final_score": 1.0,
		"candidate_scores": [],
		"duration_ms": float(duration_usec) / 1000.0,
		"cache_generation": cache_generation,
		"reason": ""
	}
	result["debug_text"] = format_diagnostics(result)

	if not selected_candidate.is_empty():
		_record_target_key(String(selected_candidate.get("key", "")))

	if debug_enabled:
		print(String(result["debug_text"]))

	return result


func validate_deterministic_selectors(selectors: Array) -> Dictionary:
	if not has_roster_context():
		return {"ok": true, "reason": ""}

	for selector_value in selectors:
		if not selector_value is Dictionary:
			return {"ok": false, "reason": "Who selector is not canonical."}

		var selector: Dictionary = selector_value

		if String(selector.get("type", "")) == CommandSchemaScript.SELECTOR_UNIT:
			var unit_value = selector.get("unit", null)

			if unit_value is Node and _unit_is_commandable(unit_value):
				continue

		if _find_candidate_for_selector(selector).is_empty():
			return {
				"ok": false,
				"reason": "The requested Who target does not exist in the current raid."
			}

	return {"ok": true, "reason": ""}


func get_cache_generation() -> int:
	return cache_generation


func get_candidate_cache_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []

	for candidate in candidate_cache:
		var copied := candidate.duplicate(true)
		copied.erase("target_units")
		snapshot.append(copied)

	return snapshot


func get_candidate_count() -> int:
	return candidate_cache.size()


func format_diagnostics(result: Dictionary) -> String:
	var lines: Array[String] = ["Who resolution"]
	lines.append('  raw: "%s"' % String(result.get("raw_transcript", "")))
	lines.append('  normalized: "%s"' % String(result.get("normalized_transcript", "")))
	lines.append('  who_text: "%s"' % String(result.get("who_text", "")))
	lines.append("  structure: " + String(result.get("inferred_structure", "unknown")))
	lines.append("  method: " + String(result.get("method", "none")))

	var candidate_scores: Array = result.get("candidate_scores", [])
	var top_count := mini(TuningScript.DEBUG_TOP_CANDIDATE_COUNT, candidate_scores.size())

	for index in range(top_count):
		var score: Dictionary = candidate_scores[index]
		lines.append(
			"  %d. %s | text %.3f | phonetic %.3f | structure %.3f | number %.3f"
			% [
				index + 1,
				String(score.get("canonical_id", "")),
				float(score.get("text_similarity", 0.0)),
				float(score.get("phonetic_similarity", 0.0)),
				float(score.get("structural_fit", 0.0)),
				float(score.get("number_agreement", 0.0))
			]
		)
		lines.append(
			"     exact %.3f | plural %.3f | prior %.3f | recent %.3f | final %.3f"
			% [
				float(score.get("exact_evidence", 0.0)),
				float(score.get("plural_agreement", 0.0)),
				float(score.get("static_prior", 0.0)),
				float(score.get("recent_use_prior", 0.0)),
				float(score.get("final_score", 0.0))
			]
		)

	if bool(result.get("ok", false)):
		lines.append("  selected: " + String(result.get("canonical_id", "")))
	else:
		lines.append("  unresolved: " + String(result.get("reason", "Unknown reason.")))

	lines.append("  duration_ms: %.3f" % float(result.get("duration_ms", 0.0)))
	return "\n".join(lines)


func _add_everyone_candidate() -> void:
	_add_candidate(
		"everyone",
		"Everyone",
		["everyone", "everybody", "all", "raid"],
		{"type": CommandSchemaScript.SELECTOR_EVERYONE, "value": ""},
		0,
		party_members
	)


func _add_class_candidates() -> void:
	for class_entry in GameState.get_voice_class_entries():
		var unit_class := String(class_entry.get("unit_class", ""))
		var matching_units := _get_units_by_class(unit_class)

		if matching_units.is_empty():
			continue

		_add_candidate(
			"class_group",
			unit_class + " class",
			class_entry.get("aliases", []),
			{"type": CommandSchemaScript.SELECTOR_CLASS, "value": unit_class},
			0,
			matching_units
		)


func _add_role_candidates() -> void:
	for role_data in GameState.get_role_options():
		var role_name := String(role_data.get("role", ""))
		var matching_units := _get_units_by_role(role_name)

		if matching_units.is_empty():
			continue

		_add_candidate(
			"role_group",
			"Role: " + String(role_data.get("display_name", role_name)),
			role_data.get("aliases", []),
			{"type": CommandSchemaScript.SELECTOR_ROLE, "value": role_name},
			0,
			matching_units
		)


func _add_row_candidates() -> void:
	var group_count := ceili(float(party_members.size()) / float(GROUP_SIZE))

	for group_number in range(1, group_count + 1):
		var start_index := (group_number - 1) * GROUP_SIZE
		var group_units: Array = []

		for index in range(start_index, mini(start_index + GROUP_SIZE, party_members.size())):
			var unit = party_members[index]

			if unit is Node:
				group_units.append(unit)

		if group_units.is_empty():
			continue

		_add_candidate(
			"row",
			"Row " + str(group_number),
			["row", "group"],
			{"type": CommandSchemaScript.SELECTOR_GROUP, "value": group_number},
			group_number,
			group_units
		)


func _add_numbered_individual_candidates() -> void:
	for unit_value in party_members:
		if not unit_value is Node:
			continue

		var unit: Node = unit_value
		var unit_class := _get_unit_class(unit)
		var unit_number := _get_unit_number(unit)

		if unit_class.is_empty() or unit_number <= 0:
			continue

		var aliases: Array = [unit_class.to_lower()]

		for class_entry in GameState.get_voice_class_entries():
			if String(class_entry.get("unit_class", "")) != unit_class:
				continue

			aliases = Array(class_entry.get("aliases", [])).duplicate()
			break

		_add_candidate(
			"numbered_individual",
			unit_class + " " + str(unit_number),
			aliases,
			{
				"type": CommandSchemaScript.SELECTOR_UNIT_IDENTITY,
				"value": unit_class + "_" + str(unit_number),
				"class": unit_class,
				"number": unit_number
			},
			unit_number,
			[unit]
		)


func _add_candidate(
	target_type: String,
	display_label: String,
	aliases_value: Variant,
	selector: Dictionary,
	number: int,
	target_units: Array
) -> void:
	var canonical_id := _canonical_id_for_selector(selector)

	for existing in candidate_cache:
		if String(existing.get("canonical_id", "")) == canonical_id:
			return

	var aliases: Array[String] = []

	if aliases_value is Array:
		for alias_value in aliases_value:
			var normalized_alias := _normalize_text(String(alias_value))

			if not normalized_alias.is_empty() and not aliases.has(normalized_alias):
				aliases.append(normalized_alias)

	var alias_representations: Array[Dictionary] = []

	for alias in aliases:
		var compact := _letters_only(alias)
		alias_representations.append({
			"text": alias,
			"compact": compact,
			"tokens": alias.split(" ", false),
			"phonetic": _phonetic_code(compact)
		})

	var target_ids: Array[String] = []

	for unit_value in target_units:
		if unit_value is Node:
			var target_id := _get_unit_target_id(unit_value)

			if not target_id.is_empty():
				target_ids.append(target_id)

	candidate_cache.append({
		"key": canonical_id,
		"target_type": target_type,
		"display_label": display_label,
		"aliases": aliases,
		"alias_representations": alias_representations,
		"selector": selector.duplicate(true),
		"number": number,
		"canonical_id": canonical_id,
		"canonical_target_ids": target_ids,
		"target_units": target_units.duplicate()
	})


func _score_candidate(
	candidate: Dictionary,
	lexical_text: String,
	inferred_structure: String,
	requested_number: int,
	plural_evidence: bool,
	command_context: Dictionary
) -> Dictionary:
	var alias_match := _best_alias_match(lexical_text, candidate)
	var target_type := String(candidate.get("target_type", ""))
	var structural_fit := _get_structural_fit(target_type, inferred_structure, requested_number)
	var number_agreement := _get_number_agreement(candidate, requested_number)
	var plural_agreement := _get_plural_agreement(target_type, plural_evidence)
	var static_prior := TuningScript.get_category_prior(target_type)
	var recent_prior := _get_recent_use_prior(String(candidate.get("key", "")))
	var command_compatibility := _get_command_compatibility(candidate, command_context)
	var final_score := (
		float(alias_match.get("text_similarity", 0.0)) * TuningScript.WEIGHT_TEXT_SIMILARITY
		+ float(alias_match.get("phonetic_similarity", 0.0)) * TuningScript.WEIGHT_PHONETIC_SIMILARITY
		+ structural_fit * TuningScript.WEIGHT_STRUCTURAL_FIT
		+ float(alias_match.get("exact_evidence", 0.0)) * TuningScript.WEIGHT_EXACT_EVIDENCE
		+ number_agreement * TuningScript.WEIGHT_NUMBER_AGREEMENT
		+ plural_agreement * TuningScript.WEIGHT_PLURAL_AGREEMENT
		+ command_compatibility * TuningScript.WEIGHT_COMMAND_COMPATIBILITY
		+ static_prior
		+ recent_prior
	)

	return {
		"key": String(candidate.get("key", "")),
		"target_type": target_type,
		"display_label": String(candidate.get("display_label", "")),
		"selector": Dictionary(candidate.get("selector", {})).duplicate(true),
		"canonical_id": String(candidate.get("canonical_id", "")),
		"canonical_target_ids": Array(candidate.get("canonical_target_ids", [])).duplicate(),
		"matched_alias": String(alias_match.get("matched_alias", "")),
		"text_similarity": float(alias_match.get("text_similarity", 0.0)),
		"phonetic_similarity": float(alias_match.get("phonetic_similarity", 0.0)),
		"structural_fit": structural_fit,
		"exact_evidence": float(alias_match.get("exact_evidence", 0.0)),
		"number_agreement": number_agreement,
		"plural_agreement": plural_agreement,
		"command_compatibility": command_compatibility,
		"static_prior": static_prior,
		"recent_use_prior": recent_prior,
		"final_score": final_score
	}


func _best_alias_match(lexical_text: String, candidate: Dictionary) -> Dictionary:
	var lexical_compact := _letters_only(lexical_text)
	var lexical_tokens := lexical_text.split(" ", false)
	var lexical_phonetic := _phonetic_code(lexical_compact)
	var best := {
		"matched_alias": "",
		"text_similarity": 0.0,
		"phonetic_similarity": 0.0,
		"exact_evidence": 0.0,
		"combined": -1.0
	}

	for representation_value in candidate.get("alias_representations", []):
		var representation: Dictionary = representation_value
		var alias_text := String(representation.get("text", ""))
		var alias_compact := String(representation.get("compact", ""))
		var character_similarity := _normalized_similarity(lexical_compact, alias_compact)
		var token_similarity := _token_similarity(
			lexical_tokens,
			Array(representation.get("tokens", []))
		)
		var text_similarity := maxf(character_similarity, token_similarity)
		var phonetic_similarity := _normalized_similarity(
			lexical_phonetic,
			String(representation.get("phonetic", ""))
		)
		var exact_evidence := 0.0

		if lexical_text == alias_text or lexical_compact == alias_compact:
			exact_evidence = 1.0
		elif lexical_tokens.has(alias_text):
			exact_evidence = 0.75

		var combined := (
			text_similarity * TuningScript.WEIGHT_TEXT_SIMILARITY
			+ phonetic_similarity * TuningScript.WEIGHT_PHONETIC_SIMILARITY
			+ exact_evidence * TuningScript.WEIGHT_EXACT_EVIDENCE
		)

		if combined > float(best.get("combined", -1.0)):
			best = {
				"matched_alias": alias_text,
				"text_similarity": text_similarity,
				"phonetic_similarity": phonetic_similarity,
				"exact_evidence": exact_evidence,
				"combined": combined
			}

	return best


func _get_structural_fit(
	target_type: String,
	inferred_structure: String,
	requested_number: int
) -> float:
	match target_type:
		"numbered_individual":
			return 1.0 if requested_number > 0 else 0.15
		"row":
			if inferred_structure == "row":
				return 1.0
			return 0.10 if requested_number > 0 else -0.45
		"class_group":
			if requested_number > 0:
				return -0.80
			return 1.0 if inferred_structure == "class_group" else 0.45
		"role_group":
			return -0.75 if requested_number > 0 else 0.65
		"everyone":
			return -1.0 if requested_number > 0 else 0.20
		_:
			return 0.0


func _get_number_agreement(candidate: Dictionary, requested_number: int) -> float:
	var candidate_number := int(candidate.get("number", 0))

	if requested_number <= 0:
		return 0.0

	if candidate_number == requested_number:
		return 1.0

	return -1.0


func _get_plural_agreement(target_type: String, plural_evidence: bool) -> float:
	if plural_evidence:
		return 0.80 if target_type in ["class_group", "role_group", "everyone"] else -0.65

	return 0.20 if target_type == "numbered_individual" else 0.0


func _get_command_compatibility(candidate: Dictionary, command_context: Dictionary) -> float:
	var action := String(command_context.get("what", ""))

	if action.is_empty():
		return 0.0

	if action in [CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE]:
		return 1.0

	var method_by_action := {
		CommandSchemaScript.ACTION_ATTACK: "command_attack",
		CommandSchemaScript.ACTION_INTERRUPT: "command_interrupt",
		CommandSchemaScript.ACTION_HEAL: "command_heal",
		CommandSchemaScript.ACTION_TAUNT: "command_taunt",
		CommandSchemaScript.ACTION_CURE: "command_cure"
	}
	var required_method := String(method_by_action.get(action, ""))

	if required_method.is_empty():
		return 0.0

	var compatible_count := 0
	var considered_count := 0

	for unit_value in candidate.get("target_units", []):
		if not unit_value is Node or not _unit_is_commandable(unit_value):
			continue

		considered_count += 1
		var unit: Node = unit_value

		if unit.has_method(required_method):
			compatible_count += 1

	if considered_count <= 0:
		return 0.0

	return float(compatible_count) / float(considered_count)


func _candidate_is_commandable(candidate: Dictionary) -> bool:
	for unit_value in candidate.get("target_units", []):
		if unit_value is Node and _unit_is_commandable(unit_value):
			return true

	return false


func _unit_is_commandable(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false

	if unit.has_method("is_alive"):
		return bool(unit.is_alive())

	return true


func _has_numbered_candidate(candidates: Array[Dictionary], requested_number: int) -> bool:
	for candidate in candidates:
		if (
			String(candidate.get("target_type", "")) in ["numbered_individual", "row"]
			and int(candidate.get("number", 0)) == requested_number
		):
			return true

	return false


func _find_candidate_for_selector(selector: Dictionary) -> Dictionary:
	var canonical_id := _canonical_id_for_selector(selector)

	for candidate in candidate_cache:
		if (
			String(candidate.get("canonical_id", "")) == canonical_id
			and _candidate_is_commandable(candidate)
		):
			return candidate

	return {}


func _canonical_id_for_selector(selector: Dictionary) -> String:
	var selector_type := String(selector.get("type", ""))

	match selector_type:
		CommandSchemaScript.SELECTOR_EVERYONE:
			return "everyone"
		CommandSchemaScript.SELECTOR_CLASS:
			return "class:" + String(selector.get("value", ""))
		CommandSchemaScript.SELECTOR_GROUP:
			return "group:" + str(int(selector.get("value", 0)))
		CommandSchemaScript.SELECTOR_ROLE:
			return "role:" + String(selector.get("value", ""))
		CommandSchemaScript.SELECTOR_UNIT_IDENTITY:
			return (
				"unit_identity:"
				+ String(selector.get("class", ""))
				+ ":"
				+ str(int(selector.get("number", 0)))
			)
		CommandSchemaScript.SELECTOR_UNIT:
			var unit_value = selector.get("unit", null)
			return "unit:" + _get_unit_target_id(unit_value) if unit_value is Node else "unit:missing"
		_:
			return selector_type + ":" + str(selector.get("value", ""))


func _extract_requested_number(text: String) -> Dictionary:
	var found_values: Array[int] = []

	for token_value in text.split(" ", false):
		var token := String(token_value)
		var number := 0

		if token.is_valid_int():
			number = int(token)
		elif NUMBER_WORDS.has(token):
			number = int(NUMBER_WORDS[token])

		if number > 0 and not found_values.has(number):
			found_values.append(number)

	return {
		"value": found_values[0] if found_values.size() == 1 else 0,
		"ambiguous": found_values.size() > 1,
		"tokens": found_values
	}


func _get_lexical_text(text: String, number_result: Dictionary) -> String:
	var output_tokens: Array[String] = []
	var requested_number := int(number_result.get("value", 0))

	for token_value in text.split(" ", false):
		var token := String(token_value)

		if FILLER_WORDS.has(token):
			continue

		if requested_number > 0:
			if token.is_valid_int() and int(token) == requested_number:
				continue

			if NUMBER_WORDS.has(token) and int(NUMBER_WORDS[token]) == requested_number:
				continue

		output_tokens.append(token)

	return " ".join(output_tokens)


func _infer_structure(text: String, number_result: Dictionary) -> String:
	var tokens := text.split(" ", false)
	var requested_number := int(number_result.get("value", 0))

	if tokens.has("row") or tokens.has("group"):
		return "row"

	if requested_number > 0:
		return "numbered_individual"

	if _has_plural_evidence(text):
		return "class_group"

	if tokens.has("everyone") or tokens.has("everybody") or tokens.has("all") or tokens.has("raid"):
		return "everyone"

	return "unknown"


func _has_plural_evidence(text: String) -> bool:
	for token_value in text.split(" ", false):
		var token := String(token_value)

		if token.length() >= 4 and token.ends_with("s"):
			return true

	return false


func _get_recent_use_prior(candidate_key: String) -> float:
	if recent_target_keys.is_empty() or candidate_key.is_empty():
		return 0.0

	var use_count := recent_target_keys.count(candidate_key)
	return (
		float(use_count)
		/ float(recent_target_keys.size())
		* TuningScript.MAX_RECENT_USE_PRIOR
	)


func _record_target_key(candidate_key: String) -> void:
	if candidate_key.is_empty():
		return

	recent_target_keys.append(candidate_key)

	while recent_target_keys.size() > TuningScript.RECENT_SELECTION_LIMIT:
		recent_target_keys.pop_front()


func _get_units_by_class(unit_class: String) -> Array:
	var matches: Array = []

	for unit_value in party_members:
		if unit_value is Node and _get_unit_class(unit_value) == unit_class:
			matches.append(unit_value)

	return matches


func _get_units_by_role(role_name: String) -> Array:
	var matches: Array = []
	var role_data := GameState.get_role_data(role_name)
	var match_role := String(role_data.get("match_role", role_name))

	for unit_value in party_members:
		if not unit_value is Node:
			continue

		var unit: Node = unit_value

		if unit.has_method("has_role") and bool(unit.has_role(match_role)):
			matches.append(unit)
			continue

		var definition := GameState.get_unit_definition(_get_unit_class(unit))

		if definition != null and definition.has_role(match_role):
			matches.append(unit)

	return matches


func _get_unit_class(unit: Node) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""

	var class_value = unit.get("unit_class")
	return String(class_value) if class_value != null else ""


func _get_unit_number(unit: Node) -> int:
	if unit == null or not is_instance_valid(unit):
		return 0

	if unit.has_method("get_class_ordinal"):
		return int(unit.get_class_ordinal())

	var number_value = unit.get("unit_number")
	return int(number_value) if number_value != null else 0


func _get_unit_target_id(unit: Node) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""

	if unit.has_method("get_member_id"):
		var member_id := String(unit.get_member_id())

		if not member_id.is_empty():
			return member_id

	var unit_class := _get_unit_class(unit)
	var unit_number := _get_unit_number(unit)

	if not unit_class.is_empty() and unit_number > 0:
		return unit_class + "_" + str(unit_number)

	return String(unit.name)


func _normalize_text(text: String) -> String:
	var normalized := text.to_lower().strip_edges()
	var punctuation: Array[String] = [".", ",", "!", "?", ":", ";", "\"", "'", "(", ")", "[", "]"]

	for character in punctuation:
		normalized = normalized.replace(character, " ")

	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")

	return normalized.strip_edges()


func _letters_only(text: String) -> String:
	var output := ""

	for index in range(text.length()):
		var character := text.substr(index, 1)

		if character >= "a" and character <= "z":
			output += character

	return output


func _phonetic_code(text: String) -> String:
	var letters := _letters_only(text)

	if letters.is_empty():
		return ""

	var output := letters.substr(0, 1).to_upper()
	var previous_code := _phonetic_digit(letters.substr(0, 1))

	for index in range(1, letters.length()):
		var code := _phonetic_digit(letters.substr(index, 1))

		if code != "0" and code != previous_code:
			output += code

		previous_code = code

		if output.length() >= 6:
			break

	while output.length() < 6:
		output += "0"

	return output


func _phonetic_digit(character: String) -> String:
	if character in ["b", "f", "p", "v"]:
		return "1"

	if character in ["c", "g", "j", "k", "q", "s", "x", "z"]:
		return "2"

	if character in ["d", "t"]:
		return "3"

	if character == "l":
		return "4"

	if character in ["m", "n"]:
		return "5"

	if character == "r":
		return "6"

	return "0"


func _token_similarity(left_tokens: Array, right_tokens: Array) -> float:
	if left_tokens.is_empty() or right_tokens.is_empty():
		return 0.0

	var intersection := 0
	var union_tokens: Array[String] = []

	for token_value in left_tokens:
		var token := String(token_value)

		if not union_tokens.has(token):
			union_tokens.append(token)

		if right_tokens.has(token):
			intersection += 1

	for token_value in right_tokens:
		var token := String(token_value)

		if not union_tokens.has(token):
			union_tokens.append(token)

	return float(intersection) / float(maxi(union_tokens.size(), 1))


func _normalized_similarity(left: String, right: String) -> float:
	if left == right:
		return 1.0

	var maximum_length := maxi(left.length(), right.length())

	if maximum_length <= 0:
		return 0.0

	return 1.0 - float(_levenshtein_distance(left, right)) / float(maximum_length)


func _levenshtein_distance(left: String, right: String) -> int:
	var previous_row: Array[int] = []
	var current_row: Array[int] = []

	for column in range(right.length() + 1):
		previous_row.append(column)

	for row in range(1, left.length() + 1):
		current_row.clear()
		current_row.append(row)

		for column in range(1, right.length() + 1):
			var insertion := current_row[column - 1] + 1
			var deletion := previous_row[column] + 1
			var substitution := previous_row[column - 1]

			if left[row - 1] != right[column - 1]:
				substitution += 1

			current_row.append(mini(insertion, mini(deletion, substitution)))

		previous_row = current_row.duplicate()

	return previous_row[right.length()]


func _failure_result(
	raw_transcript: String,
	normalized_transcript: String,
	who_text: String,
	inferred_structure: String,
	reason: String,
	started_usec: int
) -> Dictionary:
	var result := {
		"ok": false,
		"method": "weighted_phonetic",
		"raw_transcript": raw_transcript,
		"normalized_transcript": normalized_transcript,
		"who_text": who_text,
		"inferred_structure": inferred_structure,
		"selector": {},
		"canonical_id": "",
		"canonical_target_ids": [],
		"display_label": "",
		"final_score": 0.0,
		"candidate_scores": [],
		"duration_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"cache_generation": cache_generation,
		"reason": reason
	}
	result["debug_text"] = format_diagnostics(result)

	if debug_enabled:
		print(String(result["debug_text"]))

	return result
