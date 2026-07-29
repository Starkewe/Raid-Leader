extends Node

const VoiceCommandParserScript := preload("res://scripts/voice/voice_command_parser.gd")
const VocabularyScript := preload("res://scripts/voice/voice_command_vocabulary.gd")
const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const CommandTargetResolverScript := preload("res://scripts/commands/command_target_resolver.gd")
const CORPUS_PATH := "res://tests/voice/command_decoder_corpus.json"


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
		_finish_failure(String(corpus_result.get("reason", "Could not load command corpus.")))
		return

	var corpus: Array = corpus_result.get("cases", [])
	var roster := _build_full_roster()
	var parser := _new_parser(roster)
	var full_correct := 0
	var incorrect_commands := 0
	var invalid_or_unresolved := 0
	var who_correct := 0
	var what_correct := 0
	var where_correct := 0
	var when_correct := 0
	var valid_expected_count := 0
	var default_expected_count := 0
	var default_correct := 0
	var deterministic_count := 0
	var joint_count := 0
	var deterministic_duration_total := 0.0
	var joint_duration_total := 0.0
	var maximum_joint_duration := 0.0
	var category_stats: Dictionary = {}
	var slot_confusions: Dictionary = {}

	for case_index in range(corpus.size()):
		var case_value = corpus[case_index]

		if not case_value is Dictionary:
			failures.append("Corpus entry %d is not a dictionary." % case_index)
			continue

		var case: Dictionary = case_value
		var transcript := String(case.get("transcript", ""))
		var case_id := String(case.get("id", "case_%d" % case_index))
		var expected_valid := bool(case.get("expected_valid", true))
		var parse_result := parser.parse(transcript)
		var parse_ok := bool(parse_result.get("ok", false))
		var command_data: Dictionary = parse_result.get("command_data", {})
		var resolution: Dictionary = parse_result.get("command_resolution", {})
		var method := String(resolution.get("method", ""))
		var case_correct := true

		if not expected_valid:
			case_correct = not parse_ok

			if parse_ok:
				incorrect_commands += 1
				failures.append(
					'%s accepted invalid transcript "%s" as %s'
					% [case_id, transcript, String(resolution.get("final_canonical_command", ""))]
				)
			else:
				invalid_or_unresolved += 1
		else:
			valid_expected_count += 1

			if not parse_ok:
				case_correct = false
				invalid_or_unresolved += 1
				failures.append(
					'%s unresolved: "%s"; reason: %s\n%s'
					% [
						case_id,
						transcript,
						String(parse_result.get("reason", "")),
						String(resolution.get("debug_text", ""))
					]
				)
			else:
				var actual_who := _canonical_target(parse_result)
				var expected_who := String(case.get("expected_who", ""))
				var actual_what := String(command_data.get("what", ""))
				var expected_what := String(case.get("expected_what", ""))
				var actual_where := _canonical_where(command_data)
				var expected_where := _expected_where(case)
				var actual_when := String(command_data.get("when", ""))
				var expected_when := String(case.get("expected_when", "now"))
				var who_matches := actual_who == expected_who
				var what_matches := actual_what == expected_what
				var where_matches := actual_where == expected_where
				var when_matches := actual_when == expected_when
				who_correct += 1 if who_matches else 0
				what_correct += 1 if what_matches else 0
				where_correct += 1 if where_matches else 0
				when_correct += 1 if when_matches else 0
				_record_confusion(slot_confusions, "who", expected_who, actual_who)
				_record_confusion(slot_confusions, "what", expected_what, actual_what)
				_record_confusion(slot_confusions, "where", expected_where, actual_where)
				_record_confusion(slot_confusions, "when", expected_when, actual_when)
				case_correct = (
					who_matches
					and what_matches
					and where_matches
					and when_matches
				)

				if not case_correct:
					incorrect_commands += 1
					failures.append(
						"%s command mismatch: expected %s | %s | %s | %s, got %s | %s | %s | %s\n%s"
						% [
							case_id,
							expected_who,
							expected_what,
							expected_where,
							expected_when,
							actual_who,
							actual_what,
							actual_where,
							actual_when,
							String(resolution.get("debug_text", ""))
						]
					)

				var expected_method := String(case.get("expected_method", ""))

				if not expected_method.is_empty() and method != expected_method:
					case_correct = false
					failures.append(
						"%s method mismatch: expected %s, got %s"
						% [case_id, expected_method, method]
					)

				var states: Dictionary = resolution.get("slot_states", {})
				var expected_who_state := String(case.get("expected_who_state", ""))

				if (
					not expected_who_state.is_empty()
					and String(states.get("who", "")) != expected_who_state
				):
					case_correct = false
					failures.append(
						"%s Who state mismatch: expected %s, got %s"
						% [case_id, expected_who_state, String(states.get("who", ""))]
					)

				var expected_when_state := String(case.get("expected_when_state", ""))

				if (
					not expected_when_state.is_empty()
					and String(states.get("when", "")) != expected_when_state
				):
					case_correct = false
					failures.append(
						"%s When state mismatch: expected %s, got %s"
						% [case_id, expected_when_state, String(states.get("when", ""))]
					)

				var expected_default_reason := String(case.get("expected_default_reason", ""))

				if not expected_default_reason.is_empty():
					default_expected_count += 1

					if String(resolution.get("default_target_reason", "")) == expected_default_reason:
						default_correct += 1
					else:
						case_correct = false
						failures.append(
							"%s default reason mismatch: expected %s, got %s"
							% [
								case_id,
								expected_default_reason,
								String(resolution.get("default_target_reason", ""))
							]
						)

				var alignment_fragment := String(case.get("expected_alignment_contains", ""))

				if (
					not alignment_fragment.is_empty()
					and not String(resolution.get("selected_alignment", "")).contains(
						alignment_fragment
					)
				):
					case_correct = false
					failures.append(
						"%s alignment did not contain %s: %s"
						% [
							case_id,
							alignment_fragment,
							String(resolution.get("selected_alignment", ""))
						]
					)

		if case_correct:
			full_correct += 1

		_increment_category(
			category_stats,
			String(case.get("category", "uncategorized")),
			case_correct
		)

		var timings: Dictionary = resolution.get("timings", {})
		var duration := float(timings.get("total_ms", 0.0))

		if method == "deterministic":
			deterministic_count += 1
			deterministic_duration_total += duration
		elif method == "joint_weighted":
			joint_count += 1
			joint_duration_total += duration
			maximum_joint_duration = maxf(maximum_joint_duration, duration)

	_validate_direct_regressions(parser, roster)

	var total := corpus.size()
	var summary := {
		"total_samples": total,
		"exact_full_command_accuracy": float(full_correct) / float(maxi(total, 1)),
		"full_commands_correct": full_correct,
		"who_accuracy": float(who_correct) / float(maxi(valid_expected_count, 1)),
		"what_accuracy": float(what_correct) / float(maxi(valid_expected_count, 1)),
		"where_accuracy": float(where_correct) / float(maxi(valid_expected_count, 1)),
		"when_accuracy": float(when_correct) / float(maxi(valid_expected_count, 1)),
		"accuracy_by_category": _format_categories(category_stats),
		"incorrect_command_count": incorrect_commands,
		"invalid_or_unresolved_count": invalid_or_unresolved,
		"default_target_accuracy": (
			float(default_correct) / float(maxi(default_expected_count, 1))
		),
		"slot_confusion_summary": slot_confusions,
		"average_deterministic_latency_ms": (
			deterministic_duration_total / float(maxi(deterministic_count, 1))
		),
		"average_weighted_latency_ms": (
			joint_duration_total / float(maxi(joint_count, 1))
		),
		"maximum_weighted_latency_ms": maximum_joint_duration,
		"deterministic_path_percentage": (
			float(deterministic_count) / float(maxi(deterministic_count + joint_count, 1))
		),
		"joint_weighted_path_percentage": (
			float(joint_count) / float(maxi(deterministic_count + joint_count, 1))
		)
	}
	print("Command decoder corpus summary: ", JSON.stringify(summary))

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)

		get_tree().quit(1)
		return

	print("Complete command decoder corpus and direct regressions passed.")
	get_tree().quit(0)


func _validate_direct_regressions(parser: VoiceCommandParser, roster: Array) -> void:
	var exact := parser.parse("warrior one move east")
	var exact_resolution: Dictionary = exact.get("command_resolution", {})
	_expect(
		String(exact_resolution.get("method", "")) == "deterministic"
		and Array(exact_resolution.get("candidate_scores", [])).is_empty(),
		"Clear exact commands entered joint candidate scoring."
	)

	var healing_cases := {
		"priests heal rogues": "class:Rogue",
		"priest one heal rogue three": "unit_identity:Rogue:3",
		"healers heal group two": "group:2",
		"priests heal the active tank": "active_tank",
		"healers heal the raid": "raid"
	}

	for transcript_value in healing_cases.keys():
		var healing_result := parser.parse(String(transcript_value))
		var healing_command: Dictionary = healing_result.get("command_data", {})
		_expect(
			bool(healing_result.get("ok", false))
			and _canonical_healing_scope(
				Dictionary(healing_command.get("healing_scope", {}))
			) == String(healing_cases[transcript_value]),
			"%s did not preserve its explicit healing scope." % transcript_value
		)

	for invalid_heal in ["priests heal", "priests heal everyone"]:
		_expect(
			not bool(parser.parse(invalid_heal).get("ok", false)),
			"%s issued a heal without a valid explicit target." % invalid_heal
		)

	for transcript in ["move south", "move west", "rotate clockwise"]:
		var omitted := parser.parse(transcript)
		var omitted_resolution: Dictionary = omitted.get("command_resolution", {})
		var ownership: Array = omitted_resolution.get("slot_ownership", [])
		_expect(
			not _ownership_has_slot(ownership, "Who"),
			"%s assigned action or destination evidence to Who." % transcript
		)
		_expect(
			String(
				Dictionary(omitted_resolution.get("slot_initial_states", {})).get(
					"who",
					""
				)
			) == "omitted"
			and String(
				Dictionary(omitted_resolution.get("slot_states", {})).get("who", "")
			) == "defaulted",
			"%s did not record omitted-to-defaulted Who state." % transcript
		)
		_expect(
			Array(Dictionary(omitted.get("who_resolution", {})).get(
				"candidate_scores",
				[]
			)).is_empty(),
			"%s ran weighted Who scoring for an omitted target." % transcript
		)

	var please := parser.parse("please move south")
	var please_resolution: Dictionary = please.get("command_resolution", {})
	var please_candidates: Array = please_resolution.get("candidate_scores", [])
	_expect(
		_candidate_list_contains(please_candidates, "Priest class")
		and _candidate_list_contains(please_candidates, "Everyone"),
		"Please did not retain competing explicit-Priest and filler/default commands."
	)

	for action_value in VocabularyScript.ACTION_ALIASES.values():
		_expect(
			not Array(action_value).has("movies"),
			"Movies was added as a one-off action alias."
		)

	var movies := parser.parse("movies")
	var movies_resolution: Dictionary = movies.get("command_resolution", {})
	_expect(
		String(movies_resolution.get("selected_alignment", "")).contains("one_to_many"),
		"Movies did not use generalized one-to-many alignment."
	)
	_expect(
		_ownership_has_slot(
			Array(movies_resolution.get("slot_ownership", [])),
			"What + Where"
		),
		"Movies did not assign its shared span to What + Where."
	)

	var resolver = parser.get_who_resolver()
	resolver.recent_target_keys.clear()

	for index in range(12):
		resolver.recent_target_keys.append("unit_identity:Warrior:1")

	var clear_mage := parser.parse("mage one move left")
	_expect(
		_canonical_target(clear_mage) == "unit_identity:Mage:1",
		"Recent Warrior history overrode clear Mage identity evidence."
	)

	var lawyer := parser.parse("lawyer one move east")
	var lawyer_resolution: Dictionary = lawyer.get("command_resolution", {})
	_expect(
		bool(lawyer.get("ok", false))
		and lawyer_resolution.has("winner_margin")
		and float(lawyer_resolution.get("winner_margin", 0.0)) >= 0.0,
		"Winner margin rejected or was not logged for a valid forced-choice command."
	)
	_expect(
		Array(lawyer_resolution.get("candidate_scores", [])).size() <= 12,
		"Complete-command beam exceeded its configured bound."
	)

	var original_generation := resolver.get_cache_generation()
	var reduced_roster: Array = [roster[0], roster[2]]
	parser.setup_roster_context(reduced_roster)
	_expect(
		resolver.get_cache_generation() > original_generation,
		"Roster setup did not rebuild state-dependent target candidates."
	)
	parser.setup_roster_context(roster)

	var mapping := parser.parse("warrior one attack")
	var target_resolver := CommandTargetResolverScript.new()
	target_resolver.setup(roster)
	var selected_units := target_resolver.get_units_for_command(
		Dictionary(mapping.get("command_data", {}))
	)
	_expect(
		selected_units.size() == 1 and selected_units[0] == roster[0],
		"Canonical decoder output did not map to the existing execution target."
	)


func _load_corpus() -> Dictionary:
	var file := FileAccess.open(CORPUS_PATH, FileAccess.READ)

	if file == null:
		return {"ok": false, "reason": "Could not open " + CORPUS_PATH}

	var parsed = JSON.parse_string(file.get_as_text())

	if not parsed is Array:
		return {"ok": false, "reason": "Command corpus root must be an array."}

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


func _new_parser(roster: Array) -> VoiceCommandParser:
	var parser := VoiceCommandParserScript.new()
	get_tree().root.add_child(parser)
	parser.setup_roster_context(roster)
	return parser


func _canonical_target(parse_result: Dictionary) -> String:
	if not bool(parse_result.get("ok", false)):
		return ""

	var command_data: Dictionary = parse_result.get("command_data", {})
	var selectors: Array = command_data.get("who_selectors", [])

	if selectors.is_empty() or not selectors[0] is Dictionary:
		return ""

	var selector: Dictionary = selectors[0]

	match String(selector.get("type", "")):
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
			return String(selector.get("type", "")) + ":" + str(selector.get("value", ""))


func _canonical_where(command_data: Dictionary) -> String:
	var output := String(command_data.get("where", ""))

	if output == CommandSchemaScript.DESTINATION_HEALING_SCOPE:
		return output + ":" + _canonical_healing_scope(
			Dictionary(command_data.get("healing_scope", {}))
		)

	for key in ["movement_region", "movement_range", "movement_direction"]:
		var value := String(command_data.get(key, ""))

		if not value.is_empty():
			output += ":" + value

	return output


func _canonical_healing_scope(scope: Dictionary) -> String:
	match String(scope.get("type", "")):
		CommandSchemaScript.HEAL_SCOPE_ACTIVE_TANK:
			return CommandSchemaScript.HEAL_SCOPE_ACTIVE_TANK
		CommandSchemaScript.HEAL_SCOPE_RAID:
			return CommandSchemaScript.HEAL_SCOPE_RAID
		CommandSchemaScript.SELECTOR_CLASS:
			return "class:" + String(scope.get("value", ""))
		CommandSchemaScript.SELECTOR_GROUP:
			return "group:" + str(int(scope.get("value", 0)))
		CommandSchemaScript.SELECTOR_UNIT_IDENTITY:
			return (
				"unit_identity:"
				+ String(scope.get("class", ""))
				+ ":"
				+ str(int(scope.get("number", 0)))
			)

	return String(scope.get("type", "invalid"))


func _expected_where(case: Dictionary) -> String:
	var output := String(case.get("expected_where", ""))

	for key in [
		"expected_movement_region",
		"expected_movement_range",
		"expected_movement_direction"
	]:
		var value := String(case.get(key, ""))

		if not value.is_empty():
			output += ":" + value

	return output


func _ownership_has_slot(ownership: Array, slot: String) -> bool:
	for owner_value in ownership:
		if (
			owner_value is Dictionary
			and String(Dictionary(owner_value).get("slot", "")) == slot
		):
			return true

	return false


func _candidate_list_contains(candidates: Array, fragment: String) -> bool:
	for candidate_value in candidates:
		if (
			candidate_value is Dictionary
			and String(Dictionary(candidate_value).get("canonical_command", "")).contains(
				fragment
			)
		):
			return true

	return false


func _record_confusion(
	confusions: Dictionary,
	slot: String,
	expected: String,
	actual: String
) -> void:
	var key := slot + ": " + expected + " -> " + actual
	confusions[key] = int(confusions.get(key, 0)) + 1


func _increment_category(stats: Dictionary, category: String, correct: bool) -> void:
	var entry: Dictionary = stats.get(category, {"correct": 0, "total": 0})
	entry["total"] = int(entry.get("total", 0)) + 1

	if correct:
		entry["correct"] = int(entry.get("correct", 0)) + 1

	stats[category] = entry


func _format_categories(stats: Dictionary) -> Dictionary:
	var output := {}

	for category in stats.keys():
		var entry: Dictionary = stats[category]
		var total := int(entry.get("total", 0))
		var correct := int(entry.get("correct", 0))
		output[category] = {
			"correct": correct,
			"total": total,
			"accuracy": float(correct) / float(maxi(total, 1))
		}

	return output


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish_failure(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
