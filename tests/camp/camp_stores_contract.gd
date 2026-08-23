extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")
const StoragePresenterScript := preload("res://scripts/ui/storage_page_presenter.gd")


func _ready() -> void:
	var failures: Array[String] = []
	CampaignState.reset_campaign(false, 515151)
	var camp := CampScene.instantiate()
	add_child(camp)
	await get_tree().process_frame
	_validate_reachability(camp, failures)
	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	if journal == null:
		failures.append("Camp Journal was unavailable.")
		_finish(camp, failures)
		return
	journal.open_facility("storage")
	await get_tree().process_frame
	var presenter = journal.page_presenters.get("storage")
	if presenter == null or not journal.visible or journal.current_facility_id != "storage":
		failures.append("Camp Stores could not open its Journal presenter.")
		_finish(camp, failures)
		return
	if journal.header_title == null or journal.header_title.text != "The Spoils Cache":
		failures.append("Spoils Cache did not use its in-world Journal title.")
	await _validate_storage_tabs(presenter, journal, failures)
	_validate_empty_views(presenter, journal, failures)
	_validate_live_inventory(presenter, journal, failures)
	await get_tree().process_frame
	await get_tree().process_frame
	await _validate_rendered_view_icons(presenter, journal, failures)
	_validate_rendered_accessibility(journal, failures)
	_validate_debug_boundary(journal, failures)
	_finish(camp, failures)


func _validate_reachability(camp: Node, failures: Array[String]) -> void:
	var storage := camp.call("get_facility", "storage") as CampFacility
	if storage == null:
		failures.append("Camp Stores facility is missing from camp.")
		return
	if storage.display_name != "Spoils Cache":
		failures.append("Camp Stores facility was not retitled to Spoils Cache.")
	if not storage.interactive or storage.interaction_radius <= 0.0:
		failures.append("Camp Stores is not an interactive positive-radius facility.")
	var approach_id := String(camp.call("get_camp_route_approach_node_id", "storage"))
	if approach_id != "storage_approach":
		failures.append("Camp Stores does not resolve its authored approach node.")
	var player := camp.get_node_or_null("CampPlayer") as Node2D
	var path: Array = camp.call(
		"build_camp_path", player.global_position, storage.global_position, "storage"
	)
	if path.is_empty() or path[-1] != storage.global_position:
		failures.append("Camp Stores does not have a safe navigable route.")


func _validate_empty_views(
	presenter, journal: CampJournal, failures: Array[String]
) -> void:
	for view_id in StoragePresenterScript.VIEW_IDS:
		var model: Dictionary = presenter.build_view_model(view_id)
		if not Array(model.get("entries", [])).is_empty():
			failures.append("Fresh campaign '%s' Storage view was not empty." % view_id)
		if String(model.get("empty_state", "")).is_empty():
			failures.append("Fresh campaign '%s' Storage view lacks an empty state." % view_id)
		if not bool(model.get("read_only", false)):
			failures.append("Storage view '%s' is not marked read-only." % view_id)
	if journal.find_child("StorageEmptyState", true, false) == null:
		failures.append("Empty Storage page did not render an empty-state label.")


func _validate_storage_tabs(
	presenter: StoragePagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	var page := journal.find_child("StoragePage", true, false) as VBoxContainer
	var intro := journal.find_child("StorageReadOnlyNotice", true, false) as Label
	var tabs := journal.find_child("StorageTabs", true, false) as HBoxContainer
	if page == null or intro == null or tabs == null:
		failures.append("Camp Stores did not render its compact category tabs below the intro.")
		return
	if tabs.get_parent() != page or tabs.get_index() != intro.get_index() + 1:
		failures.append("Camp Stores tabs were not placed immediately below the intro.")
	if tabs.get_child_count() != StoragePresenterScript.VIEW_IDS.size():
		failures.append("Spoils Cache did not render exactly three category tabs.")
	if journal.find_child("StorageRecipesTab", true, false) != null:
		failures.append("Spoils Cache still rendered a Recipes tab.")
	var expected_tab_order: Array[String] = ["materials", "weapons", "tokens"]
	for tab_index in range(expected_tab_order.size()):
		var ordered_tab := tabs.get_child(tab_index) as Button
		if ordered_tab == null or String(ordered_tab.get_meta("storage_view_id", "")) != expected_tab_order[tab_index]:
			failures.append("Spoils Cache tabs were not ordered Materials, Weapons, Tokens.")
			break
	if presenter.current_view_id != "materials":
		failures.append("Spoils Cache did not default to the Materials tab.")

	for view_id in StoragePresenterScript.VIEW_IDS:
		var tab_name := "Storage" + view_id.capitalize() + "Tab"
		var tab := tabs.find_child(tab_name, true, false) as Button
		if tab == null:
			failures.append("Camp Stores category tab was missing for %s." % view_id)
			continue
		if tab.text != view_id.capitalize():
			failures.append("Camp Stores category tab label was incorrect for %s." % view_id)
		if String(tab.get_meta("storage_view_id", "")) != view_id:
			failures.append("Camp Stores category tab lost its view metadata for %s." % view_id)

	for removed_control_name in [
		"StorageFilters", "StorageViewSelector", "StorageNameFilter",
		"StorageBossFilter", "StorageRarityFilter", "StorageFamilyFilter",
	]:
		if journal.find_child(removed_control_name, true, false) != null:
			failures.append("Camp Stores still rendered removed filter control '%s'." % removed_control_name)

	for view_id in StoragePresenterScript.VIEW_IDS:
		var tab := journal.find_child(
			"Storage" + view_id.capitalize() + "Tab", true, false
		) as Button
		if tab == null:
			continue
		tab.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
		if presenter.current_view_id != view_id:
			failures.append("Selecting the %s Camp Stores tab did not refresh the view." % view_id)
			continue
		var heading := journal.find_child("StorageViewHeading", true, false) as Label
		var expected_title := String(presenter.build_view_model(view_id).get("title", ""))
		if heading == null or heading.text != expected_title:
			failures.append("Camp Stores heading did not refresh for the %s tab." % view_id)
		var refreshed_tabs := journal.find_child("StorageTabs", true, false) as HBoxContainer
		for candidate_id in StoragePresenterScript.VIEW_IDS:
			var candidate := refreshed_tabs.find_child(
				"Storage" + candidate_id.capitalize() + "Tab", true, false
			) as Button
			if candidate != null and candidate.disabled != (candidate_id == view_id):
				failures.append("Camp Stores active tab state was incorrect for %s." % view_id)


func _validate_live_inventory(
	presenter, _journal: CampJournal, failures: Array[String]
) -> void:
	var reward := CampaignState.debug_process_seeded_reward("ogre", "camp_stores_reward")
	if not bool(reward.get("ok", false)):
		failures.append("Camp Stores fixture reward failed: %s" % reward)
		return
	var tokens: Dictionary = presenter.build_view_model("tokens")
	if Array(tokens.get("entries", [])).size() != 1:
		failures.append("Token view did not refresh after first clear.")
	else:
		var token: Dictionary = tokens["entries"][0]
		if not String(token.get("detail_text", "")).contains("Warrior") or not String(token.get("detail_text", "")).contains("Earthgnasher"):
			failures.append("Token view omitted class or source boss.")
		if not token.get("icon_resource") is Texture2D:
			failures.append("Token view omitted its class icon.")

	var materials: Dictionary = presenter.build_view_model("materials")
	if Array(materials.get("entries", [])).is_empty():
		failures.append("Material view did not refresh after reward processing.")
	for entry_value in materials.get("entries", []):
		var entry: Dictionary = entry_value
		if (
			int(entry.get("count", 0)) <= 0
			or String(entry.get("rarity_text", "")).is_empty()
			or not entry.get("rarity_color") is Color
			or not entry.get("icon_resource") is Texture2D
			or String(entry.get("description", "")).is_empty()
		):
			failures.append("Material view lacks count/rarity/color/description accessibility data.")
			break
	var boss_filtered: Dictionary = presenter.build_view_model("materials", {"boss_id": "ogre"})
	if Array(boss_filtered.get("entries", [])).is_empty():
		failures.append("Boss filter removed Earthgnasher's own material drops.")
	var source_groups: Array = materials.get("source_groups", [])
	if source_groups.is_empty() or String(Dictionary(source_groups[0]).get("label", "")) != "Earthgnasher":
		failures.append("Boss Materials did not render single-source groups in catalog order.")
	else:
		var shared_index := -1
		for group_index in range(source_groups.size()):
			if String(Dictionary(source_groups[group_index]).get("label", "")) == "Shared Materials":
				shared_index = group_index
				break
		if shared_index < 0:
			failures.append("Boss Materials did not place multi-source entries in Shared Materials.")
		elif Array(Dictionary(source_groups[shared_index]).get("entries", [])).is_empty():
			failures.append("Shared Materials group was empty.")
	var name_filtered: Dictionary = presenter.build_view_model("materials", {"name": "no such material"})
	if not Array(name_filtered.get("entries", [])).is_empty():
		failures.append("Name filter did not exclude unmatched materials.")

	var legacy_recipes: Dictionary = presenter.build_view_model("recipes")
	if Array(legacy_recipes.get("entries", [])).size() != 2:
		failures.append("Legacy recipe model lookup no longer retained both first-clear unlocks.")
	for recipe_value in legacy_recipes.get("entries", []):
		var recipe: Dictionary = recipe_value
		if (
			String(recipe.get("craft_status", "")).is_empty()
			or not String(recipe.get("detail_text", "")).contains("Ingredients:")
			or not recipe.get("icon_resource") is Texture2D
		):
			failures.append("Legacy recipe model omitted owned counts or craftability status.")

	CampaignState.debug_grant_progression_materials({
		"earthgnasher_heartstone": 2,
		"quake_marrow": 4,
		"tempered_chainlink": 2,
		"rage_slick_hide": 2,
	})
	var rare_filtered: Dictionary = presenter.build_view_model("materials", {"rarity_id": "rare"})
	if Array(rare_filtered.get("entries", [])).is_empty():
		failures.append("Rarity filter did not expose a granted rare material.")
	var craft_result := CampaignState.craft("craft_earthgnasher_heartmaul")
	if not bool(craft_result.get("ok", false)):
		failures.append("Camp Stores fixture weapon could not be crafted through backend API.")
		return
	var warrior_id := ""
	for member in CampaignState.get_roster_members():
		if String(member.get("unit_class", "")) == "Warrior":
			warrior_id = String(member.get("member_id", ""))
			break
	if warrior_id.is_empty() or not bool(
		CampaignState.equip_weapon(warrior_id, "earthgnasher_heartmaul").get("ok", false)
	):
		failures.append("Camp Stores fixture weapon could not be equipped through backend API.")
	var weapons: Dictionary = presenter.build_view_model("weapons")
	if Array(weapons.get("entries", [])).size() != 1:
		failures.append("Crafted weapon view did not refresh.")
	else:
		var weapon: Dictionary = weapons["entries"][0]
		if (
			not String(weapon.get("detail_text", "")).contains("Power")
			or not String(weapon.get("detail_text", "")).contains("Equipped:")
			or not weapon.get("icon_resource") is Texture2D
			or not String(weapon.get("description", "")).contains("inactive future hook")
		):
			failures.append("Weapon view omitted family/stats/trait/equipped-raider information.")
	var heavy_filtered: Dictionary = presenter.build_view_model("weapons", {"family_id": "heavy_arms"})
	if Array(heavy_filtered.get("entries", [])).size() != 1:
		failures.append("Family filter did not retain the Heavy Arms weapon.")


func _validate_rendered_accessibility(
	journal: CampJournal, failures: Array[String]
) -> void:
	var content := journal.find_child("StorageInventoryContent", true, false)
	if content == null or content.get_child_count() == 0:
		failures.append("Campaign state change did not live-refresh rendered Storage content.")
	var found_bracketed_rarity := false
	for label in journal.find_children("*", "Label", true, false):
		if String(label.text).begins_with("[") and String(label.text).contains("]"):
			found_bracketed_rarity = true
			break
	if found_bracketed_rarity:
		failures.append("Material rarity retained a visible bracketed rarity prefix.")
	var presenter := journal.page_presenters.get("storage") as StoragePagePresenter
	if presenter != null:
		var materials := presenter.build_view_model("materials")
		for entry_value in materials.get("entries", []):
			var entry: Dictionary = entry_value
			var card := journal.find_child("StorageEntry_" + String(entry.get("stable_id", "")), true, false)
			var title := null if card == null else card.find_child("StorageEntryTitle", true, false) as Label
			if (
				title == null
				or title.text != "%s ×%d" % [entry.get("display_name", ""), int(entry.get("count", 0))]
				or title.get_theme_color("font_color") != entry.get("rarity_color", Color.WHITE)
			):
				failures.append("Material title did not retain the count and rarity color without a visible rarity label.")
			var icon := null if card == null else card.find_child("StorageEntryIcon", true, false) as TextureRect
			if icon == null or icon.texture != entry.get("icon_resource"):
				failures.append("Material card omitted its icon.")


func _validate_rendered_view_icons(
	presenter: StoragePagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	for view_id in StoragePresenterScript.VIEW_IDS:
		presenter.current_view_id = view_id
		presenter._queue_refresh()
		await get_tree().process_frame
		await get_tree().process_frame
		var model: Dictionary = presenter.build_view_model(view_id)
		for entry_value in model.get("entries", []):
			var entry: Dictionary = entry_value
			var card := journal.find_child("StorageEntry_" + String(entry.get("stable_id", "")), true, false)
			var icon := null if card == null else card.find_child("StorageEntryIcon", true, false) as TextureRect
			var placeholder := null if card == null else card.find_child("StorageEntryIconPlaceholder", true, false) as Label
			var icon_ok: bool = (
				entry.get("icon_resource") is Texture2D
				and icon != null
				and icon.texture == entry.get("icon_resource")
			) or (not entry.get("icon_resource") is Texture2D and placeholder != null)
			if not icon_ok:
				failures.append("Rendered %s entry omitted its icon or safe placeholder." % view_id)
	presenter.current_view_id = "materials"
	presenter._queue_refresh()
	await get_tree().process_frame


func _validate_debug_boundary(journal: CampJournal, failures: Array[String]) -> void:
	var notice := journal.find_child("StorageReadOnlyNotice", true, false) as Label
	if notice == null or notice.text != "Review the spoils of fallen foes and the weapons forged from them.":
		failures.append("Camp Stores intro copy did not match the compact progression notice.")
	var debug_panel := journal.find_child("StorageDebugControls", true, false)
	if OS.is_debug_build() and debug_panel == null:
		failures.append("Debug build omitted Camp Stores backend exercise controls.")
	for button in journal.find_children("*", "Button", true, false):
		var text := String(button.text).to_lower()
		var looks_mutating := (
			text.contains("craft") or text.contains("equip")
			or text.contains("grant") or text.contains("reward") or text.contains("spend")
		)
		if looks_mutating and not button.is_in_group("storage_debug_mutation"):
			failures.append("Production Storage page exposed mutation button: " + button.text)
	if journal.get_tree().get_nodes_in_group("storage_debug_mutation").is_empty():
		failures.append("Debug controls are not isolated in the debug-only mutation group.")


func _finish(camp: Node, failures: Array[String]) -> void:
	if camp != null and is_instance_valid(camp):
		camp.queue_free()
	if failures.is_empty():
		print("RAID_TEST_PASS:camp_stores_contract | Camp Stores contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
