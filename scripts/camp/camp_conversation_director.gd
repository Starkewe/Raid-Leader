extends Node
class_name CampConversationDirector

const CampContentCatalogScript := preload("res://scripts/core/camp_content_catalog.gd")
const CampV2TuningScript := preload("res://scripts/core/camp_v2_tuning.gd")
const TUNING := CampV2TuningScript.CONVERSATIONS

const DEBUG_HISTORY_LIMIT: int = TUNING["debug_history_limit"]
const DEFAULT_BUBBLE_DURATION: float = TUNING["bubble_duration_seconds"]
const DEFAULT_PAUSE_DURATION: float = TUNING["pause_between_bubbles_seconds"]

var population_controller: Node = null
var frames: Array[Dictionary] = []
var active_conversations: Dictionary = {}
var eligible_debug: Array[Dictionary] = []
var rejected_debug: Array[Dictionary] = []
var recent_outcomes: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var conversation_sequence: int = 0
var timing_multiplier: float = 1.0


func configure(controller: Node) -> void:
	population_controller = controller
	frames = CampContentCatalogScript.get_conversation_frames()
	rng.seed = Time.get_ticks_usec()


func _process(delta: float) -> void:
	if population_controller == null:
		return

	var scaled_delta := delta * timing_multiplier
	CampaignState.advance_camp_conversation_time(scaled_delta, active_conversations.size())
	_update_active_conversations(scaled_delta)

	if not CampaignState.is_ordinary_conversation_due():
		return
	if active_conversations.size() >= _maximum_concurrent_conversations():
		CampaignState.note_conversation_schedule_miss("concurrency_limit")
		return

	if not _try_start_scheduled_conversation("ordinary", false):
		CampaignState.note_conversation_schedule_miss("no_eligible_participants")


func force_conversation(frame_id: String = "") -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "reason": "debug_build_required"}

	if not frame_id.is_empty():
		for frame in frames:
			if String(frame.get("frame_id", "")) == frame_id:
				return _force_frame(frame)

	for frame in frames:
		if String(frame.get("frame_id", "")) == "generic_camp_check_in":
			return _force_frame(frame)

	return {"ok": false, "reason": "fallback_frame_missing"}


func force_lore_exchange() -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "reason": "debug_build_required"}

	for frame in frames:
		if String(frame.get("kind", "ordinary")) == "lore":
			return _force_frame(frame)

	return {"ok": false, "reason": "lore_frame_missing"}


func get_frame_ids() -> Array[String]:
	var result: Array[String] = []
	for frame in frames:
		result.append(String(frame.get("frame_id", "")))
	return result


func cancel_all(reason: String = "manual_cancel") -> int:
	var conversation_ids: Array = active_conversations.keys()

	for conversation_id in conversation_ids:
		_cancel_conversation(String(conversation_id), reason)

	return conversation_ids.size()


func set_accelerated_timing(enabled: bool) -> void:
	timing_multiplier = (
		float(CampV2TuningScript.ACTIVITIES.get("accelerated_timing_multiplier", 6.0))
		if enabled
		else 1.0
	)


func get_debug_report() -> Dictionary:
	var current: Array[Dictionary] = []

	for value in active_conversations.values():
		var session: Dictionary = value
		current.append(
			{
				"conversation_id": String(session.get("conversation_id", "")),
				"frame_id": String(session.get("frame", {}).get("frame_id", "")),
				"delivery": String(session.get("delivery", "")),
				"participants_by_role": Dictionary(session.get("participants_by_role", {})).duplicate(true),
				"current_beat": int(session.get("beat_index", 0)) + 1,
				"phase": String(session.get("phase", "")),
				"outcome": Dictionary(session.get("frame", {}).get("outcome", {})).duplicate(true),
			}
		)

	return {
		"persistent_cadence": CampaignState.get_camp_conversation_debug_report(),
		"current_conversations": current,
		"eligible_conversations": eligible_debug.duplicate(true),
		"rejected_conversations": rejected_debug.duplicate(true),
		"recent_completed_outcomes": recent_outcomes.duplicate(true),
		"authored_frame_count": frames.size(),
		"content_warnings": CampContentCatalogScript.get_warnings(),
		"accelerated_timing": timing_multiplier > 1.0,
	}


func _try_start_scheduled_conversation(kind: String, ignore_cooldowns: bool) -> bool:
	eligible_debug.clear()
	rejected_debug.clear()
	var candidates := _conversation_candidates()
	var frame_order := frames.duplicate(true)
	frame_order.shuffle()
	var eligible: Array[Dictionary] = []

	for frame_value in frame_order:
		var frame: Dictionary = frame_value
		if kind == "ordinary" and String(frame.get("kind", "ordinary")) == "lore":
			# Lore is rare but remains part of the ordinary scheduler at a lower weight.
			if rng.randf() > float(TUNING.get("lore_schedule_chance", 0.16)):
				_record_rejection(frame, "lore_rarity_gate")
				continue

		for first_index in range(candidates.size()):
			for second_index in range(first_index + 1, candidates.size()):
				for reverse_roles in [false, true]:
					var first: Dictionary = candidates[first_index if not reverse_roles else second_index]
					var second: Dictionary = candidates[second_index if not reverse_roles else first_index]
					var evaluation := _evaluate_frame(frame, first, second, ignore_cooldowns)
					if bool(evaluation.get("ok", false)):
						eligible.append(evaluation)
						eligible_debug.append(_debug_eligibility(evaluation))
					else:
						_record_rejection(frame, String(evaluation.get("reason", "ineligible")), first, second)

	if eligible.is_empty():
		return false

	var selected := _select_weighted_evaluation(eligible)
	return _start_conversation(selected)


func _force_frame(frame: Dictionary) -> Dictionary:
	if active_conversations.size() >= _maximum_concurrent_conversations():
		return {"ok": false, "reason": "concurrency_limit"}

	var candidates := _conversation_candidates()
	if candidates.size() < 2:
		return {"ok": false, "reason": "two_available_raiders_required"}

	for first_index in range(candidates.size()):
		for second_index in range(candidates.size()):
			if first_index == second_index:
				continue
			var evaluation := _evaluate_frame(
				frame, candidates[first_index], candidates[second_index], true, true
			)
			if bool(evaluation.get("ok", false)):
				return {
					"ok": _start_conversation(evaluation),
					"frame_id": String(frame.get("frame_id", "")),
					"participants_by_role": evaluation.get("participants_by_role", {}),
				}

	return {"ok": false, "reason": "no_valid_role_assignment", "frame_id": String(frame.get("frame_id", ""))}


func _conversation_candidates() -> Array[Dictionary]:
	if not population_controller.has_method("get_conversation_candidates"):
		return []
	return population_controller.call("get_conversation_candidates")


func _evaluate_frame(
	frame: Dictionary,
	first: Dictionary,
	second: Dictionary,
	ignore_cooldowns: bool,
	force_focused: bool = false
) -> Dictionary:
	var roles := _string_array(frame.get("roles", []))
	if roles.size() < 2:
		return {"ok": false, "reason": "invalid_roles"}

	var first_id := String(first.get("raider_id", ""))
	var second_id := String(second.get("raider_id", ""))
	if first_id.is_empty() or second_id.is_empty() or first_id == second_id:
		return {"ok": false, "reason": "invalid_pair"}

	var visit_type := String(CampaignState.get_visit_context().get("type", "normal"))
	var visit_requirements := _string_array(frame.get("required_visit_contexts", []))
	if not visit_requirements.is_empty() and visit_type not in visit_requirements and not force_focused:
		return {"ok": false, "reason": "visit_context"}

	var participants_by_role := {roles[0]: first_id, roles[1]: second_id}
	var delivery := _resolve_delivery(frame, first, second, force_focused)
	if delivery.is_empty():
		return {"ok": false, "reason": "delivery_or_station_context"}

	if not _meets_relationship_requirement(frame, first_id, second_id) and not force_focused:
		return {"ok": false, "reason": "relationship_requirement"}

	if not _meets_lore_requirement(frame, first, second):
		return {"ok": false, "reason": "lore_knowledge_requirement"}

	var memory_context := _resolve_memory_context(frame, participants_by_role)
	if (
		frame.get("memory_requirement", {}) is Dictionary
		and not Dictionary(frame.get("memory_requirement", {})).is_empty()
		and memory_context.is_empty()
		and not force_focused
	):
		return {"ok": false, "reason": "memory_requirement"}

	var cooldown_keys := _cooldown_keys(
		frame, participants_by_role, first, delivery, memory_context
	)
	if not ignore_cooldowns:
		for key in cooldown_keys.values():
			if CampaignState.get_conversation_cooldown_remaining(String(key)) > 0.0:
				return {"ok": false, "reason": "cooldown:%s" % String(key)}

	var selection_weight := 1.0
	if (
		not String(first.get("room_assignment_id", "")).is_empty()
		and String(first.get("room_assignment_id", ""))
		== String(second.get("room_assignment_id", ""))
	):
		selection_weight *= float(TUNING.get("roommate_selection_multiplier", 1.25))
	if (
		first.get("authored_connection_ids", []).has(second_id)
		or second.get("authored_connection_ids", []).has(first_id)
	):
		selection_weight *= float(
			TUNING.get("authored_connection_selection_multiplier", 1.35)
		)
	selection_weight *= _repetition_multiplier(
		frame,
		[first_id, second_id],
		String(first.get("station_id", "")) if delivery == "embedded" else "",
		String(first.get("activity_id", "")) if delivery == "embedded" else ""
	)

	return {
		"ok": true,
		"frame": frame.duplicate(true),
		"participants_by_role": participants_by_role,
		"participant_ids": [first_id, second_id],
		"delivery": delivery,
		"station_id": String(first.get("station_id", "")) if delivery == "embedded" else "",
		"activity_id": String(first.get("activity_id", "")) if delivery == "embedded" else "",
		"referenced_memory": memory_context,
		"cooldown_keys": cooldown_keys,
		"selection_weight": selection_weight,
	}


func _select_weighted_evaluation(eligible: Array[Dictionary]) -> Dictionary:
	var total_weight := 0.0
	for evaluation in eligible:
		total_weight += maxf(float(evaluation.get("selection_weight", 1.0)), 0.01)
	var roll := rng.randf_range(0.0, total_weight)
	var running := 0.0
	for evaluation in eligible:
		running += maxf(float(evaluation.get("selection_weight", 1.0)), 0.01)
		if roll <= running:
			return evaluation
	return eligible[-1]


func _resolve_delivery(
	frame: Dictionary, first: Dictionary, second: Dictionary, force_focused: bool
) -> String:
	var modes := _string_array(frame.get("delivery_modes", ["focused"]))
	if force_focused and modes.has("focused"):
		return "focused"

	var first_station := String(first.get("station_id", ""))
	var same_station := not first_station.is_empty() and first_station == String(second.get("station_id", ""))
	var same_activity := not String(first.get("activity_id", "")).is_empty() and String(first.get("activity_id", "")) == String(second.get("activity_id", ""))
	var required_activities := _string_array(frame.get("required_activity_ids", []))
	var required_stations := _string_array(frame.get("required_station_ids", []))
	var activity_ok := required_activities.is_empty() or required_activities.has(String(first.get("activity_id", "")))
	var station_ok := required_stations.is_empty() or required_stations.has(first_station)
	var embedded_ok := same_station and same_activity and activity_ok and station_ok

	if embedded_ok and modes.has("embedded") and population_controller.has_method("is_station_conversation_compatible"):
		embedded_ok = bool(
			population_controller.call(
				"is_station_conversation_compatible",
				first_station,
				String(frame.get("tone", "")),
				String(frame.get("category", ""))
			)
		)

	if embedded_ok and modes.has("embedded"):
		return "embedded"

	if not required_activities.is_empty() or not required_stations.is_empty():
		return ""
	return "focused" if modes.has("focused") else ""


func _meets_relationship_requirement(frame: Dictionary, first_id: String, second_id: String) -> bool:
	var minimum: Dictionary = Dictionary(frame.get("minimum_relationship", {})) if frame.get("minimum_relationship", {}) is Dictionary else {}
	if minimum.is_empty():
		return true
	var pair := CampaignState.get_relationship(first_id, second_id)
	var directional: Dictionary = Dictionary(pair.get("directional", {})) if pair.get("directional", {}) is Dictionary else {}
	var first_view: Dictionary = Dictionary(directional.get(first_id, {})) if directional.get(first_id, {}) is Dictionary else {}
	var second_view: Dictionary = Dictionary(directional.get(second_id, {})) if directional.get(second_id, {}) is Dictionary else {}
	for dimension in minimum.keys():
		if maxf(float(first_view.get(dimension, 0.0)), float(second_view.get(dimension, 0.0))) < float(minimum[dimension]):
			return false
	return true


func _meets_lore_requirement(frame: Dictionary, first: Dictionary, second: Dictionary) -> bool:
	if String(frame.get("kind", "ordinary")) != "lore":
		return true
	var speaker_tags := _string_array(first.get("lore_knowledge_tags", []))
	var required_tags := _string_array(frame.get("speaker_lore_tags", []))
	var topic_id := String(frame.get("lore_topic_id", ""))
	var topic := CampContentCatalogScript.get_lore_topic(topic_id)
	if required_tags.is_empty():
		required_tags = _string_array(topic.get("introducer_tags", []))
	if not required_tags.is_empty() and not _arrays_intersect(speaker_tags, required_tags):
		return false
	var learner_topics: Dictionary = Dictionary(CampaignState.get_raider_lore_knowledge(String(second.get("raider_id", ""))).get("topics", {}))
	return not learner_topics.has(topic_id)


func _resolve_memory_context(frame: Dictionary, roles: Dictionary) -> Dictionary:
	var requirement_value: Variant = frame.get("memory_requirement", {})
	if not requirement_value is Dictionary or Dictionary(requirement_value).is_empty():
		return {}
	var requirement: Dictionary = requirement_value
	var role := String(requirement.get("role", ""))
	var raider_id := String(roles.get(role, ""))
	if raider_id.is_empty():
		return {}
	var selected := CampaignState.select_conversation_memory(raider_id, requirement)
	if not selected.is_empty():
		selected["raider_id"] = raider_id
		selected["role"] = role
	return selected


func _start_conversation(selection: Dictionary) -> bool:
	var participant_ids := _string_array(selection.get("participant_ids", []))
	if participant_ids.size() != 2:
		return false

	conversation_sequence += 1
	var conversation_id := "camp_conversation_%06d" % conversation_sequence
	var frame: Dictionary = selection.get("frame", {})
	var session := selection.duplicate(true)
	session["conversation_id"] = conversation_id
	session["beat_index"] = 0
	session["phase"] = "beat"
	session["timer"] = 0.0
	session["current_speaker_id"] = ""
	active_conversations[conversation_id] = session

	if not population_controller.call(
		"begin_conversation_channels",
		conversation_id,
		Dictionary(selection.get("participants_by_role", {})),
		String(selection.get("delivery", "focused")),
		String(selection.get("station_id", ""))
	):
		active_conversations.erase(conversation_id)
		return false

	_apply_frame_cooldowns(selection)
	CampaignState.schedule_next_ordinary_conversation(
		CampaignState.get_next_conversation_cooldown(rng.randf_range(-4.0, 6.0))
	)
	_present_current_beat(conversation_id)
	return true


func _update_active_conversations(delta: float) -> void:
	for conversation_id_value in active_conversations.keys():
		var conversation_id := String(conversation_id_value)
		if not active_conversations.has(conversation_id):
			continue
		var session: Dictionary = active_conversations[conversation_id]
		if not _participants_are_valid(session):
			_cancel_conversation(conversation_id, "participant_invalidated")
			continue
		session["timer"] = float(session.get("timer", 0.0)) - delta
		active_conversations[conversation_id] = session
		if float(session["timer"]) > 0.0:
			continue

		if String(session.get("phase", "beat")) == "beat":
			population_controller.call("hide_conversation_bubbles", session.get("participant_ids", []))
			session["phase"] = "pause"
			session["timer"] = float(_current_beat(session).get("pause_after", DEFAULT_PAUSE_DURATION))
			active_conversations[conversation_id] = session
		else:
			session["beat_index"] = int(session.get("beat_index", 0)) + 1
			if int(session["beat_index"]) >= Array(session.get("frame", {}).get("beats", [])).size():
				_complete_conversation(conversation_id)
			else:
				session["phase"] = "beat"
				active_conversations[conversation_id] = session
				_present_current_beat(conversation_id)


func _present_current_beat(conversation_id: String) -> void:
	if not active_conversations.has(conversation_id):
		return
	var session: Dictionary = active_conversations[conversation_id]
	var beat := _current_beat(session)
	var role := String(beat.get("speaker_role", ""))
	var speaker_id := String(session.get("participants_by_role", {}).get(role, ""))
	var text := _resolve_authored_line(beat, speaker_id, session)
	var duration := maxf(float(beat.get("duration", DEFAULT_BUBBLE_DURATION)), 2.8)
	if not bool(population_controller.call("show_conversation_bubble", speaker_id, text, duration)):
		_cancel_conversation(conversation_id, "bubble_unavailable")
		return
	population_controller.call("set_conversation_speaker", conversation_id, speaker_id)
	session["current_speaker_id"] = speaker_id
	session["timer"] = duration
	active_conversations[conversation_id] = session


func _complete_conversation(conversation_id: String) -> void:
	if not active_conversations.has(conversation_id):
		return
	var session: Dictionary = active_conversations[conversation_id]
	var frame: Dictionary = session.get("frame", {})
	var roles: Dictionary = session.get("participants_by_role", {})
	var participant_ids := _string_array(session.get("participant_ids", []))
	var outcome: Dictionary = Dictionary(frame.get("outcome", {})).duplicate(true)
	var mapped_deltas: Dictionary = {}

	for role in Dictionary(outcome.get("relationship_deltas", {})).keys():
		var raider_id := String(roles.get(role, ""))
		if not raider_id.is_empty():
			mapped_deltas[raider_id] = Dictionary(outcome["relationship_deltas"][role]).duplicate(true)

	var personal_participants: Array[String] = []
	for role in _string_array(outcome.get("personal_roles", [])):
		var raider_id := String(roles.get(role, ""))
		if not raider_id.is_empty():
			personal_participants.append(raider_id)

	var controlled_outcome := {
		"outcome_id": String(outcome.get("outcome_id", "neutral")),
		"outcome_type": String(outcome.get("type", "neutral")),
		"controlled_outcome": true,
		"meaningful": bool(outcome.get("meaningful", false)),
		"qualifies_for_relationship_change": bool(outcome.get("qualifies_for_relationship_change", false)),
		"relationship_deltas": mapped_deltas,
		"personal_participants": personal_participants,
		"frame_id": String(frame.get("frame_id", "")),
		"delivery": String(session.get("delivery", "focused")),
		"activity_id": String(session.get("activity_id", "")),
		"station_id": String(session.get("station_id", "")),
		"tone": String(frame.get("tone", "neutral")),
		"subject_key": "conversation:%s" % String(frame.get("category", "social")),
		"significance": 68 if bool(outcome.get("meaningful", false)) else 38,
		"referenced_memory_thread_id": String(
			session.get("referenced_memory", {}).get("thread_id", "")
		),
	}
	CampaignState.record_completed_conversation(participant_ids[0], participant_ids[1], controlled_outcome)
	_transfer_authored_lore(frame, roles)
	var summary_text := _format_template(String(outcome.get("summary_template", "{first} spoke with {second}.")), roles)
	var summary := CampaignState.record_conversation_summary(
		{
			"participant_ids": participant_ids,
			"participants_by_role": roles.duplicate(true),
			"frame_id": String(frame.get("frame_id", "")),
			"outcome_id": String(outcome.get("outcome_id", "neutral")),
			"outcome_type": String(outcome.get("type", "neutral")),
			"delivery": String(session.get("delivery", "focused")),
			"activity_id": String(session.get("activity_id", "")),
			"station_id": String(session.get("station_id", "")),
			"lore_topic_id": String(frame.get("lore_topic_id", "")),
			"callback_memory_key": String(frame.get("referenced_memory_key", "")),
			"referenced_memory_thread_id": String(
				session.get("referenced_memory", {}).get("thread_id", "")
			),
			"summary_metadata": Dictionary(frame.get("summary_metadata", {})).duplicate(true),
			"summary_text": summary_text,
			"completed_camp_time": float(CampaignState.get_camp_conversation_debug_report().get("camp_time_seconds", 0.0)),
			"completed_unix_time": int(Time.get_unix_time_from_system()),
		}
	)
	_append_recent(recent_outcomes, summary, DEBUG_HISTORY_LIMIT)
	_cleanup_session(session)
	active_conversations.erase(conversation_id)


func _transfer_authored_lore(frame: Dictionary, roles: Dictionary) -> void:
	var topic_id := String(frame.get("lore_topic_id", ""))
	if topic_id.is_empty():
		return
	var topic := CampContentCatalogScript.get_lore_topic(topic_id)
	if topic.is_empty():
		return
	var learner_id := String(roles.get("learner", ""))
	if learner_id.is_empty():
		return
	CampaignState.record_lore_knowledge(
		learner_id,
		topic_id,
		"known",
		String(topic.get("canonical_fact", "")),
		String(topic.get("source_id", "authored_lore_exchange")),
		false
	)


func _cancel_conversation(conversation_id: String, reason: String) -> void:
	if not active_conversations.has(conversation_id):
		return
	var session: Dictionary = active_conversations[conversation_id]
	_cleanup_session(session)
	active_conversations.erase(conversation_id)
	_record_rejection(Dictionary(session.get("frame", {})), "cancelled:%s" % reason)


func _cleanup_session(session: Dictionary) -> void:
	if population_controller == null or not is_instance_valid(population_controller):
		return
	population_controller.call("hide_conversation_bubbles", session.get("participant_ids", []))
	population_controller.call(
		"end_conversation_channels",
		String(session.get("conversation_id", "")),
		session.get("participant_ids", []),
		String(session.get("delivery", "focused")),
		String(session.get("station_id", ""))
	)


func _participants_are_valid(session: Dictionary) -> bool:
	for participant_id in _string_array(session.get("participant_ids", [])):
		if not bool(population_controller.call("is_conversation_participant_valid", participant_id)):
			return false
	return true


func _current_beat(session: Dictionary) -> Dictionary:
	var beats: Array = session.get("frame", {}).get("beats", [])
	var index := clampi(int(session.get("beat_index", 0)), 0, maxi(beats.size() - 1, 0))
	return Dictionary(beats[index]) if not beats.is_empty() and beats[index] is Dictionary else {}


func _resolve_authored_line(beat: Dictionary, speaker_id: String, session: Dictionary) -> String:
	var member := CampaignState.get_member(speaker_id)
	var character_overrides: Dictionary = Dictionary(beat.get("character_overrides", {})) if beat.get("character_overrides", {}) is Dictionary else {}
	if character_overrides.has(speaker_id):
		return _safe_line(String(character_overrides[speaker_id]), session)
	var personality: Array = member.get("attributes", [])
	for value in beat.get("variants", []):
		if not value is Dictionary:
			continue
		var variant: Dictionary = value
		var required := _string_array(variant.get("personality_any", []))
		if required.is_empty() or _arrays_intersect(personality, required):
			return _safe_line(String(variant.get("text", beat.get("text", ""))), session)
	return _safe_line(String(beat.get("text", "")), session)


func _safe_line(text: String, session: Dictionary) -> String:
	if text.strip_edges().is_empty():
		text = String(
			session.get("frame", {}).get("safe_fallback", {}).get(
				"text", "We can finish this conversation later."
			)
		)
	return _format_template(text, session.get("participants_by_role", {}))


func _format_template(template: String, roles: Dictionary) -> String:
	var result := template
	for role in roles.keys():
		var member := CampaignState.get_member(String(roles[role]))
		result = result.replace("{%s}" % String(role), String(member.get("display_name", roles[role])))
	var role_values: Array = roles.values()
	if role_values.size() >= 2:
		result = result.replace("{first}", CampaignState.get_member_label(String(role_values[0])))
		result = result.replace("{second}", CampaignState.get_member_label(String(role_values[1])))
	return result


func _cooldown_keys(
	frame: Dictionary,
	roles: Dictionary,
	first: Dictionary,
	delivery: String,
	referenced_memory: Dictionary = {}
) -> Dictionary:
	var frame_id := String(frame.get("frame_id", ""))
	var role_names: Array = roles.keys()
	var ids := _string_array(roles.values())
	ids.sort()
	var topic_id := String(frame.get("lore_topic_id", frame.get("category", frame_id)))
	var result := {
		"frame": "frame:%s" % frame_id,
		"topic": "topic:%s" % topic_id,
		"pair": "pair:%s|%s" % ids,
		"speaker_role": "role:%s:%s" % [String(roles.get(role_names[0], "")), String(role_names[0])],
	}
	var memory_key := String(frame.get("referenced_memory_key", ""))
	if not memory_key.is_empty():
		var thread_id := String(referenced_memory.get("thread_id", memory_key))
		result["referenced_memory"] = "memory:%s" % thread_id
	if not String(frame.get("lore_topic_id", "")).is_empty():
		result["lore_topic"] = "lore:%s" % topic_id
		result["lore_delivery"] = "lore_delivery:%s" % topic_id
	if delivery == "embedded":
		result["station_activity"] = "context:%s|%s" % [String(first.get("station_id", "")), String(first.get("activity_id", ""))]
	return result


func _apply_frame_cooldowns(selection: Dictionary) -> void:
	var frame: Dictionary = selection.get("frame", {})
	var durations: Dictionary = Dictionary(frame.get("cooldowns", {})) if frame.get("cooldowns", {}) is Dictionary else {}
	var keys: Dictionary = selection.get("cooldown_keys", {})
	var mapped: Dictionary = {}
	for kind in keys.keys():
		mapped[String(keys[kind])] = float(durations.get(kind, 60.0))
	CampaignState.set_conversation_cooldowns(mapped)


func _debug_eligibility(evaluation: Dictionary) -> Dictionary:
	return {
		"frame_id": String(evaluation.get("frame", {}).get("frame_id", "")),
		"participants_by_role": Dictionary(evaluation.get("participants_by_role", {})).duplicate(true),
		"delivery": String(evaluation.get("delivery", "")),
		"station_id": String(evaluation.get("station_id", "")),
		"activity_id": String(evaluation.get("activity_id", "")),
	}


func _record_rejection(
	frame: Dictionary, reason: String, first: Dictionary = {}, second: Dictionary = {}
) -> void:
	_append_recent(
		rejected_debug,
		{
			"frame_id": String(frame.get("frame_id", "")),
			"first_id": String(first.get("raider_id", "")),
			"second_id": String(second.get("raider_id", "")),
			"reason": reason,
		},
		DEBUG_HISTORY_LIMIT
	)


func _maximum_concurrent_conversations() -> int:
	var population := int(population_controller.call("get_actor_count"))
	return (
		int(TUNING.get("maximum_conversations_large_camp", 2))
		if population >= int(TUNING.get("population_for_second_conversation", 25))
		else int(TUNING.get("maximum_conversations_small_camp", 1))
	)


func _repetition_multiplier(
	frame: Dictionary, participant_ids: Array[String], station_id: String, activity_id: String
) -> float:
	var recent := CampaignState.get_conversation_summaries("", 12)
	var result := 1.0
	var frame_id := String(frame.get("frame_id", ""))
	var sorted_ids := participant_ids.duplicate()
	sorted_ids.sort()
	for offset in range(recent.size()):
		var index := recent.size() - 1 - offset
		var summary: Dictionary = recent[index]
		if offset < 8 and String(summary.get("frame_id", "")) == frame_id:
			result *= float(TUNING.get("recent_frame_repetition_multiplier", 0.35))
			break
	for offset in range(mini(recent.size(), 6)):
		var summary: Dictionary = recent[recent.size() - 1 - offset]
		var summary_ids := _string_array(summary.get("participant_ids", []))
		summary_ids.sort()
		if summary_ids == sorted_ids:
			result *= float(TUNING.get("recent_pair_repetition_multiplier", 0.55))
			break
	if not station_id.is_empty() or not activity_id.is_empty():
		for offset in range(mini(recent.size(), 5)):
			var summary: Dictionary = recent[recent.size() - 1 - offset]
			if (
				String(summary.get("station_id", "")) == station_id
				and String(summary.get("activity_id", "")) == activity_id
			):
				result *= float(
					TUNING.get("recent_context_repetition_multiplier", 0.65)
				)
				break
	return maxf(result, 0.05)


func _arrays_intersect(first: Array, second: Array) -> bool:
	for value in first:
		if second.has(value):
			return true
	return false


func _append_recent(target: Array, value: Dictionary, limit: int) -> void:
	target.append(value.duplicate(true))
	if target.size() > limit:
		target.remove_at(0)


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result
