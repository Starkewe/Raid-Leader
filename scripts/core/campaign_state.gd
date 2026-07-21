extends Node

const RaidMemberRecordScript := preload("res://scripts/data/raid_member_record.gd")
const RaidPlanValidatorScript := preload("res://scripts/core/raid_plan_validator.gd")

signal state_changed
signal raid_plan_changed
signal roster_changed
signal attempt_recorded(summary: Dictionary)
signal visit_context_changed(context: Dictionary)

const SAVE_PATH := "user://raid_leader_campaign_v1.json"
const SCHEMA_VERSION := 3
const ACTIVE_RAID_SIZE := 20
const ATTEMPT_HISTORY_LIMIT := 5
const FIRST_REGION_ID := "beast_crucible"
const DEFAULT_FORMATION_NAME := "Default"

const STARTING_BLUEPRINT := [
	["Brann", "Warrior", "tank", ["steady", "protective"]],
	["Mara", "Priest", "healer", ["patient", "observant"]],
	["Vey", "Rogue", "dps", ["bold", "restless"]],
	["Ash", "Mage", "dps", ["curious", "reserved"]],
	["Merrow", "Mage", "dps", ["practical", "sociable"]],
	["Tamsin", "Warrior", "tank", ["vigilant", "stubborn"]],
	["Elian", "Priest", "healer", ["calm", "scholarly"]],
	["Nessa", "Rogue", "dps", ["wry", "vigilant"]],
	["Lysa", "Mage", "dps", ["precise", "quiet"]],
	["Thale", "Mage", "dps", ["bold", "curious"]],
	["Sabine", "Priest", "healer", ["practical", "warm"]],
	["Rook", "Rogue", "dps", ["steady", "competitive"]],
	["Ilya", "Rogue", "dps", ["observant", "reserved"]],
	["Yara", "Mage", "dps", ["patient", "scholarly"]],
	["Pell", "Mage", "dps", ["restless", "sociable"]],
	["Oren", "Priest", "healer", ["vigilant", "compassionate"]],
	["Calder", "Priest", "healer", ["direct", "steady"]],
	["Fen", "Rogue", "dps", ["practical", "quiet"]],
	["Corin", "Rogue", "dps", ["bold", "wry"]],
	["Sable", "Mage", "dps", ["precise", "reserved"]]
]

const DEBUG_RESERVE_BLUEPRINT := [
	["Ada", "Warrior", "tank"],
	["Holt", "Warrior", "tank"],
	["Kestrel", "Warrior", "tank"],
	["Beren", "Priest", "healer"],
	["Della", "Priest", "healer"],
	["Eris", "Priest", "healer"],
	["Galen", "Priest", "healer"],
	["Hesta", "Priest", "healer"],
	["Jori", "Rogue", "dps"],
	["Kiva", "Rogue", "dps"],
	["Lark", "Rogue", "dps"],
	["Miro", "Rogue", "dps"],
	["Nim", "Rogue", "dps"],
	["Pike", "Rogue", "dps"],
	["Quill", "Mage", "dps"],
	["Rhea", "Mage", "dps"],
	["Sol", "Mage", "dps"],
	["Tova", "Mage", "dps"],
	["Una", "Mage", "dps"],
	["Wren", "Mage", "dps"]
]

var campaign: Dictionary = {}


func _ready() -> void:
	reset_campaign(false)


func reset_campaign(emit_change: bool = true) -> void:
	campaign = _create_default_campaign()

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
	var definition := GameState.get_encounter_definition(encounter_id)
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

	for member_value in campaign.get("roster", []):
		result.append(Dictionary(member_value).duplicate(true))

	return result


func get_roster_by_id() -> Dictionary:
	var result: Dictionary = {}

	for member in campaign.get("roster", []):
		result[String(member.get("member_id", ""))] = member

	return result


func get_member(member_id: String) -> Dictionary:
	var roster_by_id := get_roster_by_id()
	return Dictionary(roster_by_id.get(member_id, {})).duplicate(true)


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


func get_reserve_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active_ids := get_active_member_ids()

	for member in campaign.get("roster", []):
		if not active_ids.has(String(member.get("member_id", ""))):
			result.append(Dictionary(member).duplicate(true))

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
	save_campaign()
	roster_changed.emit()
	raid_plan_changed.emit()
	state_changed.emit()
	return true


func reorder_active_member(
	moving_member_id: String, target_member_id: String, place_after_target: bool = false
) -> bool:
	var active_ids := get_active_member_ids()
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
	var roster: Array = campaign.get("roster", [])
	var existing_debug_count := 0

	for member in roster:
		if bool(member.get("debug_member", false)):
			existing_debug_count += 1

	if existing_debug_count > 0:
		return existing_debug_count

	var next_serial := int(campaign.get("next_member_serial", roster.size() + 1))
	var trait_pairs := [
		["steady", "practical"],
		["curious", "quiet"],
		["bold", "sociable"],
		["patient", "observant"],
		["vigilant", "reserved"]
	]

	for index in range(DEBUG_RESERVE_BLUEPRINT.size()):
		var blueprint: Array = DEBUG_RESERVE_BLUEPRINT[index]
		var member := RaidMemberRecordScript.create(
			"writ_%03d" % next_serial,
			String(blueprint[0]),
			String(blueprint[1]),
			String(blueprint[2]),
			trait_pairs[index % trait_pairs.size()],
			_debug_description(String(blueprint[1])),
			next_serial
		)
		member["source_id"] = "debug_recruitment"
		member["debug_member"] = true
		roster.append(member)
		next_serial += 1

	campaign["roster"] = roster
	campaign["next_member_serial"] = next_serial
	_augment_visit_reactions("recruitment", DEBUG_RESERVE_BLUEPRINT.size())
	save_campaign()
	roster_changed.emit()
	state_changed.emit()
	return DEBUG_RESERVE_BLUEPRINT.size()


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
		"roster_size": campaign.get("roster", []).size(),
		"active_size": get_active_member_ids().size(),
		"selected_encounter": get_selected_encounter_id(),
		"plan_validation": validate_raid_plan(),
		"visit_context": get_visit_context()
	}


func _create_default_campaign() -> Dictionary:
	var roster: Array[Dictionary] = []
	var active_member_ids: Array[String] = []

	for index in range(STARTING_BLUEPRINT.size()):
		var blueprint: Array = STARTING_BLUEPRINT[index]
		var member_id := "writ_%03d" % (index + 1)
		var member := RaidMemberRecordScript.create(
			member_id,
			String(blueprint[0]),
			String(blueprint[1]),
			String(blueprint[2]),
			Array(blueprint[3]).duplicate(),
			_starting_description(String(blueprint[0]), String(blueprint[1]), Array(blueprint[3])),
			index + 1
		)
		roster.append(member)
		active_member_ids.append(member_id)

	var default_formation := _build_default_formation_for_ids(active_member_ids, roster)

	return {
		"schema_version": SCHEMA_VERSION,
		"campaign_seed": 20004,
		"roster": roster,
		"next_member_serial": STARTING_BLUEPRINT.size() + 1,
		"raid_plan":
		{
			"region_id": FIRST_REGION_ID,
			"encounter_id": GameState.ENCOUNTER_OGRE,
			"active_member_ids": active_member_ids,
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


func _migrate_campaign(source: Dictionary) -> Dictionary:
	var defaults := _create_default_campaign()
	var migrated := source.duplicate(true)

	for key in defaults.keys():
		if not migrated.has(key):
			migrated[key] = defaults[key]

	if int(migrated.get("schema_version", 0)) < 1:
		migrated["schema_version"] = 1

	var sanitized_roster: Array[Dictionary] = []

	for member in migrated.get("roster", []):
		if member is Dictionary:
			sanitized_roster.append(RaidMemberRecordScript.sanitize(member))

	if sanitized_roster.is_empty():
		return defaults

	migrated["roster"] = sanitized_roster
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
	migrated["attempt_history"] = _normalize_attempt_history(
		migrated.get("attempt_history", {})
	)
	migrated["schema_version"] = SCHEMA_VERSION
	campaign = migrated
	_ensure_formation()
	return campaign


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
	return _build_default_formation_for_ids(get_active_member_ids(), campaign.get("roster", []))


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
	var definition := GameState.get_encounter_definition(encounter_id)
	campaign["latest_victory"] = {
		"encounter_id": encounter_id,
		"display_name": encounter_id if definition == null else definition.display_name,
		"victory_count": new_count,
		"first_victory": new_count == 1,
		"reward_summary": "A boss resource was secured immediately for future advancement systems.",
		"recorded_unix_time": int(Time.get_unix_time_from_system())
	}


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


func _starting_description(name_value: String, unit_class: String, attributes: Array) -> String:
	return (
		"%s is a %s of the first Writ: %s, %s, and already accustomed to fighting as one of twenty."
		% [name_value, unit_class.to_lower(), String(attributes[0]), String(attributes[1])]
	)


func _debug_description(unit_class: String) -> String:
	return (
		"A campaign-seeded %s reserve added for roster and forty-member stress testing."
		% unit_class.to_lower()
	)
