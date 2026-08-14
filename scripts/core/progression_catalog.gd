extends Node

const CATALOG_PATH := "res://data/progression/catalog.tres"

var _catalog: ProgressionCatalogResource
var _indexes: Dictionary = {}
var _validation_errors := PackedStringArray()


func _enter_tree() -> void:
	_catalog = load(CATALOG_PATH) as ProgressionCatalogResource
	_rebuild_indexes()


func _ready() -> void:
	if _catalog == null:
		push_error("Progression catalog could not be loaded: " + CATALOG_PATH)
		return
	_validation_errors = _catalog.get_validation_errors()
	for validation_error in _validation_errors:
		push_error("Progression catalog: " + validation_error)


func get_catalog() -> ProgressionCatalogResource:
	return _catalog


func get_validation_report() -> Dictionary:
	return {
		"valid": _catalog != null and _validation_errors.is_empty(),
		"errors": Array(_validation_errors).duplicate(),
	}


func get_region_definition(region_id: String) -> ProgressionRegionDefinition:
	return _indexes.get("regions", {}).get(region_id) as ProgressionRegionDefinition


func get_boss_definition(encounter_id: String) -> ProgressionBossDefinition:
	return _indexes.get("bosses", {}).get(encounter_id) as ProgressionBossDefinition


func get_weapon_family(family_id: String) -> WeaponFamilyDefinition:
	return _indexes.get("families", {}).get(family_id) as WeaponFamilyDefinition


func get_advancement_token(token_id: String) -> AdvancementTokenDefinition:
	return _indexes.get("tokens", {}).get(token_id) as AdvancementTokenDefinition


func get_material_rarity(rarity_id: String) -> MaterialRarityDefinition:
	return _indexes.get("rarities", {}).get(rarity_id) as MaterialRarityDefinition


func get_material(material_id: String) -> BossMaterialDefinition:
	return _indexes.get("materials", {}).get(material_id) as BossMaterialDefinition


func get_reward_table(table_id: String) -> BossRewardTableDefinition:
	return _indexes.get("reward_tables", {}).get(table_id) as BossRewardTableDefinition


func get_reward_table_for_encounter(encounter_id: String) -> BossRewardTableDefinition:
	var boss := get_boss_definition(encounter_id)
	return null if boss == null else get_reward_table(boss.reward_table_id)


func get_weapon_trait(trait_id: String) -> WeaponTraitDefinition:
	return _indexes.get("weapon_traits", {}).get(trait_id) as WeaponTraitDefinition


func get_weapon(weapon_id: String) -> WeaponDefinition:
	return _indexes.get("weapons", {}).get(weapon_id) as WeaponDefinition


func get_recipe(recipe_id: String) -> CraftingRecipeDefinition:
	return _indexes.get("recipes", {}).get(recipe_id) as CraftingRecipeDefinition


func get_raider_trait(trait_id: String) -> RaiderTraitDefinition:
	return _indexes.get("raider_traits", {}).get(trait_id) as RaiderTraitDefinition


func get_recipe_ids_for_encounter(encounter_id: String) -> Array[String]:
	var result: Array[String] = []
	var boss := get_boss_definition(encounter_id)
	if boss == null:
		return result
	for weapon_id in boss.weapon_ids:
		var weapon := get_weapon(weapon_id)
		if weapon != null and not result.has(weapon.recipe_id):
			result.append(weapon.recipe_id)
	return result


func get_class_family_ids(class_id: String) -> Array[String]:
	var normalized := RaiderClassCatalog.normalize_class_id(class_id)
	var result: Array[String] = []
	if _catalog == null:
		return result
	for family in _catalog.weapon_families:
		if family != null and family.compatible_class_ids.has(normalized):
			result.append(family.family_id)
	return result


func is_family_compatible(class_id: String, family_id: String) -> bool:
	return get_class_family_ids(class_id).has(family_id)


func get_region_completion(region_id: String, victories: Dictionary) -> Dictionary:
	var region := get_region_definition(region_id)
	if region == null:
		return {"known": false, "complete": false, "mandatory": [], "remaining": []}
	var mandatory: Array[String] = []
	var remaining: Array[String] = []
	var optional: Array[String] = []
	var apex: Array[String] = []
	for boss in region.bosses:
		if boss == null:
			continue
		if boss.apex:
			apex.append(boss.encounter_id)
		elif boss.mandatory:
			mandatory.append(boss.encounter_id)
			if int(victories.get(boss.encounter_id, 0)) <= 0:
				remaining.append(boss.encounter_id)
		else:
			optional.append(boss.encounter_id)
	return {
		"known": true,
		"complete": remaining.is_empty(),
		"mandatory": mandatory,
		"remaining": remaining,
		"optional": optional,
		"apex": apex,
	}


func _rebuild_indexes() -> void:
	_indexes = {
		"regions": {}, "bosses": {}, "families": {}, "tokens": {},
		"rarities": {}, "materials": {}, "reward_tables": {},
		"weapon_traits": {}, "weapons": {}, "recipes": {}, "raider_traits": {},
	}
	_validation_errors = PackedStringArray()
	if _catalog == null:
		return
	_index_resources(_catalog.regions, "region_id", _indexes["regions"])
	for region in _catalog.regions:
		if region == null:
			continue
		_index_resources(region.bosses, "encounter_id", _indexes["bosses"])
	_index_resources(_catalog.weapon_families, "family_id", _indexes["families"])
	_index_resources(_catalog.advancement_tokens, "token_id", _indexes["tokens"])
	_index_resources(_catalog.material_rarities, "rarity_id", _indexes["rarities"])
	_index_resources(_catalog.boss_materials, "material_id", _indexes["materials"])
	_index_resources(_catalog.reward_tables, "reward_table_id", _indexes["reward_tables"])
	_index_resources(_catalog.weapon_traits, "trait_id", _indexes["weapon_traits"])
	_index_resources(_catalog.weapons, "weapon_id", _indexes["weapons"])
	_index_resources(_catalog.crafting_recipes, "recipe_id", _indexes["recipes"])
	_index_resources(_catalog.raider_traits, "trait_id", _indexes["raider_traits"])
	_validation_errors = _catalog.get_validation_errors()


func _index_resources(resources: Array, id_property: String, target: Dictionary) -> void:
	for definition in resources:
		if definition == null:
			continue
		var stable_id := String(definition.get(id_property))
		if not stable_id.is_empty() and not target.has(stable_id):
			target[stable_id] = definition

