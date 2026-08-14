extends Resource
class_name ProgressionCatalogResource

const EncounterCatalogScript := preload("res://scripts/data/encounter_catalog.gd")
const RaiderClassCatalogScript := preload("res://scripts/data/raider_class_catalog.gd")

const REQUIRED_FAMILY_IDS: Array[String] = [
	"one_handed_arms", "heavy_arms", "conduit_staves", "ritual_implements",
	"skirmishing_arms", "projectile_arms", "battle_staves", "arcane_foci",
]
const REQUIRED_RARITY_IDS: Array[String] = ["common", "uncommon", "rare"]
const EXPECTED_CLASS_FAMILIES := {
	"warrior": ["one_handed_arms", "heavy_arms"],
	"priest": ["conduit_staves", "ritual_implements"],
	"rogue": ["skirmishing_arms", "projectile_arms"],
	"mage": ["battle_staves", "arcane_foci"],
	"hollow_anvil": ["one_handed_arms", "heavy_arms"],
	"gravelord_proxy": ["heavy_arms", "ritual_implements"],
	"sunder_clerk": ["one_handed_arms", "projectile_arms"],
	"lantern_warden": ["one_handed_arms", "arcane_foci"],
	"burden_courier": ["conduit_staves", "heavy_arms"],
	"memory_apothecary": ["conduit_staves", "ritual_implements"],
	"scar_gardener": ["ritual_implements", "skirmishing_arms"],
	"moth_surgeon": ["conduit_staves", "arcane_foci"],
	"echo_butcher": ["skirmishing_arms", "heavy_arms"],
	"ritebreaker": ["skirmishing_arms", "ritual_implements"],
	"drift_knife": ["skirmishing_arms", "projectile_arms"],
	"phasehand": ["skirmishing_arms", "arcane_foci"],
	"hearth_corsair": ["arcane_foci", "one_handed_arms"],
	"rift_tailor": ["arcane_foci", "ritual_implements"],
	"rune_slinger": ["arcane_foci", "projectile_arms"],
	"orbit_scribe": ["battle_staves", "arcane_foci"],
}

@export var catalog_revision: int = 1
@export var regions: Array[ProgressionRegionDefinition] = []
@export var weapon_families: Array[WeaponFamilyDefinition] = []
@export var advancement_tokens: Array[AdvancementTokenDefinition] = []
@export var material_rarities: Array[MaterialRarityDefinition] = []
@export var boss_materials: Array[BossMaterialDefinition] = []
@export var reward_tables: Array[BossRewardTableDefinition] = []
@export var weapon_traits: Array[WeaponTraitDefinition] = []
@export var weapons: Array[WeaponDefinition] = []
@export var crafting_recipes: Array[CraftingRecipeDefinition] = []
@export var raider_traits: Array[RaiderTraitDefinition] = []


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if catalog_revision <= 0:
		errors.append("catalog.catalog_revision must be greater than zero.")

	var region_by_id := _validate_ids(regions, "region_id", "regions", errors)
	var family_by_id := _validate_ids(
		weapon_families, "family_id", "weapon_families", errors
	)
	var token_by_id := _validate_ids(
		advancement_tokens, "token_id", "advancement_tokens", errors
	)
	var rarity_by_id := _validate_ids(
		material_rarities, "rarity_id", "material_rarities", errors
	)
	var material_by_id := _validate_ids(
		boss_materials, "material_id", "boss_materials", errors
	)
	var table_by_id := _validate_ids(
		reward_tables, "reward_table_id", "reward_tables", errors
	)
	var weapon_trait_by_id := _validate_ids(
		weapon_traits, "trait_id", "weapon_traits", errors
	)
	var weapon_by_id := _validate_ids(weapons, "weapon_id", "weapons", errors)
	var recipe_by_id := _validate_ids(
		crafting_recipes, "recipe_id", "crafting_recipes", errors
	)
	_validate_ids(raider_traits, "trait_id", "raider_traits", errors)

	_validate_exact_id_set(
		family_by_id, REQUIRED_FAMILY_IDS, "catalog.weapon_families", errors
	)
	_validate_exact_id_set(
		rarity_by_id, REQUIRED_RARITY_IDS, "catalog.material_rarities", errors
	)
	var boss_by_encounter := _validate_regions(
		region_by_id, token_by_id, table_by_id, weapon_by_id, family_by_id, errors
	)
	_validate_families(family_by_id, errors)
	_validate_tokens(token_by_id, boss_by_encounter, errors)
	_validate_rarities(rarity_by_id, errors)
	_validate_materials(material_by_id, rarity_by_id, errors)
	_validate_reward_tables(table_by_id, material_by_id, boss_by_encounter, errors)
	_validate_weapon_traits(weapon_trait_by_id, errors)
	_validate_weapons(
		weapon_by_id, family_by_id, boss_by_encounter, recipe_by_id,
		weapon_trait_by_id, errors
	)
	_validate_recipes(
		recipe_by_id, material_by_id, weapon_by_id, boss_by_encounter, errors
	)
	_validate_raider_traits(errors)
	_validate_region_family_limits(region_by_id, weapon_by_id, errors)
	return errors


func _validate_ids(
	resources: Array, id_property: String, collection_path: String,
	errors: PackedStringArray
) -> Dictionary:
	var result: Dictionary = {}
	for index in range(resources.size()):
		var definition: Resource = resources[index] as Resource
		var path := "catalog.%s[%d]" % [collection_path, index]
		if definition == null:
			errors.append("%s is missing." % path)
			continue
		var stable_id := String(definition.get(id_property)).strip_edges()
		if not _is_stable_id(stable_id):
			errors.append(
				"%s.%s is missing or malformed: '%s'." % [path, id_property, stable_id]
			)
			continue
		if result.has(stable_id):
			errors.append(
				"%s.%s duplicates stable ID '%s'." % [path, id_property, stable_id]
			)
			continue
		result[stable_id] = definition
	return result


func _validate_regions(
	region_by_id: Dictionary, token_by_id: Dictionary, table_by_id: Dictionary,
	weapon_by_id: Dictionary, family_by_id: Dictionary, errors: PackedStringArray
) -> Dictionary:
	var boss_by_encounter: Dictionary = {}
	for region_id_value in region_by_id:
		var region_id := String(region_id_value)
		var region: ProgressionRegionDefinition = region_by_id[region_id]
		var region_path := _definition_path(regions, region, "regions")
		if region.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % region_path)
		for boss_index in range(region.bosses.size()):
			var boss := region.bosses[boss_index]
			var path := "%s.bosses[%d]" % [region_path, boss_index]
			if boss == null:
				errors.append("%s is missing." % path)
				continue
			var encounter_id := boss.encounter_id.strip_edges()
			if not _is_stable_id(encounter_id):
				errors.append("%s.encounter_id is missing or malformed." % path)
				continue
			if boss_by_encounter.has(encounter_id):
				errors.append("%s.encounter_id duplicates boss '%s'." % [path, encounter_id])
			else:
				boss_by_encounter[encounter_id] = boss
			if EncounterCatalogScript.get_definition(encounter_id) == null:
				errors.append("%s.encounter_id references unknown encounter '%s'." % [path, encounter_id])
			if boss.display_name.strip_edges().is_empty():
				errors.append("%s.display_name must not be empty." % path)
			var archetype := RaiderClassCatalogScript.normalize_class_id(
				boss.archetype_class_id
			)
			if not RaiderClassCatalogScript.get_base_class_ids().has(archetype):
				errors.append("%s.archetype_class_id references unknown base class '%s'." % [path, boss.archetype_class_id])
			if not token_by_id.has(boss.token_id):
				errors.append("%s.token_id references unknown token '%s'." % [path, boss.token_id])
			if not table_by_id.has(boss.reward_table_id):
				errors.append("%s.reward_table_id references unknown reward table '%s'." % [path, boss.reward_table_id])
			if boss.weapon_ids.size() != 2:
				errors.append("%s.weapon_ids must contain exactly two weapons." % path)
			var native_found := false
			var native_families: Array = EXPECTED_CLASS_FAMILIES.get(archetype, [])
			var seen_weapons: Dictionary = {}
			for weapon_index in range(boss.weapon_ids.size()):
				var weapon_id := boss.weapon_ids[weapon_index]
				if seen_weapons.has(weapon_id):
					errors.append("%s.weapon_ids[%d] duplicates '%s'." % [path, weapon_index, weapon_id])
				seen_weapons[weapon_id] = true
				if not weapon_by_id.has(weapon_id):
					errors.append("%s.weapon_ids[%d] references unknown weapon '%s'." % [path, weapon_index, weapon_id])
					continue
				var weapon: WeaponDefinition = weapon_by_id[weapon_id]
				if weapon.source_encounter_id != encounter_id:
					errors.append("%s.weapon_ids[%d] references weapon from boss '%s'." % [path, weapon_index, weapon.source_encounter_id])
				if family_by_id.has(weapon.family_id) and native_families.has(weapon.family_id):
					native_found = true
			if not native_found:
				errors.append("%s has no archetype-native weapon for '%s'." % [path, archetype])
	return boss_by_encounter


func _validate_families(family_by_id: Dictionary, errors: PackedStringArray) -> void:
	var actual_by_class: Dictionary = {}
	for family_id_value in family_by_id:
		var family_id := String(family_id_value)
		var family: WeaponFamilyDefinition = family_by_id[family_id]
		var path := _definition_path(weapon_families, family, "weapon_families")
		if family.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % path)
		var seen: Dictionary = {}
		for class_index in range(family.compatible_class_ids.size()):
			var class_id := RaiderClassCatalogScript.normalize_class_id(
				family.compatible_class_ids[class_index]
			)
			if RaiderClassCatalogScript.get_definition(class_id).is_empty():
				errors.append("%s.compatible_class_ids[%d] references unknown class '%s'." % [path, class_index, family.compatible_class_ids[class_index]])
				continue
			if seen.has(class_id):
				errors.append("%s.compatible_class_ids[%d] duplicates class '%s'." % [path, class_index, class_id])
				continue
			seen[class_id] = true
			var class_families: Array = actual_by_class.get(class_id, [])
			class_families.append(family_id)
			actual_by_class[class_id] = class_families

	for class_id_value in EXPECTED_CLASS_FAMILIES:
		var class_id := String(class_id_value)
		var expected: Array = Array(EXPECTED_CLASS_FAMILIES[class_id]).duplicate()
		var actual: Array = Array(actual_by_class.get(class_id, [])).duplicate()
		expected.sort()
		actual.sort()
		if actual != expected:
			errors.append(
				"catalog.weapon_families compatibility for class '%s' must be exactly [%s], got [%s]."
				% [class_id, ", ".join(expected), ", ".join(actual)]
			)


func _validate_tokens(
	token_by_id: Dictionary, boss_by_encounter: Dictionary, errors: PackedStringArray
) -> void:
	for token_id_value in token_by_id:
		var token: AdvancementTokenDefinition = token_by_id[token_id_value]
		var path := _definition_path(advancement_tokens, token, "advancement_tokens")
		if token.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % path)
		var class_id := RaiderClassCatalogScript.normalize_class_id(token.archetype_class_id)
		if not RaiderClassCatalogScript.get_base_class_ids().has(class_id):
			errors.append("%s.archetype_class_id references unknown base class '%s'." % [path, token.archetype_class_id])
		if not boss_by_encounter.has(token.source_encounter_id):
			errors.append("%s.source_encounter_id references unknown boss '%s'." % [path, token.source_encounter_id])
		else:
			var boss: ProgressionBossDefinition = boss_by_encounter[token.source_encounter_id]
			if boss.token_id != token.token_id:
				errors.append("%s.token_id is not assigned by source boss '%s'." % [path, token.source_encounter_id])


func _validate_rarities(rarity_by_id: Dictionary, errors: PackedStringArray) -> void:
	var orders: Dictionary = {}
	for rarity_id_value in rarity_by_id:
		var rarity: MaterialRarityDefinition = rarity_by_id[rarity_id_value]
		var path := _definition_path(material_rarities, rarity, "material_rarities")
		if rarity.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % path)
		if orders.has(rarity.sort_order):
			errors.append("%s.sort_order duplicates rarity sort order %d." % [path, rarity.sort_order])
		orders[rarity.sort_order] = true


func _validate_materials(
	material_by_id: Dictionary, rarity_by_id: Dictionary, errors: PackedStringArray
) -> void:
	for material_id_value in material_by_id:
		var material: BossMaterialDefinition = material_by_id[material_id_value]
		var path := _definition_path(boss_materials, material, "boss_materials")
		if material.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % path)
		if not rarity_by_id.has(material.rarity_id):
			errors.append("%s.rarity_id references invalid rarity '%s'." % [path, material.rarity_id])
		if material.source_encounter_ids.is_empty():
			errors.append("%s.source_encounter_ids must not be empty." % path)
		var seen: Dictionary = {}
		for source_index in range(material.source_encounter_ids.size()):
			var encounter_id := material.source_encounter_ids[source_index]
			if EncounterCatalogScript.get_definition(encounter_id) == null:
				errors.append("%s.source_encounter_ids[%d] references unknown encounter '%s'." % [path, source_index, encounter_id])
			if seen.has(encounter_id):
				errors.append("%s.source_encounter_ids[%d] duplicates '%s'." % [path, source_index, encounter_id])
			seen[encounter_id] = true


func _validate_reward_tables(
	table_by_id: Dictionary, material_by_id: Dictionary,
	boss_by_encounter: Dictionary, errors: PackedStringArray
) -> void:
	for table_id_value in table_by_id:
		var table: BossRewardTableDefinition = table_by_id[table_id_value]
		var path := _definition_path(reward_tables, table, "reward_tables")
		if not boss_by_encounter.has(table.encounter_id):
			errors.append("%s.encounter_id references unknown progression boss '%s'." % [path, table.encounter_id])
		if table.revision <= 0:
			errors.append("%s.revision must be greater than zero." % path)
		var layer_ids: Dictionary = {}
		for layer_index in range(table.layers.size()):
			var layer := table.layers[layer_index]
			var layer_path := "%s.layers[%d]" % [path, layer_index]
			if layer == null:
				errors.append("%s is missing." % layer_path)
				continue
			if not _is_stable_id(layer.layer_id):
				errors.append("%s.layer_id is missing or malformed." % layer_path)
			elif layer_ids.has(layer.layer_id):
				errors.append("%s.layer_id duplicates '%s'." % [layer_path, layer.layer_id])
			layer_ids[layer.layer_id] = true
			if layer.minimum_rolls < 0 or layer.maximum_rolls < layer.minimum_rolls:
				errors.append("%s roll counts are invalid (%d..%d)." % [layer_path, layer.minimum_rolls, layer.maximum_rolls])
			if layer.entries.is_empty():
				errors.append("%s.entries must not be empty." % layer_path)
			var weight_total := 0.0
			for entry_index in range(layer.entries.size()):
				var entry := layer.entries[entry_index]
				var entry_path := "%s.entries[%d]" % [layer_path, entry_index]
				if entry == null:
					errors.append("%s is missing." % entry_path)
					continue
				if entry.weight_percent <= 0.0:
					errors.append("%s.weight_percent must be greater than zero." % entry_path)
				weight_total += entry.weight_percent
				if not material_by_id.has(entry.material_id):
					errors.append("%s.material_id references unknown material '%s'." % [entry_path, entry.material_id])
					continue
				var material: BossMaterialDefinition = material_by_id[entry.material_id]
				if not material.source_encounter_ids.has(table.encounter_id):
					errors.append("%s.material_id '%s' excludes rewarding boss '%s' from its source list." % [entry_path, entry.material_id, table.encounter_id])
			if not is_equal_approx(weight_total, 100.0):
				errors.append("%s weights must total 100%%, got %.3f%%." % [layer_path, weight_total])


func _validate_weapon_traits(
	trait_by_id: Dictionary, errors: PackedStringArray
) -> void:
	for trait_id_value in trait_by_id:
		var weapon_trait: WeaponTraitDefinition = trait_by_id[trait_id_value]
		var path := _definition_path(weapon_traits, weapon_trait, "weapon_traits")
		if weapon_trait.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % path)
		if weapon_trait.description.strip_edges().is_empty():
			errors.append("%s.description must not be empty." % path)
		if not _is_stable_id(weapon_trait.hook_id):
			errors.append("%s.hook_id is missing or malformed." % path)
		if weapon_trait.combat_effect_active:
			errors.append("%s.combat_effect_active must remain false in this progression pass." % path)


func _validate_weapons(
	weapon_by_id: Dictionary, family_by_id: Dictionary, boss_by_encounter: Dictionary,
	recipe_by_id: Dictionary, trait_by_id: Dictionary, errors: PackedStringArray
) -> void:
	for weapon_id_value in weapon_by_id:
		var weapon: WeaponDefinition = weapon_by_id[weapon_id_value]
		var path := _definition_path(weapons, weapon, "weapons")
		if weapon.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % path)
		if not family_by_id.has(weapon.family_id):
			errors.append("%s.family_id references unknown family '%s'." % [path, weapon.family_id])
		if not boss_by_encounter.has(weapon.source_encounter_id):
			errors.append("%s.source_encounter_id references unknown boss '%s'." % [path, weapon.source_encounter_id])
		if not recipe_by_id.has(weapon.recipe_id):
			errors.append("%s.recipe_id references unknown recipe '%s'." % [path, weapon.recipe_id])
		if not trait_by_id.has(weapon.trait_id):
			errors.append("%s.trait_id references unknown weapon trait '%s'." % [path, weapon.trait_id])
		if weapon.stat_profile == null:
			errors.append("%s.stat_profile is missing." % path)
		else:
			if weapon.stat_profile.power_multiplier <= 0.0:
				errors.append("%s.stat_profile.power_multiplier must be greater than zero." % path)
			if weapon.stat_profile.speed_multiplier <= 0.0:
				errors.append("%s.stat_profile.speed_multiplier must be greater than zero." % path)
			if (
				is_equal_approx(weapon.stat_profile.power_multiplier, 1.0)
				and is_equal_approx(weapon.stat_profile.speed_multiplier, 1.0)
				and is_zero_approx(weapon.stat_profile.range_additive)
			):
				errors.append("%s.stat_profile must modify at least one combat value." % path)


func _validate_recipes(
	recipe_by_id: Dictionary, material_by_id: Dictionary, weapon_by_id: Dictionary,
	boss_by_encounter: Dictionary, errors: PackedStringArray
) -> void:
	for recipe_id_value in recipe_by_id:
		var recipe: CraftingRecipeDefinition = recipe_by_id[recipe_id_value]
		var path := _definition_path(crafting_recipes, recipe, "crafting_recipes")
		if not boss_by_encounter.has(recipe.source_encounter_id):
			errors.append("%s.source_encounter_id references unknown boss '%s'." % [path, recipe.source_encounter_id])
		if not weapon_by_id.has(recipe.output_weapon_id):
			errors.append("%s.output_weapon_id references unknown weapon '%s'." % [path, recipe.output_weapon_id])
		else:
			var output: WeaponDefinition = weapon_by_id[recipe.output_weapon_id]
			if output.recipe_id != recipe.recipe_id:
				errors.append("%s.output_weapon_id does not link back through recipe_id." % path)
			if output.source_encounter_id != recipe.source_encounter_id:
				errors.append("%s.output_weapon_id belongs to a different source boss." % path)
		if recipe.ingredients.is_empty():
			errors.append("%s.ingredients must not be empty." % path)
		var has_rare_primary := false
		var has_cross_boss_secondary := false
		var seen_materials: Dictionary = {}
		for ingredient_index in range(recipe.ingredients.size()):
			var ingredient := recipe.ingredients[ingredient_index]
			var ingredient_path := "%s.ingredients[%d]" % [path, ingredient_index]
			if ingredient == null:
				errors.append("%s is missing." % ingredient_path)
				continue
			if ingredient.quantity <= 0:
				errors.append("%s.quantity must be greater than zero." % ingredient_path)
			if seen_materials.has(ingredient.material_id):
				errors.append("%s.material_id duplicates '%s'." % [ingredient_path, ingredient.material_id])
			seen_materials[ingredient.material_id] = true
			if not material_by_id.has(ingredient.material_id):
				errors.append("%s.material_id references unknown material '%s'." % [ingredient_path, ingredient.material_id])
				continue
			var material: BossMaterialDefinition = material_by_id[ingredient.material_id]
			if material.rarity_id == "rare" and material.source_encounter_ids.has(recipe.source_encounter_id):
				has_rare_primary = true
			if (
				not material.source_encounter_ids.has(recipe.source_encounter_id)
				and not material.source_encounter_ids.is_empty()
			):
				has_cross_boss_secondary = true
		if not has_rare_primary:
			errors.append("%s requires a rare primary component from source boss '%s'." % [path, recipe.source_encounter_id])
		if not has_cross_boss_secondary:
			errors.append("%s requires a secondary component from another boss." % path)


func _validate_raider_traits(errors: PackedStringArray) -> void:
	for index in range(raider_traits.size()):
		var raider_trait := raider_traits[index]
		if raider_trait == null:
			continue
		var path := "catalog.raider_traits[%d]" % index
		if raider_trait.tier not in ["major", "minor"]:
			errors.append("%s.tier has invalid trait tier '%s'." % [path, raider_trait.tier])
		if raider_trait.display_name.strip_edges().is_empty():
			errors.append("%s.display_name must not be empty." % path)
		if not _is_stable_id(raider_trait.hook_id):
			errors.append("%s.hook_id is missing or malformed." % path)


func _validate_region_family_limits(
	region_by_id: Dictionary, weapon_by_id: Dictionary, errors: PackedStringArray
) -> void:
	for region_id_value in region_by_id:
		var region_id := String(region_id_value)
		var region: ProgressionRegionDefinition = region_by_id[region_id]
		var family_counts: Dictionary = {}
		for boss in region.bosses:
			if boss == null:
				continue
			for weapon_id in boss.weapon_ids:
				if not weapon_by_id.has(weapon_id):
					continue
				var family_id := String(weapon_by_id[weapon_id].family_id)
				family_counts[family_id] = int(family_counts.get(family_id, 0)) + 1
		for family_id_value in family_counts:
			if int(family_counts[family_id_value]) > 2:
				errors.append("catalog.regions['%s'] has more than two weapons in family '%s'." % [region_id, family_id_value])


func _validate_exact_id_set(
	actual: Dictionary, expected_ids: Array[String], path: String,
	errors: PackedStringArray
) -> void:
	var actual_ids: Array[String] = []
	for value in actual.keys():
		actual_ids.append(String(value))
	actual_ids.sort()
	var expected := expected_ids.duplicate()
	expected.sort()
	if actual_ids != expected:
		errors.append("%s must define exactly [%s], got [%s]." % [path, ", ".join(expected), ", ".join(actual_ids)])


func _definition_path(resources: Array, definition: Resource, collection: String) -> String:
	return "catalog.%s[%d]" % [collection, resources.find(definition)]


func _is_stable_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var valid := (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
			or code == 95
		)
		if not valid:
			return false
	return not value.begins_with("_") and not value.ends_with("_")
