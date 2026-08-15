extends "res://scripts/ui/facility_page_presenter.gd"
class_name SmithPagePresenter

const VIEW_IDS: Array[String] = ["forge", "equip"]
const VIEW_LABELS := {"forge": "Forge", "equip": "Equip"}
const SmithDragSourceScript := preload("res://scripts/ui/smith_drag_source.gd")
const SmithArmoryDropZoneScript := preload(
	"res://scripts/ui/smith_armory_drop_zone.gd"
)

var current_view_id: String = "forge"
var selected_recipe_id: String = ""
var selected_raider_id: String = ""
var boss_filter: String = ""
var family_filter: String = ""
var name_filter: String = ""
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
	_add_tabs(page)
	if current_view_id == "equip":
		_add_equip_view(page, build_equip_view_model())
	else:
		_add_forge_view(page, build_forge_view_model())


func build_view_model(
	view_id: String = "", filter_override: Dictionary = {}
) -> Dictionary:
	var selected_view := current_view_id if view_id.is_empty() else view_id
	if selected_view == "equip":
		return build_equip_view_model()
	return build_forge_view_model(filter_override)


func build_forge_view_model(filter_override: Dictionary = {}) -> Dictionary:
	var filters := {
		"boss_id": boss_filter,
		"family_id": family_filter,
		"name": name_filter,
	}
	filters.merge(filter_override, true)
	var recipes: Array[Dictionary] = []
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		var entry := _build_recipe_entry(recipe_id)
		if entry.is_empty() or not _recipe_matches_filters(entry, filters):
			continue
		recipes.append(entry)
	recipes.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("display_name", "")).naturalnocasecmp_to(
				String(b.get("display_name", ""))
			) < 0
	)
	var selected := _select_entry(recipes, selected_recipe_id, "recipe_id")
	if filter_override.is_empty():
		selected_recipe_id = String(selected.get("recipe_id", ""))
	return {
		"view_id": "forge",
		"filters": filters,
		"recipes": recipes,
		"entries": recipes,
		"selected_recipe": selected,
		"selected_recipe_id": String(selected.get("recipe_id", "")),
		"empty_state": _forge_empty_state(filters),
		"action_message": action_message,
	}


func build_equip_view_model() -> Dictionary:
	var raiders := _build_equip_raiders()
	var selected := _select_entry(raiders, selected_raider_id, "raider_id")
	selected_raider_id = String(selected.get("raider_id", ""))
	var weapons := _build_weapon_entries(selected)
	return {
		"view_id": "equip",
		"raiders": raiders,
		"selected_raider": selected,
		"selected_raider_id": selected_raider_id,
		"weapons": weapons,
		"entries": weapons,
		"empty_state": (
			"No active raiders or reserve weapon holders are available."
			if raiders.is_empty()
			else "No weapons have been crafted. Forge an unlocked design first."
		),
		"action_message": action_message,
	}


func select_recipe(recipe_id: String) -> bool:
	if not CampaignState.get_unlocked_recipe_ids().has(recipe_id):
		return false
	selected_recipe_id = recipe_id
	_queue_refresh()
	return true


func select_raider(raider_id: String) -> bool:
	for entry in _build_equip_raiders():
		if String(entry.get("raider_id", "")) == raider_id:
			selected_raider_id = raider_id
			_queue_refresh()
			return true
	return false


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
	var prompt := "Forge %s?\n\nExact component cost:\n%s" % [
		String(entry.get("display_name", entry.get("weapon_id", "Weapon"))),
		"\n".join(cost_lines),
	]
	if _confirmation_dialog != null and is_instance_valid(_confirmation_dialog):
		_confirmation_dialog.dialog_text = prompt
		_confirmation_dialog.popup_centered()
	return {
		"ok": true,
		"status": "confirmation_required",
		"message": prompt,
		"recipe_id": recipe_id,
		"weapon_id": String(entry.get("weapon_id", "")),
		"components": Array(entry.get("components", [])).duplicate(true),
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
		action_message = "%s forged. It was not auto-equipped; open Equip to assign it." % weapon_name
	else:
		action_message = String(last_action_result.get("message", "Crafting failed."))
	_queue_refresh()
	return last_action_result.duplicate(true)


func equip_selected_weapon(weapon_id: String) -> Dictionary:
	if selected_raider_id.is_empty():
		return {
			"ok": false, "status": "no_raider_selected",
			"message": "Select an active raider first.",
		}
	last_action_result = CampaignState.equip_weapon(selected_raider_id, weapon_id)
	action_message = String(last_action_result.get("message", "Equipment assignment failed."))
	_queue_refresh()
	return last_action_result.duplicate(true)


func unequip_selected_weapon() -> Dictionary:
	if selected_raider_id.is_empty():
		return {
			"ok": false, "status": "no_raider_selected",
			"message": "Select a raider first.",
		}
	last_action_result = CampaignState.unequip_weapon(selected_raider_id)
	action_message = String(last_action_result.get("message", "Unequip failed."))
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


func _build_weapon_entries(selected_raider: Dictionary) -> Array[Dictionary]:
	var weapon_ids: Array[String] = CampaignState.get_crafted_weapon_ids()
	for raider in _build_equip_raiders():
		var equipped_id := String(raider.get("equipped_weapon_id", ""))
		if not equipped_id.is_empty() and not weapon_ids.has(equipped_id):
			weapon_ids.append(equipped_id)
	var result: Array[Dictionary] = []
	for weapon_id in weapon_ids:
		result.append(_build_weapon_entry(weapon_id, selected_raider))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("display_name", "")).naturalnocasecmp_to(
				String(b.get("display_name", ""))
			) < 0
	)
	return result


func _build_weapon_entry(weapon_id: String, selected_raider: Dictionary) -> Dictionary:
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	var holder_id := CampaignState.get_weapon_holder_id(weapon_id)
	var holder_name := "Unassigned" if holder_id.is_empty() else CampaignState.get_member_label(holder_id)
	var selected_id := String(selected_raider.get("raider_id", ""))
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
			"holder_id": holder_id,
			"current_holder_id": holder_id,
			"holder_name": holder_name,
			"compatible": false,
			"compatibility_text": "Unavailable — missing content",
			"can_equip": false,
			"equip_status": "unknown_definition",
			"disabled_reason": "Missing content is inactive. Select its holder and Unequip to recover the slot.",
			"selected_raider_holds": not selected_id.is_empty() and selected_id == holder_id,
			"icon_resource": null,
			"compatible_raider_names": [],
			"can_drag": false,
			"drag_disabled_reason": "Missing content may only be returned from its current holder.",
		}
	var family := ProgressionCatalog.get_weapon_family(weapon.family_id)
	var weapon_trait := ProgressionCatalog.get_weapon_trait(weapon.trait_id)
	var family_name := weapon.family_id if family == null else family.display_name
	var compatible_raider_names := _compatible_active_member_names(weapon.family_id)
	var class_id := String(selected_raider.get("class_id", ""))
	var compatible := not class_id.is_empty() and ProgressionCatalog.is_family_compatible(
		class_id, weapon.family_id
	)
	var validation := (
		CampaignState.check_equip_weapon(selected_id, weapon_id)
		if not selected_id.is_empty()
		else {
			"ok": false, "status": "no_raider_selected",
			"message": "Select an active raider to assign weapons.",
		}
	)
	var trait_name := weapon.trait_id if weapon_trait == null else weapon_trait.display_name
	var trait_description := "Definition unavailable." if weapon_trait == null else weapon_trait.description
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
		"holder_id": holder_id,
		"current_holder_id": holder_id,
		"holder_name": holder_name,
		"compatible": compatible,
		"compatibility_text": "Compatible" if compatible else "Incompatible",
		"can_equip": bool(validation.get("ok", false)),
		"equip_status": String(validation.get("status", "unknown")),
		"disabled_reason": "" if bool(validation.get("ok", false)) else _equip_disabled_reason(validation),
		"selected_raider_holds": not selected_id.is_empty() and selected_id == holder_id,
		"icon_resource": weapon.icon_resource,
		"compatible_raider_names": compatible_raider_names,
		"can_drag": holder_id.is_empty() and not compatible_raider_names.is_empty(),
		"drag_disabled_reason": (
			"Assigned to %s. Drag its raid-frame icon to move or swap it." % holder_name
			if not holder_id.is_empty()
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


func _add_intro(page: VBoxContainer) -> void:
	var intro := Label.new()
	intro.name = "SmithIntro"
	intro.text = (
		"Forge each unlocked weapon once, then assign that unique arm from Equip. "
		+ "Crafting never changes a raider's equipment automatically."
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("b9b29f"))
	page.add_child(intro)


func _add_tabs(page: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.name = "SmithTabs"
	tabs.add_theme_constant_override("separation", 8)
	page.add_child(tabs)
	for view_id in VIEW_IDS:
		var button := Button.new()
		button.name = "Smith%sTab" % view_id.capitalize()
		button.text = String(VIEW_LABELS[view_id])
		button.toggle_mode = true
		button.button_pressed = current_view_id == view_id
		button.custom_minimum_size = Vector2(180, 42)
		button.pressed.connect(_on_tab_pressed.bind(view_id))
		tabs.add_child(button)


func _add_forge_view(page: VBoxContainer, model: Dictionary) -> void:
	_add_forge_filters(page)
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
	list.custom_minimum_size = Vector2(430, 0)
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
			" · CRAFTED" if bool(recipe.get("crafted", false)) else "",
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(420, 66)
		button.pressed.connect(_on_recipe_selected.bind(String(recipe.get("recipe_id", ""))))
		list.add_child(button)
	var selected: Dictionary = model.get("selected_recipe", {})
	if not selected.is_empty():
		_add_recipe_details(content, selected)
	_add_action_message(page)


func _add_forge_filters(page: VBoxContainer) -> void:
	var filters := VBoxContainer.new()
	filters.name = "SmithForgeFilters"
	filters.add_theme_constant_override("separation", 7)
	page.add_child(filters)
	var name_input := LineEdit.new()
	name_input.name = "SmithNameFilter"
	name_input.placeholder_text = "Filter unlocked weapons by name"
	name_input.text = name_filter
	name_input.text_changed.connect(_on_name_filter_changed)
	filters.add_child(name_input)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	filters.add_child(row)
	var boss_selector := _make_filter_selector(
		"SmithBossFilter", "All source bosses", _unlocked_boss_options(), boss_filter
	)
	boss_selector.item_selected.connect(_on_boss_filter_selected.bind(boss_selector))
	row.add_child(boss_selector)
	var family_selector := _make_filter_selector(
		"SmithFamilyFilter", "All weapon families", _unlocked_family_options(), family_filter
	)
	family_selector.item_selected.connect(_on_family_filter_selected.bind(family_selector))
	row.add_child(family_selector)


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
	craft_button.text = "Forge %s" % String(recipe.get("display_name", "Weapon"))
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


func _add_equip_view(page: VBoxContainer, model: Dictionary) -> void:
	_add_drag_equip_view(page, model)


func _add_drag_equip_view(page: VBoxContainer, model: Dictionary) -> void:
	_add_wrapped_label(
		page,
		"Drag an unassigned weapon onto a raid-frame slot. Drag an equipped slot to another frame to move or swap it. Return equipped weapons to the armory below.",
		Color("c9b37b")
	)
	var armory_zone := SmithArmoryDropZoneScript.new() as SmithArmoryDropZone
	armory_zone.name = "SmithReturnToArmory"
	armory_zone.custom_minimum_size = Vector2(0, 72)
	armory_zone.equipment_action_completed.connect(_on_drag_equipment_action)
	page.add_child(armory_zone)
	var armory_label := Label.new()
	armory_label.text = "RETURN TO ARMORY\nDrop an equipped raid-frame or reserve-holder weapon here"
	armory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	armory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	armory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armory_label.add_theme_color_override("font_color", Color("d8c78e"))
	armory_zone.add_child(armory_label)
	_add_reserve_recovery(page, model.get("raiders", []))
	var weapons: Array = model.get("weapons", [])
	if weapons.is_empty():
		var no_weapons := _make_muted_label(String(model.get("empty_state", "No crafted weapons.")))
		no_weapons.name = "SmithWeaponsEmptyState"
		page.add_child(no_weapons)
		_add_action_message(page)
		return
	var list := VBoxContainer.new()
	list.name = "SmithWeaponList"
	list.add_theme_constant_override("separation", 8)
	page.add_child(list)
	for weapon_value in weapons:
		_add_drag_weapon_card(list, Dictionary(weapon_value))
	_add_action_message(page)


func _add_drag_weapon_card(parent: VBoxContainer, weapon: Dictionary) -> void:
	var panel := SmithDragSourceScript.new() as SmithDragSource
	panel.name = "SmithWeapon_" + String(weapon.get("weapon_id", "weapon"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202b31")
	style.border_color = Color("4c5555")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	panel.configure_drag(
		{
			"type": "smith_armory_weapon",
			"weapon_id": String(weapon.get("weapon_id", "")),
		},
		String(weapon.get("display_name", "Weapon")),
		weapon.get("icon_resource") as Texture2D,
		bool(weapon.get("can_drag", false))
	)
	panel.tooltip_text = (
		"Drag to a compatible raid-frame weapon slot."
		if bool(weapon.get("can_drag", false))
		else String(weapon.get("drag_disabled_reason", "Unavailable."))
	)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.texture = weapon.get("icon_resource") as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)
	var title := _add_heading(column, String(weapon.get("display_name", "Unknown weapon")), 19)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var attributes := _add_wrapped_label(column, "%s · Power %+.0f%% · Speed %+.0f%% · Range %+.1f units" % [
		String(weapon.get("family_name", "Unknown family")),
		float(weapon.get("power_percentage", 0.0)),
		float(weapon.get("speed_percentage", 0.0)),
		float(weapon.get("range_units", 0.0)),
	], Color("c7cbc6"))
	attributes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var description := _add_wrapped_label(column, String(weapon.get("description", "")), Color("9ca4a5"))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var trait_label := _add_wrapped_label(
		column, String(weapon.get("trait_text", "")), Color("9aa5aa")
	)
	trait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var compatible_names: Array = weapon.get("compatible_raider_names", [])
	var compatibility := _add_wrapped_label(column, "Compatible active raiders: %s" % (
		", ".join(compatible_names) if not compatible_names.is_empty() else "None"
	), Color("9ca4a5"))
	compatibility.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := _add_wrapped_label(column, "Current holder: %s" % String(weapon.get("holder_name", "Unassigned")), Color("c9b37b"))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not bool(weapon.get("can_drag", false)):
		var reason := _make_muted_label(String(weapon.get("drag_disabled_reason", "Unavailable.")))
		reason.name = "SmithEquipDisabledReason"
		reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(reason)


func _add_reserve_recovery(parent: VBoxContainer, raiders: Array) -> void:
	var reserve_holders: Array[Dictionary] = []
	for raider_value in raiders:
		var raider: Dictionary = raider_value
		if bool(raider.get("reserve_holder", false)):
			reserve_holders.append(raider)
	if reserve_holders.is_empty():
		return
	_add_heading(parent, "Reserve Holders — Recovery Only", 18)
	_add_wrapped_label(
		parent,
		"These reserve raiders cannot receive assignments. Drag their current weapon to Return to Armory.",
		Color("9ca4a5")
	)
	var list := HBoxContainer.new()
	list.name = "SmithReserveRecoveryList"
	list.add_theme_constant_override("separation", 8)
	parent.add_child(list)
	for raider in reserve_holders:
		var raider_id := String(raider.get("raider_id", ""))
		var weapon_id := String(raider.get("equipped_weapon_id", ""))
		var weapon := ProgressionCatalog.get_weapon(weapon_id)
		var card := SmithDragSourceScript.new() as SmithDragSource
		card.name = "SmithReserve_" + raider_id
		card.custom_minimum_size = Vector2(245, 58)
		card.configure_drag(
			{
				"type": "smith_reserve_weapon",
				"source_raider_id": raider_id,
				"weapon_id": weapon_id,
			},
			String(raider.get("display_name", "Reserve holder")),
			null if weapon == null else weapon.icon_resource,
			true
		)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("20272b")
		style.border_color = Color("6f6652")
		style.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", style)
		list.add_child(card)
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = "%s — Reserve holder\n%s" % [
			String(raider.get("display_name", "Raider")),
			String(raider.get("equipped_weapon_name", weapon_id)),
		]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_child(label)


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


func _on_tab_pressed(view_id: String) -> void:
	if view_id not in VIEW_IDS:
		return
	current_view_id = view_id
	_queue_refresh()


func _on_recipe_selected(recipe_id: String) -> void:
	selected_recipe_id = recipe_id
	_queue_refresh()


func _on_name_filter_changed(value: String) -> void:
	name_filter = value
	_queue_refresh()


func _on_boss_filter_selected(index: int, selector: OptionButton) -> void:
	boss_filter = String(selector.get_item_metadata(index))
	_queue_refresh()


func _on_family_filter_selected(index: int, selector: OptionButton) -> void:
	family_filter = String(selector.get_item_metadata(index))
	_queue_refresh()


func _queue_refresh() -> void:
	if _journal != null and is_instance_valid(_journal):
		_journal.call("_queue_refresh")


func _recipe_matches_filters(entry: Dictionary, filters: Dictionary) -> bool:
	var boss_id := String(filters.get("boss_id", ""))
	if not boss_id.is_empty() and String(entry.get("boss_id", "")) != boss_id:
		return false
	var family_id := String(filters.get("family_id", ""))
	if not family_id.is_empty() and String(entry.get("family_id", "")) != family_id:
		return false
	var query := String(filters.get("name", "")).strip_edges().to_lower()
	if not query.is_empty():
		var searchable := "%s %s %s" % [
			entry.get("display_name", ""), entry.get("recipe_display_name", ""),
			entry.get("weapon_id", ""),
		]
		if not searchable.to_lower().contains(query):
			return false
	return true


func _craft_disabled_reason(
	craft_check: Dictionary, components: Array[Dictionary]
) -> String:
	match String(craft_check.get("status", "unknown")):
		"already_owned":
			return "Already crafted. Open Equip to assign this weapon."
		"insufficient_materials":
			var shortages: Array[String] = []
			for component in components:
				var missing := int(component.get("missing", 0))
				if missing > 0:
					shortages.append("%s ×%d" % [component.get("display_name", "Material"), missing])
			return "Missing %s. Defeat source bosses and review Camp Stores." % ", ".join(shortages)
		_:
			return String(craft_check.get("message", "Crafting is unavailable."))


func _equip_disabled_reason(validation: Dictionary) -> String:
	match String(validation.get("status", "unknown")):
		"already_equipped":
			return "Already equipped by the selected raider."
		"assigned_elsewhere":
			var holder_id := String(validation.get("holder_id", ""))
			return "Assigned to %s. Select that holder and unequip it first." % CampaignState.get_member_label(holder_id)
		"incompatible_family":
			return "Incompatible: this raider's class cannot use this weapon family."
		"reserve_cannot_equip":
			return "Reserve holders may inspect and unequip, but cannot receive assignments."
		"not_crafted":
			return "This recovery entry is not present in the crafted armory."
		"no_raider_selected":
			return "Select an active raider to assign weapons."
		_:
			return String(validation.get("message", "Weapon is unavailable."))


func _forge_empty_state(filters: Dictionary) -> String:
	for value in filters.values():
		if not String(value).is_empty():
			return "No unlocked weapon recipes match the current filters."
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


func _make_filter_selector(
	node_name: String, all_label: String, options: Array[Dictionary], selected_id: String
) -> OptionButton:
	var selector := OptionButton.new()
	selector.name = node_name
	selector.custom_minimum_size = Vector2(300, 38)
	selector.add_item(all_label)
	selector.set_item_metadata(0, "")
	for option in options:
		var index := selector.item_count
		selector.add_item(String(option.get("label", option.get("id", ""))))
		selector.set_item_metadata(index, String(option.get("id", "")))
		if String(option.get("id", "")) == selected_id:
			selector.select(index)
	return selector


func _unlocked_boss_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Array[String] = []
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		var recipe := ProgressionCatalog.get_recipe(recipe_id)
		if recipe == null or seen.has(recipe.source_encounter_id):
			continue
		seen.append(recipe.source_encounter_id)
		var boss := ProgressionCatalog.get_boss_definition(recipe.source_encounter_id)
		result.append({
			"id": recipe.source_encounter_id,
			"label": recipe.source_encounter_id if boss == null else boss.display_name,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["label"]) < String(b["label"]))
	return result


func _unlocked_family_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Array[String] = []
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		var recipe := ProgressionCatalog.get_recipe(recipe_id)
		var weapon = null if recipe == null else ProgressionCatalog.get_weapon(recipe.output_weapon_id)
		if weapon == null or seen.has(weapon.family_id):
			continue
		seen.append(weapon.family_id)
		var family := ProgressionCatalog.get_weapon_family(weapon.family_id)
		result.append({
			"id": weapon.family_id,
			"label": weapon.family_id if family == null else family.display_name,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["label"]) < String(b["label"]))
	return result


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
