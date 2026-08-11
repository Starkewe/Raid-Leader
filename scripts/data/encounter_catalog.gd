extends RefCounted
class_name EncounterCatalog

const NORMAL_ORDER: Array[String] = [
	"ogre", "chainmaster", "carrion_roc", "twin_maulers"
]
const TUTORIAL_ORDER: Array[String] = [
	"cleave_close_region", "long_region_cone", "twin_sweeping_pull"
]

const DEFINITIONS := {
	"ogre": preload("res://data/encounters/ogre.tres"),
	"chainmaster": preload("res://data/encounters/chainmaster.tres"),
	"carrion_roc": preload("res://data/encounters/carrion_roc.tres"),
	"twin_maulers": preload("res://data/encounters/twin_maulers.tres"),
	"cleave_close_region": preload("res://data/encounters/cleave_close_region.tres"),
	"long_region_cone": preload("res://data/encounters/full_region_cone.tres"),
	"twin_sweeping_pull": preload("res://data/encounters/twin_sweeping_pull.tres"),
}

# Target vocabulary and command presentation belong to the encounter that
# introduces a target. Generic voice, UI, and command code only consume these
# descriptors and never branch on encounter IDs.
const TARGETS := {
	"carrion_roc": [
		{
			"display_name": "East Growth",
			"selector": {"kind": "carrion_growth", "side": "east"},
			"actions": ["attack"],
			"aliases": [
				"east growth", "the east growth", "east carrion growth",
				"the east carrion growth", "east add", "the east add"
			],
			"decoder_aliases": ["east growth"]
		},
		{
			"display_name": "West Growth",
			"selector": {"kind": "carrion_growth", "side": "west"},
			"actions": ["attack"],
			"aliases": [
				"west growth", "the west growth", "west carrion growth",
				"the west carrion growth", "west add", "the west add"
			],
			"decoder_aliases": ["west growth"]
		},
		{
			"display_name": "The Growth (unambiguous side)",
			"selector": {"kind": "carrion_growth"},
			"actions": ["attack"],
			"aliases": [
				"growth", "the growth", "carrion growth", "the carrion growth",
				"add", "the add"
			],
			"decoder_aliases": ["the growth"]
		}
	],
	"twin_maulers": [
		{
			"display_name": "West Mauler",
			"selector": {"kind": "twin_mauler", "side": "west"},
			"actions": ["attack", "taunt"],
			"aliases": [
				"west mauler", "the west mauler", "west twin", "the west twin",
				"left mauler", "the left mauler", "mauler a", "the mauler a",
				"west beast", "the west beast"
			],
			"decoder_aliases": ["west mauler", "left mauler", "mauler a"]
		},
		{
			"display_name": "East Mauler",
			"selector": {"kind": "twin_mauler", "side": "east"},
			"actions": ["attack", "taunt"],
			"aliases": [
				"east mauler", "the east mauler", "east twin", "the east twin",
				"right mauler", "the right mauler", "mauler b", "the mauler b",
				"east beast", "the east beast"
			],
			"decoder_aliases": ["east mauler", "right mauler", "mauler b"]
		}
	]
}

const QUALIFIED_PRIMARY_ENCOUNTERS: Array[String] = ["twin_maulers"]


static func get_definition(encounter_id: String) -> EncounterDefinition:
	return DEFINITIONS.get(encounter_id) as EncounterDefinition


static func get_normal_ids() -> Array[String]:
	return NORMAL_ORDER.duplicate()


static func get_tutorial_ids() -> Array[String]:
	return TUTORIAL_ORDER.duplicate()


static func get_all_ids() -> Array[String]:
	var result := get_normal_ids()
	for encounter_id in TUTORIAL_ORDER:
		if not result.has(encounter_id):
			result.append(encounter_id)
	return result


static func is_normal(encounter_id: String) -> bool:
	return NORMAL_ORDER.has(encounter_id)


static func requires_qualified_primary(encounter_id: String) -> bool:
	return QUALIFIED_PRIMARY_ENCOUNTERS.has(encounter_id)


static func get_target_definitions(encounter_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var encounter_ids: Array[String] = []
	if encounter_id.is_empty():
		for key in TARGETS.keys():
			encounter_ids.append(String(key))
	else:
		encounter_ids.append(encounter_id)

	for current_id in encounter_ids:
		for value in TARGETS.get(current_id, []):
			var target: Dictionary = Dictionary(value).duplicate(true)
			target["encounter_id"] = current_id
			result.append(target)
	return result


static func get_voice_target_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for target in get_target_definitions():
		for alias_value in target.get("decoder_aliases", target.get("aliases", [])):
			result.append({
				"alias": String(alias_value),
				"actions": Array(target.get("actions", [])).duplicate(),
				"selector": Dictionary(target.get("selector", {})).duplicate(true),
				"encounter_id": String(target.get("encounter_id", "")),
			})
	return result


static func resolve_target_alias(alias: String) -> Dictionary:
	var normalized := alias.to_lower().strip_edges()
	for target in get_target_definitions():
		for alias_value in target.get("aliases", []):
			if String(alias_value) == normalized:
				return Dictionary(target.get("selector", {})).duplicate(true)
	return {}
