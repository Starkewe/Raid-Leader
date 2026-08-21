extends "res://scripts/ui/facility_page_presenter.gd"
class_name SmithPagePresenter

const SmithDragSourceScript := preload("res://scripts/ui/smith_drag_source.gd")
const SmithArmoryDropZoneScript := preload(
	"res://scripts/ui/smith_armory_drop_zone.gd"
)

const TAB_FORGE := "forge"
const TAB_ARMORY := "armory"
const FORGE_RECIPE_LIST_WIDTH := 270.0
const FORGE_CONTENT_MIN_HEIGHT := 500.0

var selected_family_id: String = ""
var selected_tab: String = TAB_FORGE
var selected_recipe_id: String = ""
var pending_recipe_id: String = ""
var action_message: String = ""
var last_action_result: Dictionary = {}
var _journal: Node = null
var _confirmation_dialog: ConfirmationDialog = null


func present(journal: Node) -> void:
	_journal = journal
	var header := journal.get("header_title") as Label
	if header != null:
		header.text = "The Smith's Forge"
	_ensure_confirmation_dialog()
	var page := journal.call("_begin_scrolling_page") as VBoxContainer
	if page == null:
		return
	page.name = "SmithPage"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_intro(page)
	var model := build_view_model()
	if selected_family_id.is_empty():
		_add_category_gate(page, model)
	else:
		_add_selected_family_navigation(page, model)
	_add_action_message(page)


func build_view_model() -> Dictionary:
	return build_forge_view_model()


func build_forge_view_model() -> Dictionary:
	var categories := _build_weapon_categories()
	var recipes: Array[Dictionary] = []
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		var entry := _build_recipe_entry(recipe_id)
		if entry.is_empty():
			continue
		if selected_family_id.is_empty() or not _entry_matches_selected_family(entry):
			continue
		recipes.append(entry)
	recipes.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("display_name", "")).naturalnocasecmp_to(
				String(b.get("display_name", ""))
			) < 0
	)
	var selected := _select_entry(recipes, selected_recipe_id, "recipe_id")
	selected_recipe_id = String(selected.get("recipe_id", ""))
	var holders := _build_equip_raiders()
	var all_weapons := _build_weapon_entries()
	var weapons: Array[Dictionary] = []
	for weapon in all_weapons:
		if not selected_family_id.is_empty() and _entry_matches_selected_family(weapon, true):
			weapons.append(weapon)
	var reserve_recoveries := _build_reserve_recovery_entries(weapons)
	var selected_family := ProgressionCatalog.get_weapon_family(selected_family_id)
	var selected_family_name := "" if selected_family == null else selected_family.display_name
	return {
		"categories": categories,
		"weapon_families": categories,
		"weapon_categories": categories,
		"category_gate": selected_family_id.is_empty(),
		"show_category_gate": selected_family_id.is_empty(),
		"selected_family_id": selected_family_id,
		"selected_family_name": selected_family_name,
		"selected_family": {
			"family_id": selected_family_id,
			"display_name": selected_family_name,
		} if not selected_family_id.is_empty() else {},
		"selected_tab": selected_tab,
		"active_tab": selected_tab,
		"recipes": recipes,
		"filtered_recipes": recipes,
		"forge_recipes": recipes,
		"filtered_forge_entries": recipes,
		"entries": recipes,
		"selected_recipe": selected,
		"selected_recipe_id": String(selected.get("recipe_id", "")),
		"empty_state": _forge_empty_state(),
		"holders": holders,
		"weapons": weapons,
		"filtered_weapons": weapons,
		"armory_weapons": weapons,
		"filtered_armory_entries": weapons,
		"filtered_armory": weapons,
		"reserve_recoveries": reserve_recoveries,
		"filtered_reserve_recoveries": reserve_recoveries,
		"armory_empty_state": "No weapons are available in this weapon type.",
		"action_message": action_message,
	}


func reset_navigation() -> void:
	selected_family_id = ""
	selected_tab = TAB_FORGE
	selected_recipe_id = ""
	pending_recipe_id = ""
	action_message = ""
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		_confirmation_dialog.hide()
	_set_smith_drawer_family_filter("")
	_queue_refresh()


func select_family(family_id: String) -> bool:
	var family := ProgressionCatalog.get_weapon_family(family_id)
	if family == null or not _is_family_unlocked(family_id):
		return false
	selected_family_id = family_id
	selected_tab = TAB_FORGE
	selected_recipe_id = ""
	_set_smith_drawer_family_filter(family_id)
	_queue_refresh()
	return true


func select_weapon_family(family_id: String) -> bool:
	return select_family(family_id)


func select_tab(tab_id: String) -> bool:
	var normalized := tab_id.to_lower()
	if selected_family_id.is_empty() or normalized not in [TAB_FORGE, TAB_ARMORY]:
		return false
	selected_tab = normalized
	_queue_refresh()
	return true


func select_weapon_tab(tab_id: String) -> bool:
	return select_tab(tab_id)


func back_to_weapon_types() -> void:
	reset_navigation()


func select_recipe(recipe_id: String) -> bool:
	var entry := _build_recipe_entry(recipe_id)
	if entry.is_empty() or (
		not selected_family_id.is_empty() and not _entry_matches_selected_family(entry)
	):
		return false
	selected_recipe_id = recipe_id
	_queue_refresh()
	return true


func request_craft_confirmation(recipe_id: String) -> Dictionary:
	var entry := _build_recipe_entry(recipe_id)
	if entry.is_empty():
		return {
			"ok": false,
			"status": "unknown_definition",
			"message": "That unlocked recipe is unavailable.",
		}
	if not selected_family_id.is_empty() and not _entry_matches_selected_family(entry):
		return {
			"ok": false,
			"status": "wrong_weapon_family",
			"message": "Select the weapon type that contains this design first.",
		}
	if not bool(entry.get("craftable", false)):
		return {
			"ok": false,
			"status": String(entry.get("craft_status", "unavailable")),
			"message": String(entry.get("disabled_reason", "Crafting is unavailable.")),
		}
	pending_recipe_id = recipe_id
	_ensure_confirmation_dialog()
	var cost_lines: Array[String] = []
	for component_value in entry.get("components", []):
		var component: Dictionary = component_value
		cost_lines.append("• %s ×%d" % [
			String(component.get("display_name", component.get("material_id", "Unknown"))),
			int(component.get("required", 0)),
		])
	var prompt := "%s %s?\n\nExact component cost:\n%s" % [
		"Forge",
		String(entry.get("display_name", entry.get("weapon_id", "Weapon"))),
		"\n".join(cost_lines),
	]
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		_confirmation_dialog.dialog_text = prompt
		_confirmation_dialog.ok_button_text = "Forge Weapon"
		if _journal.has_method("popup_in_right_half"):
			_journal.call("popup_in_right_half", _confirmation_dialog)
		else:
			_confirmation_dialog.popup_centered()
	return {
		"ok": true,
		"status": "confirmation_required",
		"message": prompt,
		"recipe_id": recipe_id,
		"weapon_id": String(entry.get("weapon_id", "")),
		"components": Array(entry.get("components", [])).duplicate(true),
		"crafted_count": int(entry.get("crafted_count", 0)),
	}


func cancel_pending_craft() -> void:
	pending_recipe_id = ""
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		_confirmation_dialog.hide()


func confirm_pending_craft() -> Dictionary:
	if pending_recipe_id.is_empty():
		return {
			"ok": false,
			"status": "no_pending_confirmation",
			"message": "No weapon is awaiting confirmation.",
		}
	var recipe_id := pending_recipe_id
	pending_recipe_id = ""
	last_action_result = CampaignState.craft(recipe_id)
	if bool(last_action_result.get("ok", false)):
		action_message = ""
	else:
		action_message = String(last_action_result.get("message", "Crafting failed."))
	_queue_refresh()
	return last_action_result.duplicate(true)


func _build_weapon_categories() -> Array[Dictionary]:
	var unlocked_family_ids: Dictionary = {}
	var unlocked_recipe_counts: Dictionary = {}
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		var recipe := ProgressionCatalog.get_recipe(recipe_id)
		if recipe == null:
			continue
		var weapon := ProgressionCatalog.get_weapon(recipe.output_weapon_id)
		if weapon == null:
			continue
		var family_id := String(weapon.family_id)
		unlocked_family_ids[family_id] = true
		unlocked_recipe_counts[family_id] = int(unlocked_recipe_counts.get(family_id, 0)) + 1
	var result: Array[Dictionary] = []
	var catalog := ProgressionCatalog.get_catalog()
	if catalog == null:
		return result
	for family_value in catalog.weapon_families:
		var family: WeaponFamilyDefinition = family_value
		if family == null:
			continue
		var unlocked := bool(unlocked_family_ids.get(family.family_id, false))
		result.append({
			"family_id": family.family_id,
			"weapon_family_id": family.family_id,
			"display_name": family.display_name,
			"unlocked": unlocked,
			"is_unlocked": unlocked,
			"has_unlocked_design": unlocked,
			"enabled": unlocked,
			"locked": not unlocked,
			"disabled": not unlocked,
			"recipe_count": int(unlocked_recipe_counts.get(family.family_id, 0)),
		})
	return result


func _is_family_unlocked(family_id: String) -> bool:
	for category_value in _build_weapon_categories():
		var category: Dictionary = category_value
		if String(category.get("family_id", "")) == family_id:
			return bool(category.get("unlocked", false))
	return false


func _entry_matches_selected_family(
	entry: Dictionary, include_unknown: bool = false
) -> bool:
	if selected_family_id.is_empty():
		return false
	var family_id := String(entry.get("family_id", entry.get("weapon_family_id", "")))
	if family_id == selected_family_id:
		return true
	return include_unknown and bool(entry.get("missing_content", false))


func _set_smith_drawer_family_filter(family_id: String) -> void:
	if _journal == null or not is_instance_valid(_journal):
		return
	var drawer := _journal.get_tree().get_first_node_in_group("camp_raid_drawer")
	if drawer != null and drawer.has_method("set_smith_family_filter"):
		drawer.call("set_smith_family_filter", family_id)


func _build_recipe_entry(recipe_id: String) -> Dictionary:
	if not CampaignState.is_recipe_unlocked(recipe_id):
		return {}
	var recipe := ProgressionCatalog.get_recipe(recipe_id)
	if recipe == null:
		return {
			"recipe_id": recipe_id,
			"stable_id": recipe_id,
			"weapon_id": "",
			"display_name": recipe_id + " [Missing Content]",
			"description": "Unlocked recipe definition is unavailable.",
			"boss_id": "",
			"boss_name": "Unknown",
			"source_boss_id": "",
			"source_boss_name": "Unknown",
			"family_id": "",
			"family_name": "Unknown",
			"weapon_family_id": "",
			"weapon_family_name": "Unknown",
			"category": "Unknown",
			"power_percentage": 0.0,
			"power_percent": 0.0,
			"power_multiplier": 1.0,
			"speed_percentage": 0.0,
			"speed_percent": 0.0,
			"speed_multiplier": 1.0,
			"range_units": 0.0,
			"range_additive": 0.0,
			"attributes": {"power_percentage": 0.0, "speed_percentage": 0.0, "range_units": 0.0},
			"trait": _inactive_trait("Missing trait", "Definition unavailable."),
			"trait_text": "Trait — Missing trait: Definition unavailable. (inactive placeholder)",
			"icon_resource": null,
			"components": [],
			"craftable": false,
			"crafted": false,
			"crafted_count": 0,
			"craft_status": "unknown_definition",
			"disabled_reason": "This unlocked recipe definition is unavailable.",
		}
	var weapon := ProgressionCatalog.get_weapon(recipe.output_weapon_id)
	var boss := ProgressionCatalog.get_boss_definition(recipe.source_encounter_id)
	var family = null if weapon == null else ProgressionCatalog.get_weapon_family(weapon.family_id)
	var weapon_trait = null if weapon == null else ProgressionCatalog.get_weapon_trait(weapon.trait_id)
	var craft_check := CampaignState.check_craft(recipe_id)
	var components: Array[Dictionary] = []
	for ingredient in recipe.ingredients:
		if ingredient == null:
			continue
		var material := ProgressionCatalog.get_material(ingredient.material_id)
		var rarity = null if material == null else ProgressionCatalog.get_material_rarity(material.rarity_id)
		var owned := CampaignState.get_material_count(ingredient.material_id)
		var source_text := _material_source_text(material)
		components.append({
			"material_id": ingredient.material_id,
			"display_name": ingredient.material_id if material == null else material.display_name,
			"description": (
				"Material definition unavailable."
				if material == null else material.description
			),
			"icon_resource": null if material == null else material.icon_resource,
			"rarity_id": "missing" if material == null else material.rarity_id,
			"rarity_text": (
				"Missing" if material == null
				else material.rarity_id.capitalize() if rarity == null
				else rarity.display_name
			),
			"rarity_color": Color("d16d6d") if rarity == null else rarity.display_color,
			"owned": owned,
			"required": ingredient.quantity,
			"missing": maxi(ingredient.quantity - owned, 0),
			"shortage": maxi(ingredient.quantity - owned, 0),
			"source_text": source_text,
			"tooltip_text": _material_tooltip(
				material, ingredient.material_id, owned, ingredient.quantity, source_text
			),
		})
	var family_id := "" if weapon == null else weapon.family_id
	var family_name: String = family_id if family == null else family.display_name
	var trait_name: String = "Unknown" if weapon_trait == null else weapon_trait.display_name
	var trait_description: String = "Definition unavailable." if weapon_trait == null else weapon_trait.description
	var stats := null if weapon == null else weapon.stat_profile
	return {
		"recipe_id": recipe.recipe_id,
		"stable_id": recipe.recipe_id,
		"weapon_id": recipe.output_weapon_id,
		"display_name": recipe.display_name if weapon == null else weapon.display_name,
		"recipe_display_name": recipe.display_name,
		"description": "Weapon definition unavailable." if weapon == null else weapon.description,
		"icon_resource": null if weapon == null else weapon.icon_resource,
		"boss_id": recipe.source_encounter_id,
		"boss_name": recipe.source_encounter_id if boss == null else boss.display_name,
		"source_boss_id": recipe.source_encounter_id,
		"source_boss_name": recipe.source_encounter_id if boss == null else boss.display_name,
		"family_id": family_id,
		"family_name": family_name,
		"weapon_family_id": family_id,
		"weapon_family_name": family_name,
		"category": family_name,
		"power_percentage": 0.0 if stats == null else (stats.power_multiplier - 1.0) * 100.0,
		"power_percent": 0.0 if stats == null else (stats.power_multiplier - 1.0) * 100.0,
		"power_multiplier": 1.0 if stats == null else stats.power_multiplier,
		"speed_percentage": 0.0 if stats == null else (stats.speed_multiplier - 1.0) * 100.0,
		"speed_percent": 0.0 if stats == null else (stats.speed_multiplier - 1.0) * 100.0,
		"speed_multiplier": 1.0 if stats == null else stats.speed_multiplier,
		"range_units": 0.0 if stats == null else stats.range_additive,
		"range_additive": 0.0 if stats == null else stats.range_additive,
		"attributes": {
			"power_percentage": 0.0 if stats == null else (stats.power_multiplier - 1.0) * 100.0,
			"speed_percentage": 0.0 if stats == null else (stats.speed_multiplier - 1.0) * 100.0,
			"range_units": 0.0 if stats == null else stats.range_additive,
		},
		"trait": _inactive_trait(trait_name, trait_description),
		"trait_text": "Trait — %s: %s (inactive placeholder)" % [trait_name, trait_description],
		"components": components,
		"craftable": bool(craft_check.get("ok", false)),
		"crafted": CampaignState.owns_crafted_weapon(recipe.output_weapon_id),
		"crafted_count": CampaignState.get_crafted_weapon_count(recipe.output_weapon_id),
		"craft_status": String(craft_check.get("status", "unknown")),
		"disabled_reason": _craft_disabled_reason(craft_check, components),
	}


func _build_equip_raiders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active_ids := CampaignState.get_active_member_ids()
	for raider_id in active_ids:
		var member := CampaignState.get_member(raider_id)
		if not member.is_empty():
			result.append(_raider_entry(member, true))
	for member in CampaignState.get_roster_members():
		var raider_id := String(member.get("member_id", ""))
		if active_ids.has(raider_id):
			continue
		if not String(member.get("equipped_weapon_id", "")).is_empty():
			result.append(_raider_entry(member, false))
	return result


func _raider_entry(member: Dictionary, active: bool) -> Dictionary:
	var advanced_id := String(member.get("advanced_class_id", ""))
	var class_id := RaiderClassCatalog.normalize_class_id(
		String(member.get("unit_class", "")) if advanced_id.is_empty() else advanced_id
	)
	var class_definition := RaiderClassCatalog.get_definition(class_id)
	var weapon_id := String(member.get("equipped_weapon_id", ""))
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	return {
		"raider_id": String(member.get("member_id", "")),
		"stable_id": String(member.get("member_id", "")),
		"display_name": String(member.get("display_name", member.get("member_id", "Raider"))),
		"label": "%s%s" % [
			String(member.get("display_name", member.get("member_id", "Raider"))),
			" — Reserve holder" if not active else "",
		],
		"class_id": class_id,
		"class_name": String(class_definition.get("unit_class", class_id.capitalize())),
		"active": active,
		"reserve_holder": not active,
		"can_receive_assignments": active,
		"equipped_weapon_id": weapon_id,
		"equipped_weapon_name": (
			"None" if weapon_id.is_empty()
			else weapon_id + " [Missing Content]" if weapon == null
			else weapon.display_name
		),
		"equipped_weapon_missing": not weapon_id.is_empty() and weapon == null,
	}


func _build_weapon_entries() -> Array[Dictionary]:
	var weapon_ids: Array[String] = []
	for crafted_weapon_id in CampaignState.get_crafted_weapon_ids():
		if not weapon_ids.has(crafted_weapon_id):
			weapon_ids.append(crafted_weapon_id)
	for raider in _build_equip_raiders():
		var equipped_id := String(raider.get("equipped_weapon_id", ""))
		if not equipped_id.is_empty() and not weapon_ids.has(equipped_id):
			weapon_ids.append(equipped_id)
	var result: Array[Dictionary] = []
	for weapon_id in weapon_ids:
		result.append(_build_weapon_entry(weapon_id))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("display_name", "")).naturalnocasecmp_to(
				String(b.get("display_name", ""))
			) < 0
	)
	return result


func _build_weapon_entry(weapon_id: String) -> Dictionary:
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	var holder_ids := CampaignState.get_equipped_raider_ids(weapon_id)
	var active_holder_ids: Array[String] = []
	var reserve_holder_ids: Array[String] = []
	var active_holder_names: Array[String] = []
	var reserve_holder_names: Array[String] = []
	for holder_id_value in holder_ids:
		var holder_id := String(holder_id_value)
		if CampaignState.is_member_active(holder_id):
			active_holder_ids.append(holder_id)
			active_holder_names.append(CampaignState.get_member_label(holder_id))
		else:
			reserve_holder_ids.append(holder_id)
			reserve_holder_names.append(CampaignState.get_member_label(holder_id))
	var first_holder_id := "" if holder_ids.is_empty() else String(holder_ids[0])
	var crafted_count := CampaignState.get_crafted_weapon_count(weapon_id)
	var equipped_count := holder_ids.size()
	var available_count := CampaignState.get_available_weapon_count(weapon_id)
	var count_label := "EQUIPPED %d/%d" % [equipped_count, crafted_count]
	if weapon == null:
		return {
			"weapon_id": weapon_id,
			"stable_id": weapon_id,
			"display_name": weapon_id + " [Missing Content]",
			"description": "Saved weapon ID retained for recovery; its definition is unavailable.",
			"missing_content": true,
			"crafted": CampaignState.owns_crafted_weapon(weapon_id),
			"family_id": "",
			"family_name": "Unknown",
			"weapon_family_id": "",
			"weapon_family_name": "Unknown",
			"category": "Unknown",
			"power_percentage": 0.0,
			"power_percent": 0.0,
			"power_multiplier": 1.0,
			"speed_percentage": 0.0,
			"speed_percent": 0.0,
			"speed_multiplier": 1.0,
			"range_units": 0.0,
			"range_additive": 0.0,
			"attributes": {"power_percentage": 0.0, "speed_percentage": 0.0, "range_units": 0.0},
			"trait": _inactive_trait("Missing trait", "Definition unavailable."),
			"trait_text": "Trait — Missing trait: Definition unavailable. (inactive placeholder)",
			"crafted_count": crafted_count,
			"equipped_count": equipped_count,
			"available_count": available_count,
			"holder_id": first_holder_id,
			"holder_ids": holder_ids,
			"active_holder_ids": active_holder_ids,
			"reserve_holder_ids": reserve_holder_ids,
			"active_holder_names": active_holder_names,
			"reserve_holder_names": reserve_holder_names,
			"current_holder_id": first_holder_id,
			"holder_name": "Unassigned" if first_holder_id.is_empty() else CampaignState.get_member_label(first_holder_id),
			"compatibility_text": "Unavailable — missing content",
			"disabled_reason": "Missing content is inactive. Return it to the armory to clear the saved slot.",
			"icon_resource": null,
			"compatible_raider_names": [],
			"holder_active": not active_holder_ids.is_empty(),
			"holder_reserve": not reserve_holder_ids.is_empty(),
			"assignment_label": count_label,
			"drag_type": "",
			"drag_source_raider_id": "",
			"can_drag": false,
			"drag_disabled_reason": "Missing content is unavailable. Use a holder recovery entry or active raid-frame icon to return it.",
		}
	var family := ProgressionCatalog.get_weapon_family(weapon.family_id)
	var weapon_trait := ProgressionCatalog.get_weapon_trait(weapon.trait_id)
	var family_name := weapon.family_id if family == null else family.display_name
	var compatible_raider_names := _compatible_active_member_names(weapon.family_id)
	var trait_name := weapon.trait_id if weapon_trait == null else weapon_trait.display_name
	var trait_description := "Definition unavailable." if weapon_trait == null else weapon_trait.description
	var can_drag := available_count > 0 and not compatible_raider_names.is_empty()
	return {
		"weapon_id": weapon.weapon_id,
		"stable_id": weapon.weapon_id,
		"display_name": weapon.display_name,
		"description": weapon.description,
		"missing_content": false,
		"crafted": CampaignState.owns_crafted_weapon(weapon_id),
		"family_id": weapon.family_id,
		"family_name": family_name,
		"weapon_family_id": weapon.family_id,
		"weapon_family_name": family_name,
		"category": family_name,
		"power_percentage": (weapon.stat_profile.power_multiplier - 1.0) * 100.0,
		"power_percent": (weapon.stat_profile.power_multiplier - 1.0) * 100.0,
		"power_multiplier": weapon.stat_profile.power_multiplier,
		"speed_percentage": (weapon.stat_profile.speed_multiplier - 1.0) * 100.0,
		"speed_percent": (weapon.stat_profile.speed_multiplier - 1.0) * 100.0,
		"speed_multiplier": weapon.stat_profile.speed_multiplier,
		"range_units": weapon.stat_profile.range_additive,
		"range_additive": weapon.stat_profile.range_additive,
		"attributes": {
			"power_percentage": (weapon.stat_profile.power_multiplier - 1.0) * 100.0,
			"speed_percentage": (weapon.stat_profile.speed_multiplier - 1.0) * 100.0,
			"range_units": weapon.stat_profile.range_additive,
		},
		"trait": _inactive_trait(trait_name, trait_description),
		"trait_text": "Trait — %s: %s (inactive placeholder)" % [trait_name, trait_description],
		"crafted_count": crafted_count,
		"equipped_count": equipped_count,
		"available_count": available_count,
		"holder_id": first_holder_id,
		"holder_ids": holder_ids,
		"active_holder_ids": active_holder_ids,
		"reserve_holder_ids": reserve_holder_ids,
		"active_holder_names": active_holder_names,
		"reserve_holder_names": reserve_holder_names,
		"current_holder_id": first_holder_id,
		"holder_name": "Unassigned" if first_holder_id.is_empty() else CampaignState.get_member_label(first_holder_id),
		"icon_resource": weapon.icon_resource,
		"compatible_raider_names": compatible_raider_names,
		"holder_active": not active_holder_ids.is_empty(),
		"holder_reserve": not reserve_holder_ids.is_empty(),
		"assignment_label": count_label,
		"drag_type": "smith_armory_weapon" if available_count > 0 else "",
		"drag_source_raider_id": "",
		"can_drag": can_drag,
		"drag_disabled_reason": (
			"All crafted copies are assigned. Move active copies from raid-frame icons or reclaim a reserve copy."
			if available_count <= 0
			else "No active raider is compatible with this weapon family."
			if compatible_raider_names.is_empty()
			else ""
		),
	}


func _compatible_active_member_names(family_id: String) -> Array[String]:
	var result: Array[String] = []
	for member in CampaignState.get_active_members():
		var advanced_id := String(member.get("advanced_class_id", ""))
		var class_id := RaiderClassCatalog.normalize_class_id(
			advanced_id if not advanced_id.is_empty() else String(member.get("unit_class", ""))
		)
		if ProgressionCatalog.is_family_compatible(class_id, family_id):
			result.append(String(member.get("display_name", member.get("member_id", "Raider"))))
	return result


func _build_reserve_recovery_entries(
	weapons: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon in weapons:
		for holder_id_value in weapon.get("reserve_holder_ids", []):
			var holder_id := String(holder_id_value)
			var entry := weapon.duplicate(true)
			entry["recovery_id"] = "%s_%s" % [
				weapon.get("weapon_id", "weapon"), holder_id,
			]
			entry["source_raider_id"] = holder_id
			entry["holder_name"] = CampaignState.get_member_label(holder_id)
			entry["drag_type"] = "smith_reserve_weapon"
			entry["can_drag"] = true
			result.append(entry)
	return result


func _add_intro(page: VBoxContainer) -> void:
	var intro_text := "Shape the spoils of fallen foes into weapons for your raiders."
	if _journal != null and _journal.has_method("set_header_intro"):
		_journal.call("set_header_intro", "SmithIntro", intro_text)
		return
	var intro := Label.new()
	intro.name = "SmithIntro"
	intro.text = intro_text
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("b9b29f"))
	page.add_child(intro)


func _add_category_gate(page: VBoxContainer, model: Dictionary) -> void:
	var heading := _add_heading(page, "Weapon Types", 22)
	heading.name = "SmithWeaponTypesHeading"
	var grid := GridContainer.new()
	grid.name = "SmithCategoryGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	page.add_child(grid)
	for category_value in model.get("categories", []):
		var category: Dictionary = category_value
		var family_id := String(category.get("family_id", ""))
		var button := Button.new()
		button.name = "SmithCategory_" + family_id
		button.add_to_group("smith_weapon_categories")
		button.text = String(category.get("display_name", family_id))
		button.tooltip_text = (
			"Select this weapon type."
			if bool(category.get("unlocked", false))
			else "Locked — defeat a source boss to unlock a design."
		)
		button.disabled = bool(category.get("disabled", true))
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_color_override("font_color", Color("c9b37b"))
		button.pressed.connect(_on_family_selected.bind(family_id))
		grid.add_child(button)


func _add_selected_family_navigation(page: VBoxContainer, model: Dictionary) -> void:
	var selected_layout := HBoxContainer.new()
	selected_layout.name = "SmithForgeLayout" if selected_tab == TAB_FORGE else "SmithArmoryLayout"
	selected_layout.custom_minimum_size = Vector2(0, FORGE_CONTENT_MIN_HEIGHT)
	selected_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selected_layout.add_theme_constant_override("separation", 12)
	page.add_child(selected_layout)

	var item_section := VBoxContainer.new()
	item_section.name = "SmithItemSection"
	item_section.custom_minimum_size = Vector2(FORGE_RECIPE_LIST_WIDTH, 0)
	item_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_section.add_theme_constant_override("separation", 7)
	selected_layout.add_child(item_section)

	var navigation := VBoxContainer.new()
	navigation.name = "SmithSelectedFamilyNavigation"
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_theme_constant_override("separation", 7)
	item_section.add_child(navigation)

	var tabs := HBoxContainer.new()
	tabs.name = "SmithTabs"
	tabs.custom_minimum_size = Vector2(0, 40)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", 6)
	navigation.add_child(tabs)
	for tab_value in [TAB_FORGE, TAB_ARMORY]:
		var tab_button := Button.new()
		tab_button.name = "Smith" + tab_value.capitalize() + "Tab"
		tab_button.text = tab_value.capitalize()
		tab_button.custom_minimum_size = Vector2(0, 40)
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.disabled = selected_tab == tab_value
		tab_button.set_meta("smith_tab_id", tab_value)
		tab_button.set_meta("smith_tab_selected", selected_tab == tab_value)
		tab_button.pressed.connect(_on_tab_selected.bind(tab_value))
		_style_smith_tab_button(tab_button, selected_tab == tab_value)
		tabs.add_child(tab_button)

	var selected_heading := _add_heading(
		navigation, String(model.get("selected_family_name", "Weapon Type")), 20
	)
	selected_heading.name = "SmithSelectedFamilyHeading"
	selected_heading.add_theme_color_override("font_color", Color("c9b37b"))
	selected_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var detail_section := VBoxContainer.new()
	detail_section.name = "SmithDetailSection"
	detail_section.custom_minimum_size = Vector2(0, FORGE_CONTENT_MIN_HEIGHT)
	detail_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_section.add_theme_constant_override("separation", 8)
	selected_layout.add_child(detail_section)

	if selected_tab == TAB_ARMORY:
		_add_armory_view(item_section, detail_section, model)
	else:
		_add_forge_view(item_section, detail_section, model)


func _style_smith_tab_button(button: Button, selected: bool) -> void:
	button.add_theme_color_override("font_color", Color("e8dfc7") if selected else Color("aeb8ba"))
	button.add_theme_color_override("font_disabled_color", Color("e8dfc7"))
	button.add_theme_stylebox_override(
		"normal", _button_style("39464b" if selected else "1d2a31", "c9b37b" if selected else "4a575b")
	)
	button.add_theme_stylebox_override("hover", _button_style("46545a", "d5c18a"))
	button.add_theme_stylebox_override("pressed", _button_style("39464b", "c9b37b"))
	button.add_theme_stylebox_override("disabled", _button_style("39464b", "c9b37b"))


func _add_forge_view(item_section: VBoxContainer, detail_section: VBoxContainer, model: Dictionary) -> void:
	var recipes: Array = model.get("recipes", [])
	var list_scroll := ScrollContainer.new()
	list_scroll.name = "SmithRecipeListScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.custom_minimum_size = Vector2(FORGE_RECIPE_LIST_WIDTH, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_section.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.name = "SmithRecipeList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(FORGE_RECIPE_LIST_WIDTH, 0)
	list.add_theme_constant_override("separation", 7)
	list_scroll.add_child(list)

	if recipes.is_empty():
		var empty := _make_muted_label(String(model.get("empty_state", "No recipes available.")))
		empty.name = "SmithForgeEmptyState"
		list.add_child(empty)
		return
	for recipe_value in recipes:
		var recipe: Dictionary = recipe_value
		var button := Button.new()
		button.name = "SmithRecipe_" + String(recipe.get("recipe_id", "recipe"))
		button.text = "%s\n%s · %s%s" % [
			String(recipe.get("display_name", "Unknown")),
			String(recipe.get("boss_name", "Unknown source")),
			String(recipe.get("family_name", "Unknown family")),
			"",
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(260, 62)
		button.pressed.connect(_on_recipe_selected.bind(String(recipe.get("recipe_id", ""))))
		list.add_child(button)
	var selected: Dictionary = model.get("selected_recipe", {})
	if not selected.is_empty():
		_add_recipe_details(detail_section, selected)
		_add_forge_footer(detail_section, selected)


func _add_recipe_details(parent: Control, recipe: Dictionary) -> void:
	var details := VBoxContainer.new()
	details.name = "SmithRecipeDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 7)
	parent.add_child(details)
	_add_weapon_art(details, recipe)
	var recipe_title := _add_heading(details, String(recipe.get("display_name", "Unknown weapon")), 24)
	recipe_title.add_theme_color_override("font_color", Color("c9b37b"))
	var info_label := _add_wrapped_label(details, String(recipe.get("description", "")), Color("c9b37b"))
	info_label.name = "SmithRecipeInfo"
	var source_label := _add_wrapped_label(
		details, "Source: %s" % String(recipe.get("boss_name", "Unknown")), Color("b8bdba")
	)
	source_label.name = "SmithRecipeSource"
	_add_stat_rows(details, recipe)
	_add_wrapped_label(details, String(recipe.get("trait_text", "")), Color("9aa5aa"))


func _add_forge_footer(parent: VBoxContainer, recipe: Dictionary) -> void:
	var footer := VBoxContainer.new()
	footer.name = "SmithForgeFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 8)
	parent.add_child(footer)

	var component_slots := _add_component_slots(footer, recipe.get("components", []))
	component_slots.alignment = FlowContainer.ALIGNMENT_CENTER

	var craft_button := Button.new()
	craft_button.name = "SmithCraftButton"
	craft_button.text = "Forge"
	craft_button.disabled = not bool(recipe.get("craftable", false))
	craft_button.custom_minimum_size = Vector2(280, 44)
	craft_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	craft_button.pressed.connect(
		request_craft_confirmation.bind(String(recipe.get("recipe_id", "")))
	)
	footer.add_child(craft_button)
	if craft_button.disabled:
		var reason := _make_muted_label(String(recipe.get("disabled_reason", "Crafting unavailable.")))
		reason.name = "SmithCraftDisabledReason"
		reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer.add_child(reason)


func _add_weapon_art(parent: Control, recipe: Dictionary) -> void:
	var frame := PanelContainer.new()
	frame.name = "SmithWeaponArtFrame"
	frame.custom_minimum_size = Vector2(0, 280)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("10171d")
	frame_style.border_color = Color("3f4b50")
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
	parent.add_child(frame)
	var art := TextureRect.new()
	art.name = "SmithWeaponArtwork"
	art.custom_minimum_size = Vector2(0, 276)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = recipe.get("icon_resource") as Texture2D
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	if art.texture == null:
		var placeholder := Label.new()
		placeholder.name = "SmithWeaponArtworkPlaceholder"
		placeholder.text = "WEAPON ART\nUNAVAILABLE"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.add_theme_color_override("font_color", Color("777f82"))
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(placeholder)


func _add_component_slots(parent: Control, components: Array) -> HFlowContainer:
	var slots := HFlowContainer.new()
	slots.name = "SmithComponentSlots"
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_theme_constant_override("h_separation", 10)
	slots.add_theme_constant_override("v_separation", 10)
	parent.add_child(slots)
	for component_value in components:
		_add_component_slot(slots, Dictionary(component_value))
	return slots


func _add_component_slot(parent: Control, component: Dictionary) -> void:
	var material_id := String(component.get("material_id", "material"))
	var missing := int(component.get("missing", 0)) > 0
	var icon := component.get("icon_resource") as Texture2D
	var slot := PanelContainer.new()
	slot.name = "SmithComponent_" + material_id
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.custom_minimum_size = Vector2(98, 116)
	slot.tooltip_text = _component_tooltip(component)
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color("182126")
	slot_style.border_color = (
		Color("e19a91") if missing else component.get("rarity_color", Color("8f968f")) as Color
	)
	slot_style.set_border_width_all(2 if missing else 1)
	slot_style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", slot_style)
	parent.add_child(slot)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 3)
	slot.add_child(content)
	var icon_holder := CenterContainer.new()
	icon_holder.name = "SmithComponentIconHolder"
	icon_holder.custom_minimum_size = Vector2(92, 86)
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_holder)
	if icon == null:
		var placeholder := Label.new()
		placeholder.name = "SmithComponentIconPlaceholder"
		placeholder.text = "?"
		placeholder.add_theme_font_size_override("font_size", 38)
		placeholder.add_theme_color_override("font_color", Color("d16d6d"))
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_holder.add_child(placeholder)
	else:
		var icon_rect := TextureRect.new()
		icon_rect.name = "SmithComponentIcon"
		icon_rect.custom_minimum_size = Vector2(82, 82)
		icon_rect.texture = icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_holder.add_child(icon_rect)
	var count := Label.new()
	count.name = "SmithComponentCount"
	count.text = "%d/%d" % [int(component.get("owned", 0)), int(component.get("required", 0))]
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override(
		"font_color", Color("e19a91") if missing else Color("d5d4ca")
	)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(count)


func _component_tooltip(component: Dictionary) -> String:
	var display_name := String(component.get("display_name", component.get("material_id", "Unknown material")))
	var owned := int(component.get("owned", 0))
	var required := int(component.get("required", 0))
	var description := String(component.get("description", "Material definition unavailable."))
	var source := String(component.get("source_text", component.get("source", "Unknown Source")))
	if source.is_empty():
		source = "Unknown Source"
	return "%s\nCount: %d/%d\n%s\nSource: %s" % [
		display_name, owned, required, description, source,
	]


func _add_stat_rows(parent: Control, weapon_entry: Dictionary) -> void:
	var stats := VBoxContainer.new()
	stats.name = "SmithWeaponStats"
	stats.add_theme_constant_override("separation", 3)
	parent.add_child(stats)
	_add_stat_row(
		stats, "Power", float(weapon_entry.get("power_percentage", 0.0)), "%+.0f%%"
	)
	_add_stat_row(
		stats, "Speed", float(weapon_entry.get("speed_percentage", 0.0)), "%+.0f%%"
	)
	_add_stat_row(
		stats, "Range", float(weapon_entry.get("range_units", 0.0)), "%+.1f units"
	)


func _add_stat_row(
	parent: Control, label_text: String, value: float, format_string: String
) -> void:
	var row := HBoxContainer.new()
	row.name = "SmithStatRow_" + label_text
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var stat_label := Label.new()
	stat_label.name = "SmithStatLabel_" + label_text
	stat_label.text = label_text
	stat_label.custom_minimum_size = Vector2(72, 0)
	stat_label.add_theme_color_override("font_color", Color("c9b37b"))
	row.add_child(stat_label)
	var value_label := Label.new()
	value_label.name = "SmithStatValue_" + label_text
	value_label.text = format_string % value
	value_label.add_theme_color_override("font_color", _stat_value_color(value))
	row.add_child(value_label)


func _stat_value_color(value: float) -> Color:
	if value > 0.0:
		return Color("a9d39d")
	if value < 0.0:
		return Color("e19a91")
	return Color("d5d4ca")


func _on_family_selected(family_id: String) -> void:
	select_family(family_id)


func _on_tab_selected(tab_id: String) -> void:
	select_tab(tab_id)


func _add_armory_view(
	item_section: VBoxContainer, detail_section: VBoxContainer, model: Dictionary
) -> void:
	var list_scroll := ScrollContainer.new()
	list_scroll.name = "SmithArmoryListScroll"
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_section.add_child(list_scroll)

	var armory := VBoxContainer.new()
	armory.name = "SmithArmorySection"
	armory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armory.add_theme_constant_override("separation", 8)
	list_scroll.add_child(armory)

	var armory_heading := _add_heading(armory, "Crafted armory", 16)
	armory_heading.name = "SmithArmoryHeading"
	var weapons: Array = model.get("weapons", [])
	if weapons.is_empty():
		var no_weapons := _make_muted_label(
			String(model.get("armory_empty_state", "No weapons are available."))
		)
		no_weapons.name = "SmithWeaponsEmptyState"
		armory.add_child(no_weapons)
	else:
		var strip := VBoxContainer.new()
		strip.name = "SmithWeaponStrip"
		strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_theme_constant_override("separation", 7)
		armory.add_child(strip)
		for weapon_value in weapons:
			_add_drag_weapon_card(strip, Dictionary(weapon_value))

	var reserve_recoveries: Array = model.get("reserve_recoveries", [])
	if not reserve_recoveries.is_empty():
		var recovery_heading := _add_heading(armory, "Reserve recovery", 15)
		recovery_heading.name = "SmithReserveRecoveryHeading"
		var recovery_strip := VBoxContainer.new()
		recovery_strip.name = "SmithReserveRecoveryStrip"
		recovery_strip.add_theme_constant_override("separation", 7)
		armory.add_child(recovery_strip)
		for recovery_value in reserve_recoveries:
			_add_reserve_recovery_card(recovery_strip, Dictionary(recovery_value))

	if weapons.is_empty():
		_add_wrapped_label(detail_section, "No crafted weapon is available for this weapon type.", Color("8f968f"))
	else:
		_add_armory_weapon_details(detail_section, Dictionary(weapons[0]))

	var armory_zone := SmithArmoryDropZoneScript.new() as SmithArmoryDropZone
	armory_zone.name = "SmithReturnToArmory"
	armory_zone.custom_minimum_size = Vector2(0, 72)
	armory_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armory_zone.equipment_action_completed.connect(_on_drag_equipment_action)
	detail_section.add_child(armory_zone)
	var armory_label := Label.new()
	armory_label.text = "RETURN TO ARMORY\nDrop an equipped weapon here"
	armory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	armory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	armory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armory_label.add_theme_color_override("font_color", Color("d8c78e"))
	armory_zone.add_child(armory_label)


func _add_armory_weapon_details(parent: VBoxContainer, weapon: Dictionary) -> void:
	var details := VBoxContainer.new()
	details.name = "SmithArmoryDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 7)
	parent.add_child(details)
	_add_weapon_art(details, weapon)
	var title := _add_heading(details, String(weapon.get("display_name", "Unknown weapon")), 24)
	title.add_theme_color_override("font_color", Color("c9b37b"))
	_add_wrapped_label(details, String(weapon.get("description", "")), Color("c9bd7b"))
	_add_wrapped_label(
		details, String(weapon.get("assignment_label", "AVAILABLE")), Color("94b58f")
	)
	_add_stat_rows(details, weapon)
	_add_wrapped_label(details, String(weapon.get("trait_text", "")), Color("9aa5aa"))


func _add_drag_weapon_card(parent: Container, weapon: Dictionary) -> void:
	var panel := SmithDragSourceScript.new() as SmithDragSource
	panel.name = "SmithWeapon_" + String(weapon.get("weapon_id", "weapon"))
	panel.custom_minimum_size = Vector2(220, 96)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("222d33") if bool(weapon.get("can_drag", false)) else Color("1b2226")
	style.border_color = Color("4c5555")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var drag_payload := {
		"type": String(weapon.get("drag_type", "")),
		"weapon_id": String(weapon.get("weapon_id", "")),
	}
	var source_raider_id := String(weapon.get("drag_source_raider_id", ""))
	if not source_raider_id.is_empty():
		drag_payload["source_raider_id"] = source_raider_id
	panel.configure_drag(
		drag_payload,
		String(weapon.get("display_name", "Weapon")),
		weapon.get("icon_resource") as Texture2D,
		bool(weapon.get("can_drag", false))
	)
	panel.tooltip_text = _weapon_tooltip(weapon)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var icon_stack := Control.new()
	icon_stack.custom_minimum_size = Vector2(56, 56)
	icon_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_stack)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.texture = weapon.get("icon_resource") as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(icon)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	var title := _add_heading(column, String(weapon.get("display_name", "Unknown weapon")), 15)
	title.add_theme_color_override("font_color", Color("c9b37b"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var family := Label.new()
	family.text = String(weapon.get("family_name", "Unknown family"))
	family.add_theme_font_size_override("font_size", 11)
	family.add_theme_color_override("font_color", Color("c9b37b"))
	family.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(family)
	var assignment := Label.new()
	assignment.name = "SmithWeaponAssignment"
	assignment.text = String(weapon.get("assignment_label", "AVAILABLE"))
	assignment.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	assignment.add_theme_font_size_override("font_size", 10)
	assignment.add_theme_color_override(
		"font_color",
		Color("94b58f") if int(weapon.get("available_count", 0)) > 0
		else Color("a8adae")
	)
	assignment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(assignment)


func _weapon_tooltip(weapon: Dictionary) -> String:
	var compatible_names: Array = weapon.get("compatible_raider_names", [])
	var active_holder_names: Array = weapon.get("active_holder_names", [])
	var reserve_holder_names: Array = weapon.get("reserve_holder_names", [])
	var lines: Array[String] = [
		String(weapon.get("display_name", "Unknown weapon")),
		"EQUIPPED %d/%d" % [
			int(weapon.get("equipped_count", 0)),
			int(weapon.get("crafted_count", 0)),
		],
		String(weapon.get("description", "")),
		"%s · Power %+.0f%% · Speed %+.0f%% · Range %+.1f units" % [
			String(weapon.get("family_name", "Unknown family")),
			float(weapon.get("power_percentage", 0.0)),
			float(weapon.get("speed_percentage", 0.0)),
			float(weapon.get("range_units", 0.0)),
		],
		String(weapon.get("trait_text", "")),
		"Compatible active raiders: %s" % (
			", ".join(compatible_names) if not compatible_names.is_empty() else "None"
		),
		"Active holders: %s" % (
			", ".join(active_holder_names) if not active_holder_names.is_empty() else "None"
		),
		"Reserve holders: %s" % (
			", ".join(reserve_holder_names) if not reserve_holder_names.is_empty() else "None"
		),
	]
	var reason := String(weapon.get("drag_disabled_reason", ""))
	if not reason.is_empty():
		lines.append(reason)
	else:
		lines.append("Drag to a compatible active raid frame.")
	return "\n".join(lines)


func _add_reserve_recovery_card(parent: Container, recovery: Dictionary) -> void:
	var source_raider_id := String(recovery.get("source_raider_id", ""))
	var weapon_id := String(recovery.get("weapon_id", ""))
	var panel := SmithDragSourceScript.new() as SmithDragSource
	panel.name = "SmithReserve_%s_%s" % [weapon_id, source_raider_id]
	panel.custom_minimum_size = Vector2(205, 48)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("211f1c")
	style.border_color = Color("7c724f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	panel.configure_drag(
		{
			"type": "smith_reserve_weapon",
			"weapon_id": weapon_id,
			"source_raider_id": source_raider_id,
		},
		"%s — %s" % [
			recovery.get("display_name", weapon_id),
			recovery.get("holder_name", source_raider_id),
		],
		recovery.get("icon_resource") as Texture2D,
		true
	)
	panel.tooltip_text = (
		"Reserve recovery copy\n%s\nHeld by: %s\nDrag to a compatible active raid frame or Return to Armory."
		% [
			recovery.get("display_name", weapon_id),
			recovery.get("holder_name", source_raider_id),
		]
	)
	var label := Label.new()
	label.name = "SmithReserveOverlay"
	label.text = "RESERVE · %s\n%s" % [
		recovery.get("holder_name", source_raider_id),
		recovery.get("display_name", weapon_id),
	]
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("f2dfb0"))
	panel.add_child(label)


func _on_drag_equipment_action(result: Dictionary) -> void:
	last_action_result = result.duplicate(true)
	action_message = String(result.get("message", "Equipment action failed."))
	var drawer := (
		_journal.get_tree().get_first_node_in_group("camp_raid_drawer")
		if _journal != null else null
	)
	if drawer != null and drawer.has_method("show_equipment_feedback"):
		drawer.call("show_equipment_feedback", result)
	_queue_refresh()


func _add_action_message(page: VBoxContainer) -> void:
	if action_message.is_empty():
		return
	var label := _add_wrapped_label(page, action_message, Color("d9a766"))
	label.name = "SmithActionStatus"


func _ensure_confirmation_dialog() -> void:
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		return
	if _journal == null or not is_instance_valid(_journal):
		return
	_confirmation_dialog = ConfirmationDialog.new()
	_confirmation_dialog.name = "SmithCraftConfirmation"
	_confirmation_dialog.title = "Confirm weapon crafting"
	_confirmation_dialog.ok_button_text = "Forge Weapon"
	_confirmation_dialog.confirmed.connect(confirm_pending_craft)
	_confirmation_dialog.canceled.connect(cancel_pending_craft)
	_journal.add_child(_confirmation_dialog)


func _on_recipe_selected(recipe_id: String) -> void:
	selected_recipe_id = recipe_id
	_queue_refresh()


func _queue_refresh() -> void:
	if _journal != null and is_instance_valid(_journal):
		_journal.call("_queue_refresh")


func _material_tooltip(
	material: BossMaterialDefinition,
	material_id: String,
	owned: int,
	required: int,
	source_text: String
) -> String:
	var display_name := material_id if material == null else material.display_name
	var description := "Material definition unavailable." if material == null else material.description
	return "%s\nCount: %d/%d\n%s\nSource: %s" % [
		display_name,
		owned,
		required,
		description,
		source_text,
	]


func _material_source_text(material: BossMaterialDefinition) -> String:
	if material == null or material.source_encounter_ids.is_empty():
		return "Unknown Source"
	var source_names: Array[String] = []
	for encounter_id in material.source_encounter_ids:
		var boss := ProgressionCatalog.get_boss_definition(encounter_id)
		source_names.append(encounter_id if boss == null else boss.display_name)
	return ", ".join(source_names)


func _craft_disabled_reason(
	craft_check: Dictionary, components: Array[Dictionary]
) -> String:
	match String(craft_check.get("status", "unknown")):
		"insufficient_materials":
			var shortages: Array[String] = []
			for component in components:
				var missing := int(component.get("missing", 0))
				if missing > 0:
					shortages.append("%s ×%d" % [component.get("display_name", "Material"), missing])
			return "Missing %s. Defeat source bosses and review the Spoils Cache." % ", ".join(shortages)
		_:
			return String(craft_check.get("message", "Crafting is unavailable."))

func _forge_empty_state() -> String:
	return "No weapon recipes are unlocked. Defeat a Beast Crucible boss for the first time."


func _inactive_trait(display_name: String, description: String) -> Dictionary:
	return {
		"display_name": display_name,
		"description": description,
		"active": false,
		"inactive": true,
		"placeholder_label": "Inactive placeholder",
	}


func _select_entry(entries: Array[Dictionary], selected_id: String, id_field: String) -> Dictionary:
	for entry in entries:
		if String(entry.get(id_field, "")) == selected_id:
			return entry.duplicate(true)
	return {} if entries.is_empty() else entries[0].duplicate(true)


func _add_heading(parent: Control, text_value: String, size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e8dfc7"))
	parent.add_child(label)
	return label


func _add_wrapped_label(parent: Control, text_value: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _make_muted_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("8f968f"))
	return label


func _button_style(background: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
