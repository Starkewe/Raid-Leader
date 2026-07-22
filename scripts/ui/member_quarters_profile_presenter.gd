extends RefCounted
class_name MemberQuartersProfilePresenter

const CampContentCatalogScript := preload("res://scripts/core/camp_content_catalog.gd")

const ACTIVITY_LABELS := {
	"apothecary_work": "Working at the apothecary",
	"prepare_plan": "Preparing the raid plan",
	"rehearse": "Rehearsing formations",
	"rest": "Resting in the quarters",
	"smith_work": "Working at the smith",
	"socialize": "Spending time at the communal fire",
	"study_target": "Studying in the archive",
	"train": "Training",
	"victory_gather": "Visiting the victory spike",
}

const RELATIONSHIP_PRIORITY := {
	"Close friends": 70,
	"Trusted companion": 60,
	"Respectful rivals": 50,
	"Becoming friends": 40,
	"Fond but unreliable": 35,
	"Strained": 30,
	"Familiar but distant": 10,
}


static func build_profile(raider_id: String, runtime_state: Dictionary = {}) -> Dictionary:
	var member := CampaignState.get_member(raider_id)
	if member.is_empty():
		return {}

	var active := CampaignState.is_member_active(raider_id)
	var personality_description := String(member.get("personality_description", "")).strip_edges()
	if personality_description.is_empty():
		personality_description = _personality_fallback(member.get("personality_tags", []))

	return {
		"raider_id": raider_id,
		"display_name": String(member.get("display_name", "Unknown Raider")),
		"unit_class": String(member.get("unit_class", "Unknown")),
		"roster_status": "Active" if active else "Reserve",
		"biography": String(member.get("biography", "No biography is available.")),
		"personality_description": personality_description,
		"recruitment_origin": _recruitment_origin(member),
		"room_assignment": CampaignState.get_room_assignment_label(raider_id),
		"room_assignment_id": String(member.get("room_assignment_id", "")),
		"preferred_activities": _activity_list(member.get("preferred_activity_tags", [])),
		"descriptive_title": String(member.get("descriptive_title", "")).strip_edges(),
		"visual": resolve_visual(member),
		"runtime_text": runtime_text(runtime_state),
		"close_connections": _connections(raider_id, member),
		"lasting_memories": _lasting_memories(raider_id),
		"recent_experiences": _recent_experiences(raider_id),
		"personal_themes": _personal_themes(raider_id, active),
		"social_summaries": _social_summaries(raider_id),
		"combat_highlights": _combat_highlights(raider_id, member),
	}


static func resolve_visual(member: Dictionary) -> Dictionary:
	var assets: Dictionary = Dictionary(member.get("visual_assets", {}))
	var candidates := [
		{"key": "profile_sprite", "kind": "unique_sprite"},
		{"key": "profile_portrait", "kind": "character_portrait"},
		{"key": "class_fallback_portrait", "kind": "class_fallback"},
		{"key": "portrait", "kind": "legacy_portrait"},
		{"key": "neutral_fallback_portrait", "kind": "neutral_fallback"},
	]
	var checked_paths: Array[String] = []

	for candidate in candidates:
		var path := String(assets.get(String(candidate["key"]), "")).strip_edges()
		if path.is_empty() or checked_paths.has(path):
			continue
		checked_paths.append(path)
		if ResourceLoader.exists(path):
			return {
				"kind": String(candidate["kind"]),
				"path": path,
				"checked_paths": checked_paths,
			}

	return {"kind": "generated_fallback", "path": "", "checked_paths": checked_paths}


static func runtime_text(runtime_state: Dictionary) -> String:
	if runtime_state.is_empty():
		return "Settling into camp"

	var social: Dictionary = Dictionary(runtime_state.get("social_interaction", {}))
	var primary: Dictionary = Dictionary(runtime_state.get("primary_activity", {}))
	var animation_state := String(runtime_state.get("animation_state", "idle"))
	if not social.is_empty() and String(social.get("delivery", "")) == "focused":
		return "In a focused conversation"

	var activity_id := String(primary.get("activity_id", runtime_state.get("current_activity_id", "")))
	if activity_id.is_empty():
		return "Available in camp"

	var activity_text := String(ACTIVITY_LABELS.get(activity_id, _humanize(activity_id)))
	if animation_state == "walking":
		activity_text = "Walking to " + activity_text.trim_prefix("Working at ").trim_prefix("Spending time at ").trim_prefix("Resting in ").trim_prefix("Studying in ").to_lower()
	if not social.is_empty():
		activity_text += " while " + String(social.get("interaction", "talking"))
	return activity_text


static func build_debug_payload(raider_id: String, runtime_state: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return {}

	var member := CampaignState.get_member(raider_id)
	var relationships: Dictionary = {}
	for other in CampaignState.get_roster_members():
		var other_id := String(other.get("member_id", ""))
		if other_id.is_empty() or other_id == raider_id:
			continue
		var pair := CampaignState.get_relationship(raider_id, other_id)
		if not pair.is_empty():
			relationships[other_id] = pair

	return {
		"stable_id": raider_id,
		"campaign_state": CampaignState.get_raider_campaign_state(raider_id),
		"memory_threads": CampaignState.get_raider_memories(raider_id),
		"relationship_dimensions": relationships,
		"current_activity_channels": runtime_state.duplicate(true),
		"conversation_summaries": CampaignState.get_conversation_summaries(raider_id, 20),
		"sprite_resolution": resolve_visual(member),
	}


static func _connections(raider_id: String, member: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var room_id := String(member.get("room_assignment_id", ""))
	var authored_ids: Array = member.get("authored_connection_ids", [])

	for other in CampaignState.get_roster_members():
		var other_id := String(other.get("member_id", ""))
		if other_id.is_empty() or other_id == raider_id:
			continue

		var pair := CampaignState.get_relationship(raider_id, other_id)
		var same_room := not room_id.is_empty() and room_id == String(other.get("room_assignment_id", ""))
		if pair.is_empty() and not same_room and not authored_ids.has(other_id):
			continue

		var label := CampaignState.get_relationship_label(raider_id, other_id)
		var context := _relationship_context(raider_id, other_id, pair, same_room)
		var priority := int(RELATIONSHIP_PRIORITY.get(label, 0))
		if same_room:
			priority += 25
		result.append(
			{
				"raider_id": other_id,
				"name": String(other.get("display_name", "Unknown")),
				"label": label,
				"context": context,
				"priority": priority,
			}
		)

	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_priority := int(a.get("priority", 0))
			var b_priority := int(b.get("priority", 0))
			if a_priority != b_priority:
				return a_priority > b_priority
			return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
	)
	if result.size() > 6:
		result = result.slice(0, 6)
	return result


static func _relationship_context(
	raider_id: String, other_id: String, pair: Dictionary, same_room: bool
) -> String:
	if same_room:
		return "Currently shares " + CampaignState.get_room_assignment_label(raider_id) + "."

	var context: Dictionary = Dictionary(pair.get("shared_context", {}))
	var victories: Array = context.get("shared_victories", [])
	if not victories.is_empty() and victories[-1] is Dictionary:
		var data: Dictionary = Dictionary(victories[-1]).get("structured_data", {})
		var encounter := String(data.get("encounter_id", data.get("display_name", "a boss")))
		return "Defeated %s together." % _humanize(encounter)

	var activities: Dictionary = Dictionary(context.get("shared_activity_counts", {}))
	if not activities.is_empty():
		var best_activity := ""
		var best_count := 0
		for activity_id in activities.keys():
			if int(activities[activity_id]) > best_count:
				best_activity = String(activity_id)
				best_count = int(activities[activity_id])
		if not best_activity.is_empty():
			return "Worked together%s." % (
				" frequently at the " + _activity_place(best_activity) if best_count >= 3 else " at the " + _activity_place(best_activity)
			)

	var roommate_history: Array = context.get("roommate_history", [])
	if not roommate_history.is_empty():
		return "Former roommates."

	var summaries := CampaignState.get_conversation_summaries(raider_id, 20)
	for index in range(summaries.size() - 1, -1, -1):
		var summary: Dictionary = summaries[index]
		if summary.get("participant_ids", []).has(other_id):
			return String(summary.get("summary_text", "Shared a recent conversation."))

	return "Their shared history is still taking shape."


static func _lasting_memories(raider_id: String) -> Array[String]:
	var result: Array[String] = []
	var memory := CampaignState.get_raider_memories(raider_id)
	for value in memory.get("life_memories", []):
		if value is Dictionary:
			result.append(_memory_text(Dictionary(value), true))
	return result


static func _recent_experiences(raider_id: String) -> Array[String]:
	var episodes: Array[Dictionary] = []
	var memory := CampaignState.get_raider_memories(raider_id)
	for category_value in Dictionary(memory.get("active_episodes", {})).values():
		if not category_value is Array:
			continue
		for value in category_value:
			if value is Dictionary:
				episodes.append(Dictionary(value))
	episodes.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("occurred_at", 0)) > int(b.get("occurred_at", 0))
	)
	var result: Array[String] = []
	for episode in episodes.slice(0, 6):
		result.append(_memory_text(episode, false))
	return result


static func _personal_themes(raider_id: String, active: bool) -> Array[String]:
	var memory := CampaignState.get_raider_memories(raider_id)
	var threads: Array[Dictionary] = []
	for value in Dictionary(memory.get("threads", {})).values():
		if value is Dictionary and String(value.get("state", "active")) == "active":
			threads.append(Dictionary(value))
	threads.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("last_reinforced_at", 0)) > int(b.get("last_reinforced_at", 0))
	)

	var result: Array[String] = []
	for thread in threads:
		var subject := String(thread.get("subject_key", ""))
		var category := String(thread.get("category", ""))
		var text := ""
		if category == "combat" or subject.begins_with("mechanic:"):
			text = "Working to become more confident against %s." % _subject_text(subject)
		elif category == "roster":
			text = (
				"Trying to prove themselves after returning to the active raid."
				if active
				else "Adjusting to time in reserve."
			)
		elif subject.begins_with("facility_activity:"):
			text = "Spending more time at the %s." % _activity_place(subject.get_slice(":", 1))
		elif subject.begins_with("lore:"):
			text = "Studying what the Writ knows about %s." % _subject_text(subject)
		elif category == "social":
			text = "Thinking more carefully about their place among the Writ."
		if not text.is_empty() and not result.has(text):
			result.append(text)
		if result.size() >= 3:
			break
	return result


static func _social_summaries(raider_id: String) -> Array[String]:
	var result: Array[String] = []
	var summaries := CampaignState.get_conversation_summaries(raider_id, 6)
	for index in range(summaries.size() - 1, -1, -1):
		var text := String(summaries[index].get("summary_text", "")).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


static func _combat_highlights(raider_id: String, member: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var history: Dictionary = Dictionary(member.get("combat_history", {}))
	result.append(
		"%d attempts · %d victories · %d defeats"
		% [
			int(history.get("attempts", 0)),
			int(history.get("victories", 0)),
			int(history.get("defeats", 0)),
		]
	)

	var events := CampaignState.get_recent_notable_events(120)
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if not event.get("participants", []).has(raider_id):
			continue
		var event_type := String(event.get("event_type", ""))
		var data: Dictionary = Dictionary(event.get("structured_data", {}))
		var text := ""
		match event_type:
			"boss_defeated":
				text = "Helped defeat %s." % _humanize(String(data.get("encounter_id", "a boss")))
			"last_survivor":
				text = "Was the last survivor against %s." % _humanize(String(data.get("encounter_id", "a boss")))
			"interrupt_succeeded":
				text = "Landed an important interrupt."
			"exceptional_heal_or_rescue":
				text = "Was part of an exceptional rescue."
			"mechanic_successfully_resolved":
				text = "Helped resolve %s." % _subject_text(String(event.get("subject_key", "a difficult mechanic")))
		if not text.is_empty() and not result.has(text):
			result.append(text)
		if result.size() >= 5:
			break
	return result


static func _memory_text(memory: Dictionary, lasting: bool) -> String:
	var template_id := String(memory.get("prose_template_id", ""))
	var subject := String(memory.get("subject_key", memory.get("thread_id", "an important experience")))
	var data: Dictionary = Dictionary(memory.get("structured_data", memory.get("structured_arc", {})))
	match template_id:
		"overcame_repeated_mechanic_failures":
			return "Overcame repeated failures against %s." % _subject_text(subject)
		"interrupt_succeeded":
			return "Remembered landing a crucial interrupt."
		"exceptional_heal_or_rescue":
			return "Remembered an exceptional rescue during a raid."
		"last_survivor":
			return "Endured as the last survivor in a decisive attempt."
		"raider_defeated":
			return "Was defeated while confronting %s." % _subject_text(subject)
		"mechanic_failed":
			return "Struggled with %s during a recent attempt." % _subject_text(subject)
		"mechanic_successfully_resolved":
			return "Successfully resolved %s." % _subject_text(subject)
		"conversation_completed":
			return "Had a meaningful conversation in camp."
		"life_memory_arc":
			return "%s became part of their lasting personal history." % _subject_text(subject).capitalize()
	if lasting:
		return "%s became a lasting part of their history." % _subject_text(subject).capitalize()
	var event_type := String(memory.get("event_type", "experience"))
	if event_type == "raider_added_to_active_roster":
		return "Returned to the active raid."
	if event_type == "raider_moved_to_reserve":
		return "Was moved into reserve."
	if event_type == "room_assignment_changed":
		return "Settled into %s." % CampaignState.room_label(String(data.get("room_assignment_id", "")))
	return _humanize(event_type) + "."


static func _recruitment_origin(member: Dictionary) -> String:
	var source := String(member.get("source_id", "unknown"))
	match source:
		"starting_writ":
			return "Founding member of the first Writ"
		"campaign_recruit":
			return "Recruited during the current campaign"
		"debug_recruitment":
			return "Campaign recruit"
		_:
			return _humanize(source)


static func _activity_list(value: Variant) -> String:
	var labels: Array[String] = []
	if value is Array:
		for activity_id in value:
			labels.append(String(ACTIVITY_LABELS.get(String(activity_id), _humanize(String(activity_id)))))
	return "None recorded" if labels.is_empty() else ", ".join(labels)


static func _personality_fallback(value: Variant) -> String:
	var tags: Array[String] = []
	if value is Array:
		for tag in value:
			tags.append(_humanize(String(tag)).to_lower())
	if tags.is_empty():
		return "Their personality is still revealing itself."
	if tags.size() == 1:
		return "Known for being %s." % tags[0]
	return "Known for being %s and %s." % [", ".join(tags.slice(0, tags.size() - 1)), tags[-1]]


static func _activity_place(activity_id: String) -> String:
	match activity_id:
		"smith_work":
			return "smith"
		"apothecary_work":
			return "apothecary"
		"study_target":
			return "archive"
		"prepare_plan":
			return "command tent"
		"rehearse":
			return "formation yard"
		"socialize":
			return "communal fire"
		"rest":
			return "quarters"
		_:
			return _humanize(activity_id).to_lower()


static func _subject_text(subject: String) -> String:
	var pieces := subject.split(":", false)
	var value := pieces[-1] if not pieces.is_empty() else subject
	return _humanize(String(value)).to_lower()


static func _humanize(value: String) -> String:
	return value.replace("_", " ").capitalize()
