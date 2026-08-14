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
	_validate_empty_views(presenter, journal, failures)
	_validate_live_inventory(presenter, journal, failures)
	await get_tree().process_frame
	await get_tree().process_frame
	_validate_rendered_accessibility(journal, failures)
	_validate_debug_boundary(journal, failures)
	_finish(camp, failures)


func _validate_reachability(camp: Node, failures: Array[String]) -> void:
	var storage := camp.call("get_facility", "storage") as CampFacility
	if storage == null:
		failures.append("Camp Stores facility is missing from camp.")
		return
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

	var materials: Dictionary = presenter.build_view_model("materials")
	if Array(materials.get("entries", [])).is_empty():
		failures.append("Material view did not refresh after reward processing.")
	for entry_value in materials.get("entries", []):
		var entry: Dictionary = entry_value
		if (
			int(entry.get("count", 0)) <= 0
			or String(entry.get("rarity_text", "")).is_empty()
			or not entry.get("rarity_color") is Color
			or String(entry.get("description", "")).is_empty()
		):
			failures.append("Material view lacks count/rarity/color/description accessibility data.")
			break
	var boss_filtered: Dictionary = presenter.build_view_model("materials", {"boss_id": "ogre"})
	if Array(boss_filtered.get("entries", [])).is_empty():
		failures.append("Boss filter removed Earthgnasher's own material drops.")
	var name_filtered: Dictionary = presenter.build_view_model("materials", {"name": "no such material"})
	if not Array(name_filtered.get("entries", [])).is_empty():
		failures.append("Name filter did not exclude unmatched materials.")

	var recipes: Dictionary = presenter.build_view_model("recipes")
	if Array(recipes.get("entries", [])).size() != 2:
		failures.append("Recipe view did not show both first-clear unlocks.")
	for recipe_value in recipes.get("entries", []):
		var recipe: Dictionary = recipe_value
		if String(recipe.get("craft_status", "")).is_empty() or not String(recipe.get("detail_text", "")).contains("Ingredients:"):
			failures.append("Recipe view omitted owned counts or craftability status.")

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
	var found_rarity_text := false
	for label in journal.find_children("*", "Label", true, false):
		if String(label.text).begins_with("[") and String(label.text).contains("]"):
			found_rarity_text = true
			break
	if not found_rarity_text:
		failures.append("Material rarity was conveyed by color without accessible text.")


func _validate_debug_boundary(journal: CampJournal, failures: Array[String]) -> void:
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
