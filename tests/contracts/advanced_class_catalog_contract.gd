extends Node

const RaiderClassCatalogScript := preload(
	"res://scripts/data/raider_class_catalog.gd"
)
const TrainingProgressionCatalogScript := preload(
	"res://scripts/data/training_progression_catalog.gd"
)
const FixtureRuntimeScript := preload(
	"res://tests/fixtures/advanced_class_runtime_fixture.gd"
)


func _ready() -> void:
	var failures: Array[String] = []
	var advanced := RaiderClassCatalogScript.get_definition("Hollow Anvil")
	if RaiderClassCatalogScript.get_all_class_ids().size() != 20:
		failures.append("The catalog does not contain four base and sixteen advanced classes.")
	if not RaiderClassCatalogScript.validate_specialization_catalog().is_empty():
		failures.append(
			"The specialization catalog is invalid: %s"
			% RaiderClassCatalogScript.validate_specialization_catalog()
		)
	if RaiderClassCatalogScript.get_all_lineage_definitions().size() != 16:
		failures.append("The catalog does not contain sixteen secondary lineages.")
	if not TrainingProgressionCatalogScript.validate_catalog().is_empty():
		failures.append(
			"The 16-lineage Training tree catalog is invalid: %s"
			% TrainingProgressionCatalogScript.validate_catalog()
		)
	for base_class_id in RaiderClassCatalogScript.get_base_class_ids():
		if RaiderClassCatalogScript.get_lineages_for_base_class(base_class_id).size() != 4:
			failures.append("Base class '%s' does not expose four lineages." % base_class_id)
	if String(advanced.get("parent_class_id", "")) != "warrior":
		failures.append("Advanced-class parent metadata did not normalize through the catalog.")
	if String(advanced.get("secondary_archetype_id", "")) != "warrior":
		failures.append("Advanced-class secondary-archetype metadata is missing.")
	if RaiderClassCatalogScript.get_roles("sunder_clerk") != ["dps"]:
		failures.append("Sunder Clerk did not retain its authoritative DPS role.")
	if RaiderClassCatalogScript.get_roles("rift_tailor") != ["dps", "support"]:
		failures.append("Rift Tailor did not retain its DPS/support role.")
	var hollow_lineage := RaiderClassCatalogScript.get_lineage_definition(
		"Hollow Anvil Lineage"
	)
	if (
		String(hollow_lineage.get("advanced_class_id", "")) != "hollow_anvil"
		or float(hollow_lineage.get("passive_effect", {}).get("tuning", {}).get(
			"stationary_seconds", 0.0
		)) != 3.0
		or bool(hollow_lineage.get("combat_effect_active", true))
	):
		failures.append("Hollow Anvil lineage metadata is incomplete or combat-active.")
	if Dictionary(hollow_lineage.get("stat_modifiers", {})).is_empty():
		failures.append("Hollow Anvil lineage has no immediate minor stat benefit.")
	for open_lineage_id in ["gravelord_proxy", "rift_tailor"]:
		var open_lineage := RaiderClassCatalogScript.get_lineage_definition(open_lineage_id)
		if (
			String(open_lineage.get("design_status", "")) != "open"
			or not Dictionary(open_lineage.get("passive_effect", {})).is_empty()
		):
			failures.append("Open lineage '%s' invented a passive effect." % open_lineage_id)
	if String(
		RaiderClassCatalogScript.get_lineage_definition("scar_gardener").get(
			"design_status", ""
		)
	) != "seed":
		failures.append("Scar Gardener did not remain a provisional conceptual seed.")
	if not RaiderClassCatalogScript.get_voice_aliases("hollow_anvil").has("hollow anvil"):
		failures.append("Advanced-class voice aliases are missing from the catalog.")
	if not RaiderClassCatalogScript.register_runtime_script("hollow_anvil", FixtureRuntimeScript):
		failures.append("An advanced runtime could not be registered through the public seam.")

	var unit := BaseCombatUnit.new()
	add_child(unit)
	unit.configure_from_definition(RaiderClassCatalogScript.get_unit_definition("warrior"))
	unit.setup_unit_identity("Warrior", 1)
	unit.set_advanced_class_id("Hollow Anvil")
	if unit.get_advanced_class_capabilities() != ["fixture_capability"]:
		failures.append("The registered advanced runtime was not attached by BaseCombatUnit.")

	RaiderClassCatalogScript.clear_runtime_script("hollow_anvil")
	unit.queue_free()
	if failures.is_empty():
		print("RAID_TEST_PASS:advanced_class_catalog_contract | Advanced-class catalog/runtime contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
