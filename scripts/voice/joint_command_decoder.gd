extends RefCounted
class_name JointCommandDecoder

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const TuningScript := preload("res://scripts/voice/command_decoder_tuning.gd")
const VocabularyScript := preload("res://scripts/voice/voice_command_vocabulary.gd")

const SLOT_EXPLICIT := "explicit"
const SLOT_OMITTED := "omitted"
const SLOT_DEFAULTED := "defaulted"
const SLOT_INVALID := "invalid"

const METHOD_JOINT := "joint_weighted"
const METHOD_DETERMINISTIC := "deterministic"

var debug_enabled: bool = false
var who_resolver = null
var action_cache: Array[Dictionary] = []
var merged_sequence_cache: Array[Dictionary] = []
var vocabulary_generation: int = 0


func setup(new_who_resolver) -> void:
	who_resolver = new_who_resolver
	rebuild_vocabulary_cache()


func rebuild_vocabulary_cache() -> void:
	action_cache.clear()
	merged_sequence_cache.clear()
	vocabulary_generation += 1

	for entry in VocabularyScript.get_action_entries():
		var cached := _cache_text_entry(entry, String(entry.get("alias", "")))
		action_cache.append(cached)

	for action_value in [
		CommandSchemaScript.ACTION_MOVE,
		CommandSchemaScript.ACTION_DODGE
	]:
		var action := String(action_value)

		for action_alias_value in VocabularyScript.get_action_aliases(action):
			var action_alias := String(action_alias_value)

			for destination in _get_mergeable_destination_entries(action_alias):
				var destination_alias := String(destination.get("alias", ""))
				var entry := {
					"action": action,
					"action_alias": action_alias,
					"destination_alias": destination_alias,
					"where_data": Dictionary(destination.get("where_data", {})).duplicate(true),
					"canonical_terms": [action_alias, destination_alias]
				}
				merged_sequence_cache.append(
					_cache_text_entry(entry, action_alias + " " + destination_alias)
				)


func decode(
	raw_transcript: String,
	normalized_transcript: String,
	deterministic_failure: Dictionary = {}
) -> Dictionary:
	var total_started := Time.get_ticks_usec()
	var tokens := _tokens(normalized_transcript)

	if tokens.is_empty():
		return _failure(
			raw_transcript,
			normalized_transcript,
			tokens,
			"Transcript is empty.",
			deterministic_failure,
			total_started
		)

	var generation_started := Time.get_ticks_usec()
	var action_alignments := _generate_action_alignments(tokens)
	var generation_duration := Time.get_ticks_usec() - generation_started

	if action_alignments.is_empty():
		return _failure(
			raw_transcript,
			normalized_transcript,
			tokens,
			"No supported action interpretation was found.",
			deterministic_failure,
			total_started,
			{"candidate_generation_usec": generation_duration}
		)

	var scoring_started := Time.get_ticks_usec()
	var complete_candidates: Array[Dictionary] = []
	var exclusion_reasons: Dictionary = {}

	for action_alignment in action_alignments:
		var action_candidates := _complete_action_alignment(
			raw_transcript,
			normalized_transcript,
			tokens,
			action_alignment,
			exclusion_reasons
		)

		for candidate in action_candidates:
			complete_candidates.append(candidate)

	_prune_candidates(complete_candidates, TuningScript.BEAM_WIDTH)
	var scoring_duration := Time.get_ticks_usec() - scoring_started

	if complete_candidates.is_empty():
		return _failure(
			raw_transcript,
			normalized_transcript,
			tokens,
			"No complete valid command could be constructed.",
			deterministic_failure,
			total_started,
			{
				"candidate_generation_usec": generation_duration,
				"joint_scoring_usec": scoring_duration
			},
			exclusion_reasons
		)

	_sort_candidates(complete_candidates)
	var selected: Dictionary = complete_candidates[0]
	var runner_up_score := (
		float(complete_candidates[1].get("final_score", 0.0))
		if complete_candidates.size() > 1
		else 0.0
	)
	var winner_score := float(selected.get("final_score", 0.0))
	var command_data: Dictionary = Dictionary(selected.get("command_data", {})).duplicate(true)
	var selected_who_resolution: Dictionary = Dictionary(
		selected.get("who_resolution", {})
	).duplicate(true)

	if who_resolver != null:
		var selectors: Array = command_data.get("who_selectors", [])

		if not selectors.is_empty() and selectors[0] is Dictionary:
			who_resolver.record_selector(selectors[0])

	var timings := {
		"deterministic_parse_ms": float(
			deterministic_failure.get("duration_usec", 0)
		) / 1000.0,
		"candidate_generation_ms": float(generation_duration) / 1000.0,
		"joint_scoring_ms": float(scoring_duration) / 1000.0,
		"validation_ms": float(selected.get("validation_usec", 0)) / 1000.0,
		"total_ms": float(Time.get_ticks_usec() - total_started) / 1000.0
	}
	var selected_slot_states: Dictionary = Dictionary(
		selected.get("slot_states", {})
	).duplicate(true)
	var selected_initial_states := _initial_slot_states(selected_slot_states)
	var resolution := {
		"ok": true,
		"method": METHOD_JOINT,
		"raw_transcript": raw_transcript,
		"normalized_transcript": normalized_transcript,
		"original_tokens": tokens.duplicate(),
		"grammar": String(selected.get("grammar", "")),
		"slot_states": selected_slot_states,
		"slot_initial_states": selected_initial_states,
		"slot_transitions": _slot_transitions(
			selected_initial_states,
			selected_slot_states
		),
		"slot_ownership": Array(selected.get("slot_ownership", [])).duplicate(true),
		"selected_alignment": String(selected.get("alignment", "")),
		"alternative_spans": _collect_alternative_spans(action_alignments),
		"candidate_scores": complete_candidates.duplicate(true),
		"excluded_candidates": exclusion_reasons.duplicate(true),
		"winning_score": winner_score,
		"winner_score": winner_score,
		"runner_up_score": runner_up_score,
		"winner_margin": winner_score - runner_up_score,
		"default_target_reason": String(selected.get("default_target_reason", "")),
		"validation_result": Dictionary(selected.get("validation_result", {})).duplicate(true),
		"timings": timings,
		"duration_ms": float(timings.get("total_ms", 0.0)),
		"cache_generation": vocabulary_generation,
		"final_canonical_command": _canonical_command_label(command_data),
		"command_data": command_data.duplicate(true),
		"deterministic_failure": deterministic_failure.duplicate(true)
	}
	resolution["debug_text"] = format_diagnostics(resolution)
	selected_who_resolution["command_method"] = METHOD_JOINT

	if debug_enabled:
		print(String(resolution["debug_text"]))

	return {
		"ok": true,
		"command_data": command_data,
		"reason": "",
		"transcript": raw_transcript,
		"normalized_text": normalized_transcript,
		"who_resolution": selected_who_resolution,
		"command_resolution": resolution
	}


func build_deterministic_resolution(
	raw_transcript: String,
	normalized_transcript: String,
	command_data: Dictionary,
	who_resolution: Dictionary,
	duration_usec: int,
	default_target_reason: String = ""
) -> Dictionary:
	var who_state := (
		SLOT_DEFAULTED
		if not default_target_reason.is_empty()
		else SLOT_EXPLICIT
	)
	var action := String(command_data.get("what", ""))
	var where_state := (
		SLOT_EXPLICIT
		if action in [CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE]
		else SLOT_DEFAULTED
	)
	var slot_states := {
		"who": who_state,
		"what": SLOT_EXPLICIT,
		"where": where_state,
		"when": (
			SLOT_EXPLICIT
			if normalized_transcript.ends_with(" now")
			else SLOT_DEFAULTED
		)
	}
	var deterministic_ownership := _build_deterministic_ownership(
		normalized_transcript,
		command_data,
		who_state
	)
	var initial_states := _initial_slot_states(slot_states)
	var resolution := {
		"ok": true,
		"method": METHOD_DETERMINISTIC,
		"raw_transcript": raw_transcript,
		"normalized_transcript": normalized_transcript,
		"original_tokens": _tokens(normalized_transcript),
		"grammar": (
			"What → Where"
			if who_state == SLOT_DEFAULTED
			else "Who → What → Where"
		),
		"slot_states": slot_states,
		"slot_initial_states": initial_states,
		"slot_transitions": _slot_transitions(initial_states, slot_states),
		"slot_ownership": deterministic_ownership,
		"selected_alignment": "deterministic_tokens",
		"alternative_spans": [],
		"candidate_scores": [],
		"excluded_candidates": {},
		"winning_score": 1.0,
		"winner_score": 1.0,
		"runner_up_score": 0.0,
		"winner_margin": 1.0,
		"default_target_reason": default_target_reason,
		"validation_result": {"ok": true, "reason": ""},
		"timings": {
			"deterministic_parse_ms": float(duration_usec) / 1000.0,
			"candidate_generation_ms": 0.0,
			"joint_scoring_ms": 0.0,
			"validation_ms": 0.0,
			"total_ms": float(duration_usec) / 1000.0
		},
		"duration_ms": float(duration_usec) / 1000.0,
		"cache_generation": vocabulary_generation,
		"final_canonical_command": _canonical_command_label(command_data),
		"command_data": command_data.duplicate(true)
	}
	resolution["debug_text"] = format_diagnostics(resolution)
	return resolution


func _build_deterministic_ownership(
	normalized_transcript: String,
	command_data: Dictionary,
	who_state: String
) -> Array[Dictionary]:
	var tokens := _tokens(normalized_transcript)
	var action := String(command_data.get("what", ""))
	var action_start := -1
	var action_end := -1

	for alias_value in VocabularyScript.get_action_aliases(action):
		var alias_tokens := _tokens(String(alias_value))

		for start in range(tokens.size()):
			if start + alias_tokens.size() > tokens.size():
				continue

			if tokens.slice(start, start + alias_tokens.size()) == alias_tokens:
				action_start = start
				action_end = start + alias_tokens.size()
				break

		if action_start >= 0:
			break

	var ownership: Array[Dictionary] = []
	var selectors: Array = command_data.get("who_selectors", [])
	var selector: Dictionary = (
		Dictionary(selectors[0])
		if not selectors.is_empty() and selectors[0] is Dictionary
		else {}
	)

	if who_state == SLOT_EXPLICIT and action_start > 0:
		ownership.append({
			"slot": "Who",
			"start": 0,
			"end": action_start,
			"text": _join_tokens(tokens, 0, action_start),
			"canonical": _selector_label(selector)
		})

	if action_start >= 0:
		ownership.append({
			"slot": "What",
			"start": action_start,
			"end": action_end,
			"text": _join_tokens(tokens, action_start, action_end),
			"canonical": action.capitalize()
		})
		var where_end := tokens.size() - 1 if not tokens.is_empty() and tokens[-1] == "now" else tokens.size()

		if (
			action in [CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE]
			and action_end < where_end
		):
			ownership.append({
				"slot": "Where",
				"start": action_end,
				"end": where_end,
				"text": _join_tokens(tokens, action_end, where_end),
				"canonical": _where_label(command_data)
			})

	if not tokens.is_empty() and tokens[-1] == "now":
		ownership.append({
			"slot": "When",
			"start": tokens.size() - 1,
			"end": tokens.size(),
			"text": "now",
			"canonical": "Now"
		})

	return ownership


func format_diagnostics(resolution: Dictionary) -> String:
	var lines: Array[String] = ["Command decoding"]
	lines.append('  raw: "%s"' % String(resolution.get("raw_transcript", "")))
	lines.append('  normalized: "%s"' % String(resolution.get("normalized_transcript", "")))
	lines.append("  tokens: " + str(resolution.get("original_tokens", [])))
	lines.append("  method: " + String(resolution.get("method", "none")))
	lines.append("  grammar: " + String(resolution.get("grammar", "none")))
	lines.append("  alignment: " + String(resolution.get("selected_alignment", "none")))

	var slot_states: Dictionary = resolution.get("slot_states", {})
	var initial_states: Dictionary = resolution.get("slot_initial_states", {})
	lines.append(
		"  slot states: who=%s | what=%s | where=%s | when=%s"
		% [
			String(slot_states.get("who", SLOT_INVALID)),
			String(slot_states.get("what", SLOT_INVALID)),
			String(slot_states.get("where", SLOT_INVALID)),
			String(slot_states.get("when", SLOT_INVALID))
		]
	)

	if not initial_states.is_empty():
		lines.append(
			"  initial states: who=%s | what=%s | where=%s | when=%s"
			% [
				String(initial_states.get("who", SLOT_INVALID)),
				String(initial_states.get("what", SLOT_INVALID)),
				String(initial_states.get("where", SLOT_INVALID)),
				String(initial_states.get("when", SLOT_INVALID))
			]
		)

	var transitions: Dictionary = resolution.get("slot_transitions", {})

	if not transitions.is_empty():
		var transition_parts: Array[String] = []

		for slot in ["who", "what", "where", "when"]:
			var transition: Array = transitions.get(slot, [])

			if transition.size() > 1:
				transition_parts.append(
					slot
					+ "="
					+ String(transition[0])
					+ "→"
					+ String(transition[1])
				)

		if not transition_parts.is_empty():
			lines.append("  transitions: " + " | ".join(transition_parts))

	var ownership: Array = resolution.get("slot_ownership", [])

	if not ownership.is_empty():
		lines.append("  slot ownership:")

		for owner_value in ownership:
			if not owner_value is Dictionary:
				continue

			var owner: Dictionary = owner_value
			lines.append(
				'    %s [%d:%d] "%s" → %s'
				% [
					String(owner.get("slot", "")),
					int(owner.get("start", -1)),
					int(owner.get("end", -1)),
					String(owner.get("text", "")),
					String(owner.get("canonical", ""))
				]
			)

	var alternative_spans: Array = resolution.get("alternative_spans", [])

	if not alternative_spans.is_empty():
		lines.append("  alternative action spans:")

		for span_value in alternative_spans:
			if not span_value is Dictionary:
				continue

			var span: Dictionary = span_value
			lines.append(
				'    [%d:%d] "%s" → %s (%.3f)'
				% [
					int(span.get("start", -1)),
					int(span.get("end", -1)),
					String(span.get("text", "")),
					String(span.get("canonical", "")),
					float(span.get("score", 0.0))
				]
			)

	var default_reason := String(resolution.get("default_target_reason", ""))

	if not default_reason.is_empty():
		lines.append("  default target: " + default_reason)

	var candidates: Array = resolution.get("candidate_scores", [])
	var top_count := mini(TuningScript.TOP_DIAGNOSTIC_CANDIDATES, candidates.size())

	for index in range(top_count):
		var candidate: Dictionary = candidates[index]
		var components: Dictionary = candidate.get("score_components", {})
		lines.append(
			"  candidate %d: %s"
			% [index + 1, String(candidate.get("canonical_command", ""))]
		)
		lines.append(
			"    who: %.3f | action: %.3f | destination: %.3f | grammar: %.3f"
			% [
				float(components.get("who_evidence", 0.0)),
				float(components.get("action_evidence", 0.0)),
				float(components.get("destination_evidence", 0.0)),
				float(components.get("grammar", 0.0))
			]
		)
		lines.append(
			"    alignment: %.3f | validity: %.3f | costs: %.3f | final: %.3f"
			% [
				float(components.get("alignment", 0.0)),
				float(components.get("validity", 0.0)),
				float(components.get("costs", 0.0)),
				float(candidate.get("final_score", 0.0))
			]
		)
		lines.append(
			"    slot_order: %.3f | order_penalty: %.3f | contiguity: %.3f"
			% [
				float(components.get("slot_order", 0.0)),
				float(components.get("order_penalty", 0.0)),
				float(components.get("span_contiguity", 0.0))
			]
		)

	var excluded: Dictionary = resolution.get("excluded_candidates", {})

	if not excluded.is_empty():
		var exclusion_parts: Array[String] = []

		for reason in excluded.keys():
			exclusion_parts.append(
				String(reason) + "=" + str(int(excluded.get(reason, 0)))
			)

		exclusion_parts.sort()
		lines.append("  excluded: " + ", ".join(exclusion_parts))

	var validation: Dictionary = resolution.get("validation_result", {})
	lines.append(
		"  validation: "
		+ (
			"valid"
			if bool(validation.get("ok", false))
			else String(validation.get("reason", "invalid"))
		)
	)

	if bool(resolution.get("ok", false)):
		lines.append(
			"  selected: " + String(resolution.get("final_canonical_command", ""))
		)
		lines.append("  winner_score: %.3f" % float(resolution.get("winner_score", 0.0)))
		lines.append(
			"  runner_up_score: %.3f" % float(resolution.get("runner_up_score", 0.0))
		)
		lines.append(
			"  winner_margin: %.3f" % float(resolution.get("winner_margin", 0.0))
		)
	else:
		lines.append("  unresolved: " + String(resolution.get("reason", "Unknown reason.")))

	var timings: Dictionary = resolution.get("timings", {})
	lines.append(
		"  timing_ms: deterministic=%.3f | generation=%.3f | scoring=%.3f | validation=%.3f | total=%.3f"
		% [
			float(timings.get("deterministic_parse_ms", 0.0)),
			float(timings.get("candidate_generation_ms", 0.0)),
			float(timings.get("joint_scoring_ms", 0.0)),
			float(timings.get("validation_ms", 0.0)),
			float(timings.get("total_ms", 0.0))
		]
	)
	lines.append(
		"  cache_generation: " + str(int(resolution.get("cache_generation", 0)))
	)
	return "\n".join(lines)


func _complete_action_alignment(
	raw_transcript: String,
	normalized_transcript: String,
	tokens: Array[String],
	action_alignment: Dictionary,
	exclusion_reasons: Dictionary
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var action := String(action_alignment.get("action", ""))
	var action_start := int(action_alignment.get("start", 0))
	var action_end := int(action_alignment.get("end", 0))
	var leading_tokens := tokens.slice(0, action_start)
	var trailing_tokens := tokens.slice(action_end)

	if leading_tokens.size() > TuningScript.MAX_WHO_SPAN_TOKENS:
		_increment_reason(exclusion_reasons, "who_span_too_long")
		return candidates

	var where_candidates: Array[Dictionary] = []

	if bool(action_alignment.get("merged", false)):
		if not _tokens_are_when_or_empty(trailing_tokens):
			_increment_reason(exclusion_reasons, "tokens_after_merged_command")
			return candidates

		where_candidates.append({
			"where_data": Dictionary(action_alignment.get("where_data", {})).duplicate(true),
			"score": float(action_alignment.get("sequence_score", 0.0)),
			"state": SLOT_EXPLICIT,
			"span_start": action_start,
			"span_end": action_end,
			"span_text": _join_tokens(tokens, action_start, action_end),
			"alignment": "one_span_to_what_where",
			"semantic": false
		})
	elif action in [CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE]:
		where_candidates = _generate_movement_where_candidates(
			trailing_tokens,
			action_end,
			String(action_alignment.get("alias", ""))
		)
	else:
		var fixed_destination := VocabularyScript.get_action_destination(action)

		if fixed_destination.is_empty():
			_increment_reason(exclusion_reasons, "action_has_no_destination_rule")
			return candidates

		if not _tokens_are_when_or_empty(trailing_tokens):
			_increment_reason(exclusion_reasons, "unexpected_tokens_after_action")
			return candidates

		where_candidates.append({
			"where_data": fixed_destination,
			"score": 0.0,
			"state": SLOT_DEFAULTED,
			"span_start": -1,
			"span_end": -1,
			"span_text": "",
			"alignment": "action_implied_destination",
			"semantic": false
		})

	if where_candidates.is_empty():
		_increment_reason(exclusion_reasons, "no_valid_destination")
		return candidates

	var who_candidates := _generate_who_candidates(
		raw_transcript,
		normalized_transcript,
		leading_tokens,
		action,
		where_candidates[0]
	)

	if who_candidates.is_empty():
		_increment_reason(exclusion_reasons, "no_valid_who")
		return candidates

	for where_candidate in where_candidates:
		for who_candidate in who_candidates:
			var candidate := _build_complete_candidate(
				tokens,
				action_alignment,
				where_candidate,
				who_candidate
			)

			if bool(candidate.get("ok", false)):
				candidates.append(candidate)
			else:
				_increment_reason(
					exclusion_reasons,
					String(candidate.get("exclusion_reason", "validation_failed"))
				)

	_prune_candidates(candidates, TuningScript.BEAM_WIDTH)
	return candidates


func _generate_action_alignments(tokens: Array[String]) -> Array[Dictionary]:
	var exact_alignments := _find_exact_action_alignments(tokens)

	## A clear action token owns its span. Do not reinterpret it as a different
	## fuzzy action merely because that would make an otherwise illegal command
	## executable.
	if exact_alignments.size() == 1:
		var exact: Dictionary = exact_alignments[0]
		var action := String(exact.get("action", ""))
		var trailing := tokens.slice(int(exact.get("end", 0)))
		var ordinary_destinations: Array[Dictionary] = []

		if action in [CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE]:
			ordinary_destinations = _generate_movement_where_candidates(
				trailing,
				int(exact.get("end", 0)),
				String(exact.get("alias", ""))
			)

		if ordinary_destinations.is_empty():
			for merged in _merged_alignments_for_exact_action(tokens, exact):
				exact_alignments.append(merged)

		return exact_alignments

	## Multiple explicit actions preserve the existing invalid-command behavior.
	if exact_alignments.size() > 1:
		return []

	var alignments: Array[Dictionary] = []
	var seen: Dictionary = {}

	for start in range(tokens.size()):
		for span_length in range(
			1,
			mini(TuningScript.MAX_ACTION_SPAN_TOKENS, tokens.size() - start) + 1
		):
			var span_end := start + span_length
			var span_text := _join_tokens(tokens, start, span_end)

			for cached_entry in action_cache:
				var alias := String(cached_entry.get("alias", ""))
				var exact := span_text == alias
				var similarity := 1.0 if exact else _entry_similarity(span_text, cached_entry)

				if not exact and _span_contains_number(tokens, start, span_end):
					continue

				if not exact and similarity < TuningScript.MIN_ACTION_SIMILARITY:
					continue

				var key := "%s:%d:%d" % [
					String(cached_entry.get("action", "")),
					start,
					span_end
				]
				var alignment := {
					"action": String(cached_entry.get("action", "")),
					"alias": alias,
					"start": start,
					"end": span_end,
					"span_text": span_text,
					"score": similarity,
					"exact": exact,
					"merged": false,
					"alignment": "one_to_one" if span_length == 1 else "many_to_one"
				}
				_keep_best_by_key(alignments, seen, key, alignment, "score")

			if span_length > 2:
				continue

			if _span_contains_number(tokens, start, span_end):
				continue

			for sequence in merged_sequence_cache:
				var sequence_similarity := _entry_similarity(span_text, sequence)

				if sequence_similarity < TuningScript.MIN_MERGED_SEQUENCE_SIMILARITY:
					continue

				var sequence_key := "%s:%s:%d:%d" % [
					String(sequence.get("action", "")),
					String(sequence.get("destination_alias", "")),
					start,
					span_end
				]
				var merged_alignment := {
					"action": String(sequence.get("action", "")),
					"alias": String(sequence.get("action_alias", "")),
					"start": start,
					"end": span_end,
					"span_text": span_text,
					"score": sequence_similarity,
					"sequence_score": sequence_similarity,
					"exact": false,
					"merged": true,
					"where_data": Dictionary(sequence.get("where_data", {})).duplicate(true),
					"canonical_terms": Array(sequence.get("canonical_terms", [])).duplicate(),
					"alignment": "one_to_many" if span_length == 1 else "many_to_many"
				}
				_keep_best_by_key(
					alignments,
					seen,
					sequence_key,
					merged_alignment,
					"score"
				)

	_sort_alignment_scores(alignments)
	_prune_candidates(alignments, TuningScript.BEAM_WIDTH * 2, "score")
	return alignments


func _find_exact_action_alignments(tokens: Array[String]) -> Array[Dictionary]:
	var exact_alignments: Array[Dictionary] = []
	var seen: Dictionary = {}

	for cached_entry in action_cache:
		var alias_tokens := _tokens(String(cached_entry.get("alias", "")))

		for start in range(tokens.size()):
			var span_end := start + alias_tokens.size()

			if span_end > tokens.size() or tokens.slice(start, span_end) != alias_tokens:
				continue

			var key := "%s:%d:%d" % [
				String(cached_entry.get("action", "")),
				start,
				span_end
			]

			if seen.has(key):
				continue

			seen[key] = true
			exact_alignments.append({
				"action": String(cached_entry.get("action", "")),
				"alias": String(cached_entry.get("alias", "")),
				"start": start,
				"end": span_end,
				"span_text": _join_tokens(tokens, start, span_end),
				"score": 1.0,
				"exact": true,
				"merged": false,
				"alignment": "one_to_one" if alias_tokens.size() == 1 else "many_to_one"
			})

	return exact_alignments


func _merged_alignments_for_exact_action(
	tokens: Array[String],
	exact_action: Dictionary
) -> Array[Dictionary]:
	var alignments: Array[Dictionary] = []
	var start := int(exact_action.get("start", 0))
	var minimum_end := int(exact_action.get("end", start + 1))
	var maximum_end := mini(tokens.size(), start + 2)

	if maximum_end <= minimum_end:
		return alignments

	var span_text := _join_tokens(tokens, start, maximum_end)
	var exact_action_name := String(exact_action.get("action", ""))
	var exact_alias := String(exact_action.get("alias", ""))

	for sequence in merged_sequence_cache:
		if (
			String(sequence.get("action", "")) != exact_action_name
			or String(sequence.get("action_alias", "")) != exact_alias
		):
			continue

		var similarity := _entry_similarity(span_text, sequence)

		if similarity < TuningScript.MIN_MERGED_SEQUENCE_SIMILARITY:
			continue

		alignments.append({
			"action": exact_action_name,
			"alias": exact_alias,
			"start": start,
			"end": maximum_end,
			"span_text": span_text,
			"score": similarity,
			"sequence_score": similarity,
			"exact": false,
			"merged": true,
			"where_data": Dictionary(sequence.get("where_data", {})).duplicate(true),
			"canonical_terms": Array(sequence.get("canonical_terms", [])).duplicate(),
			"alignment": "many_to_many"
		})

	_prune_candidates(alignments, TuningScript.BEAM_WIDTH, "score")
	return alignments


func _generate_movement_where_candidates(
	trailing_tokens: Array,
	global_start: int,
	action_alias: String
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var tokens: Array[String] = []

	for token_value in trailing_tokens:
		tokens.append(String(token_value))

	if not tokens.is_empty() and tokens[-1] == "now":
		tokens.pop_back()

	if tokens.is_empty():
		return candidates

	var text := " ".join(tokens)
	var normalized_action_alias := action_alias.to_lower()
	var is_rotation_verb := normalized_action_alias in ["rotate", "turn"]

	if is_rotation_verb and text in ["left", "right"]:
		var rotation_direction := (
			"counterclockwise"
			if text == "left"
			else "clockwise"
		)
		candidates.append(_where_candidate(
			{"where": "movement_rotate_step", "movement_direction": rotation_direction},
			1.0,
			global_start,
			global_start + tokens.size(),
			text,
			"one_to_one",
			true
		))

	if text in [
		"clockwise",
		"one step clockwise",
		"step clockwise",
		"counterclockwise",
		"anticlockwise",
		"one step counterclockwise",
		"one step anticlockwise",
		"step counterclockwise",
		"step anticlockwise"
	]:
		var direction := (
			"counterclockwise"
			if text.contains("counterclockwise") or text.contains("anticlockwise")
			else "clockwise"
		)
		candidates.append(_where_candidate(
			{"where": "movement_rotate_step", "movement_direction": direction},
			1.0,
			global_start,
			global_start + tokens.size(),
			text,
			"one_to_one",
			false
		))

	if text in ["to me", "on me", "to player", "to the player"]:
		candidates.append(_where_candidate(
			{"where": "me"},
			1.0,
			global_start,
			global_start + tokens.size(),
			text,
			"many_to_one",
			false
		))

	if text in ["out", "move out", "go out", "spread out", "away"]:
		candidates.append(_where_candidate(
			{"where": "movement_range_step", "movement_direction": "out"},
			1.0,
			global_start,
			global_start + tokens.size(),
			text,
			"one_to_one",
			false
		))

	if text in ["in", "move in", "go in", "come in", "closer"]:
		candidates.append(_where_candidate(
			{"where": "movement_range_step", "movement_direction": "in"},
			1.0,
			global_start,
			global_start + tokens.size(),
			text,
			"one_to_one",
			false
		))

	if tokens.size() == 2:
		var first_region := _best_region_match(tokens[0], not is_rotation_verb)
		var second_range := _best_range_match(tokens[1])

		if (
			not first_region.is_empty()
			and not second_range.is_empty()
			and float(first_region.get("score", 0.0)) >= TuningScript.MIN_DESTINATION_SIMILARITY
			and float(second_range.get("score", 0.0)) >= TuningScript.MIN_DESTINATION_SIMILARITY
		):
			candidates.append(_where_candidate(
				{
					"where": "movement_slot",
					"movement_region": String(first_region.get("region", "")),
					"movement_range": String(second_range.get("range", ""))
				},
				(
					float(first_region.get("score", 0.0))
					+ float(second_range.get("score", 0.0))
				) / 2.0,
				global_start,
				global_start + tokens.size(),
				text,
				"two_ordered_terms",
				bool(first_region.get("semantic", false))
			))

	var region_match := _best_region_match(text, not is_rotation_verb)

	if (
		not region_match.is_empty()
		and float(region_match.get("score", 0.0)) >= TuningScript.MIN_DESTINATION_SIMILARITY
	):
		var region_where := (
			"movement_rotate"
			if is_rotation_verb
			else "movement_region"
		)
		candidates.append(_where_candidate(
			{
				"where": region_where,
				"movement_region": String(region_match.get("region", ""))
			},
			float(region_match.get("score", 0.0)),
			global_start,
			global_start + tokens.size(),
			text,
			"one_to_one" if tokens.size() == 1 else "many_to_one",
			bool(region_match.get("semantic", false))
		))

	if not is_rotation_verb:
		var range_match := _best_range_match(text)

		if (
			not range_match.is_empty()
			and float(range_match.get("score", 0.0)) >= TuningScript.MIN_DESTINATION_SIMILARITY
		):
			candidates.append(_where_candidate(
				{
					"where": "movement_range",
					"movement_range": String(range_match.get("range", ""))
				},
				float(range_match.get("score", 0.0)),
				global_start,
				global_start + tokens.size(),
				text,
				"one_to_one" if tokens.size() == 1 else "many_to_one",
				false
			))

	_deduplicate_where_candidates(candidates)
	_prune_candidates(candidates, TuningScript.BEAM_WIDTH, "score")
	return candidates


func _generate_who_candidates(
	raw_transcript: String,
	normalized_transcript: String,
	leading_tokens: Array,
	action: String,
	where_candidate: Dictionary
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var default_data := VocabularyScript.get_default_selector_for_action(action)
	var has_ambiguous_filler := false

	for token_value in leading_tokens:
		if VocabularyScript.AMBIGUOUS_FILLER_WORDS.has(String(token_value)):
			has_ambiguous_filler = true
			break

	if leading_tokens.is_empty():
		if not default_data.is_empty():
			candidates.append(_default_who_candidate(default_data, 0))

		return candidates

	if VocabularyScript.tokens_are_fillers(leading_tokens, true) and not default_data.is_empty():
		candidates.append(_default_who_candidate(default_data, leading_tokens.size()))

	var should_score_explicit := (
		has_ambiguous_filler
		or not VocabularyScript.tokens_are_fillers(leading_tokens, false)
	)

	if not should_score_explicit or who_resolver == null:
		return candidates

	var who_text := " ".join(leading_tokens)
	var resolution: Dictionary = who_resolver.resolve_who(
		raw_transcript,
		normalized_transcript,
		who_text,
		{
			"what": action,
			"where": String(
				Dictionary(where_candidate.get("where_data", {})).get("where", "")
			)
		},
		false
	)

	if not bool(resolution.get("ok", false)):
		return candidates

	var scores: Array = resolution.get("candidate_scores", [])
	var top_count := mini(TuningScript.TOP_WHO_CANDIDATES_PER_SPAN, scores.size())

	for index in range(top_count):
		var score_value = scores[index]

		if not score_value is Dictionary:
			continue

		var score: Dictionary = score_value
		candidates.append({
			"selector": Dictionary(score.get("selector", {})).duplicate(true),
			"state": SLOT_EXPLICIT,
			"score": float(score.get("final_score", 0.0)),
			"span_start": 0,
			"span_end": leading_tokens.size(),
			"span_text": who_text,
			"default_reason": "",
			"filler_cost": 0.0,
			"who_resolution": _who_resolution_for_candidate(resolution, score)
		})

	return candidates


func _build_complete_candidate(
	tokens: Array[String],
	action_alignment: Dictionary,
	where_candidate: Dictionary,
	who_candidate: Dictionary
) -> Dictionary:
	var selector: Dictionary = Dictionary(who_candidate.get("selector", {})).duplicate(true)

	if selector.is_empty():
		return {"ok": false, "exclusion_reason": "empty_who_selector"}

	if who_resolver != null:
		var selector_validation: Dictionary = who_resolver.validate_deterministic_selectors(
			[selector]
		)

		if not bool(selector_validation.get("ok", false)):
			return {"ok": false, "exclusion_reason": "who_target_unavailable"}

	var action := String(action_alignment.get("action", ""))
	var where_data: Dictionary = Dictionary(
		where_candidate.get("where_data", {})
	).duplicate(true)
	var command_data := {
		"who_type": String(selector.get("type", CommandSchemaScript.SELECTOR_EVERYONE)),
		"who_value": selector.get("value", ""),
		"unit": null,
		"who_selectors": [selector],
		"who_exclude_selectors": [],
		"what": action,
		"where": String(where_data.get("where", "")),
		"when": "now"
	}

	for key in where_data.keys():
		command_data[key] = where_data[key]

	var validation_started := Time.get_ticks_usec()
	var validation_result := CommandSchemaScript.validate(command_data)
	var validation_usec := Time.get_ticks_usec() - validation_started

	if not bool(validation_result.get("ok", false)):
		return {
			"ok": false,
			"exclusion_reason": "schema_validation_failed",
			"validation_result": validation_result
		}

	var who_state := String(who_candidate.get("state", SLOT_INVALID))
	var grammar := (
		"What → Where"
		if who_state == SLOT_DEFAULTED
		else "Who → What → Where"
	)
	var grammar_score := (
		TuningScript.OMITTED_WHO_GRAMMAR_SCORE
		if who_state == SLOT_DEFAULTED
		else TuningScript.CANONICAL_ORDER_SCORE
	)
	var alignment_score := _combined_alignment_score(action_alignment, where_candidate)
	var action_score := float(action_alignment.get("score", 0.0))
	var destination_score := float(where_candidate.get("score", 0.0))
	var who_score := float(who_candidate.get("score", 0.0))
	var costs := float(who_candidate.get("filler_cost", 0.0))

	if who_state == SLOT_DEFAULTED:
		costs += TuningScript.IMPLICIT_DEFAULT_COST

	if not bool(action_alignment.get("exact", false)):
		costs += TuningScript.FUZZY_ACTION_COST

	if destination_score < 0.999 and String(where_candidate.get("state", "")) == SLOT_EXPLICIT:
		costs += TuningScript.FUZZY_DESTINATION_COST

	var exact_bonus := 0.0

	if bool(action_alignment.get("exact", false)):
		exact_bonus += TuningScript.EXACT_EVIDENCE_BONUS * 0.5

	if destination_score >= 0.999 and String(where_candidate.get("state", "")) == SLOT_EXPLICIT:
		exact_bonus += TuningScript.EXACT_EVIDENCE_BONUS * 0.5

	if bool(where_candidate.get("semantic", false)):
		exact_bonus += TuningScript.CONTEXTUAL_SEMANTIC_BONUS

	var components := {
		"who_evidence": who_score,
		"action_evidence": action_score,
		"destination_evidence": destination_score,
		"grammar": grammar_score,
		"slot_order": grammar_score,
		"order_penalty": 0.0,
		"alignment": alignment_score,
		"span_contiguity": alignment_score,
		"validity": 1.0,
		"exact_bonus": exact_bonus,
		"costs": costs
	}
	var final_score := (
		who_score * TuningScript.WEIGHT_WHO_EVIDENCE
		+ action_score * TuningScript.WEIGHT_ACTION_EVIDENCE
		+ destination_score * TuningScript.WEIGHT_DESTINATION_EVIDENCE
		+ grammar_score * TuningScript.WEIGHT_GRAMMAR
		+ alignment_score * TuningScript.WEIGHT_ALIGNMENT
		+ TuningScript.WEIGHT_VALIDITY
		+ exact_bonus
		- costs
	)
	var ownership: Array[Dictionary] = []
	var who_span_start := int(who_candidate.get("span_start", -1))

	if who_span_start >= 0:
		ownership.append({
			"slot": "Who",
			"start": who_span_start,
			"end": int(who_candidate.get("span_end", -1)),
			"text": String(who_candidate.get("span_text", "")),
			"canonical": _selector_label(selector)
		})

	if bool(action_alignment.get("merged", false)):
		ownership.append({
			"slot": "What + Where",
			"start": int(action_alignment.get("start", -1)),
			"end": int(action_alignment.get("end", -1)),
			"text": String(action_alignment.get("span_text", "")),
			"canonical": (
				action.capitalize()
				+ " + "
				+ _where_label(where_data)
			)
		})
	else:
		ownership.append({
			"slot": "What",
			"start": int(action_alignment.get("start", -1)),
			"end": int(action_alignment.get("end", -1)),
			"text": String(action_alignment.get("span_text", "")),
			"canonical": action.capitalize()
		})
		var where_span_start := int(where_candidate.get("span_start", -1))

		if where_span_start >= 0:
			ownership.append({
				"slot": "Where",
				"start": where_span_start,
				"end": int(where_candidate.get("span_end", -1)),
				"text": String(where_candidate.get("span_text", "")),
				"canonical": _where_label(where_data)
			})

	if not tokens.is_empty() and tokens[-1] == "now":
		ownership.append({
			"slot": "When",
			"start": tokens.size() - 1,
			"end": tokens.size(),
			"text": "now",
			"canonical": "Now"
		})

	return {
		"ok": true,
		"command_data": command_data,
		"canonical_command": _canonical_command_label(command_data),
		"grammar": grammar,
		"slot_states": {
			"who": who_state,
			"what": SLOT_EXPLICIT,
			"where": String(where_candidate.get("state", SLOT_INVALID)),
			"when": (
				SLOT_EXPLICIT
				if not tokens.is_empty() and tokens[-1] == "now"
				else SLOT_DEFAULTED
			)
		},
		"slot_ownership": ownership,
		"alignment": (
			String(action_alignment.get("alignment", ""))
			+ " / "
			+ String(where_candidate.get("alignment", ""))
		),
		"score_components": components,
		"final_score": final_score,
		"default_target_reason": String(who_candidate.get("default_reason", "")),
		"who_resolution": Dictionary(who_candidate.get("who_resolution", {})).duplicate(true),
		"validation_result": validation_result,
		"validation_usec": validation_usec
	}


func _default_who_candidate(default_data: Dictionary, filler_count: int) -> Dictionary:
	var selector: Dictionary = Dictionary(default_data.get("selector", {})).duplicate(true)
	var reason := String(default_data.get("reason", ""))
	var who_resolution := {
		"ok": true,
		"method": "deterministic_action_default",
		"selector": selector.duplicate(true),
		"canonical_id": _canonical_id_for_selector(selector),
		"display_label": _selector_label(selector),
		"candidate_scores": [],
		"winner_score": 1.0,
		"runner_up_score": 0.0,
		"winner_margin": 1.0,
		"duration_ms": 0.0,
		"reason": ""
	}
	return {
		"selector": selector,
		"state": SLOT_DEFAULTED,
		"score": 0.0,
		"span_start": -1,
		"span_end": -1,
		"span_text": "",
		"default_reason": reason,
		"filler_cost": (
			TuningScript.FILLER_INTERPRETATION_COST
			+ maxf(0.0, float(filler_count - 1) * TuningScript.EXTRA_FILLER_TOKEN_COST)
			if filler_count > 0
			else 0.0
		),
		"who_resolution": who_resolution
	}


func _who_resolution_for_candidate(
	base_resolution: Dictionary,
	score: Dictionary
) -> Dictionary:
	var result := base_resolution.duplicate(true)
	var candidate_scores: Array = base_resolution.get("candidate_scores", [])
	var selected_score := float(score.get("final_score", 0.0))
	var runner_up := 0.0

	for candidate_value in candidate_scores:
		if not candidate_value is Dictionary:
			continue

		var candidate: Dictionary = candidate_value

		if String(candidate.get("canonical_id", "")) == String(score.get("canonical_id", "")):
			continue

		runner_up = maxf(runner_up, float(candidate.get("final_score", 0.0)))

	result["selector"] = Dictionary(score.get("selector", {})).duplicate(true)
	result["canonical_id"] = String(score.get("canonical_id", ""))
	result["canonical_target_ids"] = Array(score.get("canonical_target_ids", [])).duplicate()
	result["display_label"] = String(score.get("display_label", ""))
	result["final_score"] = selected_score
	result["winner_score"] = selected_score
	result["runner_up_score"] = runner_up
	result["winner_margin"] = selected_score - runner_up
	return result


func _get_mergeable_destination_entries(action_alias: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var is_rotation_verb := action_alias in ["rotate", "turn"]

	for region_entry in VocabularyScript.get_region_entries(false):
		var region := String(region_entry.get("region", ""))
		entries.append({
			"alias": String(region_entry.get("alias", "")),
			"where_data": {
				"where": "movement_rotate" if is_rotation_verb else "movement_region",
				"movement_region": region
			}
		})

	if not is_rotation_verb:
		for range_entry in VocabularyScript.get_range_entries():
			entries.append({
				"alias": String(range_entry.get("alias", "")),
				"where_data": {
					"where": "movement_range",
					"movement_range": String(range_entry.get("range", ""))
				}
			})

	for direction in ["clockwise", "counterclockwise", "anticlockwise"]:
		entries.append({
			"alias": direction,
			"where_data": {
				"where": "movement_rotate_step",
				"movement_direction": (
					"counterclockwise"
					if direction != "clockwise"
					else "clockwise"
				)
			}
		})

	return entries


func _best_region_match(text: String, include_semantic: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0

	for entry in VocabularyScript.get_region_entries(include_semantic):
		var alias := String(entry.get("alias", ""))
		var score := 1.0 if text == alias else _text_evidence(text, alias)

		if score > best_score:
			best_score = score
			best = entry.duplicate(true)
			best["score"] = score

	return best


func _best_range_match(text: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0

	for entry in VocabularyScript.get_range_entries():
		var alias := String(entry.get("alias", ""))
		var score := 1.0 if text == alias else _text_evidence(text, alias)

		if score > best_score:
			best_score = score
			best = entry.duplicate(true)
			best["score"] = score

	return best


func _where_candidate(
	where_data: Dictionary,
	score: float,
	span_start: int,
	span_end: int,
	span_text: String,
	alignment: String,
	semantic: bool
) -> Dictionary:
	return {
		"where_data": where_data,
		"score": score,
		"state": SLOT_EXPLICIT,
		"span_start": span_start,
		"span_end": span_end,
		"span_text": span_text,
		"alignment": alignment,
		"semantic": semantic
	}


func _deduplicate_where_candidates(candidates: Array[Dictionary]) -> void:
	var best_by_key: Dictionary = {}

	for candidate in candidates:
		var key := JSON.stringify(candidate.get("where_data", {}))

		if (
			not best_by_key.has(key)
			or float(candidate.get("score", 0.0))
			> float(Dictionary(best_by_key[key]).get("score", 0.0))
		):
			best_by_key[key] = candidate

	candidates.clear()

	for candidate_value in best_by_key.values():
		candidates.append(candidate_value)


func _combined_alignment_score(
	action_alignment: Dictionary,
	where_candidate: Dictionary
) -> float:
	if bool(action_alignment.get("merged", false)):
		return TuningScript.MERGED_ALIGNMENT_SCORE

	var action_alignment_kind := String(action_alignment.get("alignment", "one_to_one"))
	var where_alignment_kind := String(where_candidate.get("alignment", "one_to_one"))

	if action_alignment_kind == "many_to_one" or where_alignment_kind in [
		"many_to_one", "two_ordered_terms"
	]:
		return TuningScript.SPLIT_ALIGNMENT_SCORE

	return 1.0


func _cache_text_entry(entry: Dictionary, text: String) -> Dictionary:
	var cached := entry.duplicate(true)
	var normalized := _normalize_text(text)
	cached["text"] = normalized
	cached["compact"] = _compact_text(normalized)
	cached["phonetic"] = _phrase_phonetic_code(normalized)
	return cached


func _entry_similarity(span_text: String, cached_entry: Dictionary) -> float:
	var normalized := _normalize_text(span_text)
	var compact := _compact_text(normalized)
	var canonical_text := String(cached_entry.get("text", ""))
	var canonical_compact := String(cached_entry.get("compact", ""))
	var textual := _normalized_similarity(normalized, canonical_text)
	var compact_similarity := _normalized_similarity(compact, canonical_compact)
	var phonetic := _phonetic_similarity(
		_phrase_phonetic_code(normalized),
		String(cached_entry.get("phonetic", ""))
	)
	var score := maxf(
		compact_similarity * 0.55 + phonetic * 0.45,
		textual * 0.65 + phonetic * 0.35
	)

	## A merged/split canonical sequence has useful internal term boundaries even
	## when Whisper's transcript boundaries differ. Phrase phonetics receive
	## extra weight here, while compact text still guards canonical term order.
	if Array(cached_entry.get("canonical_terms", [])).size() > 1:
		score = maxf(score, compact_similarity * 0.30 + phonetic * 0.70)

	return score


func _text_evidence(left: String, right: String) -> float:
	var normalized_left := _normalize_text(left)
	var normalized_right := _normalize_text(right)
	var textual := _normalized_similarity(normalized_left, normalized_right)
	var compact := _normalized_similarity(
		_compact_text(normalized_left),
		_compact_text(normalized_right)
	)
	var phonetic := _phonetic_similarity(
		_phrase_phonetic_code(normalized_left),
		_phrase_phonetic_code(normalized_right)
	)
	return maxf(textual * 0.65 + phonetic * 0.35, compact * 0.60 + phonetic * 0.40)


func _keep_best_by_key(
	entries: Array[Dictionary],
	seen: Dictionary,
	key: String,
	candidate: Dictionary,
	score_key: String
) -> void:
	if not seen.has(key):
		seen[key] = entries.size()
		entries.append(candidate)
		return

	var index := int(seen[key])

	if float(candidate.get(score_key, 0.0)) > float(entries[index].get(score_key, 0.0)):
		entries[index] = candidate


func _sort_alignment_scores(alignments: Array[Dictionary]) -> void:
	alignments.sort_custom(func(left: Dictionary, right: Dictionary):
		var left_exact := bool(left.get("exact", false))
		var right_exact := bool(right.get("exact", false))

		if left_exact != right_exact:
			return left_exact

		var left_score := float(left.get("score", 0.0))
		var right_score := float(right.get("score", 0.0))

		if not is_equal_approx(left_score, right_score):
			return left_score > right_score

		return int(left.get("start", 0)) < int(right.get("start", 0))
	)


func _sort_candidates(candidates: Array[Dictionary]) -> void:
	candidates.sort_custom(func(left: Dictionary, right: Dictionary):
		var left_score := float(left.get("final_score", left.get("score", 0.0)))
		var right_score := float(right.get("final_score", right.get("score", 0.0)))

		if not is_equal_approx(left_score, right_score):
			return left_score > right_score

		return String(left.get("canonical_command", "")) < String(
			right.get("canonical_command", "")
		)
	)


func _prune_candidates(
	candidates: Array[Dictionary],
	limit: int,
	score_key: String = "final_score"
) -> void:
	candidates.sort_custom(func(left: Dictionary, right: Dictionary):
		return float(left.get(score_key, 0.0)) > float(right.get(score_key, 0.0))
	)

	if candidates.size() > limit:
		candidates.resize(limit)


func _collect_alternative_spans(alignments: Array[Dictionary]) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	var limit := mini(TuningScript.TOP_DIAGNOSTIC_CANDIDATES, alignments.size())

	for index in range(limit):
		var alignment: Dictionary = alignments[index]
		spans.append({
			"start": int(alignment.get("start", -1)),
			"end": int(alignment.get("end", -1)),
			"text": String(alignment.get("span_text", "")),
			"canonical": (
				String(alignment.get("action", ""))
				+ (
					" + " + _where_label(Dictionary(alignment.get("where_data", {})))
					if bool(alignment.get("merged", false))
					else ""
				)
			),
			"score": float(alignment.get("score", 0.0))
		})

	return spans


func _tokens_are_when_or_empty(tokens: Array) -> bool:
	if tokens.is_empty():
		return true

	if tokens.size() == 1 and VocabularyScript.WHEN_ALIASES.has(String(tokens[0])):
		return true

	return false


func _initial_slot_states(final_states: Dictionary) -> Dictionary:
	var initial := {}

	for slot in ["who", "what", "where", "when"]:
		var final_state := String(final_states.get(slot, SLOT_INVALID))
		initial[slot] = SLOT_OMITTED if final_state == SLOT_DEFAULTED else final_state

	return initial


func _slot_transitions(
	initial_states: Dictionary,
	final_states: Dictionary
) -> Dictionary:
	var transitions := {}

	for slot in ["who", "what", "where", "when"]:
		var initial_state := String(initial_states.get(slot, SLOT_INVALID))
		var final_state := String(final_states.get(slot, SLOT_INVALID))
		transitions[slot] = (
			[initial_state, final_state]
			if initial_state != final_state
			else [final_state]
		)

	return transitions


func _span_contains_number(tokens: Array[String], start: int, end: int) -> bool:
	for index in range(start, mini(end, tokens.size())):
		var token := tokens[index]

		if token.is_valid_int() or token in [
			"one", "two", "three", "four", "five", "six", "seven", "eight",
			"nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
			"fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"
		]:
			return true

	return false


func _tokens(text: String) -> Array[String]:
	var output: Array[String] = []

	for token_value in text.split(" ", false):
		output.append(String(token_value))

	return output


func _join_tokens(tokens: Array[String], start: int, end: int) -> String:
	var parts: Array[String] = []

	for index in range(start, mini(end, tokens.size())):
		parts.append(tokens[index])

	return " ".join(parts)


func _canonical_command_label(command_data: Dictionary) -> String:
	var selectors: Array = command_data.get("who_selectors", [])
	var selector: Dictionary = (
		Dictionary(selectors[0])
		if not selectors.is_empty() and selectors[0] is Dictionary
		else {}
	)
	return (
		_selector_label(selector)
		+ " → "
		+ String(command_data.get("what", "")).capitalize()
		+ " → "
		+ _where_label(command_data)
		+ " → Now"
	)


func _selector_label(selector: Dictionary) -> String:
	match String(selector.get("type", "")):
		CommandSchemaScript.SELECTOR_EVERYONE:
			return "Everyone"
		CommandSchemaScript.SELECTOR_CLASS:
			return String(selector.get("value", "")).capitalize() + " class"
		CommandSchemaScript.SELECTOR_ROLE:
			return String(selector.get("value", "")).capitalize() + " role"
		CommandSchemaScript.SELECTOR_GROUP:
			return "Row " + str(int(selector.get("value", 0)))
		CommandSchemaScript.SELECTOR_UNIT_IDENTITY:
			return (
				String(selector.get("class", ""))
				+ " "
				+ str(int(selector.get("number", 0)))
			)
		_:
			return String(selector.get("type", "Unknown"))


func _where_label(where_data: Dictionary) -> String:
	match String(where_data.get("where", "")):
		"boss":
			return "Boss"
		"boss_target":
			return "Boss Target"
		"curable_allies":
			return "Curable Allies"
		"me":
			return "Player"
		"movement_region", "movement_rotate":
			return String(where_data.get("movement_region", "")).capitalize()
		"movement_range":
			return String(where_data.get("movement_range", "")).capitalize()
		"movement_slot":
			return (
				String(where_data.get("movement_region", "")).capitalize()
				+ " "
				+ String(where_data.get("movement_range", "")).capitalize()
			)
		"movement_rotate_step", "movement_range_step":
			return String(where_data.get("movement_direction", "")).capitalize()
		_:
			return String(where_data.get("where", "Unknown")).capitalize()


func _canonical_id_for_selector(selector: Dictionary) -> String:
	match String(selector.get("type", "")):
		CommandSchemaScript.SELECTOR_EVERYONE:
			return "everyone"
		CommandSchemaScript.SELECTOR_CLASS:
			return "class:" + String(selector.get("value", ""))
		CommandSchemaScript.SELECTOR_ROLE:
			return "role:" + String(selector.get("value", ""))
		CommandSchemaScript.SELECTOR_GROUP:
			return "group:" + str(int(selector.get("value", 0)))
		CommandSchemaScript.SELECTOR_UNIT_IDENTITY:
			return (
				"unit_identity:"
				+ String(selector.get("class", ""))
				+ ":"
				+ str(int(selector.get("number", 0)))
			)
		_:
			return String(selector.get("type", "")) + ":" + str(selector.get("value", ""))


func _increment_reason(reasons: Dictionary, reason: String) -> void:
	reasons[reason] = int(reasons.get(reason, 0)) + 1


func _normalize_text(text: String) -> String:
	var normalized := text.to_lower().strip_edges()

	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")

	return normalized


func _compact_text(text: String) -> String:
	var output := ""

	for index in range(text.length()):
		var character := text.substr(index, 1)

		if character >= "a" and character <= "z":
			output += character

	return output


func _phonetic_code(text: String) -> String:
	var letters := _compact_text(text)

	if letters.is_empty():
		return ""

	if letters.begins_with("th") and letters.length() > 3:
		letters = letters.substr(2)

	var output := letters.substr(0, 1).to_upper()
	var previous_code := _phonetic_digit(letters.substr(0, 1))

	for index in range(1, letters.length()):
		var code := _phonetic_digit(letters.substr(index, 1))

		if code != "0" and code != previous_code:
			output += code

		previous_code = code

		if output.length() >= 8:
			break

	return output


func _phrase_phonetic_code(text: String) -> String:
	var codes: Array[String] = []

	for token in _tokens(text):
		var code := _phonetic_code(token)

		if not code.is_empty():
			codes.append(code)

	return "-".join(codes)


func _phonetic_similarity(left: String, right: String) -> float:
	if left.is_empty() or right.is_empty():
		return 0.0

	if left == right:
		return 1.0

	var initial := 1.0 if left.substr(0, 1) == right.substr(0, 1) else 0.0
	var digits := _normalized_similarity(left.substr(1), right.substr(1))
	return initial * 0.35 + digits * 0.65


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


func _normalized_similarity(left: String, right: String) -> float:
	if left == right:
		return 1.0

	if left.is_empty() or right.is_empty():
		return 0.0

	var maximum_length := maxi(left.length(), right.length())
	return 1.0 - float(_levenshtein_distance(left, right)) / float(maximum_length)


func _levenshtein_distance(left: String, right: String) -> int:
	var previous: Array[int] = []

	for column in range(right.length() + 1):
		previous.append(column)

	for row in range(1, left.length() + 1):
		var current: Array[int] = [row]
		var left_character := left.substr(row - 1, 1)

		for column in range(1, right.length() + 1):
			var cost := 0 if left_character == right.substr(column - 1, 1) else 1
			current.append(mini(
				current[column - 1] + 1,
				mini(previous[column] + 1, previous[column - 1] + cost)
			))

		previous = current

	return previous[-1]


func _failure(
	raw_transcript: String,
	normalized_transcript: String,
	tokens: Array[String],
	reason: String,
	deterministic_failure: Dictionary,
	started_usec: int,
	timing_usec: Dictionary = {},
	exclusion_reasons: Dictionary = {}
) -> Dictionary:
	var timings := {
		"deterministic_parse_ms": float(
			deterministic_failure.get("duration_usec", 0)
		) / 1000.0,
		"candidate_generation_ms": float(
			timing_usec.get("candidate_generation_usec", 0)
		) / 1000.0,
		"joint_scoring_ms": float(timing_usec.get("joint_scoring_usec", 0)) / 1000.0,
		"validation_ms": 0.0,
		"total_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0
	}
	var resolution := {
		"ok": false,
		"method": METHOD_JOINT,
		"raw_transcript": raw_transcript,
		"normalized_transcript": normalized_transcript,
		"original_tokens": tokens.duplicate(),
		"grammar": "none",
		"slot_states": {
			"who": SLOT_INVALID,
			"what": SLOT_INVALID,
			"where": SLOT_INVALID,
			"when": SLOT_DEFAULTED
		},
		"slot_initial_states": {
			"who": SLOT_INVALID,
			"what": SLOT_INVALID,
			"where": SLOT_INVALID,
			"when": SLOT_OMITTED
		},
		"slot_transitions": {
			"who": [SLOT_INVALID],
			"what": [SLOT_INVALID],
			"where": [SLOT_INVALID],
			"when": [SLOT_OMITTED, SLOT_DEFAULTED]
		},
		"slot_ownership": [],
		"selected_alignment": "none",
		"alternative_spans": [],
		"candidate_scores": [],
		"excluded_candidates": exclusion_reasons.duplicate(true),
		"winner_score": 0.0,
		"runner_up_score": 0.0,
		"winner_margin": 0.0,
		"default_target_reason": "",
		"validation_result": {"ok": false, "reason": reason},
		"timings": timings,
		"duration_ms": float(timings.get("total_ms", 0.0)),
		"cache_generation": vocabulary_generation,
		"final_canonical_command": "",
		"reason": reason,
		"deterministic_failure": deterministic_failure.duplicate(true)
	}
	resolution["debug_text"] = format_diagnostics(resolution)

	if debug_enabled:
		print(String(resolution["debug_text"]))

	return {
		"ok": false,
		"reason": reason,
		"transcript": raw_transcript,
		"normalized_text": normalized_transcript,
		"who_resolution": {},
		"command_resolution": resolution
	}
