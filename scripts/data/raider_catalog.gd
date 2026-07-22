extends RefCounted
class_name RaiderCatalog

const MasterRaiderDefinitionScript := preload(
	"res://scripts/data/master_raider_definition.gd"
)
const CATALOG_PATH := "res://data/raiders/master_raiders.json"

static var _loaded: bool = false
static var _catalog_version: int = 0
static var _definitions_by_id: Dictionary = {}
static var _ordered_ids: Array[String] = []
static var _warnings: Array[String] = []


static func get_catalog_version() -> int:
	_ensure_loaded()
	return _catalog_version


static func get_all_definitions() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []

	for raider_id in _ordered_ids:
		result.append(Dictionary(_definitions_by_id[raider_id]).duplicate(true))

	return result


static func get_definition(raider_id: String) -> Dictionary:
	_ensure_loaded()

	if not _definitions_by_id.has(raider_id):
		return {}

	return Dictionary(_definitions_by_id[raider_id]).duplicate(true)


static func has_definition(raider_id: String) -> bool:
	_ensure_loaded()
	return _definitions_by_id.has(raider_id)


static func get_warnings() -> Array[String]:
	_ensure_loaded()
	return _warnings.duplicate()


static func _ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)

	if file == null:
		_warnings.append("Master raider catalog could not be opened: " + CATALOG_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		_warnings.append("Master raider catalog is not a JSON object: " + CATALOG_PATH)
		return

	var catalog: Dictionary = parsed
	_catalog_version = int(catalog.get("catalog_version", 0))
	var defaults: Dictionary = _dictionary(catalog.get("defaults", {}))
	var class_defaults: Dictionary = _dictionary(catalog.get("class_defaults", {}))
	var entries_value: Variant = catalog.get("raiders", [])

	if not entries_value is Array:
		_warnings.append("Master raider catalog has no raiders array.")
		return

	for entry_value in entries_value:
		if not entry_value is Dictionary:
			_warnings.append("Master raider catalog contains a non-object entry.")
			continue

		var entry: Dictionary = entry_value
		var merged := defaults.duplicate(true)
		var unit_class := String(entry.get("default_class", "Mage"))

		if class_defaults.has(unit_class) and class_defaults[unit_class] is Dictionary:
			_deep_merge(merged, Dictionary(class_defaults[unit_class]))

		_deep_merge(merged, entry)
		var definition: Dictionary = MasterRaiderDefinitionScript.sanitize(merged)
		var raider_id := String(definition.get("raider_id", ""))

		if raider_id.is_empty():
			_warnings.append("Master raider definition is missing raider_id.")
			continue

		if _definitions_by_id.has(raider_id):
			_warnings.append("Duplicate master raider_id: " + raider_id)
			continue

		_definitions_by_id[raider_id] = definition
		_ordered_ids.append(raider_id)

	_ordered_ids.sort_custom(
		func(a: String, b: String) -> bool:
			var a_order := int(_definitions_by_id[a].get("catalog_order", 0))
			var b_order := int(_definitions_by_id[b].get("catalog_order", 0))
			return a < b if a_order == b_order else a_order < b_order
	)


static func _deep_merge(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		if target.get(key) is Dictionary and source[key] is Dictionary:
			var nested: Dictionary = Dictionary(target[key]).duplicate(true)
			_deep_merge(nested, Dictionary(source[key]))
			target[key] = nested
		else:
			target[key] = source[key]


static func _dictionary(value: Variant) -> Dictionary:
	return Dictionary(value).duplicate(true) if value is Dictionary else {}
