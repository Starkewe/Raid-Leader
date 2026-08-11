extends RefCounted
class_name ClassVisualCatalog

## Compatibility facade. RaiderClassCatalog is the sole class/visual source of truth.
const RaiderClassCatalogScript := preload(
	"res://scripts/data/raider_class_catalog.gd"
)


static func get_definition(class_id: String) -> ClassVisualDefinition:
	return RaiderClassCatalogScript.get_visual_definition(class_id)


static func resolve_for_unit(
	base_class_id: String, advanced_class_id: String = ""
) -> ClassVisualDefinition:
	return RaiderClassCatalogScript.resolve_visual(base_class_id, advanced_class_id)


static func get_base_definition(class_id: String) -> ClassVisualDefinition:
	var definition := RaiderClassCatalogScript.get_definition(class_id)
	if definition.is_empty():
		return null
	return RaiderClassCatalogScript.get_visual_definition(
		String(definition.get("parent_class_id", ""))
	)


static func get_neutral_definition() -> ClassVisualDefinition:
	return RaiderClassCatalogScript.get_neutral_visual_definition()


static func get_all_definitions() -> Array[ClassVisualDefinition]:
	var result: Array[ClassVisualDefinition] = []
	for definition in RaiderClassCatalogScript.get_all_definitions():
		var visual := definition.get("visual") as ClassVisualDefinition
		if visual != null:
			result.append(visual)
	return result


static func get_base_definitions() -> Array[ClassVisualDefinition]:
	var result: Array[ClassVisualDefinition] = []
	for class_id in RaiderClassCatalogScript.get_base_class_ids():
		var visual := RaiderClassCatalogScript.get_visual_definition(class_id)
		if visual != null:
			result.append(visual)
	return result


static func get_advanced_definitions() -> Array[ClassVisualDefinition]:
	var result: Array[ClassVisualDefinition] = []
	for class_id in RaiderClassCatalogScript.ADVANCED_CLASS_ORDER:
		var visual := RaiderClassCatalogScript.get_visual_definition(class_id)
		if visual != null:
			result.append(visual)
	return result


static func get_all_class_ids() -> Array[String]:
	return RaiderClassCatalogScript.get_all_class_ids()


static func is_advanced_class_id(class_id: String) -> bool:
	return RaiderClassCatalogScript.is_advanced_class_id(class_id)


static func normalize_class_id(class_id: String) -> String:
	return RaiderClassCatalogScript.normalize_class_id(class_id)
