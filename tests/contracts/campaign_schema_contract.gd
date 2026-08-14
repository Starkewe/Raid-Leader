extends Node

const PersistenceScript := preload(
	"res://scripts/core/campaign_persistence_service.gd"
)
const TEST_PATH := "user://campaign_schema_contract.json"


func _ready() -> void:
	var failures: Array[String] = []
	var run_id := OS.get_environment("RAID_TEST_RUN_ID").validate_filename().to_lower()
	var expected_directory := "raid_leader_tests_" + run_id
	if OS.get_user_data_dir().get_file() != expected_directory:
		failures.append(
			"raid-test user:// is not isolated (actual: %s)." % OS.get_user_data_dir()
		)

	var persistence = PersistenceScript.new()
	_validate_version_10_migration(persistence, failures)
	_validate_current_round_trip(persistence, failures)
	_validate_rejected_schemas(persistence, failures)

	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	if failures.is_empty():
		print("RAID_TEST_PASS:campaign_schema_contract | Clean campaign schema and isolated user data passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _validate_version_10_migration(
	persistence: CampaignPersistenceService, failures: Array[String]
) -> void:
	CampaignState.reset_campaign(false, 10101)
	var legacy := CampaignState.get_campaign_snapshot()
	legacy["schema_version"] = 10
	legacy.erase("progression")
	legacy["boss_resources"] = {
		"ogre": 3,
		"chainmaster": 2,
		"unknown_returning_boss": 7,
	}
	legacy["victories"] = {"ogre": 4, "chainmaster": 1}
	legacy["attempt_history"] = {
		"ogre": [
			{"attempt_id": "historical_victory", "encounter_id": "ogre", "outcome": "victory"},
			{"attempt_id": "historical_wipe", "encounter_id": "ogre", "outcome": "wipe"},
		],
	}
	legacy["raid_plan"]["roster_sort_mode"] = "recruit_order"
	for raider_id in legacy["raider_states"]:
		legacy["raider_states"][raider_id].erase("equipped_weapon_id")
		legacy["raider_states"][raider_id].erase("major_trait_id")
		legacy["raider_states"][raider_id].erase("minor_trait_ids")
		legacy["raider_states"][raider_id].erase("doctrine_id")
	if not CampaignState.is_campaign_snapshot_compatible(legacy):
		failures.append("CampaignState did not recognize schema 10 as migratable.")
	if not persistence.write_payload(TEST_PATH, legacy, {"kind": "migration_test"}):
		failures.append("The version-10 migration fixture could not be written.")
		return
	var before_text := _read_text(TEST_PATH)
	if not CampaignState.load_campaign(TEST_PATH):
		failures.append("CampaignState rejected a valid version-10 save.")
		return
	if _read_text(TEST_PATH) != before_text:
		failures.append("Loading version 10 rewrote the source save.")
	var migrated := CampaignState.get_campaign_snapshot()
	if int(migrated.get("schema_version", 0)) != CampaignState.SCHEMA_VERSION:
		failures.append("Version-10 save did not migrate to the current in-memory schema.")
	if migrated.has("boss_resources"):
		failures.append("Legacy boss_resources remained in the current schema.")
	if CampaignState.get_material_count("shale_caked_hide") != 3:
		failures.append("Earthgnasher legacy resources did not convert 1:1.")
	if CampaignState.get_material_count("tempered_chainlink") != 2:
		failures.append("Chainmaster legacy resources did not convert 1:1.")
	for token_id in ["earthgnasher_warrior_token", "chainmaster_priest_token"]:
		if not CampaignState.owns_advancement_token(token_id):
			failures.append("Historical victory did not grant token '%s'." % token_id)
	if CampaignState.get_unlocked_recipe_ids().size() != 4:
		failures.append("Historical victories did not unlock both source recipes each.")
	var progression: Dictionary = migrated.get("progression", {})
	if not progression.get("reward_receipts", {}).is_empty():
		failures.append("Migration rolled retroactive historical rewards.")
	if not Array(progression.get("processed_attempt_ids", [])).has("historical_victory"):
		failures.append("Migration did not seed the victorious processed attempt ID.")
	if Array(progression.get("processed_attempt_ids", [])).has("historical_wipe"):
		failures.append("Migration seeded a non-victorious processed attempt ID.")
	if int(
		progression.get("migration_diagnostics", {})
		.get("unknown_legacy_boss_resources", {}).get("unknown_returning_boss", 0)
	) != 7:
		failures.append("Unknown legacy resource entries were discarded.")
	if migrated.get("raid_plan", {}).get("roster_sort_mode", "") != "recruit_order":
		failures.append("Migration changed unrelated raid-plan state.")
	for state_value in migrated.get("raider_states", {}).values():
		var state: Dictionary = state_value
		for field_name in [
			"equipped_weapon_id", "major_trait_id", "minor_trait_ids", "doctrine_id",
		]:
			if not state.has(field_name):
				failures.append("Migration did not add raider field '%s'." % field_name)
				break


func _validate_current_round_trip(
	persistence: CampaignPersistenceService, failures: Array[String]
) -> void:
	var round_trip_path := TEST_PATH.get_basename() + "_round_trip.json"
	if not CampaignState.write_campaign(round_trip_path, {"kind": "round_trip"}):
		failures.append("Current-schema save could not be written.")
		return
	var before := CampaignState.get_campaign_snapshot()
	before.erase("visit_context")
	if not CampaignState.load_campaign(round_trip_path):
		failures.append("Current-schema save could not be loaded.")
	else:
		var after := CampaignState.get_campaign_snapshot()
		after.erase("visit_context")
		if after != before:
			var changed_keys: Array[String] = []
			for key_value in before:
				var key := String(key_value)
				if before.get(key) != after.get(key):
					changed_keys.append(key)
			failures.append(
				"Current-schema round trip changed persisted keys: %s. progression before=%s after=%s"
				% [
					", ".join(changed_keys), JSON.stringify(before.get("progression", {})),
					JSON.stringify(after.get("progression", {})),
				]
			)
	if FileAccess.file_exists(round_trip_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(round_trip_path))


func _validate_rejected_schemas(
	persistence: CampaignPersistenceService, failures: Array[String]
) -> void:
	for rejected_version in [9, CampaignState.SCHEMA_VERSION + 1]:
		var incompatible := CampaignState.get_campaign_snapshot()
		incompatible["schema_version"] = rejected_version
		if not persistence.write_payload(TEST_PATH, incompatible, {"kind": "test"}):
			failures.append("Rejected-schema fixture %d could not be written." % rejected_version)
			continue
		var before_text := _read_text(TEST_PATH)
		if CampaignState.load_campaign(TEST_PATH):
			failures.append("CampaignState accepted rejected schema %d." % rejected_version)
		elif not FileAccess.file_exists(TEST_PATH):
			failures.append("CampaignState deleted rejected schema %d." % rejected_version)
		elif _read_text(TEST_PATH) != before_text:
			failures.append("CampaignState rewrote rejected schema %d." % rejected_version)
		if int(CampaignState.get_campaign_snapshot().get("schema_version", 0)) != CampaignState.SCHEMA_VERSION:
			failures.append("Rejected schema did not leave a current in-memory campaign.")

	var corrupt_path := TEST_PATH.get_basename() + "_corrupt.json"
	var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	if file != null:
		file.store_string("{ definitely not valid json")
		file.close()
		var corrupt_before := _read_text(corrupt_path)
		if CampaignState.load_campaign(corrupt_path):
			failures.append("CampaignState accepted corrupt JSON.")
		if _read_text(corrupt_path) != corrupt_before:
			failures.append("CampaignState rewrote corrupt JSON.")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_path))


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var result := file.get_as_text()
	file.close()
	return result
