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

		var expected_method := String(case.get("expected_method", ""))

		if not expected_method.is_empty() and parse_ok:
			var actual_method := String(who_resolution.get("method", ""))

			if actual_method != expected_method:
				failures.append(
					'Case %d method mismatch: "%s" expected %s, got %s'
					% [case_index, transcript, expected_method, actual_method]
				)

		if parse_ok:
			_validate_expected_command(case_index, transcript, case, parse_result)

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
		"average_resolver_duration_ms": (
			duration_total / float(duration_count)
			if duration_count > 0
			else 0.0
		),
		"maximum_resolver_duration_ms": maximum_duration
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
