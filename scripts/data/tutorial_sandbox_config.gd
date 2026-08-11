extends RefCounted
class_name TutorialSandboxConfig

const EncounterCatalogScript := preload("res://scripts/data/encounter_catalog.gd")
const RaiderClassCatalogScript := preload(
	"res://scripts/data/raider_class_catalog.gd"
)
const ROSTER := {
	"Warrior": 2,
	"Priest": 5,
	"Rogue": 6,
	"Mage": 7,
}


static func get_roster() -> Dictionary:
	return ROSTER.duplicate(true)


static func get_encounter_ids() -> Array[String]:
	return EncounterCatalogScript.get_tutorial_ids()


static func get_roster_summary() -> String:
	var parts: Array[String] = []
	for unit_class in RaiderClassCatalogScript.get_campaign_generation_class_names():
		var count := int(ROSTER.get(unit_class, 0))
		if count > 0:
			parts.append("%d %s%s" % [count, unit_class, "" if count == 1 else "s"])
	return " · ".join(parts)
