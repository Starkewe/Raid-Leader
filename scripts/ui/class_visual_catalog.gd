extends RefCounted
class_name ClassVisualCatalog


const ClassVisualDefinitionScript := preload(
	"res://scripts/data/class_visual_definition.gd"
)

const BASE_CLASS_ORDER: Array[String] = [
	"warrior",
	"rogue",
	"mage",
	"priest"
]

const ADVANCED_CLASS_ORDER: Array[String] = [
	"hollow_anvil",
	"gravelord_proxy",
	"sunder_clerk",
	"lantern_warden",
	"burden_courier",
	"memory_apothecary",
	"scar_gardener",
	"moth_surgeon",
	"echo_butcher",
	"ritebreaker",
	"drift_knife",
	"phasehand",
	"hearth_corsair",
	"rift_tailor",
	"rune_slinger",
	"orbit_scribe"
]

const ICON_ROOT := "res://icons/class_visuals/"
const COMPACT_ICON_ROOT := "res://icons/class_visuals/compact/"
const NEUTRAL_MAIN_COLOR := Color(0.28, 0.30, 0.33, 1.0)
const NEUTRAL_ACCENT_COLOR := Color(0.0, 0.0, 0.0, 0.0)

static var _definitions: Dictionary = {}
static var _aliases: Dictionary = {}
static var _neutral_definition: ClassVisualDefinition = null


static func get_definition(class_id: String) -> ClassVisualDefinition:
	_ensure_catalog()
	return _definitions.get(_normalize_lookup(class_id)) as ClassVisualDefinition


static func resolve_for_unit(
	base_class_id: String,
	advanced_class_id: String = ""
) -> ClassVisualDefinition:
	_ensure_catalog()

	var base_id := _normalize_lookup(base_class_id)
	var advanced_id := _normalize_lookup(advanced_class_id)
	var advanced := _definitions.get(advanced_id) as ClassVisualDefinition

	if advanced != null:
		if base_id.is_empty() or advanced.primary_class == base_id:
			return advanced

	var base := get_base_definition(base_id)
	return base


static func get_base_definition(class_id: String) -> ClassVisualDefinition:
	_ensure_catalog()

	var normalized := _normalize_lookup(class_id)
	var definition := _definitions.get(normalized) as ClassVisualDefinition

	if definition == null:
		return null

	if definition.secondary_class.is_empty():
		return definition

	return _definitions.get(definition.primary_class) as ClassVisualDefinition


static func get_neutral_definition() -> ClassVisualDefinition:
	_ensure_catalog()

	if _neutral_definition == null:
		_neutral_definition = ClassVisualDefinitionScript.new(
			"neutral",
			"Unknown Class",
			"",
			"",
			NEUTRAL_MAIN_COLOR,
			NEUTRAL_ACCENT_COLOR,
			null,
			null
		)

	return _neutral_definition


static func get_all_definitions() -> Array[ClassVisualDefinition]:
	_ensure_catalog()
	var result: Array[ClassVisualDefinition] = []

	for class_id in BASE_CLASS_ORDER + ADVANCED_CLASS_ORDER:
		var definition := _definitions.get(class_id) as ClassVisualDefinition

		if definition != null:
			result.append(definition)

	return result


static func get_base_definitions() -> Array[ClassVisualDefinition]:
	_ensure_catalog()
	var result: Array[ClassVisualDefinition] = []

	for class_id in BASE_CLASS_ORDER:
		var definition := _definitions.get(class_id) as ClassVisualDefinition

		if definition != null:
			result.append(definition)

	return result


static func get_advanced_definitions() -> Array[ClassVisualDefinition]:
	_ensure_catalog()
	var result: Array[ClassVisualDefinition] = []

	for class_id in ADVANCED_CLASS_ORDER:
		var definition := _definitions.get(class_id) as ClassVisualDefinition

		if definition != null:
			result.append(definition)

	return result


static func get_all_class_ids() -> Array[String]:
	return (BASE_CLASS_ORDER + ADVANCED_CLASS_ORDER).duplicate()


static func is_advanced_class_id(class_id: String) -> bool:
	return ADVANCED_CLASS_ORDER.has(_normalize_lookup(class_id))


static func normalize_class_id(class_id: String) -> String:
	_ensure_catalog()
	var normalized := _normalize_lookup(class_id)
	return String(_aliases.get(normalized, normalized))


static func _ensure_catalog() -> void:
	if not _definitions.is_empty():
		return

	_register_base("warrior", "Warrior", "#B86A3C", "icon_warrior.png")
	_register_base("rogue", "Rogue", "#9A4FB5", "icon_rogue.png")
	_register_base("mage", "Mage", "#3F86D6", "icon_mage.png")
	_register_base("priest", "Priest", "#4FAE62", "icon_priest.png")

	_register_advanced(
		"hollow_anvil", "Hollow Anvil", "warrior", "#6F3325", "#D97A2B"
	)
	_register_advanced(
		"gravelord_proxy", "Gravelord Proxy", "warrior", "#D6A277", "#C9C1B1"
	)
	_register_advanced(
		"sunder_clerk", "Sunder Clerk", "warrior", "#B34B32", "#C9A23A"
	)
	_register_advanced(
		"lantern_warden", "Lantern Warden", "warrior", "#A76548", "#F2C14E"
	)

	_register_advanced(
		"burden_courier", "Burden Courier", "priest", "#225A3A", "#A88E52"
	)
	_register_advanced(
		"memory_apothecary", "Memory Apothecary", "priest", "#A9D592", "#D8C35A"
	)
	_register_advanced(
		"scar_gardener", "Scar Gardener", "priest", "#18B865", "#B33A4A"
	)
	_register_advanced(
		"moth_surgeon", "Moth Surgeon", "priest", "#268F82", "#E7DFC8"
	)

	_register_advanced(
		"echo_butcher", "Echo Butcher", "rogue", "#4B214F", "#C13A4A"
	)
	_register_advanced(
		"ritebreaker", "Ritebreaker", "rogue", "#C79DD4", "#E4E1F0"
	)
	_register_advanced(
		"drift_knife", "Drift Knife", "rogue", "#D62A91", "#C8D2DC"
	)
	_register_advanced(
		"phasehand", "Phasehand", "rogue", "#7A43D1", "#7FD9FF"
	)

	_register_advanced(
		"hearth_corsair", "Hearth Corsair", "mage", "#203F66", "#E88932"
	)
	_register_advanced(
		"rift_tailor", "Rift Tailor", "mage", "#98C6EA", "#7C63D9"
	)
	_register_advanced(
		"rune_slinger", "Rune Slinger", "mage", "#10B7E8", "#F2D15B"
	)
	_register_advanced(
		"orbit_scribe", "Orbit Scribe", "mage", "#3B6FE3", "#F3C24B"
	)

	_register_aliases()


static func _register_base(
	class_id: String,
	display_name: String,
	main_color_hex: String,
	icon_name: String
) -> void:
	_register(
		ClassVisualDefinitionScript.new(
			class_id,
			display_name,
			class_id,
			"",
			Color(main_color_hex),
			NEUTRAL_ACCENT_COLOR,
			_load_icon(icon_name),
			_load_compact_icon(icon_name)
		)
	)


static func _register_advanced(
	class_id: String,
	display_name: String,
	primary_class: String,
	main_color_hex: String,
	accent_color_hex: String
) -> void:
	_register(
		ClassVisualDefinitionScript.new(
			class_id,
			display_name,
			primary_class,
			class_id,
			Color(main_color_hex),
			Color(accent_color_hex),
			_load_icon("icon_" + class_id + ".png"),
			_load_compact_icon("icon_" + class_id + ".png")
		)
	)


static func _register(definition: ClassVisualDefinition) -> void:
	_definitions[definition.class_id] = definition
	_aliases[_normalize_lookup(definition.display_name)] = definition.class_id


static func _register_aliases() -> void:
	for class_id in BASE_CLASS_ORDER:
		_aliases[class_id.capitalize()] = class_id


static func _load_icon(icon_name: String) -> Texture2D:
	return load(ICON_ROOT + icon_name) as Texture2D


static func _load_compact_icon(icon_name: String) -> Texture2D:
	return load(COMPACT_ICON_ROOT + icon_name) as Texture2D


static func _normalize_lookup(value: String) -> String:
	return value.to_lower().strip_edges().replace(" ", "_").replace("-", "_")
