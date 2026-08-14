extends "res://scripts/ui/facility_page_presenter.gd"
class_name StoragePagePresenter

const VIEW_IDS: Array[String] = ["tokens", "materials", "recipes", "weapons"]
const VIEW_LABELS := {
	"tokens": "Advancement Tokens",
	"materials": "Boss Materials",
	"recipes": "Unlocked Recipes",
	"weapons": "Crafted Weapons",
}

var current_view_id: String = "materials"
var boss_filter: String = ""
var rarity_filter: String = ""
var family_filter: String = ""
var name_filter: String = ""
var _journal: Node = null
var _debug_status_label: Label = null


func present(journal: Node) -> void:
	_journal = journal
	var header := journal.get("header_title") as Label
	if header != null:
		header.text = "Camp Stores — Progression Inventory"
	var page := journal.call("_begin_scrolling_page") as VBoxContainer
	if page == null:
		return
	page.name = "StoragePage"
	_add_intro(page)
	_add_filters(page)
	var model := build_view_model()
	_add_inventory_view(page, model)
	if OS.is_debug_build():
		_add_debug_controls(page)


func build_view_model(
	view_id: String = "", filter_override: Dictionary = {}
) -> Dictionary:
	var selected_view := current_view_id if view_id.is_empty() else view_id
	if selected_view not in VIEW_IDS:
		selected_view = "materials"
	var filters := {
		"boss_id": boss_filter,
		"rarity_id": rarity_filter,
		"family_id": family_filter,
		"name": name_filter,
	}
	filters.merge(filter_override, true)
	var entries: Array[Dictionary] = []
	match selected_view:
		"tokens":
			entries = _token_entries()
		"materials":
			entries = _material_entries()
		"recipes":
			entries = _recipe_entries()
		"weapons":
			entries = _weapon_entries()
	entries = _filter_entries(entries, filters)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var name_order := String(a.get("display_name", "")).naturalnocasecmp_to(
				String(b.get("display_name", ""))
			)
			if name_order != 0:
				return name_order < 0
			return String(a.get("stable_id", "")) < String(b.get("stable_id", ""))
	)
	return {
		"view_id": selected_view,
		"title": String(VIEW_LABELS.get(selected_view, selected_view.capitalize())),
		"filters": filters,
		"entries": entries,
		"empty_state": _empty_state(selected_view, filters),
		"read_only": true,
	}


func _add_intro(page: VBoxContainer) -> void:
	var intro := Label.new()
	intro.name = "StorageReadOnlyNotice"
	intro.text = (
		"Review permanent tokens, recovered materials, unlocked designs, and forged arms. "
		+ "Camp Stores is read-only; visit the Rudimentary Smith to craft and manage weapons."
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("b9b29f"))
	page.add_child(intro)


func _add_filters(page: VBoxContainer) -> void:
	var controls := VBoxContainer.new()
	controls.name = "StorageFilters"
	controls.add_theme_constant_override("separation", 8)
	page.add_child(controls)

	var first_row := HBoxContainer.new()
	first_row.add_theme_constant_override("separation", 10)
	controls.add_child(first_row)
	var view_selector := OptionButton.new()
	view_selector.name = "StorageViewSelector"
	view_selector.custom_minimum_size = Vector2(260, 40)
	for view_id in VIEW_IDS:
		var index := view_selector.item_count
		view_selector.add_item(String(VIEW_LABELS[view_id]))
		view_selector.set_item_metadata(index, view_id)
		if view_id == current_view_id:
			view_selector.select(index)
	view_selector.item_selected.connect(_on_view_selected.bind(view_selector))
	first_row.add_child(view_selector)

	var name_input := LineEdit.new()
	name_input.name = "StorageNameFilter"
	name_input.placeholder_text = "Filter by name"
	name_input.text = name_filter
	name_input.custom_minimum_size = Vector2(340, 40)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.text_changed.connect(_on_name_filter_changed)
	first_row.add_child(name_input)

	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 10)
	controls.add_child(second_row)
	var boss_selector := _make_filter_selector(
		"StorageBossFilter", "All bosses", _boss_options(), boss_filter
	)
	boss_selector.item_selected.connect(_on_boss_filter_selected.bind(boss_selector))
	second_row.add_child(boss_selector)
	var rarity_selector := _make_filter_selector(
		"StorageRarityFilter", "All rarities", _rarity_options(), rarity_filter
	)
	rarity_selector.item_selected.connect(_on_rarity_filter_selected.bind(rarity_selector))
	second_row.add_child(rarity_selector)
	var family_selector := _make_filter_selector(
		"StorageFamilyFilter", "All families", _family_options(), family_filter
	)
	family_selector.item_selected.connect(_on_family_filter_selected.bind(family_selector))
	second_row.add_child(family_selector)


func _add_inventory_view(page: VBoxContainer, model: Dictionary) -> void:
	var heading := Label.new()
	heading.name = "StorageViewHeading"
	heading.text = String(model.get("title", "Storage"))
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("e8dfc7"))
	page.add_child(heading)

	var content := VBoxContainer.new()
	content.name = "StorageInventoryContent"
	content.add_theme_constant_override("separation", 8)
	page.add_child(content)
	var entries: Array = model.get("entries", [])
	if entries.is_empty():
		var empty := Label.new()
		empty.name = "StorageEmptyState"
		empty.text = String(model.get("empty_state", "No entries."))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("8f968f"))
		content.add_child(empty)
		return
	for entry_value in entries:
		_add_entry_card(content, Dictionary(entry_value), String(model.get("view_id", "")))


func _add_entry_card(parent: VBoxContainer, entry: Dictionary, view_id: String) -> void:
	var panel := PanelContainer.new()
	panel.name = "StorageEntry_" + String(entry.get("stable_id", "entry"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202b31")
	style.border_color = Color("4c5555")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var title := Label.new()
	title.text = _entry_title(entry, view_id)
	title.add_theme_font_size_override("font_size", 19)
	if entry.has("rarity_color"):
		title.add_theme_color_override("font_color", entry["rarity_color"] as Color)
	else:
		title.add_theme_color_override("font_color", Color("ded6bf"))
	column.add_child(title)
	var detail := Label.new()
	detail.text = String(entry.get("detail_text", ""))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", Color("b8bdba"))
	column.add_child(detail)
	var description := String(entry.get("description", ""))
	if not description.is_empty():
		var description_label := Label.new()
		description_label.text = description
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.add_theme_color_override("font_color", Color("909a96"))
		column.add_child(description_label)


func _entry_title(entry: Dictionary, view_id: String) -> String:
	var display_name := String(entry.get("display_name", "Unknown"))
	if view_id == "materials":
		return "[%s] %s  ×%d" % [
			String(entry.get("rarity_text", "UNKNOWN")).to_upper(),
			display_name, int(entry.get("count", 0)),
		]
	if view_id == "tokens":
		return "%s  ×1" % display_name
	return display_name


func _token_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for token_id in CampaignState.get_owned_advancement_token_ids():
		var token := ProgressionCatalog.get_advancement_token(token_id)
		if token == null:
			result.append(_missing_entry(token_id, "Stored token definition is unavailable."))
			continue
		var boss := ProgressionCatalog.get_boss_definition(token.source_encounter_id)
		var class_definition := RaiderClassCatalog.get_definition(token.archetype_class_id)
		result.append({
			"stable_id": token.token_id,
			"display_name": token.display_name,
			"boss_ids": [token.source_encounter_id],
			"rarity_id": "",
			"family_id": "",
			"detail_text": "Archetype: %s  •  Source: %s" % [
				String(class_definition.get("display_name", token.archetype_class_id.capitalize())),
				token.source_encounter_id if boss == null else boss.display_name,
			],
			"description": token.description,
		})
	return result


func _material_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var inventory := CampaignState.get_progression_inventory()
	for material_id_value in inventory.get("materials", {}):
		var material_id := String(material_id_value)
		var count := int(inventory["materials"][material_id_value])
		var material := ProgressionCatalog.get_material(material_id)
		if material == null:
			var missing := _missing_entry(material_id, "Stored material definition is unavailable.")
			missing["count"] = count
			missing["rarity_text"] = "Missing"
			missing["rarity_color"] = Color("d16d6d")
			result.append(missing)
			continue
		var rarity := ProgressionCatalog.get_material_rarity(material.rarity_id)
		var source_names: Array[String] = []
		for encounter_id in material.source_encounter_ids:
			var boss := ProgressionCatalog.get_boss_definition(encounter_id)
			source_names.append(encounter_id if boss == null else boss.display_name)
		result.append({
			"stable_id": material.material_id,
			"display_name": material.display_name,
			"count": count,
			"boss_ids": material.source_encounter_ids.duplicate(),
			"rarity_id": material.rarity_id,
			"rarity_text": material.rarity_id.capitalize() if rarity == null else rarity.display_name,
			"rarity_color": Color.WHITE if rarity == null else rarity.display_color,
			"family_id": "",
			"detail_text": "Sources: %s" % ", ".join(source_names),
			"description": material.description,
		})
	return result


func _recipe_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		var recipe := ProgressionCatalog.get_recipe(recipe_id)
		if recipe == null:
			result.append(_missing_entry(recipe_id, "Unlocked recipe definition is unavailable."))
			continue
		var weapon := ProgressionCatalog.get_weapon(recipe.output_weapon_id)
		var ingredient_texts: Array[String] = []
		for ingredient in recipe.ingredients:
			if ingredient == null:
				continue
			var material := ProgressionCatalog.get_material(ingredient.material_id)
			var material_name := ingredient.material_id if material == null else material.display_name
			ingredient_texts.append("%s %d/%d" % [
				material_name, CampaignState.get_material_count(ingredient.material_id),
				ingredient.quantity,
			])
		var craft_check := CampaignState.check_craft(recipe.recipe_id)
		var craft_status := String(craft_check.get("status", "unknown"))
		var boss := ProgressionCatalog.get_boss_definition(recipe.source_encounter_id)
		result.append({
			"stable_id": recipe.recipe_id,
			"display_name": recipe.display_name,
			"boss_ids": [recipe.source_encounter_id],
			"rarity_id": "",
			"family_id": "" if weapon == null else weapon.family_id,
			"craftable": bool(craft_check.get("ok", false)),
			"craft_status": craft_status,
			"detail_text": "Output: %s  •  Source: %s  •  %s\nIngredients: %s" % [
				recipe.output_weapon_id if weapon == null else weapon.display_name,
				recipe.source_encounter_id if boss == null else boss.display_name,
				"Craftable" if bool(craft_check.get("ok", false)) else craft_status.replace("_", " ").capitalize(),
				"; ".join(ingredient_texts),
			],
			"description": "Recipe status is informational; Camp Stores does not craft items.",
		})
	return result


func _weapon_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon_id in CampaignState.get_crafted_weapon_ids():
		var weapon := ProgressionCatalog.get_weapon(weapon_id)
		if weapon == null:
			result.append(_missing_entry(weapon_id, "Crafted weapon definition is unavailable."))
			continue
		var family := ProgressionCatalog.get_weapon_family(weapon.family_id)
		var weapon_trait := ProgressionCatalog.get_weapon_trait(weapon.trait_id)
		var equipped_names: Array[String] = []
		for raider_id in CampaignState.get_equipped_raider_ids(weapon.weapon_id):
			equipped_names.append(CampaignState.get_member_label(raider_id))
		var equipped_text := "None" if equipped_names.is_empty() else ", ".join(equipped_names)
		result.append({
			"stable_id": weapon.weapon_id,
			"display_name": weapon.display_name,
			"boss_ids": [weapon.source_encounter_id],
			"rarity_id": "",
			"family_id": weapon.family_id,
			"detail_text": "%s  •  Power ×%.2f  •  Speed ×%.2f  •  Range %+.1f\nEquipped: %s" % [
				weapon.family_id if family == null else family.display_name,
				weapon.stat_profile.power_multiplier, weapon.stat_profile.speed_multiplier,
				weapon.stat_profile.range_additive, equipped_text,
			],
			"description": "Trait — %s: %s (inactive future hook)" % [
				weapon.trait_id if weapon_trait == null else weapon_trait.display_name,
				"Definition unavailable" if weapon_trait == null else weapon_trait.description,
			],
		})
	return result


func _filter_entries(entries: Array[Dictionary], filters: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var selected_boss := String(filters.get("boss_id", ""))
	var selected_rarity := String(filters.get("rarity_id", ""))
	var selected_family := String(filters.get("family_id", ""))
	var name_query := String(filters.get("name", "")).strip_edges().to_lower()
	for entry in entries:
		if not selected_boss.is_empty() and not Array(entry.get("boss_ids", [])).has(selected_boss):
			continue
		if not selected_rarity.is_empty() and String(entry.get("rarity_id", "")) != selected_rarity:
			continue
		if not selected_family.is_empty() and String(entry.get("family_id", "")) != selected_family:
			continue
		if not name_query.is_empty():
			var searchable := "%s %s" % [entry.get("display_name", ""), entry.get("stable_id", "")]
			if not searchable.to_lower().contains(name_query):
				continue
		result.append(entry.duplicate(true))
	return result


func _empty_state(view_id: String, filters: Dictionary) -> String:
	var filtered := false
	for value in filters.values():
		if not String(value).is_empty():
			filtered = true
	if filtered:
		return "No %s match the current filters." % String(VIEW_LABELS[view_id]).to_lower()
	match view_id:
		"tokens":
			return "No advancement tokens yet. Each Beast Crucible boss grants one on its first clear."
		"materials":
			return "No boss materials yet. Victories add deterministic, receipt-backed reward rolls."
		"recipes":
			return "No recipes unlocked yet. A boss's first clear unlocks both of its designs."
		"weapons":
			return "No weapons crafted yet. Visit the Rudimentary Smith to forge an unlocked design."
	return "No progression entries yet."


func _make_filter_selector(
	node_name: String, all_label: String, options: Array[Dictionary], selected_id: String
) -> OptionButton:
	var selector := OptionButton.new()
	selector.name = node_name
	selector.custom_minimum_size = Vector2(250, 38)
	selector.add_item(all_label)
	selector.set_item_metadata(0, "")
	for option in options:
		var index := selector.item_count
		selector.add_item(String(option.get("label", option.get("id", ""))))
		selector.set_item_metadata(index, String(option.get("id", "")))
		if String(option.get("id", "")) == selected_id:
			selector.select(index)
	return selector


func _boss_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var region := ProgressionCatalog.get_region_definition("beast_crucible")
	if region != null:
		for boss in region.bosses:
			if boss != null:
				result.append({"id": boss.encounter_id, "label": boss.display_name})
	return result


func _rarity_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog := ProgressionCatalog.get_catalog()
	if catalog != null:
		var definitions := catalog.material_rarities.duplicate()
		definitions.sort_custom(
			func(a: MaterialRarityDefinition, b: MaterialRarityDefinition) -> bool:
				return a.sort_order < b.sort_order
		)
		for rarity in definitions:
			if rarity != null:
				result.append({"id": rarity.rarity_id, "label": rarity.display_name})
	return result


func _family_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog := ProgressionCatalog.get_catalog()
	if catalog != null:
		for family in catalog.weapon_families:
			if family != null:
				result.append({"id": family.family_id, "label": family.display_name})
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["label"]).naturalnocasecmp_to(String(b["label"])) < 0
	)
	return result


func _missing_entry(stable_id: String, description: String) -> Dictionary:
	return {
		"stable_id": stable_id,
		"display_name": stable_id + " [Missing Content]",
		"boss_ids": [], "rarity_id": "", "family_id": "",
		"detail_text": "Saved stable ID retained for content recovery.",
		"description": description,
	}


func _add_debug_controls(page: VBoxContainer) -> void:
	var separator := HSeparator.new()
	page.add_child(separator)
	var debug_panel := VBoxContainer.new()
	debug_panel.name = "StorageDebugControls"
	debug_panel.add_to_group("storage_debug_mutation")
	debug_panel.add_theme_constant_override("separation", 6)
	page.add_child(debug_panel)
	var heading := Label.new()
	heading.text = "Debug progression fixtures"
	heading.add_theme_color_override("font_color", Color("d9a766"))
	debug_panel.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	debug_panel.add_child(row)
	_add_debug_button(row, "Grant Fixture Materials", _on_debug_grant_materials)
	_add_debug_button(row, "Process Seeded Reward", _on_debug_process_reward)
	_add_debug_button(row, "Craft First Available", _on_debug_craft)
	_add_debug_button(row, "Equip First Compatible", _on_debug_equip)
	_add_debug_button(row, "Inspect Trait Slots", _on_debug_inspect_traits)
	_debug_status_label = Label.new()
	_debug_status_label.name = "StorageDebugStatus"
	_debug_status_label.text = "Debug controls mutate campaign state and are absent from release builds."
	_debug_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_panel.add_child(_debug_status_label)


func _add_debug_button(parent: HBoxContainer, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.add_to_group("storage_debug_mutation")
	button.pressed.connect(callback)
	parent.add_child(button)


func _on_debug_grant_materials() -> void:
	var grants: Dictionary = {}
	var catalog := ProgressionCatalog.get_catalog()
	if catalog != null:
		for material in catalog.boss_materials:
			if material != null:
				grants[material.material_id] = 10
	_set_debug_result(CampaignState.debug_grant_progression_materials(grants))


func _on_debug_process_reward() -> void:
	var encounter_id := "ogre" if boss_filter.is_empty() else boss_filter
	_set_debug_result(CampaignState.debug_process_seeded_reward(
		encounter_id, "storage_debug_%s_%d" % [encounter_id, Time.get_ticks_usec()]
	))


func _on_debug_craft() -> void:
	for recipe_id in CampaignState.get_unlocked_recipe_ids():
		if bool(CampaignState.check_craft(recipe_id).get("ok", false)):
			_set_debug_result(CampaignState.craft(recipe_id))
			return
	_set_debug_message("No unlocked recipe is currently craftable.")


func _on_debug_equip() -> void:
	for weapon_id in CampaignState.get_crafted_weapon_ids():
		for member in CampaignState.get_roster_members():
			var raider_id := String(member.get("member_id", ""))
			if bool(CampaignState.check_equip_weapon(raider_id, weapon_id).get("ok", false)):
				_set_debug_result(CampaignState.equip_weapon(raider_id, weapon_id))
				return
	_set_debug_message("No crafted weapon has a compatible campaign raider.")


func _on_debug_inspect_traits() -> void:
	var members := CampaignState.get_roster_members()
	if members.is_empty():
		_set_debug_message("No recruited raider is available.")
		return
	var raider_id := String(members[0].get("member_id", ""))
	_set_debug_message(JSON.stringify(CampaignState.get_raider_traits(raider_id)))


func _set_debug_result(result: Dictionary) -> void:
	_set_debug_message("%s: %s" % [result.get("status", "unknown"), result.get("message", "")])


func _set_debug_message(message: String) -> void:
	if _debug_status_label != null and is_instance_valid(_debug_status_label):
		_debug_status_label.text = message


func _on_view_selected(index: int, selector: OptionButton) -> void:
	current_view_id = String(selector.get_item_metadata(index))
	_queue_refresh()


func _on_name_filter_changed(value: String) -> void:
	name_filter = value
	_queue_refresh()


func _on_boss_filter_selected(index: int, selector: OptionButton) -> void:
	boss_filter = String(selector.get_item_metadata(index))
	_queue_refresh()


func _on_rarity_filter_selected(index: int, selector: OptionButton) -> void:
	rarity_filter = String(selector.get_item_metadata(index))
	_queue_refresh()


func _on_family_filter_selected(index: int, selector: OptionButton) -> void:
	family_filter = String(selector.get_item_metadata(index))
	_queue_refresh()


func _queue_refresh() -> void:
	if _journal != null and is_instance_valid(_journal):
		_journal.call("_queue_refresh")
