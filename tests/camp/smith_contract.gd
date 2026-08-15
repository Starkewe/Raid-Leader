extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")
const SmithPresenterScript := preload("res://scripts/ui/smith_page_presenter.gd")


func _ready() -> void:
	var failures: Array[String] = []
	CampaignState.reset_campaign(false, 616161)
	var camp := CampScene.instantiate()
	add_child(camp)
	await get_tree().process_frame
	_validate_reachability(camp, failures)
	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	if journal == null:
		failures.append("Camp Journal was unavailable.")
		_finish(camp, failures)
		return
	journal.open_facility("smith")
	await get_tree().process_frame
	var presenter = journal.page_presenters.get("smith")
	if (
		presenter == null
		or not presenter is SmithPagePresenter
		or not journal.visible
		or journal.current_facility_id != "smith"
	):
		failures.append("Rudimentary Smith could not open its Journal presenter.")
		_finish(camp, failures)
		return
	_validate_tabs_and_empty_state(presenter, journal, failures)
	await _validate_forge(presenter, journal, failures)
	await _validate_equipment(presenter, journal, failures)
	_finish(camp, failures)


func _validate_reachability(camp: Node, failures: Array[String]) -> void:
	var smith := camp.call("get_facility", "smith") as CampFacility
	if smith == null:
		failures.append("Rudimentary Smith facility is missing from camp.")
		return
	if not smith.interactive or not is_equal_approx(smith.interaction_radius, 190.0):
		failures.append("Rudimentary Smith is not interactive at the tuned 190px radius.")
	var approach_id := String(camp.call("get_camp_route_approach_node_id", "smith"))
	if approach_id != "smith_approach":
		failures.append("Rudimentary Smith does not retain its authored approach node.")
	var player := camp.get_node_or_null("CampPlayer") as Node2D
	var path: Array = camp.call("build_camp_path", player.global_position, smith.global_position, "smith")
	if path.is_empty() or path[-1] != smith.global_position:
		failures.append("Rudimentary Smith does not have a safe navigable route.")


func _validate_tabs_and_empty_state(
	presenter: SmithPagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	if SmithPresenterScript.VIEW_IDS != ["forge", "equip"]:
		failures.append("Smith does not expose exactly Forge and Equip views.")
	if journal.find_child("SmithForgeTab", true, false) == null:
		failures.append("Smith Forge tab was not rendered.")
	if journal.find_child("SmithEquipTab", true, false) == null:
		failures.append("Smith Equip tab was not rendered.")
	var forge := presenter.build_view_model("forge")
	if not Array(forge.get("recipes", [])).is_empty():
		failures.append("Fresh Smith Forge exposed locked recipes.")
	if String(forge.get("empty_state", "")).is_empty():
		failures.append("Fresh Smith Forge omitted its empty state.")
	var equip := presenter.build_view_model("equip")
	if Array(equip.get("raiders", [])).size() != CampaignState.get_active_member_ids().size():
		failures.append("Smith Equip did not list every active-party raider.")
	if not Array(equip.get("weapons", [])).is_empty():
		failures.append("Fresh Smith Equip did not show its no-weapons state.")


func _validate_forge(
	presenter: SmithPagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	var reward := CampaignState.debug_process_seeded_reward("ogre", "smith_contract_first_clear")
	if not bool(reward.get("ok", false)):
		failures.append("Smith fixture could not unlock Earthgnasher recipes: %s" % reward)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var forge := presenter.build_forge_view_model()
	var recipes: Array = forge.get("recipes", [])
	if recipes.size() != 2:
		failures.append("Forge did not show both unlocked first-clear recipes.")
		return
	if journal.find_child("SmithRecipeList", true, false) == null:
		failures.append("Campaign state change did not live-refresh rendered Forge recipes.")
	for recipe_value in recipes:
		var recipe: Dictionary = recipe_value
		if (
			String(recipe.get("boss_name", "")).is_empty()
			or String(recipe.get("family_name", "")).is_empty()
			or not recipe.has("power_percentage")
			or not recipe.has("speed_percentage")
			or not recipe.has("range_units")
		):
			failures.append("Recipe card omitted source, family, or all three weapon attributes.")
		var weapon_trait: Dictionary = recipe.get("trait", {})
		if bool(weapon_trait.get("active", true)) or not String(recipe.get("trait_text", "")).contains("inactive placeholder"):
			failures.append("Recipe trait was not explicitly labeled as an inactive placeholder.")
		var components: Array = recipe.get("components", [])
		if components.size() != 3:
			failures.append("Recipe detail did not contain only its three authored components.")
		for component_value in components:
			var component: Dictionary = component_value
			if (
				String(component.get("rarity_text", "")).is_empty()
				or not component.get("rarity_color") is Color
				or int(component.get("required", 0)) <= 0
				or not component.has("owned")
				or not component.has("missing")
			):
				failures.append("Forge component omitted rarity, counts, or shortage data.")
				break
		if not bool(recipe.get("craftable", false)) and String(recipe.get("disabled_reason", "")).is_empty():
			failures.append("Disabled recipe did not provide an actionable reason.")
	var selected: Dictionary = forge.get("selected_recipe", {})
	var recipe_id := String(selected.get("recipe_id", ""))
	var weapon_id := String(selected.get("weapon_id", ""))
	if Array(presenter.build_forge_view_model({"boss_id": "ogre"}).get("recipes", [])).size() != 2:
		failures.append("Forge source-boss filter removed matching recipes.")
	if Array(presenter.build_forge_view_model({
		"family_id": String(selected.get("family_id", "")),
	}).get("recipes", [])).is_empty():
		failures.append("Forge family filter removed its selected matching recipe.")
	if Array(presenter.build_forge_view_model({
		"name": String(selected.get("display_name", "")),
	}).get("recipes", [])).size() != 1:
		failures.append("Forge name filter did not isolate the selected weapon.")
	if not Array(presenter.build_forge_view_model({"name": "no such weapon"}).get("recipes", [])).is_empty():
		failures.append("Forge name filter retained unmatched weapons.")

	_grant_recipe_cost(selected)
	selected = presenter.build_forge_view_model().get("selected_recipe", {})
	var before := _component_counts(selected)
	var confirmation := presenter.request_craft_confirmation(recipe_id)
	if confirmation.get("status") != "confirmation_required":
		failures.append("Craftable weapon did not require confirmation.")
	elif (
		journal.find_child("SmithCraftConfirmation", true, false) == null
		or not String(confirmation.get("message", "")).contains(String(selected.get("display_name", "")))
		or Array(confirmation.get("components", [])).size() != Array(selected.get("components", [])).size()
	):
		failures.append("Craft confirmation omitted the weapon or exact component list.")
	presenter.cancel_pending_craft()
	if _component_counts(selected) != before or CampaignState.owns_crafted_weapon(weapon_id):
		failures.append("Canceling craft changed materials or weapon ownership.")
	presenter.request_craft_confirmation(recipe_id)
	var crafted := presenter.confirm_pending_craft()
	if crafted.get("status") != "crafted":
		failures.append("Confirmed Smith craft did not call the atomic backend: %s" % crafted)
	else:
		for component_value in selected.get("components", []):
			var component: Dictionary = component_value
			var material_id := String(component.get("material_id", ""))
			if CampaignState.get_material_count(material_id) != int(before.get(material_id, 0)) - int(component.get("required", 0)):
				failures.append("Confirmed Smith craft did not consume exact component quantities once.")
				break
	if not CampaignState.get_weapon_holder_id(weapon_id).is_empty():
		failures.append("Crafting auto-equipped the new weapon.")
	forge = presenter.build_forge_view_model()
	var crafted_entry := _entry_by_id(forge.get("recipes", []), "weapon_id", weapon_id)
	if crafted_entry.is_empty():
		failures.append("Already-crafted result disappeared from the unlocked Forge list.")
	elif (
		crafted_entry.get("craft_status") != "already_owned"
		or not String(crafted_entry.get("disabled_reason", "")).contains("Equip")
	):
		failures.append("Already-crafted recipe lacked its disabled Equip direction.")
	if not String(presenter.action_message).contains("not auto-equipped"):
		failures.append("Successful Forge action did not direct the player to Equip.")
	if presenter.request_craft_confirmation(recipe_id).get("status") != "already_owned":
		failures.append("Smith allowed a duplicate crafting confirmation.")


func _validate_equipment(
	presenter: SmithPagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	presenter.current_view_id = "equip"
	journal.call("_refresh_current_facility")
	await _wait_frames(2)
	if journal.find_child("SmithRaiderSelector", true, false) != null:
		failures.append("Smith Equip retained the duplicate in-menu active raider selector.")
	var drawer := get_tree().get_first_node_in_group("camp_raid_drawer") as CampRaidDrawer
	var armory := journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
	if drawer == null or not drawer.is_locked_open():
		failures.append("Smith Equip did not force the camp raid drawer open and lock it.")
	if armory == null:
		failures.append("Smith Equip did not render its Return to Armory drop target.")
	if drawer == null or armory == null:
		return
	var equip := presenter.build_equip_view_model()
	var weapon_id := "earthgnasher_heartmaul"
	if not CampaignState.owns_crafted_weapon(weapon_id):
		weapon_id = String(Array(equip.get("weapons", []))[0].get("weapon_id", "")) if not Array(equip.get("weapons", [])).is_empty() else ""
	var compatible_ids: Array[String] = []
	for raider_value in equip.get("raiders", []):
		var raider: Dictionary = raider_value
		if not bool(raider.get("active", false)):
			continue
		presenter.selected_raider_id = String(raider.get("raider_id", ""))
		var entry := _entry_by_id(
			presenter.build_equip_view_model().get("weapons", []), "weapon_id", weapon_id
		)
		if bool(entry.get("compatible", false)):
			compatible_ids.append(String(raider.get("raider_id", "")))
			if compatible_ids.size() >= 2:
				break
	if compatible_ids.size() < 2:
		failures.append("Smith fixture lacks two active compatible weapon recipients.")
		return
	var first_id := compatible_ids[0]
	var second_id := compatible_ids[1]
	var armory_card := journal.find_child("SmithWeapon_" + weapon_id, true, false) as SmithDragSource
	if armory_card == null or not armory_card.drag_enabled:
		failures.append("Unassigned crafted weapon was not rendered as a draggable armory card.")
		return
	var drop_point := Vector2(180, 24)
	var first_frame := drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	var second_frame := drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	if (
		first_frame == null
		or not first_frame._can_drop_data(drop_point, armory_card.drag_payload)
	):
		failures.append("Compatible active raid frame rejected an unassigned crafted weapon drag.")
		return
	first_frame._drop_data(drop_point, armory_card.drag_payload)
	await _wait_frames(2)
	if CampaignState.get_weapon_holder_id(weapon_id) != first_id:
		failures.append("Dropping an armory weapon on a raid frame did not equip it.")
	second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	if second_frame != null and second_frame._can_drop_data(
		drop_point, {"type": "smith_armory_weapon", "weapon_id": weapon_id}
	):
		failures.append("An already-held unique weapon remained droppable on another raid frame.")
	var assigned_entry := _entry_by_id(
		presenter.build_equip_view_model().get("weapons", []), "weapon_id", weapon_id
	)
	if (
		bool(assigned_entry.get("can_equip", true))
		or assigned_entry.get("equip_status") != "assigned_elsewhere"
		or assigned_entry.get("holder_id") != first_id
		or not String(assigned_entry.get("disabled_reason", "")).contains("unequip")
	):
		failures.append("Held weapon did not remain visible and disabled with manual-transfer direction.")
	armory = journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
	if armory == null:
		failures.append("Smith live refresh did not rebuild Return to Armory.")
		return
	armory._drop_data(drop_point, {
		"type": "smith_equipped_weapon",
		"source_raider_id": first_id,
		"weapon_id": weapon_id,
	})
	await _wait_frames(2)
	if not CampaignState.get_weapon_holder_id(weapon_id).is_empty():
		failures.append("Return to Armory did not manually unequip the current holder.")
	second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	if second_frame == null:
		failures.append("Second compatible raider frame disappeared during equipment refresh.")
		return
	second_frame._drop_data(
		drop_point, {"type": "smith_armory_weapon", "weapon_id": weapon_id}
	)
	await _wait_frames(2)
	if CampaignState.get_weapon_holder_id(weapon_id) != second_id:
		failures.append("Weapon was not claimable by drag after its holder manually unequipped it.")

	var replacement_recipe := presenter._build_recipe_entry("craft_faultline_cudgel")
	_grant_recipe_cost(replacement_recipe)
	if CampaignState.craft("craft_faultline_cudgel").get("status") != "crafted":
		failures.append("Smith replacement fixture could not be crafted.")
	else:
		await _wait_frames(2)
		second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
		second_frame._drop_data(
			drop_point,
			{"type": "smith_armory_weapon", "weapon_id": "faultline_cudgel"}
		)
		await _wait_frames(2)
		if CampaignState.get_weapon_holder_id("faultline_cudgel") != second_id:
			failures.append("Dropping a replacement weapon did not equip the selected raid frame.")
		if not CampaignState.get_weapon_holder_id(weapon_id).is_empty():
			failures.append("Equipping a replacement did not return the previous weapon to the armory.")

	first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	first_frame._drop_data(
		drop_point, {"type": "smith_armory_weapon", "weapon_id": weapon_id}
	)
	await _wait_frames(2)
	first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	var swap_payload := first_frame.get_drag_payload(drop_point)
	if not second_frame._can_drop_data(drop_point, swap_payload):
		failures.append("Compatible equipped raid frames did not accept a weapon swap drag.")
	else:
		second_frame._drop_data(drop_point, swap_payload)
		await _wait_frames(2)
		if (
			CampaignState.get_weapon_holder_id(weapon_id) != second_id
			or CampaignState.get_weapon_holder_id("faultline_cudgel") != first_id
		):
			failures.append("Frame-to-frame drag did not swap both compatible weapons atomically.")
		second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
		first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
		first_frame._drop_data(drop_point, second_frame.get_drag_payload(drop_point))
		await _wait_frames(2)

	if not CampaignState.remove_active_member(second_id):
		failures.append("Could not create a reserve-holder fixture.")
		return
	await _wait_frames(2)
	equip = presenter.build_equip_view_model()
	var reserve := _entry_by_id(equip.get("raiders", []), "raider_id", second_id)
	if reserve.is_empty() or not bool(reserve.get("reserve_holder", false)) or not String(reserve.get("label", "")).contains("Reserve holder"):
		failures.append("Reserve weapon holder was hidden or unlabeled in Equip.")
	if drawer.find_child("CampRaidFrame_" + second_id, true, false) != null:
		failures.append("Reserve holder incorrectly retained an assignment drop target in the raid drawer.")
	var reserve_card := journal.find_child("SmithReserve_" + second_id, true, false) as SmithDragSource
	if reserve_card == null or not reserve_card.drag_enabled:
		failures.append("Reserve holder did not render as a recovery-only drag source.")
	else:
		armory = journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
		armory._drop_data(drop_point, reserve_card.drag_payload)
		await _wait_frames(2)
	if not _entry_by_id(presenter.build_equip_view_model().get("raiders", []), "raider_id", second_id).is_empty():
		failures.append("Unarmed reserve raider remained in the Equip raider list.")

	var states: Dictionary = CampaignState.get_campaign_snapshot().get("raider_states", {})
	states[second_id]["equipped_weapon_id"] = "returning_content_weapon"
	if not CampaignState.debug_replace_raider_states(states):
		failures.append("Could not install Smith missing-content recovery fixture.")
		return
	await _wait_frames(2)
	equip = presenter.build_equip_view_model()
	var missing := _entry_by_id(equip.get("weapons", []), "weapon_id", "returning_content_weapon")
	if (
		missing.is_empty()
		or not bool(missing.get("missing_content", false))
		or bool(missing.get("can_equip", true))
		or not String(missing.get("disabled_reason", "")).contains("Unequip")
	):
		failures.append("Missing-content weapon was not visible as an inactive recovery entry.")
	reserve_card = journal.find_child("SmithReserve_" + second_id, true, false) as SmithDragSource
	armory = journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
	if reserve_card == null or armory == null:
		failures.append("Missing-content reserve holder did not remain recoverable through drag-and-drop.")
	else:
		armory._drop_data(drop_point, reserve_card.drag_payload)
		await _wait_frames(2)
		if not String(CampaignState.get_member(second_id).get("equipped_weapon_id", "")).is_empty():
			failures.append("Missing-content recovery drag did not clear the saved equipment slot.")


func _grant_recipe_cost(recipe: Dictionary) -> void:
	var grants: Dictionary = {}
	for component_value in recipe.get("components", []):
		var component: Dictionary = component_value
		grants[String(component.get("material_id", ""))] = int(component.get("required", 0))
	CampaignState.debug_grant_progression_materials(grants)


func _component_counts(recipe: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for component_value in recipe.get("components", []):
		var component: Dictionary = component_value
		var material_id := String(component.get("material_id", ""))
		result[material_id] = CampaignState.get_material_count(material_id)
	return result


func _entry_by_id(entries: Array, field_name: String, stable_id: String) -> Dictionary:
	for entry_value in entries:
		if entry_value is Dictionary and String(entry_value.get(field_name, "")) == stable_id:
			return Dictionary(entry_value)
	return {}


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _finish(camp: Node, failures: Array[String]) -> void:
	if camp != null and is_instance_valid(camp):
		camp.queue_free()
	if failures.is_empty():
		print("RAID_TEST_PASS:smith_contract | Smith Forge and unique equipment contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
