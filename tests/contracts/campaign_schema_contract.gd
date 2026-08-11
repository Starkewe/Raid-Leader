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

	var incompatible := CampaignState.get_campaign_snapshot()
	incompatible["schema_version"] = CampaignState.SCHEMA_VERSION - 1
	var persistence = PersistenceScript.new()
	if not persistence.write_payload(TEST_PATH, incompatible, {"kind": "test"}):
		failures.append("The incompatible fixture save could not be written.")
	elif CampaignState.load_campaign(TEST_PATH):
		failures.append("CampaignState accepted an incompatible schema.")
	elif not FileAccess.file_exists(TEST_PATH):
		failures.append("CampaignState deleted the incompatible save.")
	else:
		var retained: Dictionary = persistence.read_payload(TEST_PATH)
		if int(retained.get("campaign", {}).get("schema_version", 0)) != CampaignState.SCHEMA_VERSION - 1:
			failures.append("CampaignState rewrote the incompatible save.")
		if int(CampaignState.get_campaign_snapshot().get("schema_version", 0)) != CampaignState.SCHEMA_VERSION:
			failures.append("CampaignState did not start a current-schema campaign.")

	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	if failures.is_empty():
		print("RAID_TEST_PASS:campaign_schema_contract | Clean campaign schema and isolated user data passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
