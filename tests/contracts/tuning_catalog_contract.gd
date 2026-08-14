extends Node

const CatalogPath := "res://data/tuning/catalog.tres"
const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var catalog := load(CatalogPath) as TuningCatalogResource
	if catalog == null:
		_finish(["The typed tuning catalog did not load."])
		return

	var validation_errors := catalog.get_validation_errors()
	if not validation_errors.is_empty():
		failures.append("The authored tuning catalog is invalid: %s" % "; ".join(validation_errors))
	if not TuningCatalog.is_valid():
		failures.append("The startup TuningCatalog rejected the authored catalog.")
	if TuningCatalog.get_raid_campaign() != catalog.raid_campaign:
		failures.append("The startup catalog did not retain the loaded raid resource.")

	_validate_derived_raid_values(catalog.raid_campaign, failures)
	_validate_dodge_profiles(catalog.dodge, failures)
	_validate_representative_consumers(catalog, failures)
	_validate_invalid_fixtures(catalog, failures)
	_validate_legacy_modules_removed(failures)
	_finish(failures)


func _validate_derived_raid_values(
	tuning: RaidCampaignTuning, failures: Array[String]
) -> void:
	if tuning.get_raid_group_count() != 4:
		failures.append("Derived raid group count did not remain four.")
	if tuning.get_reserve_roster_size() != 40:
		failures.append("Derived reserve roster size did not remain forty.")
	if tuning.get_quarters_capacity() != 80:
		failures.append("Derived quarters capacity did not remain eighty.")


func _validate_dodge_profiles(
	tuning: DodgeTuningResource, failures: Array[String]
) -> void:
	var expected := {
		"warrior": [1, "physical", 0.5, 0.225, 8.0],
		"priest": [1, "physical", 1.0, 0.3, 8.0],
		"rogue": [2, "physical", 1.0, 0.3, 8.0],
		"mage": [1, "teleport", 1.5, 0.15, 12.0],
	}
	for base_class in expected:
		var profile := tuning.get_profile(base_class)
		var values: Array = expected[base_class]
		if (
			int(profile.get("charges", 0)) != values[0]
			or String(profile.get("movement_type", "")) != values[1]
			or not is_equal_approx(float(profile.get("distance_spacings", 0.0)), values[2])
			or not is_equal_approx(float(profile.get("duration", 0.0)), values[3])
			or not is_equal_approx(float(profile.get("recharge", 0.0)), values[4])
		):
			failures.append("The %s dodge profile changed during migration." % base_class)


func _validate_representative_consumers(
	catalog: TuningCatalogResource, failures: Array[String]
) -> void:
	if GameState.MAX_RAID_SIZE != catalog.raid_campaign.maximum_raid_size:
		failures.append("GameState did not obtain the raid size from the catalog.")
	if CampaignState.ACTIVE_RAID_SIZE != catalog.raid_campaign.maximum_raid_size:
		failures.append("CampaignState did not obtain the active raid size from the catalog.")
	if not is_equal_approx(
		CombatMeasurementsScript.PIXELS_PER_RANGE_UNIT,
		catalog.combat.pixels_per_range_unit
	):
		failures.append("Combat measurements did not obtain range conversion from the catalog.")
	if not is_equal_approx(
		MovementSlotResolverScript.RAIDER_FORMATION_SPACING_PIXELS,
		catalog.combat.raider_formation_spacing_pixels
	):
		failures.append("Formation spacing did not come from the catalog.")
	var voice_capture := VoiceCaptureController.new()
	if not is_equal_approx(voice_capture.max_record_seconds, catalog.voice.max_record_seconds):
		failures.append("Voice capture did not obtain its recording limit from the catalog.")
	voice_capture.free()
	if not is_equal_approx(
		catalog.camp.conversations.first_conversation_delay_seconds, 14.0
	):
		failures.append("Camp conversation timing changed during migration.")
	if catalog.camp.get_facility_interaction_radius("command_tent") != 225.0:
		failures.append("The command-tent interaction radius changed during migration.")
	if catalog.runtime_limits.combat_log_entries != 10000:
		failures.append("The combat log capacity changed during migration.")


func _validate_invalid_fixtures(
	catalog: TuningCatalogResource, failures: Array[String]
) -> void:
	var missing_domain := TuningCatalogResource.new()
	_expect_error(missing_domain.get_validation_errors(), "raid_campaign tuning resource is missing", failures)

	var invalid_raid := catalog.raid_campaign.duplicate(true) as RaidCampaignTuning
	invalid_raid.maximum_raid_size = 21
	_expect_error(invalid_raid.get_validation_errors(), "evenly divisible", failures)
	_expect_error(invalid_raid.get_validation_errors(), "complete maximum-size raid", failures)

	invalid_raid = catalog.raid_campaign.duplicate(true) as RaidCampaignTuning
	invalid_raid.campaign_cast_size = 59
	_expect_error(invalid_raid.get_validation_errors(), "campaign_class_requirements must total", failures)

	invalid_raid = catalog.raid_campaign.duplicate(true) as RaidCampaignTuning
	invalid_raid.quarters_room_count = 1
	_expect_error(invalid_raid.get_validation_errors(), "quarters capacity", failures)

	var invalid_combat := catalog.combat.duplicate(true) as CombatTuning
	invalid_combat.pixels_per_range_unit = 0.0
	invalid_combat.mid_range_units = invalid_combat.close_range_units
	_expect_error(invalid_combat.get_validation_errors(), "pixels_per_range_unit", failures)
	_expect_error(invalid_combat.get_validation_errors(), "strictly increasing", failures)

	var invalid_dodge := catalog.dodge.duplicate(true) as DodgeTuningResource
	invalid_dodge.profiles = []
	_expect_error(invalid_dodge.get_validation_errors(), "missing required dodge class 'warrior'", failures)
	var unknown_profile := DodgeProfileTuning.new()
	unknown_profile.base_class = "bard"
	unknown_profile.charges = 1
	unknown_profile.movement_type = "physical"
	unknown_profile.distance_spacings = 1.0
	unknown_profile.duration_seconds = 0.0
	unknown_profile.recharge_seconds = 1.0
	invalid_dodge.profiles = [unknown_profile]
	_expect_error(invalid_dodge.get_validation_errors(), "unknown dodge class 'bard'", failures)
	_expect_error(invalid_dodge.get_validation_errors(), "duration_seconds must be greater", failures)

	var invalid_camp := catalog.camp.duplicate(true) as CampTuning
	invalid_camp.facility_interaction_radii_pixels = (
		catalog.camp.facility_interaction_radii_pixels.duplicate(true)
	)
	invalid_camp.facility_interaction_radii_pixels.erase("archive")
	invalid_camp.facility_interaction_radii_pixels["unknown_hall"] = 100.0
	_expect_error(invalid_camp.get_validation_errors(), "missing 'archive'", failures)
	_expect_error(invalid_camp.get_validation_errors(), "unknown facility 'unknown_hall'", failures)
	var invalid_conversations := catalog.camp.conversations.duplicate(true) as CampConversationTuning
	invalid_conversations.minimum_cooldown_seconds = 90.0
	invalid_camp.conversations = invalid_conversations
	_expect_error(invalid_camp.get_validation_errors(), "minimum <= baseline <= maximum", failures)
	var invalid_activities := catalog.camp.activities.duplicate(true) as CampActivityTuning
	invalid_activities.shared_activity_chance = 1.1
	invalid_camp.activities = invalid_activities
	_expect_error(invalid_camp.get_validation_errors(), "shared_activity_chance must be in [0, 1]", failures)

	var invalid_voice := catalog.voice.duplicate(true) as VoiceTuning
	invalid_voice.min_record_seconds = invalid_voice.max_record_seconds + 1.0
	invalid_voice.target_peak = 1.1
	invalid_voice.decoder_weight_validity = 0.04
	invalid_voice.identity_partial_evidence_weight = 0.09
	invalid_voice.target_category_priors = invalid_voice.target_category_priors.duplicate(true)
	invalid_voice.target_category_priors["unknown_target"] = 0.0
	_expect_error(invalid_voice.get_validation_errors(), "min_record_seconds must not exceed", failures)
	_expect_error(invalid_voice.get_validation_errors(), "target_peak must be in [0, 1]", failures)
	_expect_error(invalid_voice.get_validation_errors(), "decoder evidence weights must total 1.0", failures)
	_expect_error(invalid_voice.get_validation_errors(), "resolver identity weights must total 1.0", failures)
	_expect_error(invalid_voice.get_validation_errors(), "unknown target type", failures)

	var invalid_limits := catalog.runtime_limits.duplicate(true) as RuntimeLimitsTuning
	invalid_limits.projectile_pool_capacity = 0
	_expect_error(invalid_limits.get_validation_errors(), "projectile_pool_capacity", failures)


func _validate_legacy_modules_removed(failures: Array[String]) -> void:
	for path in [
		"res://scripts/combat/dodge_tuning.gd",
		"res://scripts/core/camp_v2_tuning.gd",
		"res://scripts/voice/command_decoder_tuning.gd",
		"res://scripts/voice/who_resolver_tuning.gd",
	]:
		if FileAccess.file_exists(path):
			failures.append("Legacy tuning module still exists: %s" % path)


func _expect_error(
	errors: PackedStringArray, expected_fragment: String, failures: Array[String]
) -> void:
	for validation_error in errors:
		if validation_error.contains(expected_fragment):
			return
	failures.append(
		"Invalid tuning did not report '%s'. Actual errors: %s"
		% [expected_fragment, "; ".join(errors)]
	)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("RAID_TEST_PASS:tuning_catalog_contract | Tuning catalog contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
