extends Node

const VoiceCommandParserScript := preload("res://scripts/voice/voice_command_parser.gd")
const CommandTargetResolverScript := preload("res://scripts/commands/command_target_resolver.gd")
const CORPUS_PATH := "res://tests/voice/who_resolution_corpus.json"


class DummyUnit:
	extends Node

	var unit_class: String = ""
	var unit_number: int = 0
	var member_id: String = ""
	var alive: bool = true
	var roles: Array[String] = []

	func _init(new_class: String, new_number: int, new_roles: Array[String]) -> void:
		unit_class = new_class
		unit_number = new_number
		member_id = new_class.to_lower() + "_" + str(new_number)
		roles = new_roles.duplicate()
		name = new_class + "_" + str(new_number)

	func get_class_ordinal() -> int:
		return unit_number

	func get_member_id() -> String:
		return member_id

	func get_display_name() -> String:
		return unit_class + " " + str(unit_number)

	func has_role(role_name: String) -> bool:
		return roles.has(role_name)

	func is_alive() -> bool:
		return alive


var failures: Array[String] = []
var owned_units: Array[Node] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var corpus_result := _load_corpus()

	if not bool(corpus_result.get("ok", false)):
		_fail(String(corpus_result.get("reason", "Could not load Who corpus.")))
		return

	var corpus: Array = corpus_result.get("cases", [])
	var roster := _build_full_roster()
	var parser := VoiceCommandParserScript.new()
	get_tree().root.add_child(parser)
	parser.setup_roster_context(roster)

	var correct := 0
	var incorrect := 0
	var unresolved := 0
	var invalid_samples := 0
	var duration_total := 0.0
	var duration_count := 0
	var maximum_duration := 0.0
	var weighted_duration_total := 0.0
	var weighted_duration_count := 0
	var weighted_maximum_duration := 0.0
	var category_stats: Dictionary = {}
	var target_type_stats: Dictionary = {}
	var confusion: Dictionary = {}

	for case_index in range(corpus.size()):
		var case_value = corpus[case_index]

		if not case_value is Dictionary:
			failures.append("Corpus entry %d is not a dictionary." % case_index)
			continue

		var case: Dictionary = case_value
		var transcript := String(case.get("transcript", ""))
		var expected := String(case.get("expected_target", ""))
		var category := String(case.get("category", "uncategorized"))
		var expected_type := String(case.get("expected_target_type", "unspecified"))
		var parse_result := parser.parse(transcript)
		var parse_ok := bool(parse_result.get("ok", false))
		var actual := _canonical_target(parse_result)
		var case_correct := false

		if expected == "invalid":
			invalid_samples += 1
			case_correct = not parse_ok
		else:
			case_correct = parse_ok and actual == expected

		if case_correct:
			correct += 1
		elif not parse_ok:
			unresolved += 1
			failures.append(
				'Case %d unresolved: "%s" expected %s; reason: %s'
				% [case_index, transcript, expected, String(parse_result.get("reason", ""))]
			)
		else:
			incorrect += 1
			failures.append(
				'Case %d incorrect: "%s" expected %s, got %s'
				% [case_index, transcript, expected, actual]
			)

		_increment_stat(category_stats, category, case_correct)
		_increment_stat(target_type_stats, expected_type, case_correct)
		_increment_confusion(confusion, expected, actual if parse_ok else "unresolved")

		var who_resolution: Dictionary = parse_result.get("who_resolution", {})
		var duration_ms := float(who_resolution.get("duration_ms", 0.0))
		duration_total += duration_ms
		duration_count += 1
		maximum_duration = maxf(maximum_duration, duration_ms)
		var actual_method := String(who_resolution.get("method", ""))

		if actual_method == "weighted_phonetic":
			weighted_duration_total += duration_ms
			weighted_duration_count += 1
			weighted_maximum_duration = maxf(weighted_maximum_duration, duration_ms)

		var expected_method := String(case.get("expected_method", ""))

		if not expected_method.is_empty() and parse_ok:
			if actual_method != expected_method:
				failures.append(
					'Case %d method mismatch: "%s" expected %s, got %s'
					% [case_index, transcript, expected_method, actual_method]
				)

		if parse_ok:
			_validate_expected_command(case_index, transcript, case, parse_result)

	var focused_metrics := _validate_scoring_refinement(roster)
	_validate_cache_rebuild(parser, roster)
	_validate_execution_mapping(parser, roster)

	var total := corpus.size()
	var summary := {
		"total_samples": total,
		"correct_who_resolutions": correct,
		"incorrect_who_resolutions": incorrect,
		"invalid_or_unresolved_samples": invalid_samples + unresolved,
		"overall_who_accuracy": float(correct) / float(maxi(total, 1)),
		"accuracy_by_category": _format_stats(category_stats),
		"accuracy_by_target_type": _format_stats(target_type_stats),
		"confusion_summary": confusion,
		"lawyer_one_diagnostic": focused_metrics,
		"average_resolver_duration_ms": (
			duration_total / float(duration_count)
			if duration_count > 0
			else 0.0
		),
		"maximum_resolver_duration_ms": maximum_duration,
		"average_weighted_resolver_duration_ms": (
			weighted_duration_total / float(weighted_duration_count)
			if weighted_duration_count > 0
			else 0.0
		),
		"maximum_weighted_resolver_duration_ms": weighted_maximum_duration
	}
	print("Who resolution corpus summary: ", JSON.stringify(summary))

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)

		get_tree().quit(1)
		return

	print("Who resolution corpus and regression checks passed.")
	get_tree().quit(0)


func _load_corpus() -> Dictionary:
	var file := FileAccess.open(CORPUS_PATH, FileAccess.READ)

	if file == null:
		return {"ok": false, "reason": "Could not open " + CORPUS_PATH}

	var parsed = JSON.parse_string(file.get_as_text())

	if not parsed is Array:
		return {"ok": false, "reason": "Who corpus root must be an array."}

	return {"ok": true, "cases": parsed}


func _build_full_roster() -> Array:
	var roster: Array = []
	_add_class_units(roster, "Warrior", 2, ["tank", "melee"])
	_add_class_units(roster, "Priest", 5, ["healer", "caster"])
	_add_class_units(roster, "Rogue", 6, ["melee", "melee_dps", "dps"])
	_add_class_units(roster, "Mage", 7, ["ranged", "ranged_dps", "caster", "dps"])
	return roster


func _add_class_units(
	roster: Array,
	unit_class: String,
	count: int,
	unit_roles: Array[String]
) -> void:
	for unit_number in range(1, count + 1):
		var unit := DummyUnit.new(unit_class, unit_number, unit_roles)
		get_tree().root.add_child(unit)
		owned_units.append(unit)
		roster.append(unit)


func _canonical_target(parse_result: Dictionary) -> String:
	if not bool(parse_result.get("ok", false)):
		return ""

	var who_resolution: Dictionary = parse_result.get("who_resolution", {})
	var canonical_id := String(who_resolution.get("canonical_id", ""))

	if not canonical_id.is_empty():
		return canonical_id

	var command_data: Dictionary = parse_result.get("command_data", {})
	var selectors: Array = command_data.get("who_selectors", [])
	return _canonical_selector(selectors[0] if not selectors.is_empty() else {})


func _canonical_selector(selector_value: Variant) -> String:
	if not selector_value is Dictionary:
		return ""

	var selector: Dictionary = selector_value
	var selector_type := String(selector.get("type", ""))

	match selector_type:
		"everyone":
			return "everyone"
		"class":
			return "class:" + String(selector.get("value", ""))
		"group":
			return "group:" + str(int(selector.get("value", 0)))
		"role":
			return "role:" + String(selector.get("value", ""))
		"unit_identity":
			return (
				"unit_identity:"
				+ String(selector.get("class", ""))
				+ ":"
				+ str(int(selector.get("number", 0)))
			)
		_:
			return selector_type + ":" + str(selector.get("value", ""))


func _validate_expected_command(
	case_index: int,
	transcript: String,
	case: Dictionary,
	parse_result: Dictionary
) -> void:
	var expected_value = case.get("expected_command", {})

	if not expected_value is Dictionary or expected_value.is_empty():
		return

	var expected: Dictionary = expected_value
	var command_data: Dictionary = parse_result.get("command_data", {})

	for key in expected.keys():
		if command_data.get(key) != expected[key]:
			failures.append(
				'Case %d command regression: "%s" expected %s=%s, got %s'
				% [case_index, transcript, key, str(expected[key]), str(command_data.get(key))]
				)


func _validate_scoring_refinement(roster: Array) -> Dictionary:
	var parser := _new_parser(roster)
	var resolver = parser.get_who_resolver()
	_seed_recent_targets(resolver, "unit_identity:Mage:1")
	var lawyer_result := resolver.resolve_who(
		"Lawyer 1, move east.",
		"lawyer 1 move east",
		"lawyer 1",
		{"what": "move", "where": "movement_region"}
	)
	var warrior_score := _find_candidate_score(
		lawyer_result,
		"unit_identity:Warrior:1"
	)
	var mage_score := _find_candidate_score(
		lawyer_result,
		"unit_identity:Mage:1"
	)

	_expect(
		String(lawyer_result.get("canonical_id", "")) == "unit_identity:Warrior:1",
		"Lawyer 1 did not resolve to Warrior 1 with recent usage biased toward Mage 1."
	)
	_expect(
		String(lawyer_result.get("identity_text", "")) == "lawyer",
		"Lawyer 1 identity extraction did not isolate \"lawyer\"."
	)
	_expect(
		int(lawyer_result.get("recognized_number", 0)) == 1,
		"Lawyer 1 number extraction did not isolate index 1."
	)
	_expect(
		String(lawyer_result.get("inferred_structure", "")) == "numbered_individual",
		"Lawyer 1 did not infer numbered-individual structure."
	)
	_expect(
		float(warrior_score.get("identity_score", 0.0))
		> float(mage_score.get("identity_score", 0.0)),
		"Warrior 1 did not have stronger identity evidence than Mage 1 for Lawyer 1."
	)
	_expect(
		is_zero_approx(float(mage_score.get("recent_use_prior", 0.0))),
		"Mage 1 recent use was applied outside the identity tie window."
	)
	var lawyer_identity_only_result := resolver.resolve_who(
		"Lawyer one, move.",
		"lawyer one move",
		"lawyer one",
		{"what": "move"}
	)
	_expect(
		String(lawyer_identity_only_result.get("identity_text", "")) == "lawyer"
		and int(lawyer_identity_only_result.get("recognized_number", 0)) == 1
		and String(lawyer_identity_only_result.get("canonical_id", ""))
		== "unit_identity:Warrior:1",
		"Lawyer one did not preserve separated identity, index, and selection."
	)
	var lawyer_debug_text := String(lawyer_result.get("debug_text", ""))
	print("Lawyer 1 diagnostic:\n", lawyer_debug_text)

	for required_debug_label in [
		'identity_text: "lawyer"',
		"recognized_number: 1",
		"eligible candidates:",
		"identity_text_similarity:",
		"identity_phonetic_similarity:",
		"identity_score:",
		"winner_score:",
		"runner_up_score:",
		"winner_margin:"
	]:
		_expect(
			lawyer_debug_text.contains(required_debug_label),
			"Lawyer 1 diagnostics are missing " + required_debug_label
		)

	var eligible_candidates: Array = lawyer_result.get("eligible_candidates", [])
	_expect(
		eligible_candidates.size() == 4,
		"Lawyer 1 should admit only the four same-index class individuals."
	)
	_expect(
		_has_exclusion(
			lawyer_result,
			"group:1",
			"insufficient_row_identity_evidence"
		),
		"Lawyer 1 diagnostics did not explain why Row 1 was ineligible."
	)

	for score_value in lawyer_result.get("candidate_scores", []):
		if not score_value is Dictionary:
			continue

		var score: Dictionary = score_value
		_expect(
			String(score.get("target_type", "")) == "numbered_individual",
			"Lawyer 1 retained a non-individual candidate without row-like evidence."
		)
		_expect(
			int(score.get("number", 0)) == 1,
			"Lawyer 1 retained a candidate with a conflicting index."
		)
		_expect(
			String(score.get("identity_text", "")) == "lawyer",
			"A Lawyer 1 candidate received the full numbered phrase as identity text."
		)
		_expect(
			String(score.get("identity_phonetic_input", "")) == "lawyer",
			"A Lawyer 1 candidate included the number in its phonetic input."
		)

	var phonetic_scores: Array[float] = []

	for class_id in [
		"unit_identity:Warrior:1",
		"unit_identity:Priest:1",
		"unit_identity:Rogue:1",
		"unit_identity:Mage:1"
	]:
		var score := _find_candidate_score(lawyer_result, class_id)
		phonetic_scores.append(float(score.get("identity_phonetic_similarity", 0.0)))

	var all_phonetic_scores_equal := true

	for index in range(1, phonetic_scores.size()):
		if not is_equal_approx(phonetic_scores[0], phonetic_scores[index]):
			all_phonetic_scores_equal = false
			break

	_expect(
		not all_phonetic_scores_equal,
		"Lawyer still gives Warrior, Priest, Rogue, and Mage identical phonetic scores."
	)

	for candidate in resolver.get_candidate_cache_snapshot():
		for alias_value in candidate.get("identity_aliases", []):
			_expect(
				String(alias_value) != "lawyer",
				"Lawyer was added as a hard-coded identity alias."
			)

	var exact_identity_result := resolver.resolve_who(
		"Warrior one, move.",
		"warrior one move",
		"warrior one",
		{"what": "move"}
	)
	_expect(
		String(exact_identity_result.get("identity_text", "")) == "warrior"
		and int(exact_identity_result.get("recognized_number", 0)) == 1
		and String(exact_identity_result.get("canonical_id", ""))
		== "unit_identity:Warrior:1",
		"Warrior one did not preserve separated identity, index, and selection."
	)

	var lawyer_command := parser.parse("lawyer 1 move east")
	var lawyer_command_data: Dictionary = lawyer_command.get("command_data", {})
	_expect(
		bool(lawyer_command.get("ok", false))
		and _canonical_target(lawyer_command) == "unit_identity:Warrior:1"
		and String(lawyer_command_data.get("what", "")) == "move"
		and String(lawyer_command_data.get("where", "")) == "movement_region"
		and String(lawyer_command_data.get("movement_region", "")) == "east",
		"Lawyer 1 did not preserve Move and East parsing."
	)

	var lawyer_slot_command := parser.parse("lawyer 1 move north close")
	var lawyer_slot_data: Dictionary = lawyer_slot_command.get("command_data", {})
	_expect(
		bool(lawyer_slot_command.get("ok", false))
		and _canonical_target(lawyer_slot_command) == "unit_identity:Warrior:1"
		and String(lawyer_slot_data.get("where", "")) == "movement_slot"
		and String(lawyer_slot_data.get("movement_region", "")) == "north"
		and String(lawyer_slot_data.get("movement_range", "")) == "close",
		"Lawyer 1 did not preserve the North Close movement slot."
	)

	var rogue_result := resolver.resolve_who(
		"Rogue three, move.",
		"rogue three move",
		"rogue three",
		{"what": "move"}
	)
	_expect(
		String(rogue_result.get("canonical_id", "")) == "unit_identity:Rogue:3",
		"Rogue 3 did not beat Row 3 when class identity favored Rogue."
	)

	var row_parser := _new_parser(roster)
	var row_resolver = row_parser.get_who_resolver()
	_seed_recent_targets(row_resolver, "unit_identity:Warrior:1")
	var row_result := row_resolver.resolve_who(
		"Row one, move.",
		"row one move",
		"row one",
		{"what": "move"}
	)
	_expect(
		String(row_result.get("canonical_id", "")) == "group:1",
		"Clear Row 1 evidence did not beat the Warrior 1 recent-use prior."
	)

	var distorted_row_result := row_resolver.resolve_who(
		"Roe one, move.",
		"roe one move",
		"roe one",
		{"what": "move"}
	)
	_expect(
		String(distorted_row_result.get("canonical_id", "")) == "group:1",
		"Meaningful distorted row evidence did not admit and select Row 1."
	)

	var mage_parser := _new_parser(roster)
	var mage_resolver = mage_parser.get_who_resolver()
	_seed_recent_targets(mage_resolver, "unit_identity:Warrior:1")
	var mage_result := mage_resolver.resolve_who(
		"Mage one, move.",
		"mage one move",
		"mage one",
		{"what": "move"}
	)
	_expect(
		String(mage_result.get("canonical_id", "")) == "unit_identity:Mage:1",
		"A clear Mage 1 identity was overridden by Warrior 1 recent use."
	)
	_expect(
		String(mage_parser.parse("mage one move east").get("who_resolution", {}).get(
			"method",
			""
		)) == "deterministic",
		"Exact Mage 1 unexpectedly entered weighted fallback."
	)

	var tie_parser := _new_parser(roster)
	var tie_resolver = tie_parser.get_who_resolver()
	_seed_recent_targets(tie_resolver, "unit_identity:Rogue:1")
	var tied_result := tie_resolver.resolve_who(
		"One, move.",
		"one move",
		"one",
		{"what": "move"}
	)
	_expect(
		String(tied_result.get("canonical_id", "")) == "unit_identity:Rogue:1",
		"Recent use did not break a genuinely tied numbered-individual identity."
	)

	for score_value in tied_result.get("candidate_scores", []):
		if score_value is Dictionary:
			_expect(
				is_zero_approx(float(score_value.get("identity_score", 0.0))),
				"A shared number alone produced non-zero class identity evidence."
			)

	return {
		"selected": String(lawyer_result.get("canonical_id", "")),
		"winner_score": float(lawyer_result.get("winner_score", 0.0)),
		"runner_up_score": float(lawyer_result.get("runner_up_score", 0.0)),
		"winner_margin": float(lawyer_result.get("winner_margin", 0.0)),
		"warrior_identity_score": float(warrior_score.get("identity_score", 0.0)),
		"mage_identity_score": float(mage_score.get("identity_score", 0.0)),
		"duration_ms": float(lawyer_result.get("duration_ms", 0.0))
	}


func _new_parser(roster: Array) -> VoiceCommandParser:
	var parser := VoiceCommandParserScript.new()
	get_tree().root.add_child(parser)
	parser.setup_roster_context(roster)
	return parser


func _seed_recent_targets(resolver: WhoTargetResolver, canonical_id: String) -> void:
	resolver.recent_target_keys.clear()

	for index in range(12):
		resolver.recent_target_keys.append(canonical_id)


func _find_candidate_score(resolution: Dictionary, canonical_id: String) -> Dictionary:
	for score_value in resolution.get("candidate_scores", []):
		if (
			score_value is Dictionary
			and String(score_value.get("canonical_id", "")) == canonical_id
		):
			return score_value

	return {}


func _has_exclusion(
	resolution: Dictionary,
	canonical_id: String,
	reason: String
) -> bool:
	for exclusion_value in resolution.get("excluded_candidates", []):
		if (
			exclusion_value is Dictionary
			and String(exclusion_value.get("canonical_id", "")) == canonical_id
			and String(exclusion_value.get("reason", "")) == reason
		):
			return true

	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _validate_cache_rebuild(parser: VoiceCommandParser, full_roster: Array) -> void:
	var resolver := parser.get_who_resolver()
	var original_generation := resolver.get_cache_generation()
	var original_count := resolver.get_candidate_count()
	var reduced_roster: Array = [full_roster[0], full_roster[2]]
	parser.setup_roster_context(reduced_roster)

	if resolver.get_cache_generation() <= original_generation:
		failures.append("Who candidate cache generation did not advance after a roster change.")

	if resolver.get_candidate_count() >= original_count:
		failures.append("Who candidate cache did not shrink for the reduced roster.")

	for candidate in resolver.get_candidate_cache_snapshot():
		if String(candidate.get("canonical_id", "")) == "unit_identity:Warrior:2":
			failures.append("Who candidate cache retained Warrior 2 after the roster changed.")

	parser.setup_roster_context(full_roster)


func _validate_execution_mapping(parser: VoiceCommandParser, roster: Array) -> void:
	var parse_result := parser.parse("warrior one attack")

	if not bool(parse_result.get("ok", false)):
		failures.append("Canonical execution mapping setup command did not parse.")
		return

	var target_resolver := CommandTargetResolverScript.new()
	target_resolver.setup(roster)
	var selected_units := target_resolver.get_units_for_command(
		Dictionary(parse_result.get("command_data", {}))
	)

	if selected_units.size() != 1 or selected_units[0] != roster[0]:
		failures.append("Selected canonical unit_identity did not map to Warrior 1.")

	var row_result := parser.parse("row one attack")
	var row_units := target_resolver.get_units_for_command(
		Dictionary(row_result.get("command_data", {}))
	)

	if row_units.size() != 5:
		failures.append("Canonical Row 1 selector did not map to the first five raid members.")


func _increment_stat(stats: Dictionary, key: String, was_correct: bool) -> void:
	var entry: Dictionary = stats.get(key, {"total": 0, "correct": 0})
	entry["total"] = int(entry.get("total", 0)) + 1

	if was_correct:
		entry["correct"] = int(entry.get("correct", 0)) + 1

	stats[key] = entry


func _format_stats(stats: Dictionary) -> Dictionary:
	var formatted: Dictionary = {}

	for key in stats.keys():
		var entry: Dictionary = stats[key]
		var total := int(entry.get("total", 0))
		var correct := int(entry.get("correct", 0))
		formatted[key] = {
			"correct": correct,
			"total": total,
			"accuracy": float(correct) / float(maxi(total, 1))
		}

	return formatted


func _increment_confusion(confusion: Dictionary, expected: String, actual: String) -> void:
	var key := expected + " -> " + actual
	confusion[key] = int(confusion.get(key, 0)) + 1


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
