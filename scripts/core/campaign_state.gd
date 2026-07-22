extends Node

const RaidMemberRecordScript := preload("res://scripts/data/raid_member_record.gd")
const MasterRaiderDefinitionScript := preload(
	"res://scripts/data/master_raider_definition.gd"
)
const CampaignRaiderStateScript := preload("res://scripts/data/campaign_raider_state.gd")
const RaiderCatalogScript := preload("res://scripts/data/raider_catalog.gd")
const CampaignCastGeneratorScript := preload("res://scripts/core/campaign_cast_generator.gd")
const CampV2EventSystemScript := preload("res://scripts/core/camp_v2_event_system.gd")
const RaiderMemoryStoreScript := preload("res://scripts/data/raider_memory_store.gd")
const RaiderRelationshipStoreScript := preload(
	"res://scripts/data/raider_relationship_store.gd"
)
const RaiderLoreKnowledgeStoreScript := preload(
	"res://scripts/data/raider_lore_knowledge_store.gd"
)
const CampConversationStateScript := preload(
	"res://scripts/data/camp_conversation_state.gd"
)
const RaidPlanValidatorScript := preload("res://scripts/core/raid_plan_validator.gd")

signal state_changed
signal raid_plan_changed
signal roster_changed
signal attempt_recorded(summary: Dictionary)
signal visit_context_changed(context: Dictionary)
signal notable_event_recorded(event: Dictionary)
signal memory_promoted(event: Dictionary)
signal relationship_threshold_reached(event: Dictionary)

const SAVE_PATH := "user://raid_leader_campaign_v1.json"
const SCHEMA_VERSION := 7
const ACTIVE_RAID_SIZE := 20
const ATTEMPT_HISTORY_LIMIT := 5
const FIRST_REGION_ID := "beast_crucible"
const DEFAULT_FORMATION_NAME := "Default"
const QUARTERS_ROOM_COUNT := 20
const QUARTERS_ROOM_CAPACITY := 2

var campaign: Dictionary = {}
var missing_definition_warnings_emitted: Dictionary = {}


func _ready() -> void:
	reset_campaign(false)


func reset_campaign(emit_change: bool = true, seed_override: int = 0) -> void:
	missing_definition_warnings_emitted.clear()
	campaign = _create_default_campaign(seed_override)
	_print_campaign_cast_report_if_debug()

	if emit_change:
		roster_changed.emit()
		raid_plan_changed.emit()
		state_changed.emit()


func load_campaign(path: String = SAVE_PATH) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_warning("Campaign save does not exist: " + path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_warning("Campaign save could not be opened: " + path)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		push_warning("Campaign save was invalid: " + path)
		return false

	var parsed_dictionary := parsed as Dictionary
	var campaign_value: Variant = parsed_dictionary.get("campaign", parsed_dictionary)

	if not campaign_value is Dictionary:
		push_warning("Campaign save did not contain campaign data: " + path)
		return false

	campaign = _migrate_campaign(campaign_value as Dictionary)
	CampV2EventSystemScript.advance_lifecycle(
		campaign, int(Time.get_unix_time_from_system())
	)
	missing_definition_warnings_emitted.clear()
	_print_campaign_cast_report_if_debug()
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func write_campaign(path: String, metadata: Dictionary = {}) -> bool:
	if path.is_empty():
		push_warning("Campaign save path was empty.")
		return false

	var directory_path := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_result := DirAccess.make_dir_recursive_absolute(directory_path)

	if directory_result != OK:
		push_warning("Campaign save directory could not be created: " + path.get_base_dir())
		return false

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_warning("Campaign save could not be written: " + path)
		return false

	var persistent_snapshot := campaign.duplicate(true)
	# Current-visit reactions are scene texture, not durable campaign truth.
	persistent_snapshot.erase("visit_context")
	# Runtime scene state is owned by CampPopulationController and must never enter a save.
	persistent_snapshot.erase("runtime_raider_states")
	persistent_snapshot.erase("runtime_state")
	# Schema 4 stores authored identity in the catalog and save-specific state by stable ID.
	persistent_snapshot.erase("roster")
	var payload := {
		"save_metadata": metadata.duplicate(true),
		"campaign": persistent_snapshot,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func save_campaign() -> void:
	# Compatibility seam for existing state mutators. Campaign changes intentionally remain
	# in memory until CampaignSaveManager performs a named save or combat-return autosave.
	pass


func get_save_context() -> Dictionary:
	var raid_plan: Dictionary = campaign.get("raid_plan", {})
	var encounter_id := get_selected_encounter_id()
	var definition = GameState.get_encounter_definition(encounter_id)
	var victory_total := 0

	for victory_count in campaign.get("victories", {}).values():
		victory_total += int(victory_count)

	return {
		"region_id": String(raid_plan.get("region_id", FIRST_REGION_ID)),
		"region_name": "Beast Crucible",
		"encounter_id": encounter_id,
		"encounter_name": encounter_id if definition == null else definition.display_name,
		"victory_count": victory_total,
		"latest_outcome": String(campaign.get("latest_attempt", {}).get("outcome", "")),
	}


func get_available_encounter_ids() -> Array[String]:
	return [GameState.ENCOUNTER_OGRE, GameState.ENCOUNTER_CHAINMASTER]


func get_region_options() -> Array[Dictionary]:
	return [
		{
			"region_id": FIRST_REGION_ID,
			"display_name": "Beast Crucible",
			"unlocked": true,
			"encounter_ids": get_available_encounter_ids()
		},
		{
			"region_id": "future_region_1",
			"display_name": "Uncharted Region",
			"unlocked": false,
			"encounter_ids": []
		},
		{
			"region_id": "future_region_2",
			"display_name": "Uncharted Region",
			"unlocked": false,
			"encounter_ids": []
		}
	]


func get_raid_plan() -> Dictionary:
	return Dictionary(campaign.get("raid_plan", {})).duplicate(true)


func get_selected_encounter_id() -> String:
	return String(campaign.get("raid_plan", {}).get("encounter_id", GameState.ENCOUNTER_OGRE))


func set_selected_encounter(encounter_id: String) -> bool:
	if not get_available_encounter_ids().has(encounter_id):
		return false

	campaign["raid_plan"]["encounter_id"] = encounter_id
	save_campaign()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func get_roster_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var states: Dictionary = campaign.get("raider_states", {})

	for raider_id in get_selected_cast_ids():
		var state_value: Variant = states.get(raider_id, {})

		if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
			continue

		result.append(_project_member(raider_id, Dictionary(state_value)))

	return result


func get_roster_by_id() -> Dictionary:
	var result: Dictionary = {}

	for member in get_roster_members():
		result[String(member.get("member_id", ""))] = member

	return result


func get_member(member_id: String) -> Dictionary:
	var state_value: Variant = campaign.get("raider_states", {}).get(member_id, {})

	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return {}

	return _project_member(member_id, Dictionary(state_value))


func get_selected_cast_ids() -> Array[String]:
	return _string_array(campaign.get("campaign_cast", {}).get("selected_raider_ids", []))


func get_initial_cast_ids() -> Array[String]:
	return _string_array(campaign.get("campaign_cast", {}).get("initial_raider_ids", []))


func get_future_recruit_ids() -> Array[String]:
	return _string_array(campaign.get("campaign_cast", {}).get("future_raider_ids", []))


func get_raider_campaign_state(raider_id: String) -> Dictionary:
	var state_value: Variant = campaign.get("raider_states", {}).get(raider_id, {})
	return Dictionary(state_value).duplicate(true) if state_value is Dictionary else {}


func get_member_label(member_id: String) -> String:
	var member := get_member(member_id)
	return member_id if member.is_empty() else format_member_label(member)


func format_member_label(member: Dictionary) -> String:
	var member_name := String(member.get("display_name", "Unknown")).strip_edges()
	var unit_class := String(member.get("unit_class", "")).strip_edges()

	if unit_class.is_empty():
		return member_name

	var class_suffix := " (%s)" % unit_class

	if member_name.ends_with(class_suffix):
		return member_name

	return member_name + class_suffix


func get_active_member_ids() -> Array[String]:
	var result: Array[String] = []

	for member_id in campaign.get("raid_plan", {}).get("active_member_ids", []):
		result.append(String(member_id))

	return result


func get_active_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var roster_by_id := get_roster_by_id()

	for member_id in get_active_member_ids():
		if roster_by_id.has(member_id):
			result.append(Dictionary(roster_by_id[member_id]).duplicate(true))

	return result


func get_active_members_for_roster() -> Array[Dictionary]:
	var result := get_active_members()
	var raid_plan: Dictionary = campaign.get("raid_plan", {})

	if String(raid_plan.get("roster_sort_mode", "class_name")) == "class_name":
		_sort_members_by_class_then_name(result)

	return result


func get_reserve_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active_ids := get_active_member_ids()

	for member in get_roster_members():
		if not active_ids.has(String(member.get("member_id", ""))):
			result.append(Dictionary(member).duplicate(true))

	return result


func get_reserve_members_for_roster() -> Array[Dictionary]:
	var result := get_reserve_members()
	_sort_members_by_class_then_name(result)
	return result


func is_member_active(member_id: String) -> bool:
	return get_active_member_ids().has(member_id)


func swap_active_member(active_member_id: String, reserve_member_id: String) -> bool:
	var active_ids := get_active_member_ids()
	var active_index := active_ids.find(active_member_id)
	var roster_by_id := get_roster_by_id()

	if active_index < 0 or active_ids.has(reserve_member_id):
		return false

	if not roster_by_id.has(reserve_member_id):
		return false

	_ensure_formation()
	active_ids[active_index] = reserve_member_id
	campaign["raid_plan"]["active_member_ids"] = active_ids
	_sync_active_state_flags()

	var raid_plan: Dictionary = campaign["raid_plan"]
	var formation: Dictionary = raid_plan.get("formation", {})
	raid_plan["formation"] = _formation_with_replaced_member(
		formation, active_member_id, reserve_member_id
	)
	var saved_formations: Dictionary = raid_plan.get("saved_formations", {})

	for formation_name in saved_formations.keys():
		var saved_formation: Dictionary = saved_formations[formation_name]
		saved_formations[formation_name] = _formation_with_replaced_member(
			saved_formation, active_member_id, reserve_member_id
		)

	raid_plan["saved_formations"] = saved_formations
	campaign["raid_plan"] = raid_plan

	_augment_visit_reactions("roster_change", 1)
	emit_notable_event(
		{
			"event_type": "raider_moved_to_reserve",
			"source_system": "roster",
			"participants": [active_member_id],
			"memory_category": "roster",
			"subject_key": "roster_status",
			"significance": 58,
			"structured_data": {"replaced_by_id": reserve_member_id},
		},
		false
	)
	emit_notable_event(
		{
			"event_type": "raider_added_to_active_roster",
			"source_system": "roster",
			"participants": [reserve_member_id],
			"memory_category": "roster",
			"subject_key": "roster_status",
			"significance": 58,
			"structured_data": {"replaced_raider_id": active_member_id},
		},
		false
	)
	save_campaign()
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func reorder_active_member(
	moving_member_id: String, target_member_id: String, place_after_target: bool = false
) -> bool:
	var raid_plan: Dictionary = campaign.get("raid_plan", {})
	var active_ids := get_active_member_ids()

	if String(raid_plan.get("roster_sort_mode", "class_name")) == "class_name":
		active_ids.clear()

		for member in get_active_members_for_roster():
			active_ids.append(String(member.get("member_id", "")))

	var moving_index := active_ids.find(moving_member_id)
	var target_index := active_ids.find(target_member_id)

	if moving_index < 0 or target_index < 0 or moving_index == target_index:
		return false

	active_ids.remove_at(moving_index)
	target_index = active_ids.find(target_member_id)

	if place_after_target:
		target_index += 1

	active_ids.insert(clampi(target_index, 0, active_ids.size()), moving_member_id)
	campaign["raid_plan"]["active_member_ids"] = active_ids
	_sync_active_state_flags()
	campaign["raid_plan"]["roster_sort_mode"] = "custom"
	save_campaign()
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func get_formation(_encounter_id: String = "") -> Dictionary:
	_ensure_formation()
	return Dictionary(campaign["raid_plan"]["formation"]).duplicate(true)


func set_member_placement(
	member_id: String, region: String, range_name: String, _encounter_id: String = ""
) -> bool:
	if not RaidPlanValidatorScript.VALID_REGIONS.has(region):
		return false

	if not RaidPlanValidatorScript.VALID_RANGES.has(range_name):
		return false

	if not get_active_member_ids().has(member_id):
		return false

	_ensure_formation()
	campaign["raid_plan"]["formation"]["placements"][member_id] = {
		"region": region, "range": range_name
	}
	campaign["raid_plan"]["formation"]["preset_name"] = "Custom"
	save_campaign()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func apply_default_formation(_encounter_id: String = "") -> void:
	campaign["raid_plan"]["formation"] = _build_default_formation()
	save_campaign()
	raid_plan_changed.emit()
	state_changed.emit()


func replace_current_formation(source: Dictionary) -> void:
	_ensure_formation()
	campaign["raid_plan"]["formation"] = _sanitize_formation_for_active(source)
	raid_plan_changed.emit()
	state_changed.emit()


func get_saved_formation_names() -> Array[String]:
	_ensure_formation()
	var names: Array[String] = []
	var saved_formations: Dictionary = campaign["raid_plan"].get("saved_formations", {})

	for formation_name in saved_formations.keys():
		names.append(String(formation_name))

	names.sort()
	return names


func save_current_formation(formation_name: String) -> bool:
	formation_name = formation_name.strip_edges()

	if formation_name.is_empty() or formation_name.to_lower() == DEFAULT_FORMATION_NAME.to_lower():
		return false

	_ensure_formation()
	var current := get_formation()
	current["preset_name"] = formation_name
	campaign["raid_plan"]["formation"] = current.duplicate(true)
	campaign["raid_plan"]["saved_formations"][formation_name] = current.duplicate(true)
	save_campaign()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func load_formation(formation_name: String) -> bool:
	_ensure_formation()

	if formation_name == DEFAULT_FORMATION_NAME:
		apply_default_formation()
		return true

	var saved_formations: Dictionary = campaign["raid_plan"].get("saved_formations", {})

	if not saved_formations.has(formation_name):
		return false

	var source: Dictionary = saved_formations[formation_name]
	var loaded := _sanitize_formation_for_active(source)
	loaded["preset_name"] = formation_name
	campaign["raid_plan"]["formation"] = loaded
	save_campaign()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func delete_saved_formation(formation_name: String) -> bool:
	_ensure_formation()
	var saved_formations: Dictionary = campaign["raid_plan"].get("saved_formations", {})

	if not saved_formations.has(formation_name):
		return false

	saved_formations.erase(formation_name)
	campaign["raid_plan"]["saved_formations"] = saved_formations
	save_campaign()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func validate_raid_plan() -> Dictionary:
	return RaidPlanValidatorScript.validate(
		campaign.get("raid_plan", {}), get_roster_by_id(), get_available_encounter_ids()
	)


func get_role_counts() -> Dictionary:
	var counts := {"tank": 0, "healer": 0, "dps": 0}

	for member in get_active_members():
		var role := String(member.get("role", "dps"))
		counts[role] = int(counts.get(role, 0)) + 1

	return counts


func emit_notable_event(raw_event: Dictionary, emit_change: bool = true) -> Dictionary:
	if raw_event.is_empty():
		return {}

	campaign["notable_event_sequence"] = int(campaign.get("notable_event_sequence", 0)) + 1
	var prepared := raw_event.duplicate(true)
	prepared["event_id"] = String(
		prepared.get("event_id", "event_%08d" % int(campaign["notable_event_sequence"]))
	)
	prepared["recorded_unix_time"] = int(
		prepared.get("recorded_unix_time", Time.get_unix_time_from_system())
	)
	var result := CampV2EventSystemScript.process_event(campaign, prepared)
	var event: Dictionary = result.get("event", {})

	if event.is_empty():
		return {}

	_mark_profile_updates(event.get("participants", []))

	notable_event_recorded.emit(event.duplicate(true))

	for derived_value in result.get("derived_events", []):
		if not derived_value is Dictionary:
			continue

		var derived: Dictionary = derived_value
		_mark_profile_updates(derived.get("participants", []))
		notable_event_recorded.emit(derived.duplicate(true))

		match String(derived.get("event_type", "")):
			"memory_promoted":
				memory_promoted.emit(derived.duplicate(true))
			"relationship_threshold_reached":
				relationship_threshold_reached.emit(derived.duplicate(true))

		CampConversationStateScript.apply_event_pressure(
			_get_camp_conversation_store(), derived
		)

	CampConversationStateScript.apply_event_pressure(_get_camp_conversation_store(), event)

	save_campaign()

	if emit_change:
		state_changed.emit()

	return event.duplicate(true)


func get_recent_notable_events(limit: int = 30) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var records: Array = campaign.get("notable_event_records", [])
	var first_index := maxi(records.size() - maxi(limit, 0), 0)

	for value in records.slice(first_index):
		if value is Dictionary:
			result.append(Dictionary(value).duplicate(true))

	return result


func get_raid_chronicle(limit: int = 30) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Array = campaign.get("raid_chronicle", [])
	var first_index := maxi(entries.size() - maxi(limit, 0), 0)

	for value in entries.slice(first_index):
		if value is Dictionary:
			result.append(Dictionary(value).duplicate(true))

	return result


func get_raider_memories(raider_id: String) -> Dictionary:
	return RaiderMemoryStoreScript.get_raider_memory(
		Dictionary(campaign.get("memory_store", {})), raider_id
	)


func get_relationship(first_id: String, second_id: String) -> Dictionary:
	return RaiderRelationshipStoreScript.get_pair(
		Dictionary(campaign.get("relationship_store", {})), first_id, second_id
	)


func get_relationship_label(viewer_id: String, other_id: String) -> String:
	var pair := get_relationship(viewer_id, other_id)
	return RaiderRelationshipStoreScript.get_public_label(
		pair, viewer_id
	)


func get_raider_lore_knowledge(raider_id: String) -> Dictionary:
	return RaiderLoreKnowledgeStoreScript.get_raider_knowledge(
		Dictionary(campaign.get("lore_knowledge_store", {})), raider_id
	)


func get_room_options(for_raider_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var occupants_by_room := _room_occupants_by_id(campaign)

	for room_number in range(1, QUARTERS_ROOM_COUNT + 1):
		var room_id := _room_id(room_number)
		var occupant_ids: Array = occupants_by_room.get(room_id, [])
		result.append(
			{
				"room_id": room_id,
				"label": room_label(room_id),
				"capacity": QUARTERS_ROOM_CAPACITY,
				"occupant_ids": occupant_ids.duplicate(),
				"available": (
					occupant_ids.has(for_raider_id)
					or occupant_ids.size() < QUARTERS_ROOM_CAPACITY
				),
			}
		)

	return result


func room_label(room_assignment_id: String) -> String:
	if not _is_valid_room_id(room_assignment_id):
		return "Unassigned"
	return "Room %02d" % int(room_assignment_id.get_slice("_", 1))


func get_room_assignment_label(raider_id: String) -> String:
	return room_label(String(get_raider_campaign_state(raider_id).get("room_assignment_id", "")))


func get_roommate_summary(raider_id: String) -> String:
	var state := get_raider_campaign_state(raider_id)
	var room_id := String(state.get("room_assignment_id", ""))
	if room_id.is_empty():
		return "Automatic assignment pending."

	for occupant_id in _room_occupants_by_id(campaign).get(room_id, []):
		if String(occupant_id) == raider_id:
			continue
		var roommate := get_member(String(occupant_id))
		return "Roommate: %s" % String(roommate.get("display_name", occupant_id))
	return "Private for now."


func has_unseen_profile_development(raider_id: String) -> bool:
	return get_unseen_profile_development_count(raider_id) > 0


func get_unseen_profile_development_count(raider_id: String) -> int:
	var quarters: Dictionary = campaign.get("member_quarters_state", {})
	var current := int(quarters.get("profile_revisions", {}).get(raider_id, 0))
	var seen := int(quarters.get("seen_profile_revisions", {}).get(raider_id, 0))
	return maxi(current - seen, 0)


func mark_raider_profile_seen(raider_id: String) -> bool:
	if get_member(raider_id).is_empty():
		return false
	var quarters := _get_member_quarters_state()
	var current := int(quarters.get("profile_revisions", {}).get(raider_id, 0))
	var seen: Dictionary = quarters.get("seen_profile_revisions", {})
	seen[raider_id] = current
	quarters["seen_profile_revisions"] = seen
	campaign["member_quarters_state"] = quarters
	return true


func record_completed_conversation(
	first_id: String, second_id: String, controlled_outcome: Dictionary
) -> Dictionary:
	if first_id.is_empty() or second_id.is_empty() or first_id == second_id:
		return {}

	var data := controlled_outcome.duplicate(true)
	data["controlled_outcome"] = bool(data.get("controlled_outcome", true))
	data["meaningful"] = bool(data.get("meaningful", true))
	return emit_notable_event(
		{
			"event_type": "conversation_completed",
			"source_system": "conversation",
			"participants": [first_id, second_id],
			"memory_category": "social",
			"subject_key": String(data.get("subject_key", "conversation:%s" % second_id)),
			"significance": int(data.get("significance", 60)),
			"personal_participants": data.get("personal_participants", []),
			"admission_reasons": data.get(
				"admission_reasons", ["involved_specific_person"]
			),
			"reinforcement_mode": "social",
			"structured_data": data,
			"prose_template_id": String(
				data.get("prose_template_id", "conversation_completed")
			),
			"prose_parameters": data.get("prose_parameters", {}),
		}
	)


func record_significant_shared_activity(
	first_id: String, second_id: String, activity_id: String, meaningful: bool = false
) -> Dictionary:
	return emit_notable_event(
		{
			"event_type": "significant_shared_activity",
			"source_system": "camp_activity",
			"participants": [first_id, second_id],
			"memory_category": "camp_life",
			"subject_key": "facility_activity:%s" % activity_id,
			"significance": 55 if meaningful else 40,
			"structured_data": {
				"activity_id": activity_id,
				"meaningful": meaningful,
				"threshold_worthy": false,
			},
			"prose_template_id": "significant_shared_activity",
			"prose_parameters": {"activity_id": activity_id},
		}
	)


func reinforce_memory_through_reflection(
	raider_id: String, category: String, subject_key: String, authored_significance: bool = false
) -> Dictionary:
	return emit_notable_event(
		{
			"event_type": "self_reflection",
			"source_system": "reflection",
			"participants": [raider_id],
			"memory_category": category,
			"subject_key": subject_key,
			"significance": 45,
			"memory_strength": 0.22,
			"reinforcement_mode": "self",
			"authored_significance": authored_significance,
			"admission_reasons": ["reinforces_existing_thread"],
			"structured_data": {"reflection": true},
		}
	)


func record_lore_knowledge(
	raider_id: String,
	topic_id: String,
	knowledge_state: String,
	interpretation: String,
	source_id: String,
	shared_with_raid: bool = false
) -> Dictionary:
	return emit_notable_event(
		{
			"event_type": "lore_learned",
			"source_system": "lore",
			"participants": [raider_id],
			"memory_category": "personal_reflection",
			"subject_key": "lore:%s" % topic_id,
			"significance": 50,
			"admission_reasons": [],
			"structured_data": {
				"topic_id": topic_id,
				"knowledge_state": knowledge_state,
				"interpretation": interpretation,
				"source_id": source_id,
				"shared_with_raid": shared_with_raid,
			},
		}
	)


func advance_camp_conversation_time(delta: float, concurrent_conversations: int = 0) -> void:
	CampConversationStateScript.advance(
		_get_camp_conversation_store(), delta, concurrent_conversations
	)


func is_ordinary_conversation_due() -> bool:
	return CampConversationStateScript.is_due(_get_camp_conversation_store())


func get_next_conversation_cooldown(variance: float = 0.0) -> float:
	return CampConversationStateScript.get_next_cooldown(
		_get_camp_conversation_store(), variance
	)


func schedule_next_ordinary_conversation(cooldown: float) -> void:
	CampConversationStateScript.schedule_next(_get_camp_conversation_store(), cooldown)


func set_conversation_cooldowns(cooldown_durations: Dictionary) -> void:
	CampConversationStateScript.set_cooldowns(
		_get_camp_conversation_store(), cooldown_durations
	)


func get_conversation_cooldown_remaining(key: String) -> float:
	return CampConversationStateScript.cooldown_remaining(
		_get_camp_conversation_store(), key
	)


func note_conversation_schedule_miss(reason: String) -> void:
	CampConversationStateScript.note_schedule_miss(
		_get_camp_conversation_store(), reason
	)


func record_conversation_summary(summary: Dictionary) -> Dictionary:
	if summary.is_empty():
		return {}
	return CampConversationStateScript.add_summary(
		_get_camp_conversation_store(), summary
	)


func get_conversation_summaries(raider_id: String = "", limit: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var summaries: Array = _get_camp_conversation_store().get("recent_summaries", [])
	var first_index := maxi(summaries.size() - maxi(limit, 0), 0)

	for value in summaries.slice(first_index):
		if not value is Dictionary:
			continue
		var summary := Dictionary(value)
		if raider_id.is_empty() or summary.get("participant_ids", []).has(raider_id):
			result.append(summary.duplicate(true))

	return result


func get_camp_conversation_debug_report() -> Dictionary:
	return CampConversationStateScript.get_debug_report(
		_get_camp_conversation_store()
	)


func recruit_raider(raider_id: String, recruitment_source: String) -> bool:
	var states: Dictionary = campaign.get("raider_states", {})
	var state_value: Variant = states.get(raider_id, {})

	if not state_value is Dictionary or bool(state_value.get("recruited", false)):
		return false

	var state: Dictionary = state_value
	state["recruited"] = true
	state["recruitment_source"] = recruitment_source
	states[raider_id] = state
	campaign["raider_states"] = states
	_assign_room_automatically_internal(raider_id)
	emit_notable_event(
		{
			"event_type": "raider_recruited",
			"source_system": "recruitment",
			"participants": [raider_id],
			"memory_category": "roster",
			"subject_key": "recruitment",
			"significance": 70,
			"structured_data": {"recruitment_source": recruitment_source},
		},
		false
	)
	_augment_visit_reactions("recruitment", 1)
	roster_changed.emit()
	state_changed.emit()
	return true


func set_room_assignment(
	raider_id: String, room_assignment_id: String, roommate_id: String = ""
) -> bool:
	if room_assignment_id == "auto" or room_assignment_id.is_empty():
		return assign_raider_room_automatically(raider_id)
	if not _is_valid_room_id(room_assignment_id):
		return false

	var states: Dictionary = campaign.get("raider_states", {})
	var state_value: Variant = states.get(raider_id, {})

	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return false

	var participants: Array[String] = [raider_id]
	if not roommate_id.is_empty() and roommate_id != raider_id:
		var roommate_value: Variant = states.get(roommate_id, {})
		if not roommate_value is Dictionary or not bool(roommate_value.get("recruited", false)):
			return false
		participants.append(roommate_id)

	var existing_occupants: Array = _room_occupants_by_id(campaign).get(room_assignment_id, [])
	for participant_id in participants:
		existing_occupants.erase(participant_id)
	if existing_occupants.size() + participants.size() > QUARTERS_ROOM_CAPACITY:
		return false

	var previous_room := String(Dictionary(state_value).get("room_assignment_id", ""))
	var changed := false
	for participant_id in participants:
		var participant_state: Dictionary = Dictionary(states[participant_id])
		if String(participant_state.get("room_assignment_id", "")) != room_assignment_id:
			participant_state["room_assignment_id"] = room_assignment_id
			states[participant_id] = participant_state
			changed = true

	if not changed:
		return true

	for occupant_id in existing_occupants:
		if not participants.has(String(occupant_id)):
			participants.append(String(occupant_id))

	campaign["raider_states"] = states
	emit_notable_event(
		{
			"event_type": "room_assignment_changed",
			"source_system": "quarters",
			"participants": participants,
			"memory_category": "roster",
			"subject_key": "room_assignment",
			"significance": 52,
			"personal_participants": [raider_id] if participants.size() == 2 else [],
			"structured_data": {
				"previous_room_assignment_id": previous_room,
				"room_assignment_id": room_assignment_id,
				"meaningful": false,
			},
		},
		false
	)
	state_changed.emit()
	return true


func assign_raider_room_automatically(raider_id: String) -> bool:
	var state := get_raider_campaign_state(raider_id)
	if state.is_empty() or not bool(state.get("recruited", false)):
		return false
	var occupants_by_room := _room_occupants_by_id(campaign)
	var current_room := String(state.get("room_assignment_id", ""))
	if _is_valid_room_id(current_room):
		var current_occupants: Array = occupants_by_room.get(current_room, [])
		if current_occupants.size() <= QUARTERS_ROOM_CAPACITY:
			return true

	for room_number in range(1, QUARTERS_ROOM_COUNT + 1):
		var room_id := _room_id(room_number)
		var occupants: Array = occupants_by_room.get(room_id, [])
		if occupants.size() < QUARTERS_ROOM_CAPACITY:
			return set_room_assignment(raider_id, room_id)
	return false


func advance_raider_class(
	raider_id: String, advanced_class_id: String, specialization_id: String = ""
) -> bool:
	var states: Dictionary = campaign.get("raider_states", {})
	var state_value: Variant = states.get(raider_id, {})

	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return false

	var state: Dictionary = state_value
	var previous_class := String(state.get("advanced_class_id", ""))
	state["advanced_class_id"] = advanced_class_id
	state["specialization_id"] = specialization_id
	states[raider_id] = state
	campaign["raider_states"] = states
	emit_notable_event(
		{
			"event_type": "class_advanced",
			"source_system": "class_advancement",
			"participants": [raider_id],
			"memory_category": "personal_reflection",
			"subject_key": "class_advancement:%s" % advanced_class_id,
			"significance": 88,
			"is_milestone": true,
			"permanent_eligible": true,
			"promotion_reason": "important_class_milestone",
			"force_episode": true,
			"structured_data": {
				"previous_advanced_class_id": previous_class,
				"advanced_class_id": advanced_class_id,
				"specialization_id": specialization_id,
			},
			"life_prose_template_id": "important_class_milestone",
		},
		false
	)
	state_changed.emit()
	return true


func advance_memory_lifecycle(now_unix_time: int = 0) -> void:
	var now := now_unix_time if now_unix_time > 0 else int(Time.get_unix_time_from_system())
	CampV2EventSystemScript.advance_lifecycle(campaign, now)
	save_campaign()
	state_changed.emit()


func record_attempt(summary: Dictionary) -> void:
	if summary.is_empty():
		return

	var encounter_id := String(summary.get("encounter_id", get_selected_encounter_id()))
	var known_discoveries := get_discoveries(encounter_id)
	var known_abilities: Array = known_discoveries.get("ability_ids", [])
	var known_phases: Array = known_discoveries.get("phase_ids", [])
	var newly_observed_abilities: Array[String] = []
	var newly_observed_phases: Array[String] = []

	for ability_id in summary.get("observed_ability_ids", []):
		if not known_abilities.has(ability_id):
			newly_observed_abilities.append(String(ability_id))

	for phase_id in summary.get("observed_phase_ids", []):
		if not known_phases.has(phase_id):
			newly_observed_phases.append(String(phase_id))

	summary["newly_discovered_ability_ids"] = newly_observed_abilities
	summary["newly_discovered_phase_ids"] = newly_observed_phases
	var history: Dictionary = campaign.get("attempt_history", {})
	var encounter_history: Array = history.get(encounter_id, [])
	encounter_history.append(summary.duplicate(true))

	if encounter_history.size() > ATTEMPT_HISTORY_LIMIT:
		encounter_history = encounter_history.slice(
			encounter_history.size() - ATTEMPT_HISTORY_LIMIT
		)

	history[encounter_id] = encounter_history
	campaign["attempt_history"] = history
	campaign["latest_attempt"] = summary.duplicate(true)
	_update_discoveries_from_attempt(summary)

	if String(summary.get("outcome", "")) == "victory":
		_record_victory(encounter_id)

	_record_active_raider_combat_history(String(summary.get("outcome", "")))
	_emit_attempt_notable_events(summary)
	save_campaign()
	attempt_recorded.emit(summary.duplicate(true))
	state_changed.emit()


func get_attempt_history(encounter_id: String = "") -> Array[Dictionary]:
	if encounter_id.is_empty():
		encounter_id = get_selected_encounter_id()

	var result: Array[Dictionary] = []
	var stored_history: Array = campaign.get("attempt_history", {}).get(encounter_id, [])
	var first_index := maxi(stored_history.size() - ATTEMPT_HISTORY_LIMIT, 0)

	for summary in stored_history.slice(first_index):
		if summary is Dictionary:
			result.append(Dictionary(summary).duplicate(true))

	return result


func get_latest_attempt(encounter_id: String = "") -> Dictionary:
	var history := get_attempt_history(encounter_id)
	return {} if history.is_empty() else history[-1]


func get_discoveries(encounter_id: String = "") -> Dictionary:
	if encounter_id.is_empty():
		encounter_id = get_selected_encounter_id()

	return Dictionary(campaign.get("discoveries", {}).get(encounter_id, {})).duplicate(true)


func get_latest_victory() -> Dictionary:
	return Dictionary(campaign.get("latest_victory", {})).duplicate(true)


func get_victory_count(encounter_id: String) -> int:
	return int(campaign.get("victories", {}).get(encounter_id, 0))


func begin_visit(context_type: String = "normal", details: Dictionary = {}) -> void:
	var base_budget: int = int(
		(
			{
				"normal": 2,
				"wipe": 9,
				"first_victory": 16,
				"repeat_victory": 8,
				"recruitment": 14,
				"apex_victory": 22,
				"roster_change": 4
			}
			. get(context_type, 2)
		)
	)

	campaign["visit_context"] = {
		"type": context_type,
		"reaction_budget": int(base_budget),
		"reactions_emitted": 0,
		"details": details.duplicate(true),
		"started_unix_time": int(Time.get_unix_time_from_system())
	}
	CampConversationStateScript.apply_visit_pressure(
		_get_camp_conversation_store(), context_type
	)
	save_campaign()
	visit_context_changed.emit(get_visit_context())
	state_changed.emit()


func get_visit_context() -> Dictionary:
	return Dictionary(campaign.get("visit_context", {})).duplicate(true)


func consume_visit_reaction() -> bool:
	var context: Dictionary = campaign.get("visit_context", {})
	var emitted := int(context.get("reactions_emitted", 0))
	var budget := int(context.get("reaction_budget", 0))

	if emitted >= budget:
		return false

	context["reactions_emitted"] = emitted + 1
	campaign["visit_context"] = context
	return true


func ensure_debug_reserves() -> int:
	var states: Dictionary = campaign.get("raider_states", {})
	var recruited_count := 0
	var recruited_ids: Array[String] = []

	for raider_id in get_future_recruit_ids():
		var state_value: Variant = states.get(raider_id, {})

		if not state_value is Dictionary:
			continue

		var state: Dictionary = state_value

		if bool(state.get("recruited", false)):
			continue

		state["recruited"] = true
		state["recruitment_source"] = "debug_recruitment"
		states[raider_id] = state
		recruited_count += 1
		recruited_ids.append(raider_id)

	if recruited_count <= 0:
		return 0

	campaign["raider_states"] = states
	_ensure_valid_room_assignments(campaign)
	_augment_visit_reactions("recruitment", recruited_count)
	emit_notable_event(
		{
			"event_type": "raider_recruited",
			"source_system": "debug_recruitment",
			"participants": recruited_ids,
			"memory_category": "roster",
			"subject_key": "recruitment",
			"significance": 70,
			"structured_data": {
				"recruitment_source": "debug_recruitment",
				"recruited_count": recruited_count,
			},
			"prose_template_id": "large_recruitment",
		},
		false
	)
	save_campaign()
	roster_changed.emit()
	state_changed.emit()
	return recruited_count


func mark_apex_victory_hook(region_id: String, unlocked_region_ids: Array[String]) -> void:
	# No current encounter calls this. It is the narrow V1 seam for the later regional apex.
	for unlocked_region_id in unlocked_region_ids:
		if not campaign["unlocked_regions"].has(unlocked_region_id):
			campaign["unlocked_regions"].append(unlocked_region_id)

	begin_visit(
		"apex_victory",
		{"region_id": region_id, "unlocked_region_ids": unlocked_region_ids.duplicate()}
	)


func get_campaign_debug_summary() -> Dictionary:
	return {
		"schema_version": int(campaign.get("schema_version", 0)),
		"roster_size": get_roster_members().size(),
		"active_size": get_active_member_ids().size(),
		"selected_encounter": get_selected_encounter_id(),
		"plan_validation": validate_raid_plan(),
		"visit_context": get_visit_context(),
		"campaign_cast": get_campaign_cast_report(),
	}


func get_campaign_cast_report() -> Dictionary:
	var cast: Dictionary = campaign.get("campaign_cast", {})
	var diagnostics: Dictionary = campaign.get("data_diagnostics", {})
	var class_distribution: Dictionary = {}
	var role_distribution: Dictionary = {}
	var states: Dictionary = campaign.get("raider_states", {})

	for raider_id in get_selected_cast_ids():
		var state_value: Variant = states.get(raider_id, {})

		if not state_value is Dictionary:
			continue

		var state: Dictionary = state_value
		var unit_class := String(state.get("current_class", "Unknown"))
		var definition := _get_definition_with_fallback(raider_id)
		var role := String(definition.get("default_role", "unknown"))
		class_distribution[unit_class] = int(class_distribution.get(unit_class, 0)) + 1
		role_distribution[role] = int(role_distribution.get(role, 0)) + 1

	var warnings := _string_array(cast.get("generation_warnings", []))

	for catalog_warning in RaiderCatalogScript.get_warnings():
		if not warnings.has(catalog_warning):
			warnings.append(catalog_warning)

	return {
		"campaign_seed": int(campaign.get("campaign_seed", 0)),
		"catalog_version": int(cast.get("catalog_version", 0)),
		"selected_40": get_selected_cast_ids(),
		"initial_20": get_initial_cast_ids(),
		"future_20": get_future_recruit_ids(),
		"class_distribution": class_distribution,
		"role_distribution": role_distribution,
		"generation_validation_warnings": warnings,
		"migrated_raider_ids": _string_array(diagnostics.get("migrated_raider_ids", [])),
		"missing_definition_ids": _string_array(
			diagnostics.get("missing_definition_ids", [])
		),
		"migrated_from_schema": int(diagnostics.get("migrated_from_schema", SCHEMA_VERSION)),
	}


func print_campaign_cast_report() -> void:
	print("[Camp V2 Campaign Cast]\n" + JSON.stringify(get_campaign_cast_report(), "\t"))


func get_camp_v2_event_debug_report() -> Dictionary:
	return CampV2EventSystemScript.get_debug_report(campaign)


func print_camp_v2_event_debug_report() -> void:
	print(
		"[Camp V2 Events, Memories, Relationships]\n"
		+ JSON.stringify(get_camp_v2_event_debug_report(), "\t")
	)


func run_camp_v2_event_debug_smoke() -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "reason": "debug_build_required"}

	var active_ids := get_active_member_ids()

	if active_ids.size() < 3:
		return {"ok": false, "reason": "at_least_three_active_raiders_required"}

	var first_id := active_ids[0]
	var second_id := active_ids[1]
	var third_id := active_ids[2]

	for repeat_index in range(3):
		emit_notable_event(
			{
				"event_type": "mechanic_failed",
				"source_system": "debug_smoke",
				"participants": [first_id],
				"memory_category": "combat",
				"subject_key": "debug_mechanic:iron_collar",
				"significance": 65,
				"memory_strength": 0.38,
				"structured_data": {"debug_repeat": repeat_index + 1},
			},
			false
		)

	emit_notable_event(
		{
			"event_type": "mechanic_successfully_resolved",
			"source_system": "debug_smoke",
			"participants": [first_id],
			"memory_category": "combat",
			"subject_key": "debug_mechanic:iron_collar",
			"significance": 82,
			"memory_strength": 0.65,
			"force_episode": true,
			"structured_data": {"resolves_thread": true},
			"life_prose_template_id": "overcame_repeated_mechanic_failures",
		},
		false
	)

	record_completed_conversation(
		first_id,
		second_id,
		{
			"outcome_id": "debug_mutual_understanding",
			"controlled_outcome": true,
			"qualifies_for_relationship_change": true,
			"meaningful": true,
			"significance": 75,
			"relationship_deltas": {
				first_id: {"affinity": 58, "trust": 55, "respect": 22},
				second_id: {"affinity": 50, "trust": 45, "respect": 24},
			},
		}
	)

	emit_notable_event(
		{
			"event_type": "boss_attempt_completed",
			"source_system": "debug_smoke",
			"participants": [first_id, second_id, third_id],
			"distinctive_participants": [
				{
					"raider_id": third_id,
					"admission_reasons": ["unusual_for_raider", "meaningful_agency"],
					"memory_strength": 0.6,
				}
			],
			"memory_category": "combat",
			"subject_key": "debug_group_event",
			"significance": 70,
			"structured_data": {"debug": true},
		},
		false
	)

	record_lore_knowledge(
		third_id,
		"debug_beast_crucible_origin",
		"partial",
		"The Crucible may predate its keepers.",
		"debug_archive_fragment",
		false
	)
	state_changed.emit()
	return {
		"ok": true,
		"raider_id": first_id,
		"partner_id": second_id,
		"chronicle_participants": [first_id, second_id, third_id],
	}


func _create_default_campaign(seed_override: int = 0) -> Dictionary:
	var campaign_seed := seed_override if seed_override != 0 else _generate_campaign_seed()
	var generation := CampaignCastGeneratorScript.generate(
		campaign_seed, RaiderCatalogScript.get_all_definitions()
	)
	var active_member_ids := _string_array(generation.get("initial_raider_ids", []))
	var states: Dictionary = {}
	var projected_roster: Array[Dictionary] = []

	for raider_id in _string_array(generation.get("selected_raider_ids", [])):
		var definition := RaiderCatalogScript.get_definition(raider_id)
		var is_initial := active_member_ids.has(raider_id)
		var recruitment: Dictionary = definition.get("recruitment", {})
		var state := CampaignRaiderStateScript.create(
			raider_id,
			String(definition.get("default_class", "Mage")),
			is_initial,
			is_initial,
			String(
				recruitment.get("source_hint", "starting_writ" if is_initial else "unrecruited")
			)
		)
		if is_initial:
			var initial_index := active_member_ids.find(raider_id)
			state["room_assignment_id"] = _room_id(
				floori(float(initial_index) / float(QUARTERS_ROOM_CAPACITY)) + 1
			)
		states[raider_id] = state

		if is_initial:
			projected_roster.append(_project_member_from(definition, state))

	var default_formation := _build_default_formation_for_ids(
		active_member_ids, projected_roster
	)

	return {
		"schema_version": SCHEMA_VERSION,
		"campaign_seed": campaign_seed,
		"campaign_cast":
		{
			"catalog_version": RaiderCatalogScript.get_catalog_version(),
			"selected_raider_ids": _string_array(generation.get("selected_raider_ids", [])),
			"initial_raider_ids": active_member_ids.duplicate(),
			"future_raider_ids": _string_array(generation.get("future_raider_ids", [])),
			"generation_warnings": _string_array(generation.get("warnings", [])),
		},
		"raider_states": states,
		"fallback_raider_definitions": {},
		"data_diagnostics":
		{
			"migrated_from_schema": SCHEMA_VERSION,
			"migrated_raider_ids": [],
			"missing_definition_ids": [],
		},
		"memory_store": CampV2EventSystemScript.create_memory_store(),
		"relationship_store": CampV2EventSystemScript.create_relationship_store(),
		"lore_knowledge_store": CampV2EventSystemScript.create_lore_store(),
		"camp_conversation_state": CampConversationStateScript.create_store(),
		"member_quarters_state": {
			"profile_revisions": {},
			"seen_profile_revisions": {},
		},
		"notable_event_records": [],
		"raid_chronicle": [],
		"notable_event_sequence": 0,
		"raid_plan":
		{
			"region_id": FIRST_REGION_ID,
			"encounter_id": GameState.ENCOUNTER_OGRE,
			"active_member_ids": active_member_ids,
			"roster_sort_mode": "class_name",
			"formation": default_formation,
			"saved_formations": {},
			"support_selections": {},
			"encounter_configuration": {}
		},
		"unlocked_regions": [FIRST_REGION_ID],
		"victories": {},
		"boss_resources": {},
		"discoveries": {},
		"attempt_history": {},
		"latest_attempt": {},
		"latest_victory": {},
		"visit_context":
		{
			"type": "normal",
			"reaction_budget": 2,
			"reactions_emitted": 0,
			"details": {},
			"started_unix_time": int(Time.get_unix_time_from_system())
		}
	}


func _sort_members_by_class_then_name(members: Array[Dictionary]) -> void:
	members.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var class_order := String(a.get("unit_class", "")).naturalnocasecmp_to(
				String(b.get("unit_class", ""))
			)

			if class_order != 0:
				return class_order < 0

			var name_order := String(a.get("display_name", "")).naturalnocasecmp_to(
				String(b.get("display_name", ""))
			)

			if name_order != 0:
				return name_order < 0

			return String(a.get("member_id", "")).naturalnocasecmp_to(
				String(b.get("member_id", ""))
			) < 0
	)


func _migrate_campaign(source: Dictionary) -> Dictionary:
	var source_version := int(source.get("schema_version", 0))
	var source_seed := int(source.get("campaign_seed", 20004))
	var defaults := _create_default_campaign(source_seed)
	var migrated := source.duplicate(true)

	for key in defaults.keys():
		if not migrated.has(key):
			migrated[key] = defaults[key]

	var default_plan: Dictionary = defaults["raid_plan"]
	var raid_plan_value: Variant = migrated.get("raid_plan", {})
	var raid_plan: Dictionary = (
		Dictionary(raid_plan_value).duplicate(true)
		if raid_plan_value is Dictionary
		else default_plan.duplicate(true)
	)

	for plan_key in default_plan.keys():
		if plan_key in ["formation", "saved_formations"]:
			continue

		if not raid_plan.has(plan_key):
			raid_plan[plan_key] = default_plan[plan_key]

	var formation_value: Variant = raid_plan.get("formation")
	var legacy_formations: Dictionary = {}

	if not formation_value is Dictionary:
		var legacy_formations_value: Variant = raid_plan.get("formations", {})
		legacy_formations = (
			Dictionary(legacy_formations_value) if legacy_formations_value is Dictionary else {}
		)
		var selected_encounter := String(raid_plan.get("encounter_id", GameState.ENCOUNTER_OGRE))
		formation_value = legacy_formations.get(selected_encounter, {})

		if not formation_value is Dictionary or Dictionary(formation_value).is_empty():
			formation_value = default_plan["formation"]

	raid_plan["formation"] = Dictionary(formation_value).duplicate(true)

	var saved_formations_value: Variant = raid_plan.get("saved_formations", {})
	var saved_formations: Dictionary = (
		Dictionary(saved_formations_value).duplicate(true)
		if saved_formations_value is Dictionary
		else {}
	)

	for legacy_encounter_id in legacy_formations.keys():
		var legacy_formation_value: Variant = legacy_formations[legacy_encounter_id]

		if not legacy_formation_value is Dictionary:
			continue

		var imported_name := "Imported %s layout" % String(legacy_encounter_id).capitalize()

		if saved_formations.has(imported_name):
			continue

		var imported_formation := Dictionary(legacy_formation_value).duplicate(true)
		imported_formation["preset_name"] = imported_name
		saved_formations[imported_name] = imported_formation

	raid_plan["saved_formations"] = saved_formations
	raid_plan.erase("formations")
	migrated["raid_plan"] = raid_plan

	if not _has_layered_raider_data(migrated):
		if not _migrate_legacy_raider_data(migrated, defaults, source_version):
			return defaults
	else:
		_sanitize_layered_raider_data(migrated, defaults, source_version)

	CampV2EventSystemScript.sanitize_campaign_stores(
		migrated,
		_string_array(migrated.get("campaign_cast", {}).get("selected_raider_ids", []))
	)
	migrated["camp_conversation_state"] = CampConversationStateScript.sanitize_store(
		migrated.get("camp_conversation_state", {}),
		_string_array(migrated.get("campaign_cast", {}).get("selected_raider_ids", []))
	)
	migrated["member_quarters_state"] = _sanitize_member_quarters_state(
		migrated.get("member_quarters_state", {}),
		_string_array(migrated.get("campaign_cast", {}).get("selected_raider_ids", [])),
		migrated
	)
	_ensure_valid_room_assignments(migrated)
	migrated.erase("roster")
	migrated.erase("next_member_serial")
	migrated["attempt_history"] = _normalize_attempt_history(
		migrated.get("attempt_history", {})
	)
	migrated["schema_version"] = SCHEMA_VERSION
	campaign = migrated
	_sync_active_state_flags()
	_ensure_formation()
	return campaign


func _has_layered_raider_data(source: Dictionary) -> bool:
	return source.get("campaign_cast") is Dictionary and source.get("raider_states") is Dictionary


func _migrate_legacy_raider_data(
	migrated: Dictionary, defaults: Dictionary, source_version: int
) -> bool:
	var legacy_roster: Array[Dictionary] = []

	for member_value in migrated.get("roster", []):
		if member_value is Dictionary:
			legacy_roster.append(RaidMemberRecordScript.sanitize(member_value))

	if legacy_roster.is_empty():
		push_warning("Legacy campaign had no valid roster; a new campaign was created instead.")
		return false

	var selected_ids: Array[String] = []
	var legacy_by_id: Dictionary = {}

	for index in range(legacy_roster.size()):
		var member := legacy_roster[index]
		var raider_id := String(member.get("member_id", "")).strip_edges()

		if raider_id.is_empty():
			raider_id = "legacy_%03d" % (index + 1)
			member["member_id"] = raider_id

		if legacy_by_id.has(raider_id):
			push_warning("Legacy roster contained duplicate member_id: " + raider_id)
			continue

		legacy_by_id[raider_id] = member
		selected_ids.append(raider_id)

	for generated_id in _string_array(
		defaults.get("campaign_cast", {}).get("selected_raider_ids", [])
	):
		if selected_ids.size() >= CampaignCastGeneratorScript.CAST_SIZE:
			break

		_append_unique_id(selected_ids, generated_id)

	var initial_ids: Array[String] = []

	for member in legacy_roster:
		if String(member.get("source_id", "")) == "starting_writ":
			_append_unique_id(initial_ids, String(member.get("member_id", "")))

	for generated_id in _string_array(
		defaults.get("campaign_cast", {}).get("initial_raider_ids", [])
	):
		if initial_ids.size() >= CampaignCastGeneratorScript.INITIAL_SIZE:
			break

		if selected_ids.has(generated_id):
			_append_unique_id(initial_ids, generated_id)

	for raider_id in selected_ids:
		if initial_ids.size() >= CampaignCastGeneratorScript.INITIAL_SIZE:
			break
		_append_unique_id(initial_ids, raider_id)

	if initial_ids.size() > CampaignCastGeneratorScript.INITIAL_SIZE:
		initial_ids = initial_ids.slice(0, CampaignCastGeneratorScript.INITIAL_SIZE)

	var future_ids: Array[String] = []

	for raider_id in selected_ids:
		if not initial_ids.has(raider_id):
			future_ids.append(raider_id)

	var active_ids := _string_array(
		migrated.get("raid_plan", {}).get("active_member_ids", [])
	)
	var states: Dictionary = {}
	var fallback_definitions: Dictionary = {}
	var missing_definition_ids: Array[String] = []

	for raider_id in selected_ids:
		var legacy_member: Dictionary = legacy_by_id.get(raider_id, {})
		var definition := RaiderCatalogScript.get_definition(raider_id)

		if definition.is_empty():
			definition = MasterRaiderDefinitionScript.fallback(raider_id, legacy_member)
			fallback_definitions[raider_id] = definition
			missing_definition_ids.append(raider_id)

		var is_legacy_member := not legacy_member.is_empty()
		var is_initial := initial_ids.has(raider_id)
		var recruitment: Dictionary = definition.get("recruitment", {})
		var state := CampaignRaiderStateScript.create(
			raider_id,
			String(
				legacy_member.get("unit_class", definition.get("default_class", "Mage"))
			),
			is_legacy_member or is_initial,
			active_ids.has(raider_id),
			String(
				legacy_member.get(
					"source_id",
					recruitment.get("source_hint", "starting_writ" if is_initial else "unrecruited")
				)
			)
		)

		if is_legacy_member:
			state["advanced_class_id"] = String(legacy_member.get("advanced_class_id", ""))
			state["specialization_id"] = String(legacy_member.get("specialization_id", ""))
			state["debug_member"] = bool(legacy_member.get("debug_member", false))

		states[raider_id] = CampaignRaiderStateScript.sanitize(
			state, raider_id, String(definition.get("default_class", "Mage"))
		)

	var warnings := _string_array(
		defaults.get("campaign_cast", {}).get("generation_warnings", [])
	)

	if selected_ids.size() != CampaignCastGeneratorScript.CAST_SIZE:
		warnings.append(
			"Migrated cast contains %d raiders instead of %d so no legacy raider was discarded."
			% [selected_ids.size(), CampaignCastGeneratorScript.CAST_SIZE]
		)

	migrated["campaign_cast"] = {
		"catalog_version": RaiderCatalogScript.get_catalog_version(),
		"selected_raider_ids": selected_ids,
		"initial_raider_ids": initial_ids,
		"future_raider_ids": future_ids,
		"generation_warnings": warnings,
	}
	migrated["raider_states"] = states
	migrated["fallback_raider_definitions"] = fallback_definitions
	migrated["data_diagnostics"] = {
		"migrated_from_schema": source_version,
		"migrated_raider_ids": legacy_by_id.keys(),
		"missing_definition_ids": missing_definition_ids,
	}
	return true


func _sanitize_layered_raider_data(
	migrated: Dictionary, defaults: Dictionary, source_version: int
) -> void:
	var cast_value: Variant = migrated.get("campaign_cast", {})
	var cast: Dictionary = Dictionary(cast_value).duplicate(true) if cast_value is Dictionary else {}
	var selected_ids := _unique_string_array(cast.get("selected_raider_ids", []))
	var active_ids := _unique_string_array(
		migrated.get("raid_plan", {}).get("active_member_ids", [])
	)

	for active_id in active_ids:
		_append_unique_id(selected_ids, active_id)

	for generated_id in _string_array(
		defaults.get("campaign_cast", {}).get("selected_raider_ids", [])
	):
		if selected_ids.size() >= CampaignCastGeneratorScript.CAST_SIZE:
			break
		_append_unique_id(selected_ids, generated_id)

	var initial_ids := _unique_string_array(cast.get("initial_raider_ids", []))
	initial_ids = _only_selected_ids(initial_ids, selected_ids)

	for generated_id in _string_array(
		defaults.get("campaign_cast", {}).get("initial_raider_ids", [])
	):
		if initial_ids.size() >= CampaignCastGeneratorScript.INITIAL_SIZE:
			break

		if selected_ids.has(generated_id):
			_append_unique_id(initial_ids, generated_id)

	for raider_id in selected_ids:
		if initial_ids.size() >= CampaignCastGeneratorScript.INITIAL_SIZE:
			break
		_append_unique_id(initial_ids, raider_id)

	if initial_ids.size() > CampaignCastGeneratorScript.INITIAL_SIZE:
		initial_ids = initial_ids.slice(0, CampaignCastGeneratorScript.INITIAL_SIZE)

	var stored_future := _only_selected_ids(
		_unique_string_array(cast.get("future_raider_ids", [])), selected_ids
	)
	var future_ids: Array[String] = []

	for raider_id in stored_future:
		if not initial_ids.has(raider_id):
			_append_unique_id(future_ids, raider_id)

	for raider_id in selected_ids:
		if not initial_ids.has(raider_id):
			_append_unique_id(future_ids, raider_id)

	var source_states_value: Variant = migrated.get("raider_states", {})
	var source_states: Dictionary = (
		Dictionary(source_states_value) if source_states_value is Dictionary else {}
	)
	var fallback_value: Variant = migrated.get("fallback_raider_definitions", {})
	var stored_fallbacks: Dictionary = (
		Dictionary(fallback_value).duplicate(true) if fallback_value is Dictionary else {}
	)
	var sanitized_fallbacks: Dictionary = {}
	var states: Dictionary = {}
	var missing_definition_ids: Array[String] = []

	for raider_id in selected_ids:
		var definition := RaiderCatalogScript.get_definition(raider_id)

		if definition.is_empty():
			var fallback_source: Dictionary = {}

			if stored_fallbacks.get(raider_id) is Dictionary:
				fallback_source = Dictionary(stored_fallbacks[raider_id])

			definition = MasterRaiderDefinitionScript.fallback(raider_id, fallback_source)
			sanitized_fallbacks[raider_id] = definition
			missing_definition_ids.append(raider_id)

		var state_source: Dictionary = {}

		if source_states.get(raider_id) is Dictionary:
			state_source = Dictionary(source_states[raider_id])
		else:
			var is_initial := initial_ids.has(raider_id)
			state_source = CampaignRaiderStateScript.create(
				raider_id,
				String(definition.get("default_class", "Mage")),
				is_initial,
				active_ids.has(raider_id),
				"starting_writ" if is_initial else "unrecruited"
			)

		var state := CampaignRaiderStateScript.sanitize(
			state_source, raider_id, String(definition.get("default_class", "Mage"))
		)

		if initial_ids.has(raider_id) or active_ids.has(raider_id):
			state["recruited"] = true

		states[raider_id] = state

	if active_ids.is_empty():
		active_ids = initial_ids.duplicate()

	var valid_active_ids: Array[String] = []

	for raider_id in active_ids:
		if selected_ids.has(raider_id) and states.has(raider_id):
			_append_unique_id(valid_active_ids, raider_id)

	migrated["raid_plan"]["active_member_ids"] = valid_active_ids
	var warnings := _unique_string_array(cast.get("generation_warnings", []))

	if selected_ids.size() != CampaignCastGeneratorScript.CAST_SIZE:
		warnings.append(
			"Stored cast contains %d raiders instead of %d."
			% [selected_ids.size(), CampaignCastGeneratorScript.CAST_SIZE]
		)

	migrated["campaign_cast"] = {
		"catalog_version": RaiderCatalogScript.get_catalog_version(),
		"selected_raider_ids": selected_ids,
		"initial_raider_ids": initial_ids,
		"future_raider_ids": future_ids,
		"generation_warnings": warnings,
	}
	migrated["raider_states"] = states
	migrated["fallback_raider_definitions"] = sanitized_fallbacks
	var diagnostics_value: Variant = migrated.get("data_diagnostics", {})
	var diagnostics: Dictionary = (
		Dictionary(diagnostics_value).duplicate(true) if diagnostics_value is Dictionary else {}
	)
	diagnostics["migrated_from_schema"] = int(
		diagnostics.get("migrated_from_schema", source_version)
	)
	diagnostics["migrated_raider_ids"] = _unique_string_array(
		diagnostics.get("migrated_raider_ids", [])
	)
	diagnostics["missing_definition_ids"] = missing_definition_ids
	migrated["data_diagnostics"] = diagnostics


func _normalize_attempt_history(source: Variant) -> Dictionary:
	var normalized: Dictionary = {}

	if not source is Dictionary:
		return normalized

	for encounter_id_value in (source as Dictionary).keys():
		var encounter_id := String(encounter_id_value)
		var history_value: Variant = (source as Dictionary).get(encounter_id_value, [])

		if not history_value is Array:
			continue

		var sanitized: Array[Dictionary] = []

		for summary_value in (history_value as Array):
			if summary_value is Dictionary:
				sanitized.append(Dictionary(summary_value).duplicate(true))

		while sanitized.size() > ATTEMPT_HISTORY_LIMIT:
			sanitized.pop_front()

		normalized[encounter_id] = sanitized

	return normalized


func _ensure_formation() -> void:
	if not campaign.has("raid_plan"):
		return

	var raid_plan: Dictionary = campaign["raid_plan"]
	var formation_value: Variant = raid_plan.get("formation", {})
	var formation_source: Dictionary = (
		Dictionary(formation_value) if formation_value is Dictionary else {}
	)
	raid_plan["formation"] = _sanitize_formation_for_active(formation_source)

	if not raid_plan.get("saved_formations") is Dictionary:
		raid_plan["saved_formations"] = {}

	raid_plan.erase("formations")
	campaign["raid_plan"] = raid_plan


func _build_default_formation() -> Dictionary:
	return _build_default_formation_for_ids(get_active_member_ids(), get_roster_members())


func _sanitize_formation_for_active(source: Dictionary) -> Dictionary:
	var default_formation := _build_default_formation()
	var placements: Dictionary = default_formation["placements"]
	var source_placements_value: Variant = source.get("placements", {})
	var source_placements: Dictionary = (
		Dictionary(source_placements_value) if source_placements_value is Dictionary else {}
	)

	for member_id in get_active_member_ids():
		var placement_value: Variant = source_placements.get(member_id)

		if not placement_value is Dictionary:
			continue

		var placement: Dictionary = placement_value
		var region := String(placement.get("region", ""))
		var range_name := String(placement.get("range", ""))

		if (
			RaidPlanValidatorScript.VALID_REGIONS.has(region)
			and RaidPlanValidatorScript.VALID_RANGES.has(range_name)
		):
			placements[member_id] = {"region": region, "range": range_name}

	var preset_name := String(source.get("preset_name", "Custom"))

	if preset_name == "Balanced Writ":
		preset_name = DEFAULT_FORMATION_NAME

	return {"preset_name": preset_name, "placements": placements}


func _formation_with_replaced_member(
	source: Dictionary, outgoing_member_id: String, incoming_member_id: String
) -> Dictionary:
	var result := source.duplicate(true)
	var placements_value: Variant = result.get("placements", {})
	var placements: Dictionary = (
		Dictionary(placements_value) if placements_value is Dictionary else {}
	)

	if placements.has(outgoing_member_id):
		var outgoing_placement_value: Variant = placements[outgoing_member_id]

		if outgoing_placement_value is Dictionary:
			placements[incoming_member_id] = Dictionary(outgoing_placement_value).duplicate(true)

		placements.erase(outgoing_member_id)

	result["placements"] = placements
	return result


func _build_default_formation_for_ids(active_ids: Array[String], roster: Array) -> Dictionary:
	var roster_by_id: Dictionary = {}

	for member in roster:
		roster_by_id[String(member.get("member_id", ""))] = member

	var placements: Dictionary = {}
	var role_indices := {"tank": 0, "healer": 0, "dps": 0}
	var healer_regions := ["southwest", "southeast", "west", "east", "south"]
	var melee_regions := ["northwest", "northeast", "west", "east", "north", "south"]
	var ranged_regions := [
		"north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"
	]

	for member_id in active_ids:
		var member: Dictionary = roster_by_id.get(member_id, {})
		var role := String(member.get("role", "dps"))
		var unit_class := String(member.get("unit_class", "Mage"))
		var role_index := int(role_indices.get(role, 0))
		var region := "south"
		var range_name := "far"

		match role:
			"tank":
				region = ["south", "north"][role_index % 2]
				range_name = "close"
			"healer":
				region = String(healer_regions[role_index % healer_regions.size()])
				range_name = "mid"
			_:
				if unit_class == "Rogue":
					region = String(melee_regions[role_index % melee_regions.size()])
					range_name = "close"
				else:
					region = String(ranged_regions[role_index % ranged_regions.size()])
					range_name = "far"

		placements[member_id] = {"region": region, "range": range_name}
		role_indices[role] = role_index + 1

	return {"preset_name": DEFAULT_FORMATION_NAME, "placements": placements}


func _update_discoveries_from_attempt(summary: Dictionary) -> void:
	var encounter_id := String(summary.get("encounter_id", ""))
	var discoveries: Dictionary = campaign.get("discoveries", {})
	var encounter_discoveries: Dictionary = discoveries.get(
		encounter_id,
		{"ability_ids": [], "phase_ids": [], "phase_names": [], "reliable_failures": []}
	)

	for ability_id in summary.get("observed_ability_ids", []):
		_append_unique_value(encounter_discoveries["ability_ids"], ability_id)

	for phase_id in summary.get("observed_phase_ids", []):
		_append_unique_value(encounter_discoveries["phase_ids"], phase_id)

	for phase_name in summary.get("observed_phase_names", []):
		_append_unique_value(encounter_discoveries["phase_names"], phase_name)

	for failure in summary.get("reliable_failures", []):
		_append_unique_value(encounter_discoveries["reliable_failures"], failure)

	discoveries[encounter_id] = encounter_discoveries
	campaign["discoveries"] = discoveries


func _record_victory(encounter_id: String) -> void:
	var victories: Dictionary = campaign.get("victories", {})
	var new_count := int(victories.get(encounter_id, 0)) + 1
	victories[encounter_id] = new_count
	campaign["victories"] = victories
	var boss_resources: Dictionary = campaign.get("boss_resources", {})
	boss_resources[encounter_id] = int(boss_resources.get(encounter_id, 0)) + 1
	campaign["boss_resources"] = boss_resources
	var definition = GameState.get_encounter_definition(encounter_id)
	campaign["latest_victory"] = {
		"encounter_id": encounter_id,
		"display_name": encounter_id if definition == null else definition.display_name,
		"victory_count": new_count,
		"first_victory": new_count == 1,
		"reward_summary": "A boss resource was secured immediately for future advancement systems.",
		"recorded_unix_time": int(Time.get_unix_time_from_system())
	}


func _record_active_raider_combat_history(outcome: String) -> void:
	var states: Dictionary = campaign.get("raider_states", {})

	for raider_id in get_active_member_ids():
		var state_value: Variant = states.get(raider_id, {})

		if not state_value is Dictionary:
			continue

		var state: Dictionary = state_value
		var history_value: Variant = state.get("combat_history", {})
		var history: Dictionary = (
			Dictionary(history_value).duplicate(true) if history_value is Dictionary else {}
		)
		history["attempts"] = int(history.get("attempts", 0)) + 1

		if outcome == "victory":
			history["victories"] = int(history.get("victories", 0)) + 1
		else:
			history["defeats"] = int(history.get("defeats", 0)) + 1

		state["combat_history"] = history
		states[raider_id] = state

	campaign["raider_states"] = states


func _emit_attempt_notable_events(summary: Dictionary) -> void:
	var active_ids := get_active_member_ids()
	var attempt_id := String(summary.get("attempt_id", "attempt"))
	var encounter_id := String(summary.get("encounter_id", get_selected_encounter_id()))
	var outcome := String(summary.get("outcome", "wipe"))
	var deaths := _dictionary_array(summary.get("deaths", []))
	emit_notable_event(
		{
			"event_type": "boss_attempt_completed",
			"source_system": "combat_attempt",
			"participants": active_ids,
			"memory_category": "combat",
			"subject_key": "boss_attempt:%s" % encounter_id,
			"significance": 65 if outcome == "victory" else 50,
			"structured_data": {
				"attempt_id": attempt_id,
				"encounter_id": encounter_id,
				"outcome": outcome,
				"boss_progress_percent": float(summary.get("boss_progress_percent", 0.0)),
				"death_count": deaths.size(),
				"severe_wipe": outcome != "victory" and deaths.size() >= 10,
			},
			"prose_template_id": "boss_attempt_completed",
			"prose_parameters": {"encounter_id": encounter_id, "outcome": outcome},
		},
		false
	)

	if outcome == "victory":
		emit_notable_event(
			{
				"event_type": "boss_defeated",
				"source_system": "combat_attempt",
				"participants": active_ids,
				"memory_category": "combat",
				"subject_key": "boss_victory:%s" % encounter_id,
				"significance": 90 if get_victory_count(encounter_id) == 1 else 72,
				"is_milestone": get_victory_count(encounter_id) == 1,
				"structured_data": {
					"attempt_id": attempt_id,
					"encounter_id": encounter_id,
					"first_victory": get_victory_count(encounter_id) == 1,
				},
				"prose_template_id": "boss_defeated",
				"prose_parameters": {"encounter_id": encounter_id},
			},
			false
		)

	for interrupt_value in summary.get("successful_interrupts", []):
		if not interrupt_value is Dictionary:
			continue

		var interrupt: Dictionary = interrupt_value
		var interrupter_id := String(interrupt.get("member_id", ""))

		if interrupter_id.is_empty():
			continue

		emit_notable_event(
			{
				"event_type": "interrupt_succeeded",
				"source_system": "combat_attempt",
				"participants": [interrupter_id],
				"memory_category": "combat",
				"subject_key": "interrupt:%s:%s" % [
					encounter_id, String(interrupt.get("ability_id", "unknown"))
				],
				"significance": 62,
				"memory_strength": 0.4,
				"structured_data": interrupt.duplicate(true),
				"prose_template_id": "interrupt_succeeded",
			},
			false
		)

	for mechanic_value in summary.get("mechanic_outcomes", []):
		if not mechanic_value is Dictionary:
			continue

		var mechanic: Dictionary = mechanic_value
		var mechanic_participants := _string_array(mechanic.get("participant_ids", []))

		if mechanic_participants.is_empty():
			continue

		var succeeded := String(mechanic.get("outcome", "failed")) == "resolved"
		emit_notable_event(
			{
				"event_type": (
					"mechanic_successfully_resolved" if succeeded else "mechanic_failed"
				),
				"source_system": "combat_attempt",
				"participants": mechanic_participants,
				"memory_category": "combat",
				"subject_key": "mechanic:%s:%s" % [
					encounter_id, String(mechanic.get("ability_id", "unknown"))
				],
				"significance": 68 if succeeded else 64,
				"structured_data": mechanic.duplicate(true),
				"prose_template_id": (
					"mechanic_successfully_resolved" if succeeded else "mechanic_failed"
				),
			},
			false
		)

	for rescue_value in summary.get("exceptional_heals", []):
		if not rescue_value is Dictionary:
			continue

		var rescue: Dictionary = rescue_value
		var healer_id := String(rescue.get("healer_id", ""))
		var target_id := String(rescue.get("target_id", ""))

		if healer_id.is_empty() or target_id.is_empty() or healer_id == target_id:
			continue

		var rescue_data := rescue.duplicate(true)
		rescue_data["threshold_worthy"] = bool(rescue.get("rescue", false))
		rescue_data["relationship_deltas"] = {
			healer_id: {"affinity": 2, "trust": 1, "respect": 2},
			target_id: {"affinity": 4, "trust": 8, "respect": 4},
		}
		emit_notable_event(
			{
				"event_type": "exceptional_heal_or_rescue",
				"source_system": "combat_attempt",
				"participants": [healer_id, target_id],
				"personal_participants": [healer_id] if bool(rescue.get("rescue", false)) else [],
				"admission_reasons": ["meaningful_agency", "involved_specific_person"],
				"memory_category": "combat",
				"subject_key": "rescue:%s" % target_id,
				"significance": 74 if bool(rescue.get("rescue", false)) else 62,
				"structured_data": rescue_data,
				"prose_template_id": "exceptional_heal_or_rescue",
			},
			false
		)

	if deaths.size() <= 2:
		for death in deaths:
			var defeated_id := String(death.get("member_id", ""))

			if defeated_id.is_empty():
				continue

			emit_notable_event(
				{
					"event_type": "raider_defeated",
					"source_system": "combat_attempt",
					"participants": [defeated_id],
					"memory_category": "combat",
					"subject_key": "defeat:%s:%s" % [
						encounter_id, String(death.get("cause_ability_id", "unknown"))
					],
					"significance": 58,
					"structured_data": death.duplicate(true),
					"prose_template_id": "raider_defeated",
				},
				false
			)

	var death_ids: Array[String] = []

	for death in deaths:
		_append_unique_id(death_ids, String(death.get("member_id", "")))

	var living_ids: Array[String] = []

	for raider_id in active_ids:
		if not death_ids.has(raider_id):
			living_ids.append(raider_id)

	var last_survivor_id := ""

	if outcome == "victory" and living_ids.size() == 1:
		last_survivor_id = living_ids[0]
	elif outcome != "victory" and deaths.size() >= 3:
		var latest_death: Dictionary = deaths[0]

		for death in deaths:
			if float(death.get("time", 0.0)) > float(latest_death.get("time", 0.0)):
				latest_death = death

		last_survivor_id = String(latest_death.get("member_id", ""))

	if not last_survivor_id.is_empty():
		emit_notable_event(
			{
				"event_type": "last_survivor",
				"source_system": "combat_attempt",
				"participants": [last_survivor_id],
				"memory_category": "combat",
				"subject_key": "last_survivor:%s" % encounter_id,
				"significance": 88 if outcome == "victory" else 76,
				"memory_strength": 0.75,
				"structured_data": {
					"attempt_id": attempt_id,
					"encounter_id": encounter_id,
					"outcome": outcome,
				},
				"prose_template_id": "last_survivor",
			},
			false
		)


func _project_member(raider_id: String, state: Dictionary) -> Dictionary:
	return _project_member_from(_get_definition_with_fallback(raider_id), state)


func _project_member_from(definition: Dictionary, state: Dictionary) -> Dictionary:
	var raider_id := String(state.get("raider_id", definition.get("raider_id", "")))
	return {
		# Camp V1 and combat consumers retain these aliases while stable IDs remain authoritative.
		"member_id": raider_id,
		"raider_id": raider_id,
		"display_name": String(definition.get("display_name", "Unnamed Raider")),
		"unit_class": String(
			state.get("current_class", definition.get("default_class", "Mage"))
		),
		"role": String(definition.get("default_role", "dps")),
		"attributes": Array(definition.get("personality_tags", [])).duplicate(),
		"personality_tags": Array(definition.get("personality_tags", [])).duplicate(),
		"personality_description": String(definition.get("personality_description", "")),
		"description": String(definition.get("biography", "")),
		"biography": String(definition.get("biography", "")),
		"speech_profile_id": String(definition.get("speech_profile_id", "writ_default")),
		"visual_assets": Dictionary(definition.get("visual_assets", {})).duplicate(true),
		"preferred_activity_tags": Array(
			definition.get("preferred_activity_tags", [])
		).duplicate(),
		"permitted_class_paths": Array(definition.get("permitted_class_paths", [])).duplicate(),
		"lore_knowledge_tags": Array(definition.get("lore_knowledge_tags", [])).duplicate(),
		"authored_connection_ids": Array(
			definition.get("authored_connection_ids", [])
		).duplicate(),
		"recruitment_metadata": Dictionary(definition.get("recruitment", {})).duplicate(true),
		"recruit_order": int(definition.get("catalog_order", 0)),
		"advanced_class_id": String(state.get("advanced_class_id", "")),
		"specialization_id": String(state.get("specialization_id", "")),
		"source_id": String(state.get("recruitment_source", "unknown")),
		"room_assignment_id": String(state.get("room_assignment_id", "")),
		"combat_history": Dictionary(state.get("combat_history", {})).duplicate(true),
		"permanent_milestone_ids": Array(
			state.get("permanent_milestone_ids", [])
		).duplicate(),
		"descriptive_title": String(state.get("descriptive_title", "")),
		"debug_member": bool(state.get("debug_member", false)),
	}


func _get_definition_with_fallback(raider_id: String) -> Dictionary:
	var definition := RaiderCatalogScript.get_definition(raider_id)

	if not definition.is_empty():
		return definition

	var fallback_value: Variant = campaign.get("fallback_raider_definitions", {}).get(
		raider_id, {}
	)
	var fallback_source: Dictionary = (
		Dictionary(fallback_value) if fallback_value is Dictionary else {}
	)
	definition = MasterRaiderDefinitionScript.fallback(raider_id, fallback_source)

	if not missing_definition_warnings_emitted.has(raider_id):
		missing_definition_warnings_emitted[raider_id] = true
		push_warning(
			"Missing master raider definition for stable ID '%s'; using saved fallback identity."
			% raider_id
		)

	return definition


func _get_member_quarters_state() -> Dictionary:
	var value: Variant = campaign.get("member_quarters_state", {})
	if not value is Dictionary:
		campaign["member_quarters_state"] = {
			"profile_revisions": {},
			"seen_profile_revisions": {},
		}
	return campaign["member_quarters_state"]


func _mark_profile_updates(participant_ids_value: Variant) -> void:
	var quarters := _get_member_quarters_state()
	var revisions: Dictionary = quarters.get("profile_revisions", {})
	for raider_id in _unique_string_array(participant_ids_value):
		if not get_selected_cast_ids().has(raider_id):
			continue
		revisions[raider_id] = int(revisions.get(raider_id, 0)) + 1
	quarters["profile_revisions"] = revisions
	campaign["member_quarters_state"] = quarters


func _sanitize_member_quarters_state(
	source: Variant, valid_raider_ids: Array[String], campaign_source: Dictionary
) -> Dictionary:
	var raw: Dictionary = Dictionary(source) if source is Dictionary else {}
	var revisions: Dictionary = {}
	var seen: Dictionary = {}
	var raw_revisions: Dictionary = (
		Dictionary(raw.get("profile_revisions", {}))
		if raw.get("profile_revisions", {}) is Dictionary
		else {}
	)
	var raw_seen: Dictionary = (
		Dictionary(raw.get("seen_profile_revisions", {}))
		if raw.get("seen_profile_revisions", {}) is Dictionary
		else {}
	)

	for raider_id in valid_raider_ids:
		var revision := maxi(int(raw_revisions.get(raider_id, 0)), 0)
		if revision > 0:
			revisions[raider_id] = revision
		var seen_revision := clampi(int(raw_seen.get(raider_id, 0)), 0, revision)
		if seen_revision > 0:
			seen[raider_id] = seen_revision

	if revisions.is_empty():
		for event_value in campaign_source.get("notable_event_records", []):
			if not event_value is Dictionary:
				continue
			for raider_id in _unique_string_array(Dictionary(event_value).get("participants", [])):
				if valid_raider_ids.has(raider_id):
					revisions[raider_id] = int(revisions.get(raider_id, 0)) + 1

	return {
		"profile_revisions": revisions,
		"seen_profile_revisions": seen,
	}


func _ensure_valid_room_assignments(target_campaign: Dictionary) -> void:
	var states_value: Variant = target_campaign.get("raider_states", {})
	if not states_value is Dictionary:
		return
	var states: Dictionary = states_value
	var selected_ids := _string_array(
		target_campaign.get("campaign_cast", {}).get("selected_raider_ids", [])
	)
	var occupants_by_room: Dictionary = {}
	var needs_assignment: Array[String] = []

	for raider_id in selected_ids:
		var state_value: Variant = states.get(raider_id, {})
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		if not bool(state.get("recruited", false)):
			state["room_assignment_id"] = ""
			states[raider_id] = state
			continue
		var room_id := String(state.get("room_assignment_id", ""))
		var occupants: Array = occupants_by_room.get(room_id, [])
		if not _is_valid_room_id(room_id) or occupants.size() >= QUARTERS_ROOM_CAPACITY:
			state["room_assignment_id"] = ""
			states[raider_id] = state
			needs_assignment.append(raider_id)
			continue
		occupants.append(raider_id)
		occupants_by_room[room_id] = occupants

	for raider_id in needs_assignment:
		for room_number in range(1, QUARTERS_ROOM_COUNT + 1):
			var room_id := _room_id(room_number)
			var occupants: Array = occupants_by_room.get(room_id, [])
			if occupants.size() >= QUARTERS_ROOM_CAPACITY:
				continue
			var state: Dictionary = Dictionary(states[raider_id])
			state["room_assignment_id"] = room_id
			states[raider_id] = state
			occupants.append(raider_id)
			occupants_by_room[room_id] = occupants
			break

	target_campaign["raider_states"] = states


func _assign_room_automatically_internal(raider_id: String) -> bool:
	var state_value: Variant = campaign.get("raider_states", {}).get(raider_id, {})
	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return false
	var state: Dictionary = state_value
	var current_room := String(state.get("room_assignment_id", ""))
	var occupants_by_room := _room_occupants_by_id(campaign)
	if _is_valid_room_id(current_room):
		var current_occupants: Array = occupants_by_room.get(current_room, [])
		if current_occupants.size() <= QUARTERS_ROOM_CAPACITY:
			return true

	for room_number in range(1, QUARTERS_ROOM_COUNT + 1):
		var room_id := _room_id(room_number)
		if Array(occupants_by_room.get(room_id, [])).size() >= QUARTERS_ROOM_CAPACITY:
			continue
		state["room_assignment_id"] = room_id
		campaign["raider_states"][raider_id] = state
		return true
	return false


func _room_occupants_by_id(target_campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var states_value: Variant = target_campaign.get("raider_states", {})
	if not states_value is Dictionary:
		return result
	var states: Dictionary = states_value
	for raider_id_value in states.keys():
		var state_value: Variant = states[raider_id_value]
		if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
			continue
		var room_id := String(state_value.get("room_assignment_id", ""))
		if not _is_valid_room_id(room_id):
			continue
		var occupants: Array = result.get(room_id, [])
		occupants.append(String(raider_id_value))
		result[room_id] = occupants
	return result


func _is_valid_room_id(room_assignment_id: String) -> bool:
	if not room_assignment_id.begins_with("quarters_"):
		return false
	var room_number := int(room_assignment_id.get_slice("_", 1))
	return room_number >= 1 and room_number <= QUARTERS_ROOM_COUNT


func _room_id(room_number: int) -> String:
	return "quarters_%02d" % clampi(room_number, 1, QUARTERS_ROOM_COUNT)


func _sync_active_state_flags() -> void:
	var states_value: Variant = campaign.get("raider_states", {})

	if not states_value is Dictionary:
		return

	var states: Dictionary = states_value
	var active_ids := get_active_member_ids()

	for raider_id in states.keys():
		var state_value: Variant = states[raider_id]

		if not state_value is Dictionary:
			continue

		var state: Dictionary = state_value
		state["active"] = active_ids.has(String(raider_id))

		if bool(state["active"]):
			state["recruited"] = true

		states[raider_id] = state

	campaign["raider_states"] = states


func _generate_campaign_seed() -> int:
	return maxi(
		int(Time.get_unix_time_from_system() * 1000.0) + int(Time.get_ticks_msec()), 1
	)


func _print_campaign_cast_report_if_debug() -> void:
	if OS.is_debug_build():
		print_campaign_cast_report()


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in value:
			result.append(String(entry))

	return result


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if value is Array:
		for entry in value:
			if entry is Dictionary:
				result.append(Dictionary(entry).duplicate(true))

	return result


func _unique_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	for entry in _string_array(value):
		_append_unique_id(result, entry)

	return result


func _only_selected_ids(ids: Array[String], selected_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []

	for raider_id in ids:
		if selected_ids.has(raider_id):
			_append_unique_id(result, raider_id)

	return result


func _append_unique_id(target: Array[String], raider_id: String) -> void:
	raider_id = raider_id.strip_edges()

	if not raider_id.is_empty() and not target.has(raider_id):
		target.append(raider_id)


func _augment_visit_reactions(context_type: String, magnitude: int) -> void:
	var context: Dictionary = campaign.get("visit_context", {})
	context["type"] = context_type
	context["reaction_budget"] = (
		int(context.get("reaction_budget", 0)) + clampi(magnitude * 2, 3, 24)
	)
	context["details"] = {"magnitude": magnitude}
	campaign["visit_context"] = context


func _append_unique_value(target: Array, value: Variant) -> void:
	if not target.has(value):
		target.append(value)


func _get_camp_conversation_store() -> Dictionary:
	var value: Variant = campaign.get("camp_conversation_state", {})
	if not value is Dictionary:
		campaign["camp_conversation_state"] = CampConversationStateScript.create_store()
	return campaign["camp_conversation_state"]
