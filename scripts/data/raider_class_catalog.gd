extends RefCounted
class_name RaiderClassCatalog

const ClassVisualDefinitionScript := preload(
	"res://scripts/data/class_visual_definition.gd"
)

const UNIT_DEFINITIONS: Array[UnitDefinition] = [
	preload("res://data/units/warrior.tres"),
	preload("res://data/units/rogue.tres"),
	preload("res://data/units/mage.tres"),
	preload("res://data/units/priest.tres"),
]
const BASE_CLASS_ORDER: Array[String] = ["warrior", "rogue", "mage", "priest"]
const ADVANCED_CLASS_ORDER: Array[String] = [
	"hollow_anvil", "gravelord_proxy", "sunder_clerk", "lantern_warden",
	"burden_courier", "memory_apothecary", "scar_gardener", "moth_surgeon",
	"echo_butcher", "ritebreaker", "drift_knife", "phasehand",
	"hearth_corsair", "rift_tailor", "rune_slinger", "orbit_scribe",
]
const ICON_ROOT := "res://icons/class_visuals/"
const COMPACT_ICON_ROOT := "res://icons/class_visuals/compact/"
const DEFAULT_WEAPON_ICON_ROOT := "res://icons/weapon_visuals/defaults/"
const DEFAULT_WEAPON_FAMILY_BY_CLASS: Dictionary = {
	"warrior": "one_handed_arms",
	"rogue": "skirmishing_arms",
	"mage": "battle_staves",
	"priest": "conduit_staves",
	"hollow_anvil": "heavy_arms",
	"gravelord_proxy": "heavy_arms",
	"sunder_clerk": "one_handed_arms",
	"lantern_warden": "arcane_foci",
	"burden_courier": "conduit_staves",
	"memory_apothecary": "conduit_staves",
	"scar_gardener": "skirmishing_arms",
	"moth_surgeon": "conduit_staves",
	"echo_butcher": "skirmishing_arms",
	"ritebreaker": "ritual_implements",
	"drift_knife": "projectile_arms",
	"phasehand": "skirmishing_arms",
	"hearth_corsair": "one_handed_arms",
	"rift_tailor": "ritual_implements",
	"rune_slinger": "projectile_arms",
	"orbit_scribe": "battle_staves",
}
const NEUTRAL_MAIN_COLOR := Color(0.28, 0.30, 0.33, 1.0)
const NEUTRAL_ACCENT_COLOR := Color(0.0, 0.0, 0.0, 0.0)

static var _definitions: Dictionary = {}
static var _aliases: Dictionary = {}
static var _neutral_visual: ClassVisualDefinition = null


static func get_definition(class_id: String) -> Dictionary:
	_ensure_catalog()
	var canonical := normalize_class_id(class_id)
	return Dictionary(_definitions.get(canonical, {})).duplicate(true)


static func get_base_class_ids() -> Array[String]:
	return BASE_CLASS_ORDER.duplicate()


static func get_base_class_names() -> Array[String]:
	_ensure_catalog()
	var result: Array[String] = []
	for class_id in BASE_CLASS_ORDER:
		var definition: Dictionary = _definitions[class_id]
		result.append(String(definition.get("unit_class", "")))
	return result


static func get_campaign_generation_class_names() -> Array[String]:
	_ensure_catalog()
	var ids := BASE_CLASS_ORDER.duplicate()
	ids.sort_custom(
		func(a: String, b: String) -> bool:
			return int(_definitions[a].get("campaign_generation_order", 0)) < int(
				_definitions[b].get("campaign_generation_order", 0)
			)
	)
	var result: Array[String] = []
	for class_id in ids:
		result.append(String(_definitions[class_id].get("unit_class", "")))
	return result


static func get_all_class_ids() -> Array[String]:
	return (BASE_CLASS_ORDER + ADVANCED_CLASS_ORDER).duplicate()


static func get_all_definitions() -> Array[Dictionary]:
	_ensure_catalog()
	var result: Array[Dictionary] = []
	for class_id in BASE_CLASS_ORDER + ADVANCED_CLASS_ORDER:
		result.append(Dictionary(_definitions[class_id]).duplicate(true))
	return result


static func get_advanced_classes_for_parent(parent_class: String) -> Array[Dictionary]:
	_ensure_catalog()
	var parent_id := normalize_class_id(parent_class)
	var result: Array[Dictionary] = []
	for class_id in ADVANCED_CLASS_ORDER:
		var definition: Dictionary = _definitions[class_id]
		if String(definition.get("parent_class_id", "")) == parent_id:
			result.append(definition.duplicate(true))
	return result


static func normalize_class_id(class_id: String) -> String:
	_ensure_catalog()
	var normalized := _normalize_lookup(class_id)
	return String(_aliases.get(normalized, normalized))


static func is_advanced_class_id(class_id: String) -> bool:
	return ADVANCED_CLASS_ORDER.has(normalize_class_id(class_id))


static func get_unit_definition(class_id: String) -> UnitDefinition:
	var definition := get_definition(class_id)
	return definition.get("unit_definition") as UnitDefinition


static func get_roles(class_id: String) -> Array[String]:
	var definition := get_definition(class_id)
	var result: Array[String] = []
	for role in definition.get("roles", []):
		result.append(String(role))
	return result


static func get_voice_aliases(class_id: String) -> Array[String]:
	var definition := get_definition(class_id)
	var result: Array[String] = []
	for alias in definition.get("voice_aliases", []):
		result.append(String(alias))
	return result


static func get_voice_entries(include_advanced: bool = false) -> Array[Dictionary]:
	_ensure_catalog()
	var ids: Array[String] = []
	ids.append_array(BASE_CLASS_ORDER)
	if include_advanced:
		ids.append_array(ADVANCED_CLASS_ORDER)
	var result: Array[Dictionary] = []
	for class_id in ids:
		var definition: Dictionary = _definitions[class_id]
		result.append({
			"class_id": class_id,
			"unit_class": String(definition.get("unit_class", "")),
			"aliases": Array(definition.get("voice_aliases", [])).duplicate(),
		})
	return result


static func get_visual_definition(class_id: String) -> ClassVisualDefinition:
	var definition := get_definition(class_id)
	return definition.get("visual") as ClassVisualDefinition


static func get_camp_color(class_id: String) -> Color:
	var definition := get_definition(class_id)
	return definition.get("camp_color", Color("79818a")) as Color


static func get_default_weapon_icon(class_id: String) -> Texture2D:
	var definition := get_definition(class_id)
	return definition.get("default_weapon_icon") as Texture2D


static func get_default_weapon_family_id(class_id: String) -> String:
	var definition := get_definition(class_id)
	return String(definition.get("default_weapon_family_id", ""))


static func resolve_visual(
	base_class_id: String, advanced_class_id: String = ""
) -> ClassVisualDefinition:
	var base_id := normalize_class_id(base_class_id)
	var advanced_id := normalize_class_id(advanced_class_id)
	if ADVANCED_CLASS_ORDER.has(advanced_id):
		var advanced: Dictionary = _definitions.get(advanced_id, {})
		if base_id.is_empty() or String(advanced.get("parent_class_id", "")) == base_id:
			return advanced.get("visual") as ClassVisualDefinition
	return get_visual_definition(base_id)


static func get_runtime_script(class_id: String) -> Script:
	var definition := get_definition(class_id)
	return definition.get("runtime_script") as Script


static func register_runtime_script(class_id: String, runtime_script: Script) -> bool:
	_ensure_catalog()
	var canonical := normalize_class_id(class_id)
	if not ADVANCED_CLASS_ORDER.has(canonical) or runtime_script == null:
		return false
	var definition: Dictionary = _definitions[canonical]
	definition["runtime_script"] = runtime_script
	_definitions[canonical] = definition
	return true


static func clear_runtime_script(class_id: String) -> void:
	_ensure_catalog()
	var canonical := normalize_class_id(class_id)
	if not _definitions.has(canonical):
		return
	var definition: Dictionary = _definitions[canonical]
	definition["runtime_script"] = null
	_definitions[canonical] = definition


static func get_neutral_visual_definition() -> ClassVisualDefinition:
	if _neutral_visual == null:
		_neutral_visual = ClassVisualDefinitionScript.new(
			"neutral", "Unknown Class", "", "", NEUTRAL_MAIN_COLOR,
			NEUTRAL_ACCENT_COLOR, null, null
		)
	return _neutral_visual


static func _ensure_catalog() -> void:
	if not _definitions.is_empty():
		return

	_register_base(UNIT_DEFINITIONS[0], "#B86A3C", "#9c5650", "icon_warrior.png", 0)
	_register_base(UNIT_DEFINITIONS[1], "#9A4FB5", "#677d55", "icon_rogue.png", 2)
	_register_base(UNIT_DEFINITIONS[2], "#3F86D6", "#5c6f9d", "icon_mage.png", 3)
	_register_base(UNIT_DEFINITIONS[3], "#4FAE62", "#d6c9a2", "icon_priest.png", 1)

	_register_advanced("hollow_anvil", "Hollow Anvil", "warrior", "#6F3325", "#D97A2B")
	_register_advanced("gravelord_proxy", "Gravelord Proxy", "warrior", "#D6A277", "#C9C1B1")
	_register_advanced("sunder_clerk", "Sunder Clerk", "warrior", "#B34B32", "#C9A23A")
	_register_advanced("lantern_warden", "Lantern Warden", "warrior", "#A76548", "#F2C14E")
	_register_advanced("burden_courier", "Burden Courier", "priest", "#225A3A", "#A88E52")
	_register_advanced("memory_apothecary", "Memory Apothecary", "priest", "#A9D592", "#D8C35A")
	_register_advanced("scar_gardener", "Scar Gardener", "priest", "#18B865", "#B33A4A")
	_register_advanced("moth_surgeon", "Moth Surgeon", "priest", "#268F82", "#E7DFC8")
	_register_advanced("echo_butcher", "Echo Butcher", "rogue", "#4B214F", "#C13A4A")
	_register_advanced("ritebreaker", "Ritebreaker", "rogue", "#C79DD4", "#E4E1F0")
	_register_advanced("drift_knife", "Drift Knife", "rogue", "#D62A91", "#C8D2DC")
	_register_advanced("phasehand", "Phasehand", "rogue", "#7A43D1", "#7FD9FF")
	_register_advanced("hearth_corsair", "Hearth Corsair", "mage", "#203F66", "#E88932")
	_register_advanced("rift_tailor", "Rift Tailor", "mage", "#98C6EA", "#7C63D9")
	_register_advanced("rune_slinger", "Rune Slinger", "mage", "#10B7E8", "#F2D15B")
	_register_advanced("orbit_scribe", "Orbit Scribe", "mage", "#3B6FE3", "#F3C24B")


static func _register_base(
	unit_definition: UnitDefinition, main_color_hex: String, camp_color_hex: String,
	icon_name: String, campaign_generation_order: int
) -> void:
	var class_id := _normalize_lookup(unit_definition.unit_class)
	var visual := ClassVisualDefinitionScript.new(
		class_id, unit_definition.display_name, class_id, "", Color(main_color_hex),
		NEUTRAL_ACCENT_COLOR, _load_icon(icon_name), _load_compact_icon(icon_name)
	)
	_register({
		"class_id": class_id,
		"display_name": unit_definition.display_name,
		"parent_class_id": class_id,
		"unit_class": unit_definition.unit_class,
		"unit_definition": unit_definition,
		"roles": unit_definition.roles.duplicate(),
		"voice_aliases": unit_definition.get_all_voice_aliases(),
		"visual": visual,
		"camp_color": Color(camp_color_hex),
		"campaign_generation_order": campaign_generation_order,
		"runtime_script": null,
		"default_weapon_family_id": _default_weapon_family_id(class_id),
		"default_weapon_icon": _load_default_weapon_icon(class_id),
		"advanced": false,
	})


static func _register_advanced(
	class_id: String, display_name: String, parent_class_id: String,
	main_color_hex: String, accent_color_hex: String
) -> void:
	var parent: Dictionary = _definitions[parent_class_id]
	var aliases: Array[String] = [class_id, class_id.replace("_", " "), display_name.to_lower()]
	var visual := ClassVisualDefinitionScript.new(
		class_id, display_name, parent_class_id, class_id, Color(main_color_hex),
		Color(accent_color_hex), _load_icon("icon_" + class_id + ".png"),
		_load_compact_icon("icon_" + class_id + ".png")
	)
	_register({
		"class_id": class_id,
		"display_name": display_name,
		"parent_class_id": parent_class_id,
		"unit_class": String(parent.get("unit_class", "")),
		"unit_definition": parent.get("unit_definition"),
		"roles": Array(parent.get("roles", [])).duplicate(),
		"voice_aliases": aliases,
		"visual": visual,
		"camp_color": parent.get("camp_color", visual.main_color),
		"runtime_script": null,
		"default_weapon_family_id": _default_weapon_family_id(class_id),
		"default_weapon_icon": _load_default_weapon_icon(class_id),
		"advanced": true,
	})


static func _register(definition: Dictionary) -> void:
	var class_id := String(definition.get("class_id", ""))
	_definitions[class_id] = definition
	_aliases[_normalize_lookup(class_id)] = class_id
	_aliases[_normalize_lookup(String(definition.get("display_name", class_id)))] = class_id
	for alias in definition.get("voice_aliases", []):
		_aliases[_normalize_lookup(String(alias))] = class_id


static func _load_icon(icon_name: String) -> Texture2D:
	return load(ICON_ROOT + icon_name) as Texture2D


static func _load_compact_icon(icon_name: String) -> Texture2D:
	return load(COMPACT_ICON_ROOT + icon_name) as Texture2D


static func _load_default_weapon_icon(class_id: String) -> Texture2D:
	var family_id := _default_weapon_family_id(class_id)
	if family_id.is_empty():
		return null
	return load(DEFAULT_WEAPON_ICON_ROOT + family_id + ".png") as Texture2D


static func _default_weapon_family_id(class_id: String) -> String:
	return String(DEFAULT_WEAPON_FAMILY_BY_CLASS.get(class_id, ""))


static func _normalize_lookup(value: String) -> String:
	return value.to_lower().strip_edges().replace(" ", "_").replace("-", "_")
