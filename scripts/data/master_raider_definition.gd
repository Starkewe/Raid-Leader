extends Resource
class_name MasterRaiderDefinition


static func sanitize(source: Dictionary) -> Dictionary:
	var definition := source.duplicate(true)
	var raider_id := String(definition.get("raider_id", "")).strip_edges()
	var default_class := String(definition.get("default_class", "Mage")).strip_edges()
	definition["raider_id"] = raider_id
	definition["display_name"] = String(definition.get("display_name", "Unnamed Raider")).strip_edges()
	definition["biography"] = String(definition.get("biography", ""))
	definition["personality_tags"] = _string_array(definition.get("personality_tags", []))
	definition["personality_description"] = String(
		definition.get("personality_description", "")
	).strip_edges()
	definition["speech_profile_id"] = String(
		definition.get("speech_profile_id", "writ_default")
	)
	definition["visual_assets"] = _dictionary(definition.get("visual_assets", {}))
	definition["preferred_activity_tags"] = _string_array(
		definition.get("preferred_activity_tags", [])
	)
	definition["permitted_class_paths"] = _string_array(
		definition.get("permitted_class_paths", [default_class])
	)
	definition["lore_knowledge_tags"] = _string_array(
		definition.get("lore_knowledge_tags", [])
	)
	definition["authored_connection_ids"] = _string_array(
		definition.get("authored_connection_ids", [])
	)
	definition["recruitment"] = _dictionary(definition.get("recruitment", {}))
	definition["default_class"] = default_class
	definition["default_role"] = String(definition.get("default_role", "dps")).strip_edges()
	definition["catalog_order"] = int(definition.get("catalog_order", 0))
	return definition


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()

			if not text.is_empty() and not result.has(text):
				result.append(text)

	return result


static func _dictionary(value: Variant) -> Dictionary:
	return Dictionary(value).duplicate(true) if value is Dictionary else {}
