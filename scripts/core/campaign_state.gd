extends Node

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
const CampContentCatalogScript := preload("res://scripts/core/camp_content_catalog.gd")
const RaidPlanValidatorScript := preload("res://scripts/core/raid_plan_validator.gd")
const CampaignPersistenceServiceScript := preload(
	"res://scripts/core/campaign_persistence_service.gd"
)
const CampaignRosterServiceScript := preload("res://scripts/core/campaign_roster_service.gd")
const CampaignRaidPlanServiceScript := preload(
	"res://scripts/core/campaign_raid_plan_service.gd"
)
const CampaignProgressionServiceScript := preload(
	"res://scripts/core/campaign_progression_service.gd"
)
const CampaignRewardServiceScript := preload(
	"res://scripts/core/campaign_reward_service.gd"
)
const CampaignSocialMemoryServiceScript := preload(
	"res://scripts/core/campaign_social_memory_service.gd"
)

signal state_changed
signal raid_plan_changed
signal roster_changed
signal attempt_recorded(summary: Dictionary)
signal visit_context_changed(context: Dictionary)
signal notable_event_recorded(event: Dictionary)
signal memory_promoted(event: Dictionary)
signal relationship_threshold_reached(event: Dictionary)

const SAVE_PATH := "user://raid_leader_saves/autosave.json"
const SCHEMA_VERSION := 11
const MIGRATABLE_SCHEMA_VERSION := 10
var ACTIVE_RAID_SIZE: int
var ATTEMPT_HISTORY_LIMIT: int
const FIRST_REGION_ID := "beast_crucible"
const DEFAULT_FORMATION_NAME := "Default"
var QUARTERS_ROOM_COUNT: int
var QUARTERS_ROOM_CAPACITY: int

var _campaign: Dictionary = {}
var _persistence_service = CampaignPersistenceServiceScript.new()
var _roster_service = CampaignRosterServiceScript.new()
var _raid_plan_service = CampaignRaidPlanServiceScript.new()
var _progression_service = CampaignProgressionServiceScript.new()
var _reward_service = CampaignRewardServiceScript.new()
var _social_memory_service = CampaignSocialMemoryServiceScript.new()


func _enter_tree() -> void:
	var tuning := TuningCatalogAccess.get_raid_campaign()
	ACTIVE_RAID_SIZE = tuning.maximum_raid_size
	ATTEMPT_HISTORY_LIMIT = tuning.attempt_history_limit
	QUARTERS_ROOM_COUNT = tuning.quarters_room_count
	QUARTERS_ROOM_CAPACITY = tuning.quarters_room_capacity


func _ready() -> void:
	reset_campaign(false)


func reset_campaign(emit_change: bool = true, seed_override: int = 0) -> void:
	_campaign = _create_default_campaign(seed_override)
	_print_campaign_cast_report_if_debug()

	if emit_change:
		roster_changed.emit()
		raid_plan_changed.emit()
		state_changed.emit()


func load_campaign(path: String = SAVE_PATH) -> bool:
	var payload: Dictionary = _persistence_service.read_payload(path)
	if not bool(payload.get("ok", false)):
		push_warning("Campaign save could not be loaded (%s): %s" % [
			String(payload.get("error", "invalid")), path
		])
		return false
	var source: Dictionary = payload.get("campaign", {})
	if not _is_current_schema_compatible(source):
		push_warning(
			"Campaign schema is incompatible; starting a new campaign and preserving: " + path
		)
		reset_campaign(true)
		return false
	if int(source.get("schema_version", -1)) == MIGRATABLE_SCHEMA_VERSION:
		source = _migrate_version_10_campaign(source)
	_campaign = _sanitize_current_campaign(source)
	CampV2EventSystemScript.advance_lifecycle(
		_campaign, int(Time.get_unix_time_from_system())
	)
	_print_campaign_cast_report_if_debug()
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func write_campaign(path: String, metadata: Dictionary = {}) -> bool:
	_capture_camp_positions_for_save()
	var persistent_snapshot := _campaign.duplicate(true)
	# Current-visit reactions are scene texture, not durable _campaign truth.
	persistent_snapshot.erase("visit_context")
	# Runtime scene state is owned by CampPopulationController and must never enter a save.
	persistent_snapshot.erase("runtime_raider_states")
	persistent_snapshot.erase("runtime_state")
	# Authored identity stays in the catalog; saves retain only stable-ID _campaign state.
	persistent_snapshot.erase("roster")
	var written: bool = _persistence_service.write_payload(path, persistent_snapshot, metadata)
	if not written:
		push_warning("Campaign save could not be written: " + path)
	return written


func get_campaign_snapshot() -> Dictionary:
	return _campaign.duplicate(true)


func is_campaign_snapshot_compatible(source: Dictionary) -> bool:
	return _is_current_schema_compatible(source)


func debug_replace_raider_states(states: Dictionary) -> bool:
	if not GameState.is_raid_test_mode():
		return false
	_campaign["raider_states"] = states.duplicate(true)
	_ensure_valid_room_assignments(_campaign)
	_sync_active_state_flags()
	roster_changed.emit()
	state_changed.emit()
	return true


func _capture_camp_positions_for_save() -> void:
	for controller in get_tree().get_nodes_in_group("camp_population_controller"):
		if (
			controller != null
			and is_instance_valid(controller)
			and controller.has_method("persist_current_positions")
		):
			controller.call("persist_current_positions")


func get_save_context() -> Dictionary:
	var raid_plan: Dictionary = _campaign.get("raid_plan", {})
	var encounter_id := get_selected_encounter_id()
	var definition = GameState.get_encounter_definition(encounter_id)
	var victory_total := 0

	for victory_count in _campaign.get("victories", {}).values():
		victory_total += int(victory_count)

	return {
		"region_id": String(raid_plan.get("region_id", FIRST_REGION_ID)),
		"region_name": "Beast Crucible",
		"encounter_id": encounter_id,
		"encounter_name": encounter_id if definition == null else definition.display_name,
		"victory_count": victory_total,
		"latest_outcome": String(_campaign.get("latest_attempt", {}).get("outcome", "")),
	}


func get_available_encounter_ids() -> Array[String]:
	return GameState.get_normal_encounter_ids()


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
	return _raid_plan_service.get_plan(_campaign)


func get_selected_encounter_id() -> String:
	return _raid_plan_service.get_encounter(_campaign, GameState.ENCOUNTER_OGRE)


func set_selected_encounter(encounter_id: String) -> bool:
	if not get_available_encounter_ids().has(encounter_id):
		return false

	_raid_plan_service.set_encounter(_campaign, encounter_id)
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func get_roster_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var states: Dictionary = _campaign.get("raider_states", {})

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
	var state_value: Variant = _campaign.get("raider_states", {}).get(member_id, {})

	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return {}

	return _project_member(member_id, Dictionary(state_value))


func set_raider_roles(raider_id: String, roles: Array[String]) -> bool:
	var state_value: Variant = _campaign.get("raider_states", {}).get(raider_id, {})

	if not state_value is Dictionary:
		return false

	var normalized_roles := _unique_string_array(roles)

	if normalized_roles.is_empty():
		return false

	var state: Dictionary = Dictionary(state_value)
	state["assigned_roles"] = normalized_roles
	_campaign["raider_states"][raider_id] = state
	roster_changed.emit()
	state_changed.emit()
	return true


func get_selected_cast_ids() -> Array[String]:
	return _string_array(_campaign.get("campaign_cast", {}).get("selected_raider_ids", []))


func get_initial_cast_ids() -> Array[String]:
	return _string_array(_campaign.get("campaign_cast", {}).get("initial_raider_ids", []))


func get_future_recruit_ids() -> Array[String]:
	return _string_array(_campaign.get("campaign_cast", {}).get("future_raider_ids", []))


func get_raider_campaign_state(raider_id: String) -> Dictionary:
	var state_value: Variant = _campaign.get("raider_states", {}).get(raider_id, {})
	return Dictionary(state_value).duplicate(true) if state_value is Dictionary else {}


func get_raider_camp_position(raider_id: String) -> Dictionary:
	var state := get_raider_campaign_state(raider_id)
	var value: Variant = state.get("last_camp_position", [])

	if value is Array and value.size() >= 2:
		return {
			"valid": true,
			"position": Vector2(float(value[0]), float(value[1])),
		}

	return {"valid": false, "position": Vector2.ZERO}


func set_raider_camp_position(raider_id: String, position: Vector2) -> bool:
	var states_value: Variant = _campaign.get("raider_states", {})
	if not states_value is Dictionary:
		return false

	var states: Dictionary = states_value
	var state_value: Variant = states.get(raider_id, {})
	if not state_value is Dictionary:
		return false

	if position.x != position.x or position.y != position.y:
		return clear_raider_camp_position(raider_id)

	var state: Dictionary = Dictionary(state_value).duplicate(true)
	state["last_camp_position"] = [position.x, position.y]
	states[raider_id] = state
	_campaign["raider_states"] = states
	return true


func clear_raider_camp_position(raider_id: String) -> bool:
	var states_value: Variant = _campaign.get("raider_states", {})
	if not states_value is Dictionary:
		return false

	var states: Dictionary = states_value
	var state_value: Variant = states.get(raider_id, {})
	if not state_value is Dictionary:
		return false

	var state: Dictionary = Dictionary(state_value).duplicate(true)
	state["last_camp_position"] = []
	states[raider_id] = state
	_campaign["raider_states"] = states
	return true


func get_member_label(member_id: String) -> String:
	var member := get_member(member_id)
	return member_id if member.is_empty() else format_member_label(member)


func format_member_label(member: Dictionary) -> String:
	return CampaignRosterServiceScript.format_member_label(member)


func get_active_member_ids() -> Array[String]:
	var result: Array[String] = []

	for member_id in _campaign.get("raid_plan", {}).get("active_member_ids", []):
		result.append(String(member_id))

	return result


func add_active_member(member_id: String) -> bool:
	if not _roster_service.add_active_member(
		_campaign, member_id, _string_array(get_roster_by_id().keys()), ACTIVE_RAID_SIZE
	):
		return false
	_commit_active_roster_change(
		member_id, "raider_added_to_active_roster", 58
	)
	return true


func remove_active_member(member_id: String) -> bool:
	if not _roster_service.remove_active_member(_campaign, member_id):
		return false
	_commit_active_roster_change(member_id, "raider_moved_to_reserve", 58)
	return true


func _commit_active_roster_change(
	member_id: String, event_type: String, significance: int
) -> void:
	_sync_active_state_flags()
	_ensure_formation()
	var raid_plan: Dictionary = _campaign.get("raid_plan", {})
	var saved_formations: Dictionary = Dictionary(
		raid_plan.get("saved_formations", {})
	).duplicate(true)
	for formation_name in saved_formations:
		if saved_formations[formation_name] is Dictionary:
			saved_formations[formation_name] = _sanitize_formation_for_active(
				Dictionary(saved_formations[formation_name])
			)
	raid_plan["saved_formations"] = saved_formations
	_campaign["raid_plan"] = raid_plan
	emit_notable_event({
		"event_type": event_type,
		"source_system": "roster",
		"participants": [member_id],
		"memory_category": "roster",
		"subject_key": "roster_status",
		"significance": significance,
	}, false)
	_augment_visit_reactions("roster_change", 1)
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()


func get_active_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var roster_by_id := get_roster_by_id()

	for member_id in get_active_member_ids():
		if roster_by_id.has(member_id):
			result.append(Dictionary(roster_by_id[member_id]).duplicate(true))

	return result


func get_active_members_for_roster() -> Array[Dictionary]:
	var result := get_active_members()
	var raid_plan: Dictionary = _campaign.get("raid_plan", {})

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
	_campaign["raid_plan"]["active_member_ids"] = active_ids
	_sync_active_state_flags()

	var raid_plan: Dictionary = _campaign["raid_plan"]
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
	_campaign["raid_plan"] = raid_plan

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
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func reorder_active_member(
	moving_member_id: String, target_member_id: String, place_after_target: bool = false
) -> bool:
	var raid_plan: Dictionary = _campaign.get("raid_plan", {})
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
	_campaign["raid_plan"]["active_member_ids"] = active_ids
	_sync_active_state_flags()
	_campaign["raid_plan"]["roster_sort_mode"] = "custom"
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func get_formation(_encounter_id: String = "") -> Dictionary:
	_ensure_formation()
	return Dictionary(_campaign["raid_plan"]["formation"]).duplicate(true)


func set_member_placement(
	member_id: String,
	region: String,
	range_name: String,
	_encounter_id: String = "",
	preserve_preset_name: bool = false
) -> bool:
	if not RaidPlanValidatorScript.VALID_REGIONS.has(region):
		return false

	if not RaidPlanValidatorScript.VALID_RANGES.has(range_name):
		return false

	if not get_active_member_ids().has(member_id):
		return false

	_ensure_formation()
	_campaign["raid_plan"]["formation"]["placements"][member_id] = {
		"region": region, "range": range_name
	}
	if not preserve_preset_name:
		_campaign["raid_plan"]["formation"]["preset_name"] = "Custom"
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func move_formation_mini_region(
	source_region: String,
	source_range: String,
	destination_region: String,
	destination_range: String,
	preserve_preset_name: bool = false
) -> bool:
	if not RaidPlanValidatorScript.VALID_REGIONS.has(source_region):
		return false

	if not RaidPlanValidatorScript.VALID_RANGES.has(source_range):
		return false

	if not RaidPlanValidatorScript.VALID_REGIONS.has(destination_region):
		return false

	if not RaidPlanValidatorScript.VALID_RANGES.has(destination_range):
		return false

	if source_region == destination_region and source_range == destination_range:
		return false

	var raid_plan_value: Variant = _campaign.get("raid_plan", {})
	if not raid_plan_value is Dictionary:
		return false

	var raid_plan: Dictionary = raid_plan_value
	var formation_value: Variant = raid_plan.get("formation", {})
	if not formation_value is Dictionary:
		return false

	var formation: Dictionary = formation_value
	var placements_value: Variant = formation.get("placements", {})
	if not placements_value is Dictionary:
		return false

	var placements: Dictionary = placements_value
	var source_member_ids: Array[String] = []
	var source_key := source_region + ":" + source_range

	for member_id in get_active_member_ids():
		var placement_value: Variant = placements.get(member_id, {})
		if not placement_value is Dictionary:
			continue

		var placement: Dictionary = placement_value
		var placement_key := "%s:%s" % [
			String(placement.get("region", "")), String(placement.get("range", ""))
		]

		if placement_key == source_key:
			source_member_ids.append(member_id)

	if source_member_ids.is_empty():
		return false

	var next_formation := formation.duplicate(true)
	var next_placements := placements.duplicate(true)

	for member_id in source_member_ids:
		next_placements[member_id] = {
			"region": destination_region,
			"range": destination_range,
		}

	next_formation["placements"] = next_placements
	if not preserve_preset_name:
		next_formation["preset_name"] = "Custom"

	_campaign["raid_plan"]["formation"] = next_formation
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func apply_default_formation(_encounter_id: String = "") -> void:
	_campaign["raid_plan"]["formation"] = _build_default_formation()
	raid_plan_changed.emit()
	state_changed.emit()


func replace_current_formation(source: Dictionary) -> void:
	_ensure_formation()
	_campaign["raid_plan"]["formation"] = _sanitize_formation_for_active(source)
	raid_plan_changed.emit()
	state_changed.emit()


func get_saved_formation_names() -> Array[String]:
	_ensure_formation()
	var names: Array[String] = []
	var saved_formations: Dictionary = _campaign["raid_plan"].get("saved_formations", {})

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
	_campaign["raid_plan"]["formation"] = current.duplicate(true)
	_campaign["raid_plan"]["saved_formations"][formation_name] = current.duplicate(true)
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func load_formation(formation_name: String) -> bool:
	_ensure_formation()

	if formation_name == DEFAULT_FORMATION_NAME:
		apply_default_formation()
		return true

	var saved_formations: Dictionary = _campaign["raid_plan"].get("saved_formations", {})

	if not saved_formations.has(formation_name):
		return false

	var source: Dictionary = saved_formations[formation_name]
	var loaded := _sanitize_formation_for_active(source)
	loaded["preset_name"] = formation_name
	_campaign["raid_plan"]["formation"] = loaded
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func delete_saved_formation(formation_name: String) -> bool:
	_ensure_formation()
	var saved_formations: Dictionary = _campaign["raid_plan"].get("saved_formations", {})

	if not saved_formations.has(formation_name):
		return false

	saved_formations.erase(formation_name)
	_campaign["raid_plan"]["saved_formations"] = saved_formations
	if String(_campaign["raid_plan"]["formation"].get("preset_name", "")) == formation_name:
		_campaign["raid_plan"]["formation"] = _build_default_formation()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func validate_raid_plan() -> Dictionary:
	return RaidPlanValidatorScript.validate(
		_campaign.get("raid_plan", {}), get_roster_by_id(), get_available_encounter_ids()
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

	_campaign["notable_event_sequence"] = int(_campaign.get("notable_event_sequence", 0)) + 1
	var prepared := raw_event.duplicate(true)
	prepared["event_id"] = String(
		prepared.get("event_id", "event_%08d" % int(_campaign["notable_event_sequence"]))
	)
	prepared["recorded_unix_time"] = int(
		prepared.get("recorded_unix_time", Time.get_unix_time_from_system())
	)
	var result := CampV2EventSystemScript.process_event(_campaign, prepared)
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

	if emit_change:
		state_changed.emit()

	return event.duplicate(true)


func get_recent_notable_events(limit: int = 30) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var records: Array = _campaign.get("notable_event_records", [])
	var first_index := maxi(records.size() - maxi(limit, 0), 0)

	for value in records.slice(first_index):
		if value is Dictionary:
			result.append(Dictionary(value).duplicate(true))

	return result


func get_raid_chronicle(limit: int = 30) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Array = _campaign.get("raid_chronicle", [])
	var first_index := maxi(entries.size() - maxi(limit, 0), 0)

	for value in entries.slice(first_index):
		if value is Dictionary:
			result.append(Dictionary(value).duplicate(true))

	return result


func get_raider_memories(raider_id: String) -> Dictionary:
	return _social_memory_service.get_memories(_campaign, raider_id)


func select_conversation_memory(raider_id: String, criteria: Dictionary) -> Dictionary:
	return RaiderMemoryStoreScript.select_relevant_thread(
		Dictionary(_campaign.get("memory_store", {})),
		raider_id,
		criteria,
		int(Time.get_unix_time_from_system())
	)


func get_relationship(first_id: String, second_id: String) -> Dictionary:
	return _social_memory_service.get_relationship(_campaign, first_id, second_id)


func get_relationship_label(viewer_id: String, other_id: String) -> String:
	var pair := get_relationship(viewer_id, other_id)
	return RaiderRelationshipStoreScript.get_public_label(
		pair, viewer_id
	)


func get_raider_lore_knowledge(raider_id: String) -> Dictionary:
	return _social_memory_service.get_lore(_campaign, raider_id)


func get_room_options(for_raider_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var occupants_by_room := _room_occupants_by_id(_campaign)

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

	var roommate_names: Array[String] = []

	for occupant_id in _room_occupants_by_id(_campaign).get(room_id, []):
		if String(occupant_id) == raider_id:
			continue
		var roommate := get_member(String(occupant_id))
		roommate_names.append(String(roommate.get("display_name", occupant_id)))

	if roommate_names.size() == 1:
		return "Roommate: %s" % roommate_names[0]

	if roommate_names.size() > 1:
		return "Roommates: %s" % ", ".join(roommate_names)

	return "Private for now."


func has_unseen_profile_development(raider_id: String) -> bool:
	return get_unseen_profile_development_count(raider_id) > 0


func get_unseen_profile_development_count(raider_id: String) -> int:
	var quarters: Dictionary = _campaign.get("member_quarters_state", {})
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
	_campaign["member_quarters_state"] = quarters
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


func adjust_conversation_pressure(amount: float, source: String = "debug_control") -> float:
	CampConversationStateScript.adjust_pressure(
		_get_camp_conversation_store(), clampf(amount, -100.0, 100.0), source
	)
	return float(_get_camp_conversation_store().get("pressure", 0.0))


func recruit_raider(raider_id: String, recruitment_source: String) -> bool:
	var states: Dictionary = _campaign.get("raider_states", {})
	var state_value: Variant = states.get(raider_id, {})

	if not state_value is Dictionary or bool(state_value.get("recruited", false)):
		return false

	var state: Dictionary = state_value
	state["recruited"] = true
	state["recruitment_source"] = recruitment_source
	states[raider_id] = state
	_campaign["raider_states"] = states
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

	var states: Dictionary = _campaign.get("raider_states", {})
	var state_value: Variant = states.get(raider_id, {})

	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return false

	var participants: Array[String] = [raider_id]
	if not roommate_id.is_empty() and roommate_id != raider_id:
		var roommate_value: Variant = states.get(roommate_id, {})
		if not roommate_value is Dictionary or not bool(roommate_value.get("recruited", false)):
			return false
		participants.append(roommate_id)

	var existing_occupants: Array = _room_occupants_by_id(_campaign).get(room_assignment_id, [])
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

	_campaign["raider_states"] = states
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
	var occupants_by_room := _room_occupants_by_id(_campaign)
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
	var states: Dictionary = _campaign.get("raider_states", {})
	var state_value: Variant = states.get(raider_id, {})

	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return false

	var state: Dictionary = state_value
	var previous_class := String(state.get("advanced_class_id", ""))
	state["advanced_class_id"] = advanced_class_id
	state["specialization_id"] = specialization_id
	states[raider_id] = state
	_campaign["raider_states"] = states
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
	CampV2EventSystemScript.advance_lifecycle(_campaign, now)
	state_changed.emit()


func record_attempt(summary: Dictionary) -> Dictionary:
	if summary.is_empty():
		return {
			"ok": false, "status": "invalid_summary",
			"message": "Attempt summary must not be empty.", "receipt": {},
		}

	var attempt_summary := summary.duplicate(true)
	var attempt_id := String(attempt_summary.get("attempt_id", "")).strip_edges()
	if attempt_id.is_empty():
		return {
			"ok": false, "status": "invalid_attempt_id",
			"message": "Campaign attempts require a stable attempt ID.", "receipt": {},
		}
	var existing_receipt: Dictionary = Dictionary(
		_campaign.get("progression", {}).get("reward_receipts", {}).get(attempt_id, {})
	).duplicate(true)
	if not existing_receipt.is_empty() or _has_recorded_attempt(attempt_id):
		return {
			"ok": true,
			"status": "duplicate",
			"message": "This attempt was already recorded.",
			"receipt": existing_receipt,
		}
	if Array(
		_campaign.get("progression", {}).get("processed_attempt_ids", [])
	).has(attempt_id):
		return {
			"ok": true,
			"status": "duplicate_historical",
			"message": "This historical attempt was already processed.",
			"receipt": {},
		}

	var encounter_id := String(
		attempt_summary.get("encounter_id", get_selected_encounter_id())
	)
	attempt_summary["encounter_id"] = encounter_id
	var reward_result := {
		"ok": true, "status": "not_applicable", "message": "", "receipt": {},
	}
	if String(attempt_summary.get("outcome", "")) == "victory":
		reward_result = _reward_service.process_victory(_campaign, attempt_summary)
		if not bool(reward_result.get("ok", false)):
			return reward_result

	var known_discoveries := get_discoveries(encounter_id)
	var known_abilities: Array = known_discoveries.get("ability_ids", [])
	var known_phases: Array = known_discoveries.get("phase_ids", [])
	var newly_observed_abilities: Array[String] = []
	var newly_observed_phases: Array[String] = []

	for ability_id in attempt_summary.get("observed_ability_ids", []):
		if not known_abilities.has(ability_id):
			newly_observed_abilities.append(String(ability_id))

	for phase_id in attempt_summary.get("observed_phase_ids", []):
		if not known_phases.has(phase_id):
			newly_observed_phases.append(String(phase_id))

	attempt_summary["newly_discovered_ability_ids"] = newly_observed_abilities
	attempt_summary["newly_discovered_phase_ids"] = newly_observed_phases
	var history: Dictionary = _campaign.get("attempt_history", {})
	var encounter_history: Array = history.get(encounter_id, [])
	encounter_history.append(attempt_summary.duplicate(true))

	if encounter_history.size() > ATTEMPT_HISTORY_LIMIT:
		encounter_history = encounter_history.slice(
			encounter_history.size() - ATTEMPT_HISTORY_LIMIT
		)

	history[encounter_id] = encounter_history
	_campaign["attempt_history"] = history
	_campaign["latest_attempt"] = attempt_summary.duplicate(true)
	_update_discoveries_from_attempt(attempt_summary)

	_record_active_raider_combat_history(String(attempt_summary.get("outcome", "")))
	_emit_attempt_notable_events(attempt_summary)
	attempt_recorded.emit(attempt_summary.duplicate(true))
	state_changed.emit()
	return {
		"ok": true,
		"status": String(reward_result.get("status", "recorded")),
		"message": (
			String(reward_result.get("message", ""))
			if String(attempt_summary.get("outcome", "")) == "victory"
			else "Attempt recorded."
		),
		"receipt": Dictionary(reward_result.get("receipt", {})).duplicate(true),
	}


func get_attempt_history(encounter_id: String = "") -> Array[Dictionary]:
	if encounter_id.is_empty():
		encounter_id = get_selected_encounter_id()

	return _progression_service.get_attempt_history(
		_campaign, encounter_id, ATTEMPT_HISTORY_LIMIT
	)


func get_latest_attempt(encounter_id: String = "") -> Dictionary:
	var history := get_attempt_history(encounter_id)
	return {} if history.is_empty() else history[-1]


func get_discoveries(encounter_id: String = "") -> Dictionary:
	if encounter_id.is_empty():
		encounter_id = get_selected_encounter_id()

	return Dictionary(_campaign.get("discoveries", {}).get(encounter_id, {})).duplicate(true)


func get_latest_victory() -> Dictionary:
	return Dictionary(_campaign.get("latest_victory", {})).duplicate(true)


func get_progression_inventory() -> Dictionary:
	return _progression_service.get_inventory(_campaign)


func get_latest_reward_receipt() -> Dictionary:
	var latest := get_latest_victory()
	var attempt_id := String(latest.get("attempt_id", ""))
	if attempt_id.is_empty():
		return {}
	return Dictionary(
		_campaign.get("progression", {}).get("reward_receipts", {}).get(attempt_id, {})
	).duplicate(true)


func get_material_count(material_id: String) -> int:
	return _progression_service.get_material_count(_campaign, material_id)


func get_owned_advancement_token_ids() -> Array[String]:
	return _string_array(
		_campaign.get("progression", {}).get("advancement_token_ids", [])
	)


func get_unlocked_recipe_ids() -> Array[String]:
	return _string_array(
		_campaign.get("progression", {}).get("unlocked_recipe_ids", [])
	)


func get_crafted_weapon_ids() -> Array[String]:
	return _string_array(
		_campaign.get("progression", {}).get("crafted_weapon_ids", [])
	)


func owns_advancement_token(token_id: String) -> bool:
	return get_owned_advancement_token_ids().has(token_id)


func is_recipe_unlocked(recipe_id: String) -> bool:
	return get_unlocked_recipe_ids().has(recipe_id)


func owns_crafted_weapon(weapon_id: String) -> bool:
	return get_crafted_weapon_ids().has(weapon_id)


func check_craft(recipe_id: String) -> Dictionary:
	return _progression_service.check_craft(_campaign, recipe_id)


func craft(recipe_id: String) -> Dictionary:
	var result := _progression_service.craft(_campaign, recipe_id)
	if bool(result.get("ok", false)):
		state_changed.emit()
	return result


func check_equip_weapon(raider_id: String, weapon_id: String) -> Dictionary:
	return _progression_service.check_equip(_campaign, raider_id, weapon_id)


func equip_weapon(raider_id: String, weapon_id: String) -> Dictionary:
	var result := _progression_service.equip(_campaign, raider_id, weapon_id)
	if bool(result.get("ok", false)):
		roster_changed.emit()
		state_changed.emit()
	return result


func check_move_or_swap_equipped_weapon(
	source_raider_id: String, destination_raider_id: String
) -> Dictionary:
	return _progression_service.check_move_or_swap_equipped_weapon(
		_campaign, source_raider_id, destination_raider_id
	)


func move_or_swap_equipped_weapon(
	source_raider_id: String, destination_raider_id: String
) -> Dictionary:
	var result := _progression_service.move_or_swap_equipped_weapon(
		_campaign, source_raider_id, destination_raider_id
	)
	if bool(result.get("ok", false)):
		roster_changed.emit()
		state_changed.emit()
	return result


func unequip_weapon(raider_id: String) -> Dictionary:
	var result := _progression_service.unequip(_campaign, raider_id)
	if bool(result.get("ok", false)):
		roster_changed.emit()
		state_changed.emit()
	return result


func get_raider_traits(raider_id: String) -> Dictionary:
	return _progression_service.get_raider_traits(_campaign, raider_id)


func assign_raider_major_trait(raider_id: String, trait_id: String) -> Dictionary:
	var result := _progression_service.assign_major_trait(_campaign, raider_id, trait_id)
	if bool(result.get("ok", false)):
		state_changed.emit()
	return result


func assign_raider_minor_trait(
	raider_id: String, slot_index: int, trait_id: String
) -> Dictionary:
	var result := _progression_service.assign_minor_trait(
		_campaign, raider_id, slot_index, trait_id
	)
	if bool(result.get("ok", false)):
		state_changed.emit()
	return result


func get_progression_diagnostics() -> Array[Dictionary]:
	return _progression_service.get_missing_content_diagnostics(_campaign)


func get_weapon_holder_id(weapon_id: String) -> String:
	return _progression_service.get_weapon_holder_id(_campaign, weapon_id)


func get_equipped_raider_ids(weapon_id: String) -> Array[String]:
	var result: Array[String] = []
	var holder_id := get_weapon_holder_id(weapon_id)
	if not holder_id.is_empty():
		result.append(holder_id)
	return result


func debug_grant_progression_materials(grants: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return {
			"ok": false, "status": "debug_only",
			"message": "Fixture grants are available only in debug builds.",
		}
	var result := _progression_service.debug_grant_materials(_campaign, grants)
	if bool(result.get("ok", false)):
		state_changed.emit()
	return result


func debug_process_seeded_reward(encounter_id: String, attempt_id: String) -> Dictionary:
	if not OS.is_debug_build():
		return {
			"ok": false, "status": "debug_only",
			"message": "Seeded rewards are available only in debug builds.",
		}
	return record_attempt({
		"attempt_id": attempt_id,
		"encounter_id": encounter_id,
		"outcome": "victory",
	})


func get_region_progression(region_id: String = FIRST_REGION_ID) -> Dictionary:
	return ProgressionCatalog.get_region_completion(
		region_id, Dictionary(_campaign.get("victories", {}))
	)


func get_victory_count(encounter_id: String) -> int:
	return _progression_service.get_victory_count(_campaign, encounter_id)


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

	_campaign["visit_context"] = {
		"type": context_type,
		"reaction_budget": int(base_budget),
		"reactions_emitted": 0,
		"details": details.duplicate(true),
		"started_unix_time": int(Time.get_unix_time_from_system())
	}
	CampConversationStateScript.apply_visit_pressure(
		_get_camp_conversation_store(), context_type
	)
	visit_context_changed.emit(get_visit_context())
	state_changed.emit()


func get_visit_context() -> Dictionary:
	return Dictionary(_campaign.get("visit_context", {})).duplicate(true)


func consume_visit_reaction() -> bool:
	var context: Dictionary = _campaign.get("visit_context", {})
	var emitted := int(context.get("reactions_emitted", 0))
	var budget := int(context.get("reaction_budget", 0))

	if emitted >= budget:
		return false

	context["reactions_emitted"] = emitted + 1
	_campaign["visit_context"] = context
	return true


func ensure_debug_reserves() -> int:
	var states: Dictionary = _campaign.get("raider_states", {})
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

	_campaign["raider_states"] = states
	_ensure_valid_room_assignments(_campaign)
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
	roster_changed.emit()
	state_changed.emit()
	return recruited_count


func mark_apex_victory_hook(region_id: String, unlocked_region_ids: Array[String]) -> void:
	# No current encounter calls this. It is the narrow V1 seam for the later regional apex.
	for unlocked_region_id in unlocked_region_ids:
		if not _campaign["unlocked_regions"].has(unlocked_region_id):
			_campaign["unlocked_regions"].append(unlocked_region_id)

	begin_visit(
		"apex_victory",
		{"region_id": region_id, "unlocked_region_ids": unlocked_region_ids.duplicate()}
	)


func get_campaign_debug_summary() -> Dictionary:
	return {
		"schema_version": int(_campaign.get("schema_version", 0)),
		"roster_size": get_roster_members().size(),
		"active_size": get_active_member_ids().size(),
		"selected_encounter": get_selected_encounter_id(),
		"plan_validation": validate_raid_plan(),
		"visit_context": get_visit_context(),
		"campaign_cast": get_campaign_cast_report(),
	}


func get_campaign_cast_report() -> Dictionary:
	var cast: Dictionary = _campaign.get("campaign_cast", {})
	var class_distribution: Dictionary = {}
	var role_distribution: Dictionary = {}
	var states: Dictionary = _campaign.get("raider_states", {})

	for raider_id in get_selected_cast_ids():
		var state_value: Variant = states.get(raider_id, {})

		if not state_value is Dictionary:
			continue

		var state: Dictionary = state_value
		var unit_class := String(state.get("current_class", "Unknown"))
		var definition := RaiderCatalogScript.get_definition(raider_id)
		var role := String(definition.get("default_role", "unknown"))
		class_distribution[unit_class] = int(class_distribution.get(unit_class, 0)) + 1
		role_distribution[role] = int(role_distribution.get(role, 0)) + 1

	var warnings := _string_array(cast.get("generation_warnings", []))

	for catalog_warning in RaiderCatalogScript.get_warnings():
		if not warnings.has(catalog_warning):
			warnings.append(catalog_warning)

	return {
		"campaign_seed": int(_campaign.get("campaign_seed", 0)),
		"catalog_version": int(cast.get("catalog_version", 0)),
		"selected_40": get_selected_cast_ids(),
		"initial_20": get_initial_cast_ids(),
		"future_20": get_future_recruit_ids(),
		"class_distribution": class_distribution,
		"role_distribution": role_distribution,
		"generation_validation_warnings": warnings,
		"missing_definition_ids": [],
	}


func print_campaign_cast_report() -> void:
	print("[Camp V2 Campaign Cast]\n" + JSON.stringify(get_campaign_cast_report(), "\t"))


func get_camp_v2_event_debug_report() -> Dictionary:
	return CampV2EventSystemScript.get_debug_report(_campaign)


func validate_master_raider_definitions() -> Dictionary:
	return RaiderCatalogScript.validate_all()


func get_camp_v2_integration_debug_report() -> Dictionary:
	var raider_states: Dictionary = {}
	for raider_id in get_selected_cast_ids():
		raider_states[raider_id] = get_raider_campaign_state(raider_id)
	return {
		"save_schema_version": int(_campaign.get("schema_version", 0)),
		"campaign_cast_and_seed": get_campaign_cast_report(),
		"raider_campaign_states": raider_states,
		"events_memories_chronicle_relationships_lore": get_camp_v2_event_debug_report(),
		"conversation_pressure_and_cooldowns": get_camp_conversation_debug_report(),
		"recent_member_quarters_summaries": get_conversation_summaries("", 30),
		"member_quarters_state": Dictionary(
			_campaign.get("member_quarters_state", {})
		).duplicate(true),
		"master_raider_validation": validate_master_raider_definitions(),
		"camp_content_validation": CampContentCatalogScript.get_validation_report(),
		"central_tuning": TuningCatalogAccess.get_camp().get_summary(),
	}


func force_representative_notable_event() -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "reason": "debug_build_required"}
	var active_ids := get_active_member_ids()
	if active_ids.size() < 3:
		return {"ok": false, "reason": "at_least_three_active_raiders_required"}
	var participants: Array[String] = []
	for index in range(mini(active_ids.size(), 5)):
		participants.append(active_ids[index])
	var event := emit_notable_event(
		{
			"event_type": "boss_attempt_completed",
			"source_system": "debug_integration_control",
			"participants": participants,
			"distinctive_participants": [
				{
					"raider_id": participants[0],
					"admission_reasons": ["meaningful_agency"],
					"memory_strength": 0.55,
				}
			],
			"memory_category": "combat",
			"subject_key": "debug:representative_raid_event",
			"significance": 72,
			"structured_data": {
				"debug": true,
				"expected_chronicle_entries": 1,
				"expected_personal_memories": 1,
			},
			"prose_template_id": "debug_representative_raid_event",
		},
		false
	)
	state_changed.emit()
	return {"ok": not event.is_empty(), "event": event}


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
			"allow_large_relationship_delta": true,
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
		"progression": CampaignProgressionServiceScript.create_empty_progression(),
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


func _is_current_schema_compatible(source: Dictionary) -> bool:
	var source_version := int(source.get("schema_version", -1))
	if source_version == MIGRATABLE_SCHEMA_VERSION:
		return _is_version_10_schema_compatible(source)
	if source_version != SCHEMA_VERSION:
		return false
	if not source.has("campaign_seed"):
		return false
	var defaults := _create_default_campaign(int(source["campaign_seed"]))
	for required_key in defaults.keys():
		if required_key == "visit_context":
			continue
		if not source.has(required_key):
			return false
	for dictionary_key in [
		"campaign_cast", "raider_states", "raid_plan", "memory_store",
		"relationship_store", "lore_knowledge_store", "camp_conversation_state",
		"member_quarters_state", "victories", "progression", "discoveries",
		"attempt_history", "latest_attempt", "latest_victory"
	]:
		if not source.get(dictionary_key) is Dictionary:
			return false
	for array_key in ["notable_event_records", "raid_chronicle", "unlocked_regions"]:
		if not source.get(array_key) is Array:
			return false
	var raid_plan: Dictionary = source["raid_plan"]
	var default_plan: Dictionary = defaults["raid_plan"]
	for plan_key in default_plan.keys():
		if not raid_plan.has(plan_key):
			return false
	for plan_dictionary_key in [
		"formation", "saved_formations", "support_selections", "encounter_configuration"
	]:
		if not raid_plan.get(plan_dictionary_key) is Dictionary:
			return false
	if not raid_plan.get("active_member_ids") is Array:
		return false
	for raider_id in _string_array(source["campaign_cast"].get("selected_raider_ids", [])):
		if RaiderCatalogScript.get_definition(raider_id).is_empty():
			return false
	return true


func _is_version_10_schema_compatible(source: Dictionary) -> bool:
	if int(source.get("schema_version", -1)) != MIGRATABLE_SCHEMA_VERSION:
		return false
	if not source.has("campaign_seed"):
		return false
	for dictionary_key in [
		"campaign_cast", "raider_states", "raid_plan", "memory_store",
		"relationship_store", "lore_knowledge_store", "camp_conversation_state",
		"member_quarters_state", "victories", "boss_resources", "discoveries",
		"attempt_history", "latest_attempt", "latest_victory",
	]:
		if not source.get(dictionary_key) is Dictionary:
			return false
	for array_key in ["notable_event_records", "raid_chronicle", "unlocked_regions"]:
		if not source.get(array_key) is Array:
			return false
	var raid_plan: Dictionary = source["raid_plan"]
	for dictionary_key in [
		"formation", "saved_formations", "support_selections", "encounter_configuration",
	]:
		if not raid_plan.get(dictionary_key) is Dictionary:
			return false
	if not raid_plan.get("active_member_ids") is Array:
		return false
	return true


func _migrate_version_10_campaign(source: Dictionary) -> Dictionary:
	var migrated := source.duplicate(true)
	migrated["progression"] = (
		CampaignProgressionServiceScript.migrate_version_10_progression(source)
	)
	migrated.erase("boss_resources")
	migrated["schema_version"] = SCHEMA_VERSION
	return migrated


func _sanitize_current_campaign(source: Dictionary) -> Dictionary:
	var source_seed := int(source.get("campaign_seed", 20004))
	var defaults := _create_default_campaign(source_seed)
	var sanitized := source.duplicate(true)

	for key in defaults.keys():
		if not sanitized.has(key):
			sanitized[key] = defaults[key]

	var default_plan: Dictionary = defaults["raid_plan"]
	var raid_plan_value: Variant = sanitized.get("raid_plan", {})
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
	raid_plan["formation"] = Dictionary(formation_value).duplicate(true)

	var saved_formations_value: Variant = raid_plan.get("saved_formations", {})
	var saved_formations: Dictionary = (
		Dictionary(saved_formations_value).duplicate(true)
		if saved_formations_value is Dictionary
		else {}
	)

	raid_plan["saved_formations"] = saved_formations
	sanitized["raid_plan"] = raid_plan

	_sanitize_current_raider_data(sanitized, defaults)
	sanitized["progression"] = CampaignProgressionServiceScript.sanitize_progression(
		sanitized.get("progression", {})
	)
	CampaignProgressionServiceScript.reconcile_duplicate_weapon_assignments(sanitized)
	var latest_reward_attempt_id := String(
		sanitized.get("latest_victory", {}).get("attempt_id", "")
	)
	if (
		not latest_reward_attempt_id.is_empty()
		and sanitized["progression"]["reward_receipts"].has(latest_reward_attempt_id)
	):
		sanitized["latest_victory"] = Dictionary(
			sanitized["progression"]["reward_receipts"][latest_reward_attempt_id]
		).duplicate(true)

	CampV2EventSystemScript.sanitize_campaign_stores(
		sanitized,
		_string_array(sanitized.get("campaign_cast", {}).get("selected_raider_ids", []))
	)
	sanitized["camp_conversation_state"] = CampConversationStateScript.sanitize_store(
		sanitized.get("camp_conversation_state", {}),
		_string_array(sanitized.get("campaign_cast", {}).get("selected_raider_ids", []))
	)
	sanitized["member_quarters_state"] = _sanitize_member_quarters_state(
		sanitized.get("member_quarters_state", {}),
		_string_array(sanitized.get("campaign_cast", {}).get("selected_raider_ids", [])),
		sanitized
	)
	_ensure_valid_room_assignments(sanitized)
	sanitized["attempt_history"] = _normalize_attempt_history(
		sanitized.get("attempt_history", {})
	)
	sanitized["schema_version"] = SCHEMA_VERSION
	_campaign = sanitized
	_sync_active_state_flags()
	_ensure_formation()
	return _campaign


func _sanitize_current_raider_data(sanitized: Dictionary, defaults: Dictionary) -> void:
	var cast_value: Variant = sanitized.get("campaign_cast", {})
	var cast: Dictionary = Dictionary(cast_value).duplicate(true) if cast_value is Dictionary else {}
	var selected_ids := _unique_string_array(cast.get("selected_raider_ids", []))
	var active_ids := _unique_string_array(
		sanitized.get("raid_plan", {}).get("active_member_ids", [])
	)

	for active_id in active_ids:
		_append_unique_id(selected_ids, active_id)

	for generated_id in _string_array(
		defaults.get("campaign_cast", {}).get("selected_raider_ids", [])
	):
		if selected_ids.size() >= TuningCatalogAccess.get_raid_campaign().campaign_cast_size:
			break
		_append_unique_id(selected_ids, generated_id)

	var initial_ids := _unique_string_array(cast.get("initial_raider_ids", []))
	initial_ids = _only_selected_ids(initial_ids, selected_ids)

	for generated_id in _string_array(
		defaults.get("campaign_cast", {}).get("initial_raider_ids", [])
	):
		if initial_ids.size() >= TuningCatalogAccess.get_raid_campaign().initial_roster_size:
			break

		if selected_ids.has(generated_id):
			_append_unique_id(initial_ids, generated_id)

	for raider_id in selected_ids:
		if initial_ids.size() >= TuningCatalogAccess.get_raid_campaign().initial_roster_size:
			break
		_append_unique_id(initial_ids, raider_id)

	if initial_ids.size() > TuningCatalogAccess.get_raid_campaign().initial_roster_size:
		initial_ids = initial_ids.slice(0, TuningCatalogAccess.get_raid_campaign().initial_roster_size)

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

	var source_states_value: Variant = sanitized.get("raider_states", {})
	var source_states: Dictionary = (
		Dictionary(source_states_value) if source_states_value is Dictionary else {}
	)
	var states: Dictionary = {}

	for raider_id in selected_ids:
		var definition := RaiderCatalogScript.get_definition(raider_id)

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

	sanitized["raid_plan"]["active_member_ids"] = valid_active_ids
	var warnings := _unique_string_array(cast.get("generation_warnings", []))

	if selected_ids.size() != TuningCatalogAccess.get_raid_campaign().campaign_cast_size:
		warnings.append(
			"Stored cast contains %d raiders instead of %d."
			% [selected_ids.size(), TuningCatalogAccess.get_raid_campaign().campaign_cast_size]
		)

	sanitized["campaign_cast"] = {
		"catalog_version": RaiderCatalogScript.get_catalog_version(),
		"selected_raider_ids": selected_ids,
		"initial_raider_ids": initial_ids,
		"future_raider_ids": future_ids,
		"generation_warnings": warnings,
	}
	sanitized["raider_states"] = states


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
	if not _campaign.has("raid_plan"):
		return

	var raid_plan: Dictionary = _campaign["raid_plan"]
	var formation_value: Variant = raid_plan.get("formation", {})
	var formation_source: Dictionary = (
		Dictionary(formation_value) if formation_value is Dictionary else {}
	)
	raid_plan["formation"] = _sanitize_formation_for_active(formation_source)

	if not raid_plan.get("saved_formations") is Dictionary:
		raid_plan["saved_formations"] = {}

	raid_plan.erase("formations")
	_campaign["raid_plan"] = raid_plan


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
	var discoveries: Dictionary = _campaign.get("discoveries", {})
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
	_campaign["discoveries"] = discoveries


func _has_recorded_attempt(attempt_id: String) -> bool:
	var history_value: Variant = _campaign.get("attempt_history", {})
	if not history_value is Dictionary:
		return false
	for encounter_history_value in history_value.values():
		if not encounter_history_value is Array:
			continue
		for summary_value in encounter_history_value:
			if (
				summary_value is Dictionary
				and String(summary_value.get("attempt_id", "")) == attempt_id
			):
				return true
	return false


func _record_active_raider_combat_history(outcome: String) -> void:
	var states: Dictionary = _campaign.get("raider_states", {})

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

	_campaign["raider_states"] = states


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
	return _project_member_from(RaiderCatalogScript.get_definition(raider_id), state)


func _project_member_from(definition: Dictionary, state: Dictionary) -> Dictionary:
	var raider_id := String(state.get("raider_id", definition.get("raider_id", "")))
	var assigned_roles := _unique_string_array(state.get("assigned_roles", []))
	var default_role := String(definition.get("default_role", "dps"))

	if assigned_roles.is_empty():
		assigned_roles.append(default_role)

	var weapon_projection := _runtime_weapon_projection(state)
	return {
		# Camp V1 and combat consumers retain these aliases while stable IDs remain authoritative.
		"member_id": raider_id,
		"raider_id": raider_id,
		"display_name": String(definition.get("display_name", "Unnamed Raider")),
		"unit_class": String(
			state.get("current_class", definition.get("default_class", "Mage"))
		),
		"role": assigned_roles[0],
		"roles": assigned_roles,
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
		"equipped_weapon_id": String(state.get("equipped_weapon_id", "")),
		"weapon_runtime_active": bool(weapon_projection.get("active", false)),
		"weapon_family_id": String(weapon_projection.get("family_id", "")),
		"weapon_stat_profile": Dictionary(
			weapon_projection.get("stat_profile", {})
		).duplicate(true),
		"major_trait_id": String(state.get("major_trait_id", "")),
		"minor_trait_ids": Array(state.get("minor_trait_ids", [])).duplicate(),
		"doctrine_id": String(state.get("doctrine_id", "")),
		"source_id": String(state.get("recruitment_source", "unknown")),
		"room_assignment_id": String(state.get("room_assignment_id", "")),
		"combat_history": Dictionary(state.get("combat_history", {})).duplicate(true),
		"permanent_milestone_ids": Array(
			state.get("permanent_milestone_ids", [])
		).duplicate(),
		"descriptive_title": String(state.get("descriptive_title", "")),
		"debug_member": bool(state.get("debug_member", false)),
	}


func _runtime_weapon_projection(state: Dictionary) -> Dictionary:
	var weapon_id := String(state.get("equipped_weapon_id", ""))
	if weapon_id.is_empty() or not owns_crafted_weapon(weapon_id):
		return {"active": false, "family_id": "", "stat_profile": {}}
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	if weapon == null or weapon.stat_profile == null:
		return {"active": false, "family_id": "", "stat_profile": {}}
	var class_id := String(state.get("advanced_class_id", ""))
	if class_id.is_empty():
		class_id = String(state.get("current_class", ""))
	if not ProgressionCatalog.is_family_compatible(class_id, weapon.family_id):
		return {"active": false, "family_id": weapon.family_id, "stat_profile": {}}
	return {
		"active": true,
		"family_id": weapon.family_id,
		"stat_profile": weapon.stat_profile.to_dictionary(),
	}


func _get_member_quarters_state() -> Dictionary:
	var value: Variant = _campaign.get("member_quarters_state", {})
	if not value is Dictionary:
		_campaign["member_quarters_state"] = {
			"profile_revisions": {},
			"seen_profile_revisions": {},
		}
	return _campaign["member_quarters_state"]


func _mark_profile_updates(participant_ids_value: Variant) -> void:
	var quarters := _get_member_quarters_state()
	var revisions: Dictionary = quarters.get("profile_revisions", {})
	for raider_id in _unique_string_array(participant_ids_value):
		if not get_selected_cast_ids().has(raider_id):
			continue
		revisions[raider_id] = int(revisions.get(raider_id, 0)) + 1
	quarters["profile_revisions"] = revisions
	_campaign["member_quarters_state"] = quarters


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
	var state_value: Variant = _campaign.get("raider_states", {}).get(raider_id, {})
	if not state_value is Dictionary or not bool(state_value.get("recruited", false)):
		return false
	var state: Dictionary = state_value
	var current_room := String(state.get("room_assignment_id", ""))
	var occupants_by_room := _room_occupants_by_id(_campaign)
	if _is_valid_room_id(current_room):
		var current_occupants: Array = occupants_by_room.get(current_room, [])
		if current_occupants.size() <= QUARTERS_ROOM_CAPACITY:
			return true

	for room_number in range(1, QUARTERS_ROOM_COUNT + 1):
		var room_id := _room_id(room_number)
		if Array(occupants_by_room.get(room_id, [])).size() >= QUARTERS_ROOM_CAPACITY:
			continue
		state["room_assignment_id"] = room_id
		_campaign["raider_states"][raider_id] = state
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
	var states_value: Variant = _campaign.get("raider_states", {})

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

	_campaign["raider_states"] = states


func _generate_campaign_seed() -> int:
	return maxi(
		int(Time.get_unix_time_from_system() * 1000.0) + int(Time.get_ticks_msec()), 1
	)


func _print_campaign_cast_report_if_debug() -> void:
	if not OS.is_debug_build():
		return

	var report := get_campaign_cast_report()
	var warnings: Array = report.get("generation_validation_warnings", [])
	if not warnings.is_empty():
		push_warning("Campaign cast validation warnings: " + JSON.stringify(warnings))


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
	var context: Dictionary = _campaign.get("visit_context", {})
	context["type"] = context_type
	context["reaction_budget"] = (
		int(context.get("reaction_budget", 0)) + clampi(magnitude * 2, 3, 24)
	)
	context["details"] = {"magnitude": magnitude}
	_campaign["visit_context"] = context


func _append_unique_value(target: Array, value: Variant) -> void:
	if not target.has(value):
		target.append(value)


func _get_camp_conversation_store() -> Dictionary:
	var value: Variant = _campaign.get("camp_conversation_state", {})
	if not value is Dictionary:
		_campaign["camp_conversation_state"] = CampConversationStateScript.create_store()
	return _campaign["camp_conversation_state"]
