extends "res://scripts/ui/facility_page_presenter.gd"
class_name SmithPagePresenter

const SmithDragSourceScript := preload("res://scripts/ui/smith_drag_source.gd")
const SmithArmoryDropZoneScript := preload(
	"res://scripts/ui/smith_armory_drop_zone.gd"
)

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
		header.text = "Rudimentary Smith — Forge and Armory"
	_ensure_confirmation_dialog()
	var page := journal.call("_begin_scrolling_page") as VBoxContainer
	if page == null:
		return
	page.name = "SmithPage"
	_add_intro(page)
	var model := build_forge_view_model()
	_add_armory_strip(page, model)
	_add_forge_view(page, model)
	_add_action_message(page)


func build_view_model() -> Dictionary:
	return build_forge_view_model()


func build_forge_view_model() -> Dictionary:
	var recipes: Array[Dictionary] = []
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		var entry := _build_recipe_entry(recipe_id)
		if entry.is_empty():
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
	var weapons := _build_weapon_entries()
	return {
		"recipes": recipes,
		"entries": recipes,
		"selected_recipe": selected,
		"selected_recipe_id": String(selected.get("recipe_id", "")),
		"empty_state": _forge_empty_state(),
		"holders": holders,
		"weapons": weapons,
		"reserve_recoveries": _build_reserve_recovery_entries(weapons),
		"armory_empty_state": "No weapons have been crafted. Forge an unlocked design first.",
		"action_message": action_message,
	}


func select_recipe(recipe_id: String) -> bool:
	if not CampaignState.get_unlocked_recipe_ids().has(recipe_id):
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
	var crafted_count := int(entry.get("crafted_count", 0))
	var prompt := "%s %s?\n\nExact component cost:\n%s" % [
		"Forge another" if crafted_count > 0 else "Forge",
		String(entry.get("display_name", entry.get("weapon_id", "Weapon"))),
		"\n".join(cost_lines),
	]
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		_confirmation_dialog.dialog_text = prompt
		_confirmation_dialog.ok_button_text = (
			"Forge Another" if crafted_count > 0 else "Forge Weapon"
		)
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
		"crafted_count": crafted_count,
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
		var weapon := ProgressionCatalog.get_weapon(
			String(last_action_result.get("weapon_id", ""))
		)
		var weapon_name := (
			String(last_action_result.get("weapon_id", "Weapon"))
			if weapon == null else weapon.display_name
		)
		action_message = (
			"%s forged (crafted Ã—%d, available %d). It was not auto-equipped; drag an available copy from the armory to a raid frame."
			% [
				weapon_name,
				int(last_action_result.get("crafted_count", 0)),
				int(last_action_result.get("available_count", 0)),
			]
		)
	else:
		action_message = String(last_action_result.get("message", "Crafting failed."))
	_queue_refresh()
	return last_action_result.duplicate(true)


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
		components.append({
			"material_id": ingredient.material_id,
			"display_name": ingredient.material_id if material == null else material.display_name,
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
	var count_label := "CRAFTED ×%d · EQUIPPED %d · AVAILABLE %d" % [
		crafted_count, equipped_count, available_count,
	]
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
	var intro := Label.new()
	intro.name = "SmithIntro"
	intro.text = (
		"Forge unlocked designs as often as materials allow. Each craft adds one counted "
		+ "copy; drag an available copy from the armory to an active raid frame."
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("b9b29f"))
	page.add_child(intro)

func _add_forge_view(page: VBoxContainer, model: Dictionary) -> void:
	var recipes: Array = model.get("recipes", [])
	if recipes.is_empty():
		var empty := _make_muted_label(String(model.get("empty_state", "No recipes available.")))
		empty.name = "SmithForgeEmptyState"
		page.add_child(empty)
		return
	var content := HBoxContainer.new()
	content.name = "SmithForgeContent"
	content.add_theme_constant_override("separation", 16)
	page.add_child(content)
	var list := VBoxContainer.new()
	list.name = "SmithRecipeList"
	list.custom_minimum_size = Vector2(270, 0)
	list.add_theme_constant_override("separation", 7)
	content.add_child(list)
	for recipe_value in recipes:
		var recipe: Dictionary = recipe_value
		var button := Button.new()
		button.name = "SmithRecipe_" + String(recipe.get("recipe_id", "recipe"))
		button.text = "%s\n%s · %s%s" % [
			String(recipe.get("display_name", "Unknown")),
			String(recipe.get("boss_name", "Unknown source")),
			String(recipe.get("family_name", "Unknown family")),
			" · CRAFTED ×%d" % int(recipe.get("crafted_count", 0))
			if int(recipe.get("crafted_count", 0)) > 0 else "",
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(260, 62)
		button.pressed.connect(_on_recipe_selected.bind(String(recipe.get("recipe_id", ""))))
		list.add_child(button)
	var selected: Dictionary = model.get("selected_recipe", {})
	if not selected.is_empty():
		_add_recipe_details(content, selected)


func _add_recipe_details(parent: HBoxContainer, recipe: Dictionary) -> void:
	var details := VBoxContainer.new()
	details.name = "SmithRecipeDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 7)
	parent.add_child(details)
	_add_heading(details, String(recipe.get("display_name", "Unknown weapon")), 24)
	_add_wrapped_label(details, String(recipe.get("description", "")), Color("b8bdba"))
	_add_wrapped_label(details, "Source: %s · Family/category: %s" % [
		String(recipe.get("boss_name", "Unknown")), String(recipe.get("family_name", "Unknown")),
	], Color("c9b37b"))
	_add_wrapped_label(details, "Power %+.0f%% · Speed %+.0f%% · Range %+.1f units" % [
		float(recipe.get("power_percentage", 0.0)),
		float(recipe.get("speed_percentage", 0.0)),
		float(recipe.get("range_units", 0.0)),
	], Color("d5d4ca"))
	_add_wrapped_label(details, String(recipe.get("trait_text", "")), Color("9aa5aa"))
	_add_heading(details, "Components", 19)
	for component_value in recipe.get("components", []):
		var component: Dictionary = component_value
		var component_label := _add_wrapped_label(details, "[%s] %s — %d/%d%s" % [
			String(component.get("rarity_text", "Unknown")).to_upper(),
			String(component.get("display_name", "Unknown material")),
			int(component.get("owned", 0)), int(component.get("required", 0)),
			" · SHORT %d" % int(component.get("missing", 0)) if int(component.get("missing", 0)) > 0 else "",
		], component.get("rarity_color", Color.WHITE) as Color)
		component_label.name = "SmithComponent_" + String(component.get("material_id", "material"))
	var craft_button := Button.new()
	craft_button.name = "SmithCraftButton"
	craft_button.text = "%s %s" % [
		"Forge another" if int(recipe.get("crafted_count", 0)) > 0 else "Forge",
		String(recipe.get("display_name", "Weapon")),
	]
	craft_button.disabled = not bool(recipe.get("craftable", false))
	craft_button.custom_minimum_size = Vector2(280, 44)
	craft_button.pressed.connect(
		request_craft_confirmation.bind(String(recipe.get("recipe_id", "")))
	)
	details.add_child(craft_button)
	if craft_button.disabled:
		var reason := _make_muted_label(String(recipe.get("disabled_reason", "Crafting unavailable.")))
		reason.name = "SmithCraftDisabledReason"
		details.add_child(reason)


func _add_armory_strip(page: VBoxContainer, model: Dictionary) -> void:
	_add_heading(page, "Crafted Armory", 21)
	_add_wrapped_label(
		page,
		"Drag an available weapon onto a compatible raid-frame slot. Drag active raid-frame icons to move or swap weapons. Reserve-held arms can be reclaimed directly.",
		Color("c9b37b")
	)
	var row := VBoxContainer.new()
	row.name = "SmithArmorySection"
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var weapon_area := VBoxContainer.new()
	weapon_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(weapon_area)
	var weapons: Array = model.get("weapons", [])
	if weapons.is_empty():
		var no_weapons := _make_muted_label(
			String(model.get("armory_empty_state", "No crafted weapons."))
		)
		no_weapons.name = "SmithWeaponsEmptyState"
		weapon_area.add_child(no_weapons)
	else:
		var strip := HFlowContainer.new()
		strip.name = "SmithWeaponStrip"
		strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_theme_constant_override("h_separation", 8)
		strip.add_theme_constant_override("v_separation", 8)
		weapon_area.add_child(strip)
		for weapon_value in weapons:
			_add_drag_weapon_card(strip, Dictionary(weapon_value))
	var reserve_recoveries: Array = model.get("reserve_recoveries", [])
	if not reserve_recoveries.is_empty():
		_add_heading(row, "Reserve recovery", 16)
		var recovery_strip := HFlowContainer.new()
		recovery_strip.name = "SmithReserveRecoveryStrip"
		recovery_strip.add_theme_constant_override("h_separation", 7)
		recovery_strip.add_theme_constant_override("v_separation", 7)
		row.add_child(recovery_strip)
		for recovery_value in reserve_recoveries:
			_add_reserve_recovery_card(recovery_strip, Dictionary(recovery_value))
	var armory_zone := SmithArmoryDropZoneScript.new() as SmithArmoryDropZone
	armory_zone.name = "SmithReturnToArmory"
	armory_zone.custom_minimum_size = Vector2(0, 72)
	armory_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armory_zone.equipment_action_completed.connect(_on_drag_equipment_action)
	row.add_child(armory_zone)
	var armory_label := Label.new()
	armory_label.text = "RETURN TO ARMORY\nDrop an equipped weapon here"
	armory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	armory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	armory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armory_label.add_theme_color_override("font_color", Color("d8c78e"))
	armory_zone.add_child(armory_label)
	page.add_child(HSeparator.new())


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
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var family := Label.new()
	family.text = String(weapon.get("family_name", "Unknown family"))
	family.add_theme_font_size_override("font_size", 11)
	family.add_theme_color_override("font_color", Color("aeb5b3"))
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
		"Crafted ×%d · Equipped %d · Available %d" % [
			int(weapon.get("crafted_count", 0)),
			int(weapon.get("equipped_count", 0)),
			int(weapon.get("available_count", 0)),
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
			return "Missing %s. Defeat source bosses and review Camp Stores." % ", ".join(shortages)
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
