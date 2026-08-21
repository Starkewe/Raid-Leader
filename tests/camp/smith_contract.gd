extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	CampaignState.reset_campaign(false, 616161)
	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(2)
	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	var drawer := camp.get_node_or_null("CampHUD/CampRaidDrawer") as CampRaidDrawer
	var presenter := (
		journal.page_presenters.get("smith") as SmithPagePresenter
		if journal != null else null
	)
	_expect(journal != null, "Camp Journal was unavailable.", failures)
	_expect(drawer != null, "Camp raid drawer was unavailable.", failures)
	_expect(presenter != null, "Smith presenter was unavailable.", failures)
	if journal == null or drawer == null or presenter == null:
		_finish(camp, failures)
		return

	journal.open_facility("smith")
	await _wait_frames(2)
	_validate_category_gate(presenter, journal, drawer, failures)

	var reward := CampaignState.debug_process_seeded_reward("ogre", "smith_contract_first_clear")
	_expect(bool(reward.get("ok", false)), "Smith fixture could not unlock recipes.", failures)
	await _wait_frames(3)
	_validate_categories_after_unlock(presenter, journal, failures)

	var family_id := "heavy_arms"
	if not presenter.select_family(family_id):
		for category_value in presenter.build_view_model().get("categories", []):
			var category: Dictionary = category_value
			if bool(category.get("unlocked", false)):
				family_id = String(category.get("family_id", ""))
				break
	_expect(presenter.selected_family_id == family_id, "Selecting an unlocked category failed.", failures)
	await _wait_frames(3)
	_validate_forge(presenter, journal, drawer, failures)
	await _validate_armory_and_equipment(presenter, journal, drawer, failures)
	await _validate_reserve_and_missing_recovery(presenter, journal, drawer, failures)

	presenter.back_to_weapon_types()
	await _wait_frames(3)
	_expect(presenter.selected_family_id.is_empty(), "Back did not return to weapon types.", failures)
	_expect(journal.find_child("SmithCategoryGrid", true, false) != null, "Weapon type gate did not return after Back.", failures)
	_expect(journal.find_child("SmithTabs", true, false) == null, "Smith tabs remained on the weapon type gate.", failures)
	var gate_action := journal.find_child("CampJournalHeaderAction", true, false) as Button
	_expect(gate_action != null and gate_action.text == "Close  [Esc]", "Smith gate header action did not return to Close.", failures)
	_expect(drawer.get_smith_family_filter().is_empty(), "Back did not clear the Smith drawer family filter.", failures)

	_expect(presenter.select_family(family_id), "Smith could not re-enter the selected family for Escape validation.", failures)
	await _wait_frames(3)
	var nested_action := journal.find_child("CampJournalHeaderAction", true, false) as Button
	_expect(nested_action != null and nested_action.text == "Back to Weapon Types", "Smith nested page did not expose the header back action.", failures)
	journal.close_for_escape()
	await _wait_frames(3)
	_expect(journal.is_open() and presenter.selected_family_id.is_empty(), "First Smith Escape did not return to weapon types.", failures)
	journal.close_for_escape()
	await _wait_frames(2)
	_expect(not journal.is_open(), "Second Smith Escape did not close the journal.", failures)
	_expect(drawer.get_smith_family_filter().is_empty(), "Closing Smith did not clear its drawer family filter.", failures)
	journal.open_facility("smith")
	await _wait_frames(3)
	_expect(presenter.selected_family_id.is_empty(), "Reopening Smith did not reset to the weapon type gate.", failures)
	_finish(camp, failures)


func _validate_category_gate(
	presenter: SmithPagePresenter, journal: CampJournal, drawer: CampRaidDrawer,
	failures: Array[String]
) -> void:
	_expect(journal.header_title.text == "The Smith's Forge", "Smith header copy was not updated.", failures)
	var header_action := journal.find_child("CampJournalHeaderAction", true, false) as Button
	_expect(
		header_action != null and header_action.text == "Close  [Esc]",
		"Smith weapon-type gate did not retain the journal Close action.", failures
	)
	var intro := journal.find_child("SmithIntro", true, false) as Label
	_expect(
		intro != null
		and intro.text == "Shape the spoils of fallen foes into weapons for your raiders.",
		"Smith intro copy was not updated.", failures
	)
	var header_separator := journal.find_child("CampJournalHeaderSeparator", true, false) as HSeparator
	_expect(
		intro != null
		and header_separator != null
		and intro.get_parent() == header_separator.get_parent()
		and intro.get_index() < header_separator.get_index(),
		"Smith intro was not moved above the Journal header divider.", failures
	)
	var model := presenter.build_view_model()
	var categories: Array = model.get("categories", [])
	_expect(categories.size() == 8, "Smith category gate did not expose all eight weapon families.", failures)
	_expect(presenter.selected_family_id.is_empty(), "Fresh Smith did not start at the category gate.", failures)
	_expect(Array(model.get("recipes", [])).is_empty(), "Category gate exposed Forge recipes before selection.", failures)
	_expect(Array(model.get("weapons", [])).is_empty(), "Category gate exposed Armory entries before selection.", failures)
	var grid := journal.find_child("SmithCategoryGrid", true, false) as GridContainer
	_expect(grid != null and grid.columns == 2, "Smith weapon types were not rendered as a two-column grid.", failures)
	for category_value in categories:
		var category: Dictionary = category_value
		var family_id := String(category.get("family_id", ""))
		var button := journal.find_child("SmithCategory_" + family_id, true, false) as Button
		_expect(button != null, "Smith category button was missing for %s." % family_id, failures)
		if button != null:
			_expect(button.disabled == bool(category.get("disabled", true)), "Smith category lock state was not reflected in the button.", failures)
	_expect(journal.find_child("SmithTabs", true, false) == null, "Smith rendered Forge/Armory tabs before a category was selected.", failures)
	_expect(journal.find_child("SmithBackToWeaponTypes", true, false) == null, "Smith retained the removed inline back button.", failures)
	_expect(drawer.get_smith_family_filter().is_empty(), "Fresh Smith set a drawer family filter before category selection.", failures)
	for frame in _frames(drawer):
		var raid_frame: CampRaidFrame = frame
		_expect(not raid_frame.smith_drop_target_enabled, "Category gate left a raid frame as an equipment target.", failures)


func _validate_categories_after_unlock(
	presenter: SmithPagePresenter, journal: CampJournal, failures: Array[String]
) -> void:
	var categories: Array = presenter.build_view_model().get("categories", [])
	var unlocked_count := 0
	for category_value in categories:
		var category: Dictionary = category_value
		var button := journal.find_child(
			"SmithCategory_" + String(category.get("family_id", "")), true, false
		) as Button
		if bool(category.get("unlocked", false)):
			unlocked_count += 1
		_expect(button != null, "Unlocked Smith category button disappeared after reward refresh.", failures)
		if button != null:
			_expect(button.disabled == not bool(category.get("unlocked", false)), "Locked Smith category was not disabled.", failures)
	_expect(unlocked_count >= 2, "Smith fixture did not unlock multiple weapon families.", failures)


func _validate_forge(
	presenter: SmithPagePresenter, journal: CampJournal, drawer: CampRaidDrawer,
	failures: Array[String]
) -> void:
	var model := presenter.build_view_model()
	var header_action := journal.find_child("CampJournalHeaderAction", true, false) as Button
	_expect(
		header_action != null and header_action.text == "Back to Weapon Types",
		"Smith selected-family page did not move the back action into the journal header.", failures
	)
	_expect(journal.find_child("SmithBackToWeaponTypes", true, false) == null, "Smith selected-family page retained the inline back button.", failures)
	_expect(model.get("selected_tab") == "forge", "Selecting a weapon type did not open the Forge tab.", failures)
	_expect(model.get("selected_family_id") == presenter.selected_family_id, "Forge model lost the selected family.", failures)
	var recipes: Array = model.get("recipes", [])
	_expect(not recipes.is_empty(), "Selected unlocked weapon type did not expose Forge designs.", failures)
	_expect(journal.find_child("SmithRecipeList", true, false) != null, "Forge tab did not render its recipe list.", failures)
	var recipe_list_scroll := journal.find_child("SmithRecipeListScroll", true, false) as ScrollContainer
	_expect(
		recipe_list_scroll != null
		and recipe_list_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and recipe_list_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"Forge recipe list did not provide a vertical overflow scroll area.", failures
	)
	_expect(journal.find_child("SmithArmorySection", true, false) == null, "Forge tab retained Armory cards outside the Armory tab.", failures)
	_expect(journal.find_child("SmithReturnToArmory", true, false) == null, "Forge tab retained Return to Armory outside the Armory tab.", failures)
	_expect(drawer.get_smith_family_filter() == presenter.selected_family_id, "Forge selection did not reach the raid drawer.", failures)
	for recipe_value in recipes:
		var recipe: Dictionary = recipe_value
		_expect(
			String(recipe.get("family_id", "")) == presenter.selected_family_id,
			"Forge content was not filtered to the selected family.", failures
		)
		_expect(
			not String(recipe.get("trait_text", "")).is_empty()
			and not bool(Dictionary(recipe.get("trait", {})).get("active", true)),
			"Forge recipe did not retain its inactive trait placeholder.", failures
		)
	var selected: Dictionary = model.get("selected_recipe", {})
	_expect(not selected.is_empty(), "Forge did not select a recipe.", failures)
	var stats := journal.find_child("SmithWeaponStats", true, false) as Control
	_expect(stats != null, "Forge recipe details omitted separate stat rows.", failures)
	for stat_name in ["Power", "Speed", "Range"]:
		_expect(
			journal.find_child("SmithStatLabel_" + stat_name, true, false) != null
			and journal.find_child("SmithStatValue_" + stat_name, true, false) != null,
			"Forge stat row omitted its separate %s label/value." % stat_name, failures
		)
	var weapon_art := journal.find_child("SmithWeaponArtwork", true, false) as TextureRect
	var selected_weapon_icon := selected.get("icon_resource") as Texture2D
	_expect(
		weapon_art != null
		and weapon_art.texture == selected_weapon_icon,
		"Forge recipe details did not use the selected weapon icon for its artwork.", failures
	)
	var info_label := journal.find_child("SmithRecipeInfo", true, false) as Label
	var source_label := journal.find_child("SmithRecipeSource", true, false) as Label
	_expect(
		info_label != null
		and source_label != null
		and info_label.get_theme_color("font_color") == Color("c9b37b")
		and source_label.get_theme_color("font_color") == Color("b8bdba"),
		"Forge info/source emphasis did not accent the description over the source line.", failures
	)
	var detail_text := _visible_text(journal.find_child("SmithRecipeDetails", true, false))
	_expect(
		not detail_text.to_upper().contains("FAMILY/CATEGORY"),
		"Forge source line still exposed Family/category copy.", failures
	)
	_expect(
		not detail_text.to_upper().contains("COMPONENTS"),
		"Forge recipe details retained the removed Components heading.", failures
	)
	var component_slots := journal.find_child("SmithComponentSlots", true, false) as HFlowContainer
	_expect(component_slots != null, "Forge recipe details did not render component slots.", failures)
	_expect(
		is_zero_approx(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))),
		"Smith component tooltips retained a mouseover delay.", failures
	)
	_expect(
		component_slots != null and component_slots.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Smith component-slot container did not ignore mouse input for its child slots.", failures
	)
	var footer := journal.find_child("SmithForgeFooter", true, false) as VBoxContainer
	var spacer := journal.find_child("SmithForgeFooterSpacer", true, false) as Control
	var item_section := journal.find_child("SmithItemSection", true, false) as Control
	var detail_section := journal.find_child("SmithDetailSection", true, false) as Control
	_expect(
		footer != null
		and spacer == null
		and item_section != null
		and detail_section != null
		and component_slots != null
		and footer.get_parent() == detail_section
		and component_slots.get_parent() == footer
		and footer.alignment == BoxContainer.ALIGNMENT_CENTER,
		"Forge controls were not ordered inside the right detail footer without the old spacer.", failures
	)
	var craft_button := journal.find_child("SmithCraftButton", true, false) as Button
	_expect(
		footer != null
		and craft_button != null
		and craft_button.get_parent() == footer
		and craft_button.text == "Forge",
		"Forge button was not moved into the Smith footer.", failures
	)
	var shell := journal.find_child("CampJournalRightHalfShell", true, false) as Control
	var forge_layout := journal.find_child("SmithForgeLayout", true, false) as Control
	var artwork_frame := journal.find_child("SmithWeaponArtFrame", true, false) as Control
	_expect(
		shell != null
		and footer != null
		and footer.get_global_rect().get_center().x > shell.get_global_rect().get_center().x,
		"Forge footer was centered across the full Journal width instead of the right content column.",
		failures
	)
	_expect(
		item_section != null
		and detail_section != null
		and item_section.get_parent() == forge_layout
		and detail_section.get_parent() == forge_layout
		and detail_section.get_global_rect().position.x > item_section.get_global_rect().position.x,
		"Forge did not retain a left item column and right detail column.",
		failures
	)
	_expect(
		artwork_frame != null
		and detail_section != null
		and artwork_frame.get_global_rect().position.y <= detail_section.get_global_rect().position.y + 2.0,
		"Smith artwork did not begin at the top of the right detail column.",
		failures
	)
	_expect(
		forge_layout != null
		and footer != null
		and footer.get_global_rect().end.y >= forge_layout.get_global_rect().end.y - 2.0,
		"Forge components and button were not anchored to the bottom of the Forge section.",
		failures
	)
	var shortage_seen := false
	for component_value in selected.get("components", []):
		var component: Dictionary = component_value
		var material_id := String(component.get("material_id", ""))
		var slot := journal.find_child("SmithComponent_" + material_id, true, false) as PanelContainer
		_expect(slot != null, "Forge component slot was missing for %s." % material_id, failures)
		if slot == null:
			continue
		_expect(
			slot.mouse_filter == Control.MOUSE_FILTER_STOP,
			"Smith component slot was not explicitly hoverable for %s." % material_id,
			failures
		)
		var expected_icon := component.get("icon_resource") as Texture2D
		var icon := slot.find_child("SmithComponentIcon", true, false) as TextureRect
		var placeholder := slot.find_child("SmithComponentIconPlaceholder", true, false) as Label
		_expect(
			(expected_icon != null and icon != null and icon.texture == expected_icon)
			or (expected_icon == null and placeholder != null),
			"Forge component slot did not render its icon or safe placeholder for %s." % material_id,
			failures
		)
		var count := slot.find_child("SmithComponentCount", true, false) as Label
		_expect(
			count != null
			and count.text == "%d/%d" % [int(component.get("owned", 0)), int(component.get("required", 0))],
			"Forge component slot count was not rendered as owned/required for %s." % material_id,
			failures
		)
		var tooltip_lines := slot.tooltip_text.split("\n")
		var expected_name := String(component.get("display_name", material_id))
		var expected_count := "Count: %d/%d" % [
			int(component.get("owned", 0)), int(component.get("required", 0))
		]
		var expected_description := String(
			component.get("description", "Material definition unavailable.")
		)
		_expect(
			tooltip_lines.size() >= 4
			and tooltip_lines[0] == expected_name
			and tooltip_lines[1] == expected_count
			and tooltip_lines[2] == expected_description
			and tooltip_lines[3].begins_with("Source: "),
			"Forge component tooltip did not use name/count/description/source order for %s."
			% material_id,
			failures
		)
		_expect(
			slot.tooltip_text.contains(expected_count)
			and slot.tooltip_text.contains("Source:")
			and not slot.tooltip_text.contains(String(component.get("rarity_text", ""))),
			"Forge component tooltip exposed incomplete or visible rarity copy for %s." % material_id,
			failures
		)
		if int(component.get("missing", 0)) > 0:
			shortage_seen = true
			_expect(
				count != null and count.get_theme_color("font_color") == Color("e19a91"),
				"Insufficient Forge component count was not red for %s." % material_id,
				failures
			)
	_expect(shortage_seen, "Smith fixture did not expose an insufficient component for red-count validation.", failures)
	var fallback_slots := HFlowContainer.new()
	presenter._add_component_slot(fallback_slots, {
		"material_id": "missing_material",
		"display_name": "Missing Material",
		"description": "Definition unavailable.",
		"rarity_text": "Missing",
		"rarity_color": Color("d16d6d"),
		"icon_resource": null,
		"owned": 0,
		"required": 1,
		"missing": 1,
		"tooltip_text": "Missing Material\nMissing\nDefinition unavailable.\nCount: 0/1",
	})
	var fallback_slot := fallback_slots.get_child(0) as PanelContainer
	_expect(
		fallback_slot != null
		and fallback_slot.find_child("SmithComponentIconPlaceholder", true, false) != null
		and fallback_slot.tooltip_text.contains("Missing Material"),
		"Missing material/icon did not produce a safe placeholder slot and tooltip.", failures
	)

	var recipe_id := String(selected.get("recipe_id", ""))
	var weapon_id := String(selected.get("weapon_id", ""))
	_grant_recipe_cost(selected)
	await _wait_frames(2)
	var confirmation := presenter.request_craft_confirmation(recipe_id)
	_expect(confirmation.get("status") == "confirmation_required", "Craftable weapon did not require confirmation.", failures)
	_expect(
		not String(confirmation.get("message", "")).to_lower().contains("another"),
		"Forge confirmation retained the removed 'another' action copy.", failures
	)
	_expect(journal.find_child("SmithCraftConfirmation", true, false) != null, "Forge confirmation dialog was not retained.", failures)
	presenter.cancel_pending_craft()
	var crafted := presenter.confirm_pending_craft()
	_expect(crafted.get("status") == "no_pending_confirmation", "Canceling craft did not clear pending confirmation.", failures)
	presenter.request_craft_confirmation(recipe_id)
	crafted = presenter.confirm_pending_craft()
	_expect(crafted.get("status") == "crafted", "Confirmed Smith craft did not call the atomic backend.", failures)
	_expect(presenter.action_message.is_empty(), "Successful craft rendered a removed Smith post-craft action message.", failures)
	await _wait_frames(3)
	var crafted_entry := _entry_by_id(presenter.build_view_model().get("recipes", []), "weapon_id", weapon_id)
	_expect(int(crafted_entry.get("crafted_count", 0)) == 1, "Crafted count backend data was not retained.", failures)
	_expect(
		_not_visible_copy_text(journal),
		"Smith Forge displayed removed CRAFTED ×N copy text.", failures
	)


func _validate_armory_and_equipment(
	presenter: SmithPagePresenter, journal: CampJournal, drawer: CampRaidDrawer,
	failures: Array[String]
) -> void:
	_expect(presenter.select_tab("armory"), "Armory tab could not be selected.", failures)
	await _wait_frames(3)
	_expect(presenter.selected_tab == "armory", "Armory tab selection did not update presenter state.", failures)
	var armory := journal.find_child("SmithArmorySection", true, false) as Control
	var return_zone := journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
	_expect(armory != null, "Armory tab did not render crafted weapon cards.", failures)
	_expect(return_zone != null, "Armory tab did not render Return to Armory.", failures)
	_expect(journal.find_child("SmithRecipeList", true, false) == null, "Armory tab retained Forge recipe content.", failures)
	if return_zone == null:
		return
	var model := presenter.build_view_model()
	var weapons: Array = model.get("weapons", [])
	_expect(not weapons.is_empty(), "Selected family Armory model was empty after crafting.", failures)
	if weapons.is_empty():
		return
	var weapon: Dictionary = weapons[0]
	var weapon_id := String(weapon.get("weapon_id", ""))
	var card := journal.find_child("SmithWeapon_" + weapon_id, true, false) as SmithDragSource
	_expect(card != null, "Armory weapon card was not rendered.", failures)
	if card == null:
		return
	var assignment := card.find_child("SmithWeaponAssignment", true, false) as Label
	_expect(assignment != null and assignment.text == "EQUIPPED 0/1", "Armory card did not display EQUIPPED 0/1.", failures)
	var compatible: CampRaidFrame = null
	var incompatible: CampRaidFrame = null
	for frame_value in _frames(drawer):
		var frame: CampRaidFrame = frame_value
		if frame.family_compatible and compatible == null:
			compatible = frame
		elif not frame.family_compatible and incompatible == null:
			incompatible = frame
	_expect(compatible != null, "Smith fixture had no compatible raid-frame target.", failures)
	_expect(incompatible != null, "Smith fixture had no incompatible raid-frame target.", failures)
	var payload := card.drag_payload
	if compatible != null:
		_expect(compatible._can_drop_data(Vector2(90, 22), payload), "Compatible Smith raid frame rejected the selected-family weapon.", failures)
	if incompatible != null:
		_expect(not incompatible._can_drop_data(Vector2(90, 22), payload), "Incompatible Smith raid frame accepted a selected-family weapon.", failures)
		_expect(not incompatible.get_drag_payload(Vector2(190, 22)).is_empty() or String(incompatible.member.get("equipped_weapon_id", "")).is_empty(), "Incompatible frame lost its equipped-weapon drag source.", failures)
	if compatible == null:
		return
	var compatible_id := compatible.member_id
	compatible._drop_data(Vector2(90, 22), payload)
	await _wait_frames(3)
	_expect(CampaignState.get_weapon_holder_id(weapon_id) == compatible_id, "Compatible Smith frame did not equip the armory weapon.", failures)
	model = presenter.build_view_model()
	weapon = _entry_by_id(model.get("weapons", []), "weapon_id", weapon_id)
	assignment = journal.find_child("SmithWeaponAssignment", true, false) as Label
	_expect(String(weapon.get("assignment_label", "")) == "EQUIPPED 1/1", "Armory model did not update its equipped count.", failures)
	_expect(assignment != null and assignment.text == "EQUIPPED 1/1", "Armory card did not update its equipped count.", failures)
	var equipped_frame := drawer.find_child("CampRaidFrame_" + compatible_id, true, false) as CampRaidFrame
	if equipped_frame != null:
		var equipped_payload := equipped_frame.get_drag_payload(Vector2(190, 22))
		_expect(not equipped_payload.is_empty(), "Equipped weapon could not be dragged from its Smith frame.", failures)
		if not equipped_payload.is_empty():
			var refreshed_return_zone := journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
			_expect(refreshed_return_zone != null, "Return to Armory disappeared during equipment refresh.", failures)
			if refreshed_return_zone != null:
				refreshed_return_zone._drop_data(Vector2(30, 30), equipped_payload)
			await _wait_frames(3)
			_expect(CampaignState.get_weapon_holder_id(weapon_id).is_empty(), "Return to Armory did not unequip the weapon.", failures)
			_expect(journal.find_child("SmithActionStatus", true, false) != null, "Equipment-drag feedback disappeared from Smith.", failures)


func _validate_reserve_and_missing_recovery(
	presenter: SmithPagePresenter, journal: CampJournal, drawer: CampRaidDrawer,
	failures: Array[String]
) -> void:
	var model := presenter.build_view_model()
	var weapons: Array = model.get("weapons", [])
	if weapons.is_empty():
		failures.append("Reserve recovery fixture had no selected-family weapon.")
		return
	var weapon: Dictionary = weapons[0]
	var weapon_id := String(weapon.get("weapon_id", ""))
	var source_id := ""
	for frame_value in _frames(drawer):
		var frame: CampRaidFrame = frame_value
		if frame.family_compatible and bool(CampaignState.check_equip_weapon(frame.member_id, weapon_id).get("ok", false)):
			source_id = frame.member_id
			break
	if source_id.is_empty() or not CampaignState.equip_weapon(source_id, weapon_id).get("ok", false):
		failures.append("Reserve recovery fixture could not assign a selected-family weapon.")
		return
	if not CampaignState.remove_active_member(source_id):
		failures.append("Reserve recovery fixture could not move its holder to reserve.")
		return
	await _wait_frames(3)
	var reserve_model := presenter.build_view_model()
	var reserve_entry := _entry_by_id(reserve_model.get("weapons", []), "weapon_id", weapon_id)
	var reserve_card := journal.find_child("SmithReserve_%s_%s" % [weapon_id, source_id], true, false) as SmithDragSource
	_expect(
		reserve_card != null
		and reserve_card.drag_enabled
		and Array(reserve_entry.get("reserve_holder_ids", [])).has(source_id),
		"Reserve-held weapon did not remain an individual Armory recovery entry.", failures
	)
	if reserve_card != null:
		var reclaim_target: CampRaidFrame = null
		for frame_value in _frames(drawer):
			var frame: CampRaidFrame = frame_value
			if frame.family_compatible and bool(CampaignState.check_reclaim_reserve_weapon(source_id, frame.member_id).get("ok", false)):
				reclaim_target = frame
				break
		if reclaim_target != null:
			var reclaim_target_id := reclaim_target.member_id
			_expect(
				reclaim_target._can_drop_data(Vector2(90, 22), reserve_card.drag_payload),
				"Compatible active frame rejected reserve recovery.", failures
			)
			reclaim_target._drop_data(Vector2(90, 22), reserve_card.drag_payload)
			await _wait_frames(3)
			_expect(
				CampaignState.get_weapon_holder_id(weapon_id) == reclaim_target_id,
				"Reserve recovery did not equip the active target.", failures
			)
	else:
		return

	var states: Dictionary = CampaignState.get_campaign_snapshot().get("raider_states", {})
	if not states.has(source_id):
		failures.append("Missing-content fixture could not find the reserve holder.")
		return
	states[source_id]["equipped_weapon_id"] = "returning_content_weapon"
	if not CampaignState.debug_replace_raider_states(states):
		failures.append("Missing-content fixture could not install an unknown saved weapon.")
		return
	await _wait_frames(3)
	var missing_model := presenter.build_view_model()
	var missing := _entry_by_id(
		missing_model.get("weapons", []), "weapon_id", "returning_content_weapon"
	)
	var missing_card := journal.find_child(
		"SmithReserve_returning_content_weapon_%s" % source_id, true, false
	) as SmithDragSource
	var return_zone := journal.find_child("SmithReturnToArmory", true, false) as SmithArmoryDropZone
	_expect(
		bool(missing.get("missing_content", false))
		and Array(missing.get("reserve_holder_ids", [])).has(source_id)
		and missing_card != null
		and return_zone != null,
		"Missing-content recovery was not accessible from the filtered Armory tab.", failures
	)
	if missing_card != null and return_zone != null:
		return_zone._drop_data(Vector2(30, 30), missing_card.drag_payload)
		await _wait_frames(3)
		_expect(
			String(CampaignState.get_member(source_id).get("equipped_weapon_id", "")).is_empty(),
			"Missing-content recovery did not clear the saved reserve slot.", failures
		)


func _frames(drawer: CampRaidDrawer) -> Array:
	var result: Array = []
	for child in drawer.stack.get_children():
		if child is CampRaidFrame:
			result.append(child)
	return result


func _not_visible_copy_text(journal: CampJournal) -> bool:
	return not _visible_text(journal).to_upper().contains("CRAFTED ×")


func _visible_text(node: Node) -> String:
	var result := ""
	if node is Label:
		result += String((node as Label).text) + "\n"
	elif node is Button:
		result += String((node as Button).text) + "\n"
	for child in node.get_children():
		result += _visible_text(child)
	return result


func _grant_recipe_cost(recipe: Dictionary) -> void:
	var grants: Dictionary = {}
	for component_value in recipe.get("components", []):
		var component: Dictionary = component_value
		grants[String(component.get("material_id", ""))] = int(component.get("required", 0))
	CampaignState.debug_grant_progression_materials(grants)


func _entry_by_id(entries: Array, field_name: String, stable_id: String) -> Dictionary:
	for entry_value in entries:
		if entry_value is Dictionary and String(entry_value.get(field_name, "")) == stable_id:
			return Dictionary(entry_value)
	return {}


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(camp: Node, failures: Array[String]) -> void:
	if camp != null and is_instance_valid(camp):
		camp.queue_free()
	CampaignState.reset_campaign(false, 616161)
	if failures.is_empty():
		print("RAID_TEST_PASS:smith_contract | Smith category-first Forge and equipment contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
