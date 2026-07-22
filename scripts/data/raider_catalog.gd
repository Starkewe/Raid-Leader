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
static var _validation_report: Dictionary = {}


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


static func validate_all() -> Dictionary:
	_ensure_loaded()
	return _validation_report.duplicate(true)


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
	_validation_report = _build_validation_report(catalog, entries_value)
	for error in _validation_report.get("errors", []):
		if not _warnings.has(error):
			_warnings.append(error)
	for warning in _validation_report.get("warnings", []):
		if not _warnings.has(warning):
			_warnings.append(warning)


static func _build_validation_report(catalog: Dictionary, entries: Array) -> Dictionary:
	var schema: Dictionary = _dictionary(catalog.get("authoring_schema", {}))
	var required_fields := _string_array(
		schema.get(
			"required_fields",
			[
				"raider_id",
				"display_name",
				"biography",
				"personality_tags",
				"default_class",
				"default_role",
				"catalog_order",
			]
		)
	)
	var valid_class_paths := _string_array(
		schema.get("valid_class_paths", ["Warrior", "Priest", "Rogue", "Mage"])
	)
	var valid_activity_ids := _string_array(schema.get("valid_activity_ids", []))
	var valid_lore_tags := _string_array(schema.get("valid_lore_tags", []))
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var raw_by_id: Dictionary = {}
	var duplicate_ids: Array[String] = []
	var missing_asset_paths: Array[String] = []
	var invalid_connections: Array[String] = []
	var invalid_class_paths: Array[String] = []
	var invalid_activity_ids: Array[String] = []
	var invalid_lore_tags: Array[String] = []
	var stable_id_pattern := RegEx.new()
	stable_id_pattern.compile("^[a-z][a-z0-9_]{2,63}$")

	for index in range(entries.size()):
		var value: Variant = entries[index]
		if not value is Dictionary:
			errors.append("Raider entry %d is not an object." % index)
			continue
		var entry: Dictionary = value
		var raider_id := String(entry.get("raider_id", "")).strip_edges()
		if raider_id.is_empty():
			errors.append("Raider entry %d is missing raider_id." % index)
			continue
		if raw_by_id.has(raider_id):
			duplicate_ids.append(raider_id)
			errors.append("Duplicate master raider_id: " + raider_id)
			continue
		raw_by_id[raider_id] = entry
		if stable_id_pattern.search(raider_id) == null:
			errors.append("Raider ID does not match the stable-ID format: " + raider_id)

	for raider_id in _ordered_ids:
		var definition: Dictionary = _definitions_by_id[raider_id]
		var authored_entry: Dictionary = _dictionary(raw_by_id.get(raider_id, {}))
		for field in required_fields:
			if not authored_entry.has(field) or _field_is_missing(authored_entry[field]):
				errors.append("%s is missing required field: %s" % [raider_id, field])

		for class_path in _string_array(definition.get("permitted_class_paths", [])):
			var valid := (
				ResourceLoader.exists(class_path)
				if class_path.begins_with("res://")
				else valid_class_paths.has(class_path)
			)
			if not valid:
				var issue := "%s -> %s" % [raider_id, class_path]
				invalid_class_paths.append(issue)
				errors.append("Invalid class path: " + issue)

		for activity_id in _string_array(definition.get("preferred_activity_tags", [])):
			if not valid_activity_ids.is_empty() and not valid_activity_ids.has(activity_id):
				var issue := "%s -> %s" % [raider_id, activity_id]
				invalid_activity_ids.append(issue)
				errors.append("Invalid preferred activity: " + issue)

		for lore_tag in _string_array(definition.get("lore_knowledge_tags", [])):
			if not valid_lore_tags.is_empty() and not valid_lore_tags.has(lore_tag):
				var issue := "%s -> %s" % [raider_id, lore_tag]
				invalid_lore_tags.append(issue)
				errors.append("Invalid lore tag: " + issue)

		for connection_id in _string_array(definition.get("authored_connection_ids", [])):
			if connection_id == raider_id or not raw_by_id.has(connection_id):
				var issue := "%s -> %s" % [raider_id, connection_id]
				invalid_connections.append(issue)
				errors.append("Invalid authored connection: " + issue)
			elif not _string_array(
				Dictionary(_definitions_by_id.get(connection_id, {})).get(
					"authored_connection_ids", []
				)
			).has(raider_id):
				warnings.append("Authored connection is one-way: %s -> %s" % [raider_id, connection_id])

		var assets: Dictionary = _dictionary(definition.get("visual_assets", {}))
		var fallback_found := false
		for asset_key in assets.keys():
			var asset_path := String(assets[asset_key]).strip_edges()
			if asset_path.is_empty():
				continue
			if ResourceLoader.exists(asset_path):
				if String(asset_key) in [
					"profile_sprite",
					"profile_portrait",
					"class_fallback_portrait",
					"portrait",
					"neutral_fallback_portrait",
				]:
					fallback_found = true
			else:
				var issue := "%s -> %s" % [raider_id, asset_path]
				missing_asset_paths.append(issue)
				warnings.append("Missing visual asset; fallback will be used: " + issue)
		if not fallback_found:
			errors.append("No resolvable visual fallback for raider: " + raider_id)

	return {
		"valid": errors.is_empty(),
		"catalog_version": int(catalog.get("catalog_version", 0)),
		"definition_count": _ordered_ids.size(),
		"capacity_target": int(schema.get("capacity_target", 150)),
		"duplicate_ids": duplicate_ids,
		"missing_asset_paths": missing_asset_paths,
		"invalid_authored_connections": invalid_connections,
		"invalid_class_paths": invalid_class_paths,
		"invalid_preferred_activity_ids": invalid_activity_ids,
		"invalid_lore_tags": invalid_lore_tags,
		"errors": errors,
		"warnings": warnings,
	}


static func _field_is_missing(value: Variant) -> bool:
	if value == null:
		return true
	if value is String:
		return String(value).strip_edges().is_empty()
	if value is Array:
		return Array(value).is_empty()
	return false


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


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result
