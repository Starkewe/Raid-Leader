extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")


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
	_validate_combined_empty_state(presenter, journal, failures)
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


func _validate_combined_empty_state(
	presenter: SmithPagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	if journal.find_child("SmithTabs", true, false) != null:
		failures.append("Smith retained separate Forge or Equip tabs.")
	if journal.find_child("SmithArmorySection", true, false) == null:
		failures.append("Smith did not render its combined crafted armory section.")
	if journal.find_child("SmithReturnToArmory", true, false) == null:
		failures.append("Smith did not keep Return to Armory on the crafting screen.")
	for removed_filter_name in [
		"SmithForgeFilters", "SmithNameFilter", "SmithBossFilter", "SmithFamilyFilter",
	]:
		if journal.find_child(removed_filter_name, true, false) != null:
			failures.append("Smith retained removed filter node '%s'." % removed_filter_name)
	var forge := presenter.build_view_model()
	if not Array(forge.get("recipes", [])).is_empty():
		failures.append("Fresh Smith Forge exposed locked recipes.")
	if String(forge.get("empty_state", "")).is_empty():
		failures.append("Fresh Smith Forge omitted its empty state.")
	if Array(forge.get("holders", [])).size() != CampaignState.get_active_member_ids().size():
		failures.append("Combined Smith model omitted active raid-frame holders.")
	if not Array(forge.get("weapons", [])).is_empty():
		failures.append("Fresh Smith armory did not show its no-weapons state.")


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
	if (
		String(recipes[0].get("display_name", "")).naturalnocasecmp_to(
			String(recipes[1].get("display_name", ""))
		) > 0
	):
		failures.append("Unlocked recipes were not shown in stable name order.")

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
	await _wait_frames(2)
	forge = presenter.build_forge_view_model()
	var crafted_entry := _entry_by_id(forge.get("recipes", []), "weapon_id", weapon_id)
	if crafted_entry.is_empty():
		failures.append("Already-crafted result disappeared from the unlocked Forge list.")
	elif int(crafted_entry.get("crafted_count", 0)) != 1:
		failures.append("Recipe did not report CRAFTED ×1 after its first craft.")
	if not String(presenter.action_message).contains("not auto-equipped"):
		failures.append("Successful Forge action did not direct the player to the armory.")
	if journal.find_child("SmithWeapon_" + weapon_id, true, false) == null:
		failures.append("Successful crafting did not live-refresh the combined armory strip.")
	for expected_count in [2, 3]:
		_grant_recipe_cost(crafted_entry)
		crafted_entry = _entry_by_id(
			presenter.build_forge_view_model().get("recipes", []), "weapon_id", weapon_id
		)
		var another_confirmation := presenter.request_craft_confirmation(recipe_id)
		if (
			another_confirmation.get("status") != "confirmation_required"
			or not String(another_confirmation.get("message", "")).contains("Forge another")
		):
			failures.append("Crafted recipe did not offer Forge another confirmation.")
			break
		var another_result := presenter.confirm_pending_craft()
		if (
			another_result.get("status") != "crafted"
			or int(another_result.get("crafted_count", 0)) != expected_count
		):
			failures.append("Forge another did not create exactly one counted copy.")
			break
		await _wait_frames(2)
		crafted_entry = _entry_by_id(
			presenter.build_forge_view_model().get("recipes", []), "weapon_id", weapon_id
		)
	if int(crafted_entry.get("crafted_count", 0)) != 3:
		failures.append("Smith did not live-refresh the recipe to CRAFTED ×3.")
	var weapon_entry := _entry_by_id(
		presenter.build_forge_view_model().get("weapons", []), "weapon_id", weapon_id
	)
	if (
		int(weapon_entry.get("crafted_count", 0)) != 3
		or int(weapon_entry.get("available_count", 0)) != 3
	):
		failures.append("Stacked armory card did not report crafted/equipped/available counts.")


func _validate_equipment(
	presenter: SmithPagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	journal.call("_refresh_current_facility")
	await _wait_frames(2)
	if journal.find_child("SmithTabs", true, false) != null:
		failures.append("Combined Smith unexpectedly rendered view tabs.")
	var drawer := get_tree().get_first_node_in_group("camp_raid_drawer") as CampRaidDrawer
	var armory := journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
	if drawer == null or not drawer.is_locked_open():
		failures.append("Combined Smith did not force the camp raid drawer open and lock it.")
	if armory == null:
		failures.append("Combined Smith did not render its Return to Armory drop target.")
	if drawer == null or armory == null:
		return
	var smith_model := presenter.build_forge_view_model()
	var weapon_id := "earthgnasher_heartmaul"
	if not CampaignState.owns_crafted_weapon(weapon_id):
		weapon_id = String(Array(smith_model.get("weapons", []))[0].get("weapon_id", "")) if not Array(smith_model.get("weapons", [])).is_empty() else ""
	var compatible_ids: Array[String] = []
	for raider_value in smith_model.get("holders", []):
		var raider: Dictionary = raider_value
		if not bool(raider.get("active", false)):
			continue
		var member_id := String(raider.get("raider_id", ""))
		if bool(CampaignState.check_equip_weapon(member_id, weapon_id).get("ok", false)):
			compatible_ids.append(member_id)
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
	var drag_preview := armory_card.build_drag_preview()
	if (
		drag_preview.z_as_relative
		or drag_preview.z_index != RenderingServer.CANVAS_ITEM_Z_MAX
		or drag_preview.mouse_filter != Control.MOUSE_FILTER_IGNORE
	):
		failures.append("Smith weapon drag preview was not promoted above menu layers.")
	drag_preview.free()
	var drop_point := Vector2(180, 22)
	var first_frame := drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	var second_frame := drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	if first_frame == null:
		failures.append("Compatible active raid frame was not rendered.")
		return
	for target_point in [Vector2(22, 22), Vector2(90, 22), drop_point]:
		if not first_frame._can_drop_data(target_point, armory_card.drag_payload):
			failures.append(
				"Compatible raid frame rejected a crafted weapon over drop point %s."
				% target_point
			)
			return
	if not first_frame.drop_allowed or first_frame.drop_reason.is_empty():
		failures.append("Compatible raid frame did not expose its valid highlighted drop state.")
		return
	if second_frame == null or not second_frame._can_drop_data(
		drop_point, armory_card.drag_payload
	):
		failures.append("Second compatible frame rejected an available counted copy.")
		return
	if not first_frame.drop_reason.is_empty() or first_frame.drop_allowed:
		failures.append("Entering a new raid-frame target did not clear the previous highlight.")
	second_frame._on_mouse_exited()
	if not second_frame.drop_reason.is_empty() or second_frame.drop_allowed:
		failures.append("Mouse exit did not immediately clear raid-frame drop feedback.")
	if not first_frame._can_drop_data(Vector2(90, 22), armory_card.drag_payload):
		failures.append("First raid frame did not restore its current-target highlight.")
		return
	first_frame._notification(Control.NOTIFICATION_DRAG_END)
	if not first_frame.drop_reason.is_empty() or first_frame.drop_allowed:
		failures.append("Canceling a drag did not clear all raid-frame feedback.")
	if not first_frame._can_drop_data(Vector2(90, 22), armory_card.drag_payload):
		failures.append("First raid frame did not accept the restarted drag.")
		return
	await _drag_control_to(
		armory_card,
		first_frame.to_global(Vector2(90, 22))
	)
	await _wait_frames(3)
	if CampaignState.get_weapon_holder_id(weapon_id) != first_id:
		failures.append("Compatible active raid frame rejected an unassigned crafted weapon drag.")
		return
	second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	if second_frame == null or not second_frame._can_drop_data(
		drop_point, {"type": "smith_armory_weapon", "weapon_id": weapon_id}
	):
		failures.append("A second available copy was not droppable on another raid frame.")
	else:
		second_frame._drop_data(
			drop_point, {"type": "smith_armory_weapon", "weapon_id": weapon_id}
		)
		await _wait_frames(2)
	var counted_holders := CampaignState.get_equipped_raider_ids(weapon_id)
	if counted_holders.size() != 2 or not counted_holders.has(first_id) or not counted_holders.has(second_id):
		failures.append("Two Smith drops did not assign two fungible copies.")
	var assigned_entry := _entry_by_id(
		presenter.build_forge_view_model().get("weapons", []), "weapon_id", weapon_id
	)
	if (
		not bool(assigned_entry.get("can_drag", false))
		or int(assigned_entry.get("crafted_count", 0)) != 3
		or int(assigned_entry.get("equipped_count", 0)) != 2
		or int(assigned_entry.get("available_count", 0)) != 1
	):
		failures.append("Stacked armory did not stay draggable with one copy available.")
	armory = journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
	if armory == null:
		failures.append("Smith live refresh did not rebuild Return to Armory.")
		return
	first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	if first_frame == null:
		failures.append("Equipped raid frame disappeared before its armory-return drag.")
		return
	await _drag_control_to(
		first_frame,
		armory.get_global_rect().get_center(),
		drop_point
	)
	await _wait_frames(3)
	if CampaignState.get_equipped_raider_ids(weapon_id) != [second_id]:
		failures.append("Pointer-driven Return to Armory did not return exactly one copy.")
	if CampaignState.get_available_weapon_count(weapon_id) != 2:
		failures.append("Returning one equipped copy did not increment available count once.")
	second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	if second_frame == null:
		failures.append("Second compatible raider frame disappeared during equipment refresh.")
		return
	first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	first_frame._drop_data(
		drop_point, {"type": "smith_armory_weapon", "weapon_id": weapon_id}
	)
	await _wait_frames(2)
	if not CampaignState.get_equipped_raider_ids(weapon_id).has(first_id):
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
		if CampaignState.get_equipped_raider_ids(weapon_id) != [first_id]:
			failures.append("Equipping a replacement did not return exactly the destination copy.")

	first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
	second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
	var swap_payload := first_frame.get_drag_payload(drop_point)
	if not second_frame._can_drop_data(drop_point, swap_payload):
		failures.append("Compatible equipped raid frames did not accept a weapon swap drag.")
	else:
		await _drag_control_to(
			first_frame,
			second_frame.to_global(Vector2(90, 22)),
			drop_point
		)
		await _wait_frames(3)
		if (
			CampaignState.get_weapon_holder_id(weapon_id) != second_id
			or CampaignState.get_weapon_holder_id("faultline_cudgel") != first_id
		):
			failures.append("Pointer-driven frame swap did not exchange both weapons atomically.")
		second_frame = drawer.find_child("CampRaidFrame_" + second_id, true, false) as CampRaidFrame
		first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
		first_frame._drop_data(drop_point, second_frame.get_drag_payload(drop_point))
		await _wait_frames(2)

	var reserve_weapon_id := String(
		CampaignState.get_member(second_id).get("equipped_weapon_id", "")
	)
	if not CampaignState.remove_active_member(second_id):
		failures.append("Could not create a reserve-holder fixture.")
		return
	await _wait_frames(2)
	smith_model = presenter.build_forge_view_model()
	var reserve := _entry_by_id(smith_model.get("holders", []), "raider_id", second_id)
	if reserve.is_empty() or not bool(reserve.get("reserve_holder", false)) or not String(reserve.get("label", "")).contains("Reserve holder"):
		failures.append("Reserve weapon holder was hidden from the combined Smith model.")
	if drawer.find_child("CampRaidFrame_" + second_id, true, false) != null:
		failures.append("Reserve holder incorrectly retained an assignment drop target in the raid drawer.")
	var reserve_entry := _entry_by_id(
		smith_model.get("weapons", []), "weapon_id", reserve_weapon_id
	)
	var reserve_card := journal.find_child(
		"SmithReserve_%s_%s" % [reserve_weapon_id, second_id], true, false
	) as SmithDragSource
	if (
		reserve_entry.is_empty()
		or not bool(reserve_entry.get("holder_reserve", false))
		or not Array(reserve_entry.get("reserve_holder_ids", [])).has(second_id)
		or reserve_card == null
		or not reserve_card.drag_enabled
		or reserve_card.drag_payload.get("type") != "smith_reserve_weapon"
		or reserve_card.find_child("SmithReserveOverlay", true, false) == null
	):
		failures.append("Reserve holder did not render as an individual recovery entry.")
	else:
		first_frame = drawer.find_child("CampRaidFrame_" + first_id, true, false) as CampRaidFrame
		if first_frame == null or not first_frame._can_drop_data(
			drop_point, reserve_card.drag_payload
		):
			failures.append("Compatible active frame rejected a reserve-held weapon reclaim drag.")
		else:
			first_frame._drop_data(drop_point, reserve_card.drag_payload)
		await _wait_frames(2)
	if CampaignState.get_weapon_holder_id(reserve_weapon_id) != first_id:
		failures.append("Reserve-held weapon was not reclaimed by the active raider.")
	if not String(CampaignState.get_member(second_id).get("equipped_weapon_id", "")).is_empty():
		failures.append("Reserve reclamation did not clear the reserve holder.")
	if not CampaignState.get_weapon_holder_id(weapon_id).is_empty():
		failures.append("Reserve reclamation did not release the active raider's previous weapon.")
	if not _entry_by_id(
		presenter.build_forge_view_model().get("holders", []), "raider_id", second_id
	).is_empty():
		failures.append("Unarmed reserve raider remained in the combined Smith holder model.")

	var states: Dictionary = CampaignState.get_campaign_snapshot().get("raider_states", {})
	states[second_id]["equipped_weapon_id"] = "returning_content_weapon"
	if not CampaignState.debug_replace_raider_states(states):
		failures.append("Could not install Smith missing-content recovery fixture.")
		return
	await _wait_frames(2)
	smith_model = presenter.build_forge_view_model()
	var missing := _entry_by_id(
		smith_model.get("weapons", []), "weapon_id", "returning_content_weapon"
	)
	if (
		missing.is_empty()
		or not bool(missing.get("missing_content", false))
		or bool(missing.get("can_drag", true))
		or not Array(missing.get("reserve_holder_ids", [])).has(second_id)
		or not String(missing.get("disabled_reason", "")).contains("Return")
	):
		failures.append("Missing-content weapon was not visible as an inactive recovery entry.")
	reserve_card = journal.find_child(
		"SmithReserve_returning_content_weapon_%s" % second_id, true, false
	) as SmithDragSource
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


func _drag_control_to(
	source: Control, target_position: Vector2, source_local_position: Variant = null
) -> void:
	var source_position := source.get_global_rect().get_center()
	if source_local_position is Vector2:
		source_position = source.to_global(source_local_position)
	_send_mouse_motion(source_position, Vector2.ZERO, 0)
	await _wait_frames(1)
	_send_mouse_button(source_position, true)
	await _wait_frames(1)
	var threshold_position := source_position + Vector2(16, 0)
	_send_mouse_motion(
		threshold_position,
		threshold_position - source_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await _wait_frames(1)
	_send_mouse_motion(
		target_position,
		target_position - threshold_position,
		MOUSE_BUTTON_MASK_LEFT
	)
	await _wait_frames(2)
	_send_mouse_button(target_position, false)


func _send_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)


func _send_mouse_motion(
	position: Vector2, relative: Vector2, button_mask: int
) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	event.button_mask = button_mask
	Input.parse_input_event(event)


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
