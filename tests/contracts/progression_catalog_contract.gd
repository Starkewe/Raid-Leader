extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var catalog := ProgressionCatalog.get_catalog()
	if catalog == null:
		failures.append("Progression catalog did not load.")
		_finish(failures)
		return
	var report := ProgressionCatalog.get_validation_report()
	if not bool(report.get("valid", false)):
		failures.append("Production progression catalog is invalid: %s" % report.get("errors", []))
	if int(ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", -1
	)) != 2:
		failures.append("Canvas textures do not default to linear filtering with mipmaps.")
	_validate_production_content(catalog, failures)
	_validate_malformed_fixtures(catalog, failures)
	_finish(failures)


func _validate_production_content(
	catalog: ProgressionCatalogResource, failures: Array[String]
) -> void:
	if catalog.weapon_families.size() != 8:
		failures.append("Catalog does not expose all eight weapon families.")
	if catalog.reward_tables.size() != 4:
		failures.append("Catalog does not expose all four reward tables.")
	if catalog.weapons.size() != 8 or catalog.crafting_recipes.size() != 8:
		failures.append("Catalog does not expose eight weapons and recipes.")
	if catalog.boss_materials.size() != 14:
		failures.append("Catalog does not expose all fourteen production materials.")
	for material_value in catalog.boss_materials:
		var material: BossMaterialDefinition = material_value
		if material == null:
			continue
		var expected_icon_path := "res://icons/material_visuals/material_%s.png" % material.material_id
		if material.icon_resource == null:
			failures.append("Material '%s' is missing its inventory icon." % material.material_id)
			continue
		if material.icon_resource.resource_path != expected_icon_path:
			failures.append("Material '%s' does not use its material icon asset." % material.material_id)
		var material_image := material.icon_resource.get_image()
		if material_image == null:
			failures.append("Material '%s' inventory icon did not import as an image." % material.material_id)
			continue
		if material_image.get_width() != material_image.get_height():
			failures.append("Material '%s' inventory icon is not square." % material.material_id)
		if not _texture_has_mipmaps(material.icon_resource):
			failures.append("Material '%s' inventory icon has no mipmaps." % material.material_id)
		for corner in [
			Vector2i(0, 0),
			Vector2i(material_image.get_width() - 1, 0),
			Vector2i(0, material_image.get_height() - 1),
			Vector2i(material_image.get_width() - 1, material_image.get_height() - 1),
		]:
			if material_image.get_pixelv(corner).a > 0.0:
				failures.append("Material '%s' inventory icon has an opaque corner." % material.material_id)
				break
	if not catalog.raider_traits.is_empty():
		failures.append("Production raider trait definitions must remain empty in this pass.")
	var region := ProgressionCatalog.get_region_definition("beast_crucible")
	if region == null or region.bosses.size() != 4:
		failures.append("Beast Crucible does not expose four progression bosses.")
	else:
		var archetypes := {
			"ogre": "warrior", "chainmaster": "priest",
			"carrion_roc": "mage", "twin_maulers": "rogue",
		}
		for boss in region.bosses:
			if not boss.mandatory or boss.apex:
				failures.append("Boss '%s' is not a mandatory non-apex boss." % boss.encounter_id)
			if boss.archetype_class_id != archetypes.get(boss.encounter_id, ""):
				failures.append("Boss '%s' has the wrong archetype." % boss.encounter_id)
			if boss.weapon_ids.size() != 2:
				failures.append("Boss '%s' does not unlock two recipes." % boss.encounter_id)
			var table := ProgressionCatalog.get_reward_table_for_encounter(boss.encounter_id)
			if table == null or table.layers.size() != 3:
				failures.append("Boss '%s' does not have three reward layers." % boss.encounter_id)
				continue
			var counts := {}
			for layer in table.layers:
				counts[layer.layer_id] = [layer.minimum_rolls, layer.maximum_rolls]
			if counts.get("basic") != [2, 4]:
				failures.append("Boss '%s' Basic layer is not 2–4 rolls." % boss.encounter_id)
			if counts.get("valuable") != [1, 1]:
				failures.append("Boss '%s' Valuable layer is not exactly one roll." % boss.encounter_id)
			if counts.get("bonus") != [0, 0]:
				failures.append("Boss '%s' Bonus layer is not configured for zero rolls." % boss.encounter_id)

	for class_id_value in ProgressionCatalogResource.EXPECTED_CLASS_FAMILIES:
		var class_id := String(class_id_value)
		var expected: Array = Array(
			ProgressionCatalogResource.EXPECTED_CLASS_FAMILIES[class_id]
		).duplicate()
		var actual: Array = ProgressionCatalog.get_class_family_ids(class_id)
		expected.sort()
		actual.sort()
		if actual != expected:
			failures.append("Compatibility drift for '%s': %s != %s" % [class_id, actual, expected])

	var expected_default_families := {
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
	var default_icon_paths := {}
	for class_id in RaiderClassCatalog.get_all_class_ids():
		var family_id := RaiderClassCatalog.get_default_weapon_family_id(class_id)
		if family_id != String(expected_default_families.get(class_id, "")):
			failures.append("Class '%s' has the wrong default weapon family." % class_id)
		if not ProgressionCatalog.is_family_compatible(class_id, family_id):
			failures.append(
				"Class '%s' default weapon family '%s' is incompatible." % [class_id, family_id]
			)
		var icon := RaiderClassCatalog.get_default_weapon_icon(class_id)
		if icon == null:
			failures.append("Class '%s' is missing its default weapon icon." % class_id)
			continue
		if icon.get_width() != 64 or icon.get_height() != 64:
			failures.append("Class '%s' default weapon icon is not 64x64." % class_id)
		elif not _texture_has_mipmaps(icon):
			failures.append("Class '%s' default weapon icon has no mipmaps." % class_id)
		var expected_path := "res://icons/weapon_visuals/defaults/%s.png" % family_id
		if icon.resource_path != expected_path:
			failures.append(
				"Class '%s' default weapon icon does not use its family asset." % class_id
			)
		default_icon_paths[icon.resource_path] = true
	if default_icon_paths.size() != 8:
		failures.append("Default weapons do not resolve to exactly eight family icons.")

	var expected_stats := {
		"earthgnasher_heartmaul": [1.15, 0.90, 0.5],
		"faultline_cudgel": [1.08, 1.00, 0.0],
		"litany_of_links": [1.10, 0.95, 2.0],
		"collarhook_blade": [1.06, 1.05, 1.0],
		"carrion_resonator": [1.10, 1.00, 2.0],
		"crashbone_longbow": [1.08, 0.95, 5.0],
		"twin_fang_knives": [1.04, 1.12, 0.0],
		"rampage_maul": [1.13, 0.92, 0.5],
	}
	for weapon_id_value in expected_stats:
		var weapon := ProgressionCatalog.get_weapon(String(weapon_id_value))
		var expected: Array = expected_stats[weapon_id_value]
		if weapon == null or weapon.stat_profile == null:
			failures.append("Missing weapon/stat profile: " + String(weapon_id_value))
			continue
		if weapon.icon_resource == null:
			failures.append("Crafted weapon '%s' is missing its inventory icon." % weapon_id_value)
		elif not _texture_has_mipmaps(weapon.icon_resource):
			failures.append("Crafted weapon '%s' inventory icon has no mipmaps." % weapon_id_value)
		if (
			not is_equal_approx(weapon.stat_profile.power_multiplier, expected[0])
			or not is_equal_approx(weapon.stat_profile.speed_multiplier, expected[1])
			or not is_equal_approx(weapon.stat_profile.range_additive, expected[2])
		):
			failures.append("Weapon stat profile drifted for '%s'." % weapon_id_value)


func _texture_has_mipmaps(texture: Texture2D) -> bool:
	var image := texture.get_image()
	return image != null and image.has_mipmaps()


func _validate_malformed_fixtures(
	catalog: ProgressionCatalogResource, failures: Array[String]
) -> void:
	var invalid := _copy(catalog)
	invalid.weapon_families[0].family_id = "Bad ID"
	_expect_error(invalid, "catalog.weapon_families[0].family_id", failures)

	invalid = _copy(catalog)
	invalid.weapon_families[1].family_id = invalid.weapon_families[0].family_id
	_expect_error(invalid, "duplicates stable ID", failures)

	invalid = _copy(catalog)
	invalid.regions[0].bosses[0].encounter_id = "unknown_encounter"
	_expect_error(invalid, "references unknown encounter", failures)

	invalid = _copy(catalog)
	invalid.weapon_families[0].compatible_class_ids[0] = "unknown_class"
	_expect_error(invalid, "references unknown class", failures)

	invalid = _copy(catalog)
	invalid.weapons[0].family_id = "unknown_family"
	_expect_error(invalid, "references unknown family", failures)

	invalid = _copy(catalog)
	invalid.reward_tables[0].layers[0].entries[0].material_id = "unknown_material"
	_expect_error(invalid, "references unknown material", failures)

	invalid = _copy(catalog)
	invalid.weapons[0].recipe_id = "unknown_recipe"
	_expect_error(invalid, "references unknown recipe", failures)

	invalid = _copy(catalog)
	invalid.regions[0].bosses[0].weapon_ids[0] = "unknown_weapon"
	_expect_error(invalid, "references unknown weapon", failures)

	invalid = _copy(catalog)
	invalid.weapons[0].trait_id = "unknown_trait"
	_expect_error(invalid, "references unknown weapon trait", failures)

	invalid = _copy(catalog)
	invalid.boss_materials[0].rarity_id = "mythic"
	_expect_error(invalid, "references invalid rarity", failures)

	invalid = _copy(catalog)
	var invalid_trait := RaiderTraitDefinition.new()
	invalid_trait.trait_id = "fixture_trait"
	invalid_trait.display_name = "Fixture"
	invalid_trait.tier = "mythic"
	invalid_trait.hook_id = "fixture_hook"
	invalid.raider_traits.append(invalid_trait)
	_expect_error(invalid, "invalid trait tier", failures)

	invalid = _copy(catalog)
	invalid.crafting_recipes[0].ingredients[0].quantity = 0
	_expect_error(invalid, "quantity must be greater than zero", failures)

	invalid = _copy(catalog)
	invalid.weapons[0].stat_profile.power_multiplier = 0.0
	_expect_error(invalid, "power_multiplier must be greater than zero", failures)

	invalid = _copy(catalog)
	invalid.reward_tables[0].layers[0].minimum_rolls = 5
	invalid.reward_tables[0].layers[0].maximum_rolls = 4
	_expect_error(invalid, "roll counts are invalid", failures)

	invalid = _copy(catalog)
	invalid.reward_tables[0].layers[0].entries[0].weight_percent = 44.0
	_expect_error(invalid, "weights must total 100%", failures)

	invalid = _copy(catalog)
	invalid.reward_tables[0].layers[0].entries[0].material_id = "crucible_binding_iron"
	_expect_error(invalid, "excludes rewarding boss", failures)

	invalid = _copy(catalog)
	invalid.crafting_recipes[0].ingredients[0].material_id = "quake_marrow"
	_expect_error(invalid, "requires a rare primary component", failures)

	invalid = _copy(catalog)
	invalid.crafting_recipes[0].ingredients[2].material_id = "shale_caked_hide"
	_expect_error(invalid, "requires a secondary component from another boss", failures)

	invalid = _copy(catalog)
	invalid.weapons[4].family_id = "one_handed_arms"
	_expect_error(invalid, "more than two weapons in family", failures)

	invalid = _copy(catalog)
	invalid.regions[0].bosses[0].weapon_ids = ["earthgnasher_heartmaul"]
	_expect_error(invalid, "exactly two weapons", failures)

	invalid = _copy(catalog)
	invalid.regions[0].bosses[0].archetype_class_id = "mage"
	_expect_error(invalid, "has no archetype-native weapon", failures)

	invalid = _copy(catalog)
	invalid.weapon_families[0].compatible_class_ids.erase("warrior")
	_expect_error(invalid, "compatibility for class 'warrior' must be exactly", failures)


func _copy(catalog: ProgressionCatalogResource) -> ProgressionCatalogResource:
	return catalog.duplicate(true) as ProgressionCatalogResource


func _expect_error(
	catalog: ProgressionCatalogResource, fragment: String, failures: Array[String]
) -> void:
	var errors := catalog.get_validation_errors()
	for validation_error in errors:
		if validation_error.contains(fragment):
			return
	failures.append("Malformed fixture did not report '%s'. Actual: %s" % [fragment, errors])


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("RAID_TEST_PASS:progression_catalog_contract | Progression catalog contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
