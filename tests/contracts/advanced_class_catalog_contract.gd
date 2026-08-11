extends Node

const RaiderClassCatalogScript := preload(
	"res://scripts/data/raider_class_catalog.gd"
)
const FixtureRuntimeScript := preload(
	"res://tests/fixtures/advanced_class_runtime_fixture.gd"
)


func _ready() -> void:
	var failures: Array[String] = []
	var advanced := RaiderClassCatalogScript.get_definition("Hollow Anvil")
	if RaiderClassCatalogScript.get_all_class_ids().size() != 20:
		failures.append("The catalog does not contain four base and sixteen advanced classes.")
	if String(advanced.get("parent_class_id", "")) != "warrior":
		failures.append("Advanced-class parent metadata did not normalize through the catalog.")
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
