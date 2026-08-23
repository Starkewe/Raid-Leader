extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")
const TrainingCatalog := preload("res://scripts/data/training_progression_catalog.gd")
const RaiderState := preload("res://scripts/data/campaign_raider_state.gd")
const SAVE_PATH := "user://training_progression_contract.json"

var failures: Array[String] = []
var attempt_sequence := 0


func _ready() -> void:
	_validate_catalog_and_migration()
	CampaignState.reset_campaign(false, 818181)
	var reward := CampaignState.debug_process_seeded_reward(
		"ogre", "training_progression_first_clear"
	)
	_expect(bool(reward.get("ok", false)), "Training fixture could not grant a Warrior token.")
	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(3)
	var facility := camp.call("get_facility", "training") as CampFacility
	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	var drawer := camp.get_node_or_null("CampHUD/CampRaidDrawer") as CampRaidDrawer
	var presenter := (
		journal.page_presenters.get("training") as TrainingPagePresenter
		if journal != null else null
	)
	_validate_reachability(camp, facility)
	_expect(journal != null, "Camp Journal was unavailable.")
	_expect(drawer != null, "Camp raid drawer was unavailable.")
	_expect(presenter != null, "Training presenter was unavailable.")
	if journal == null or drawer == null or presenter == null:
		_finish(camp)
		return

	journal.open_facility("training")
	await _wait_frames(3)
	_validate_initial_ui(journal, drawer, presenter)
	await _validate_benefits_animation(journal, presenter)
	var warrior_id := _first_active_member_of_class("Warrior")
	_expect(not warrior_id.is_empty(), "Training fixture lacks an active Warrior.")
	if warrior_id.is_empty():
		_finish(camp)
		return
	presenter.preview_lineage_by_raider[warrior_id] = "sunder_clerk"
	_expect(presenter.select_raider(warrior_id), "Training could not select its Warrior.")
	await _wait_frames(2)
	_validate_first_lock(presenter, warrior_id)
	await _wait_frames(2)
	_validate_entry_progression(warrior_id)
	_validate_tier_one(warrior_id)
	_validate_switching_and_partial_reset(presenter, warrior_id)
	_validate_weapon_return(presenter, warrior_id)
	_validate_capstone_and_victory_banking(warrior_id)
	_validate_projection_and_persistence(warrior_id)
	await _validate_drawer_detachment(journal, drawer, presenter, warrior_id)
	await _validate_reserve_tab(presenter)
	_finish(camp)


func _validate_catalog_and_migration() -> void:
	_expect(TrainingCatalog.validate_catalog().is_empty(), "Training progression catalog is invalid.")
	_expect(RaiderClassCatalog.get_all_lineage_ids().size() == 16, "Training does not define 16 lineages.")
	for lineage_id in RaiderClassCatalog.get_all_lineage_ids():
		_expect(
			Array(TrainingCatalog.get_definition(lineage_id).get("nodes", [])).size() == 11,
			"%s does not have entry + 3x3 + capstone nodes." % lineage_id
		)
	var legacy := RaiderState.sanitize(
		{
			"raider_id": "legacy",
			"recruited": true,
			"current_class": "Warrior",
			"specialization_unlocked": true,
			"secondary_lineage_id": "sunder_clerk",
			"advanced_class_id": "sunder_clerk",
		},
		"legacy",
		"Warrior"
	)
	_expect(
		legacy.get("advanced_class_completed_id") == "sunder_clerk",
		"Legacy one-click advanced classes were not migrated as completed."
	)
	_expect(
		Array(legacy.get("lineage_progress_by_id", {}).get("sunder_clerk", {}).get("completed_node_ids", [])).size() == 11,
		"Legacy migration did not preserve all class milestones."
	)


func _validate_reachability(camp: Node, facility: CampFacility) -> void:
	if facility == null:
		failures.append("Training facility is missing from camp.")
		return
	_expect(facility.interactive and facility.interaction_radius > 0.0, "Training is not interactable.")
	var approach_id := String(camp.call("get_camp_route_approach_node_id", "training"))
	_expect(approach_id == "training_approach", "Training has no authored approach node.")


func _validate_initial_ui(
	journal: CampJournal, drawer: CampRaidDrawer, presenter: TrainingPagePresenter
) -> void:
	_expect(journal.current_facility_id == "training", "Training Journal page did not open.")
	_expect(journal.header_title.text == "Training and Recreation", "Training title is incorrect.")
	_expect(not journal.header_intro.visible, "Training retained the removed introductory paragraph.")
	_expect(journal.find_child("TrainingActiveTab", true, false) != null, "Active tab is missing.")
	_expect(journal.find_child("TrainingReserveTab", true, false) != null, "Reserve tab is missing.")
	var tree := journal.find_child("TrainingProgressionTree", true, false) as Control
	_expect(tree != null, "Training progression tree is missing.")
	_expect(journal.find_child("TrainingPreviousLineage", true, false) != null, "Previous-lineage arrow is missing.")
	_expect(journal.find_child("TrainingNextLineage", true, false) != null, "Next-lineage arrow is missing.")
	_expect(journal.find_child("TrainingLockLineage", true, false) != null, "Bottom lineage lock button is missing.")
	var lock_label := String((journal.find_child("TrainingLockLineage", true, false) as Button).text)
	_expect(
		["Begin Lineage", "Current Lineage", "Change Lineage"].has(lock_label),
		"Lineage action button contains text outside the approved three labels."
	)
	_expect(journal.find_child("TrainingTreeTokenGate", true, false) == null, "Old token gate still renders.")
	_expect(journal.find_child("TrainingLineageGrid", true, false) == null, "Old lineage box grid still renders.")
	if tree != null:
		_expect(int(tree.get_meta("branch_count", 0)) == 4, "Carousel does not expose four lineage paths.")
		_expect(int(tree.get_meta("node_count", 0)) == 11, "Talent tree does not render 11 nodes.")
		_expect(bool(tree.get_meta("uses_full_resolution_icon", false)), "Tree still uses the compact class icon.")
		_expect(not bool(tree.get_meta("has_connectors", true)), "Tree retained connector lines.")
		_expect(not bool(tree.get_meta("talent_labels_visible", true)), "Tree retained numeric talent labels.")
		_expect(bool(tree.get_meta("inactive_nodes_quiet", false)), "Inactive nodes are still highlighted.")
		_expect(bool(tree.get_meta("row_completion_glow_secondary", false)), "Completed rows lack secondary glow support.")
		_expect(bool(tree.get_meta("node_effects_contained", false)), "Node effects are not contained inside their slots.")
		_expect(bool(tree.get_meta("navigation_uses_class_colors", false)), "Lineage arrows are not class-colored.")
	var identity_header := journal.find_child("TrainingIdentityHeader", true, false) as Control
	var raider_identity := journal.find_child("TrainingRaiderIdentity", true, false) as Control
	var class_identity := journal.find_child("TrainingClassIdentity", true, false) as Control
	var icon_frame := journal.find_child("TrainingClassIconFrame", true, false) as Control
	if identity_header != null and raider_identity != null and class_identity != null:
		_expect(
			is_equal_approx(raider_identity.anchor_left, 0.0)
			and is_equal_approx(raider_identity.anchor_right, 0.0)
			and is_equal_approx(class_identity.anchor_left, 1.0)
			and is_equal_approx(class_identity.anchor_right, 1.0),
			"Training identity labels are not anchored to the top corners."
		)
	if icon_frame != null:
		_expect(icon_frame.position.y > 0.0, "Training class icon is still flush with the header top.")
	var bonuses := journal.find_child("TrainingBonusesPanel", true, false) as Control
	var bonuses_scroll := journal.find_child("TrainingBonusesScroll", true, false) as ScrollContainer
	_expect(bonuses != null and bonuses_scroll != null, "Scrollable class bonuses panel is missing.")
	_expect(journal.find_child("TrainingBonusesHeading", true, false) == null, "Benefits panel retained a header.")
	_expect(
		journal.find_child("TrainingCurrentBenefitsButton", true, false) != null
		and journal.find_child("TrainingActiveBenefitsHeading", true, false) != null
		and journal.find_child("TrainingPassiveBenefitsHeading", true, false) != null,
		"Current Benefits control or Active/Passive content sections are missing."
	)
	var benefits_button := journal.find_child("TrainingCurrentBenefitsButton", true, false) as Button
	var benefits_content_panel := journal.find_child("TrainingBenefitsContentPanel", true, false) as Control
	if bonuses != null and benefits_button != null and benefits_content_panel != null:
		_expect(
			benefits_button.get_parent().get_parent() == bonuses
			and benefits_content_panel.get_parent() == bonuses,
			"Current Benefits button is not fixed outside the sliding content panel."
		)
	var benefits_content := journal.find_child("TrainingBenefitsContent", true, false) as VBoxContainer
	var benefits_text := ""
	if benefits_content != null:
		for child in benefits_content.get_children():
			if child is Label:
				benefits_text += (child as Label).text + "\n"
	_expect(not benefits_text.contains("Role:"), "Passive benefits still include the raid role.")
	_expect(
			not benefits_text.contains("No talent rewards earned on this path yet"),
			"Passive benefits still include the empty reward placeholder."
	)
	if bonuses != null:
		_expect(not bool(bonuses.get_meta("expanded", true)), "Benefits panel did not default closed.")
	if tree != null and bonuses != null:
		_expect(bonuses.get_index() > tree.get_index(), "Class bonuses are not below the lineage lock/tree.")
	_expect(
		journal.find_child("TrainingClassIcon", true, false) != null
		and journal.find_child("TrainingSelectedClass", true, false) != null
		and journal.find_child("TrainingRoleLabel", true, false) != null
		and journal.find_child("TrainingRaiderPrimaryClass", true, false) != null,
		"Training identity header is missing its icon, class, role, or primary-class labels."
	)
	var previous_arrow := journal.find_child("TrainingPreviousLineage", true, false) as Control
	var next_arrow := journal.find_child("TrainingNextLineage", true, false) as Control
	var lock_button := journal.find_child("TrainingLockLineage", true, false) as Control
	if previous_arrow != null and next_arrow != null and lock_button != null:
		_expect(
			is_equal_approx(previous_arrow.position.y, lock_button.position.y)
			and is_equal_approx(next_arrow.position.y, lock_button.position.y),
			"Lineage arrows are not aligned with the Begin Lineage action."
		)
	_expect(journal.find_child("TrainingBenefitPreview", true, false) == null, "Removed top benefit preview still renders.")
	_expect(
		not drawer.is_locked_open() and drawer.get_menu_context().is_empty(),
		"Training still owns or locks the camp raid drawer."
	)
	_expect(
		drawer.find_child("TrainingBenefitsPopout", true, false) == null,
		"Removed raid-frame Training benefits popout still exists."
	)
	for label_value in journal.find_children("*", "Label", true, false):
		var label := label_value as Label
		if label != null:
			_expect(not label.text.contains("Preview lineages"), "Roster retained Preview lineages text.")
	var model := presenter.build_view_model()
	_expect(model.get("tab_id") == "active", "Training did not open active-first.")
	var selected_id := String(model.get("selected_raider_id", ""))
	var selected_status := CampaignState.get_raider_specialization_status(selected_id)
	var active_lineage_id := String(selected_status.get("secondary_lineage_id", ""))
	var preview_lineage_id := String(model.get("preview_lineage_id", ""))
	if not active_lineage_id.is_empty():
		_expect(
			preview_lineage_id == active_lineage_id,
			"Training did not default the preview to the raider's active lineage."
		)
	else:
		var eligible_preview_ids: Array[String] = []
		for lineage_value in selected_status.get("eligible_lineages", []):
			eligible_preview_ids.append(String(Dictionary(lineage_value).get("lineage_id", "")))
		_expect(
			eligible_preview_ids.has(preview_lineage_id),
			"Training did not choose an eligible default lineage preview."
		)
	var class_label := journal.find_child("TrainingRaiderClass_" + selected_id, true, false) as Label
	_expect(class_label != null and not class_label.text.is_empty(), "Roster class name did not replace preview text.")


func _validate_benefits_animation(
	journal: CampJournal, presenter: TrainingPagePresenter
) -> void:
	var shell := journal.find_child("TrainingBonusesPanel", true, false) as Control
	var content_panel := journal.find_child("TrainingBenefitsContentPanel", true, false) as Control
	var benefits_scroll := journal.find_child("TrainingBonusesScroll", true, false) as ScrollContainer
	var button := journal.find_child("TrainingCurrentBenefitsButton", true, false) as Button
	if shell == null or content_panel == null or benefits_scroll == null or button == null:
		return
	var button_position := button.global_position
	var closed_style := button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		closed_style != null and closed_style.border_width_top > 0,
		"Current Benefits closed state lost its beveled top edge."
	)
	button.pressed.emit()
	await _wait_frames(2)
	_expect(bool(shell.get_meta("expanded", false)), "Current Benefits did not open its content panel.")
	_expect(benefits_scroll.visible, "Benefits content remained hidden while opening.")
	_expect(button.global_position == button_position, "Current Benefits button moved while opening.")
	_expect(content_panel.global_position.y < button.global_position.y, "Benefits content did not slide above the button.")
	var open_style := button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		open_style != null and open_style.border_width_top > 0,
		"Current Benefits lost its beveled edge at the start of opening."
	)
	_expect(presenter.cycle_lineage(1), "Training could not cycle while benefits were open.")
	await _wait_frames(3)
	var cycled_shell := journal.find_child("TrainingBonusesPanel", true, false) as Control
	var cycled_scroll := journal.find_child("TrainingBonusesScroll", true, false) as ScrollContainer
	var cycled_content := journal.find_child("TrainingBenefitsContentPanel", true, false) as Control
	var cycled_button := journal.find_child("TrainingCurrentBenefitsButton", true, false) as Button
	_expect(presenter.benefits_panel_expanded, "Cycling lineages closed the Current Benefits panel state.")
	if cycled_shell != null and cycled_scroll != null and cycled_content != null and cycled_button != null:
		_expect(bool(cycled_shell.get_meta("expanded", false)), "Cycled lineage rebuilt the benefits panel closed.")
		_expect(cycled_scroll.visible, "Cycled lineage hid the open benefits content.")
		_expect(cycled_content.position.y < 0.0, "Cycled lineage did not restore the open benefits slide.")
		var cycled_style := cycled_button.get_theme_stylebox("normal") as StyleBoxFlat
		_expect(
			cycled_style != null and cycled_style.border_width_top > 0,
			"Cycled lineage lost the beveled Current Benefits edge."
		)
		cycled_button.pressed.emit()
	else:
		_expect(false, "Cycled lineage lost the Current Benefits controls.")
	await get_tree().create_timer(0.5).timeout
	_expect(not presenter.benefits_panel_expanded, "Current Benefits did not close its content panel.")
	if cycled_shell != null and cycled_scroll != null:
		_expect(not bool(cycled_shell.get_meta("expanded", true)), "Current Benefits did not close its content panel.")
		_expect(not cycled_scroll.visible, "Benefits content remained visible after closing.")


func _validate_first_lock(presenter: TrainingPagePresenter, warrior_id: String) -> void:
	var before := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(not bool(before.get("lineage_token_spent", false)), "Fresh Warrior already spent a class token.")
	_expect(before.get("matching_token_id") == "earthgnasher_warrior_token", "Warrior token was not matched.")
	_expect(Array(before.get("eligible_lineages", [])).size() == 4, "Warrior cannot preview four lineages.")
	var request: Dictionary = presenter.request_lineage_lock("sunder_clerk")
	_expect(request.get("status") == "confirmation_required", "First lineage lock skipped confirmation.")
	var locked: Dictionary = presenter.confirm_pending_action()
	_expect(locked.get("status") == "lineage_locked", "Token did not begin Sunder Clerk.")
	_expect(not CampaignState.owns_advancement_token("earthgnasher_warrior_token"), "Spent token remained owned.")
	var state := CampaignState.get_raider_campaign_state(warrior_id)
	_expect(state.get("secondary_lineage_id") == "sunder_clerk", "Active lineage was not stored.")
	_expect(String(state.get("advanced_class_id", "")).is_empty(), "Lineage lock granted class identity early.")
	var member := CampaignState.get_member(warrior_id)
	_expect(member.get("class_roles") == ["dps"], "Sunder Clerk raid role did not apply immediately.")
	_expect(not Dictionary(member.get("lineage_stat_modifiers", {})).is_empty(), "Projected raider did not receive lineage stats.")
	_expect(not Dictionary(member.get("lineage_passive_effect", {})).is_empty(), "Projected raider did not receive the lineage passive.")
	var status := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(status.get("stage") == "lineage", "First lock did not enter the lineage stage.")
	_expect(not Dictionary(status.get("preview_lineage", {})).get("stat_modifiers", {}).is_empty(), "Lineage has no immediate stat benefit.")


func _validate_entry_progression(warrior_id: String) -> void:
	_record_victory("ogre", warrior_id, {
		"successful_boss_taunt_swap": 30,
		"rear_boss_basic_attack": 100,
	})
	_record_victory("chainmaster", warrior_id, {})
	var before := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(_objective_current(before, "entry", "unique_bosses") == 2, "Entry did not count two unique bosses.")
	_expect(String(before.get("advanced_class_id", "")).is_empty(), "Class identity unlocked before all entry objectives.")
	_record_victory("twin_maulers", warrior_id, {})
	var after := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(_node_state(after, "entry") == "completed", "Entry node did not complete after its concurrent objectives.")
	_expect(after.get("advanced_class_id") == "sunder_clerk", "Entry did not grant the advanced class identity.")
	_expect(String(after.get("advanced_class_completed_id", "")).is_empty(), "Entry incorrectly completed the full class.")
	_expect(_node_state(after, "tier_1_left") == "available", "Tier 1 did not open after entry completion.")


func _validate_tier_one(warrior_id: String) -> void:
	_record_victory("ogre", warrior_id, {
		"sunder_clerk_tier_1_left": 1,
		"sunder_clerk_tier_1_center": 1,
		"sunder_clerk_tier_1_right": 1,
	})
	var status := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	for node_id in TrainingCatalog.TIER_NODE_IDS[0]:
		_expect(_node_state(status, node_id) == "completed", "Tier 1 node %s did not auto-award." % node_id)
	_expect(_node_state(status, "tier_2_left") == "available", "Tier 2 did not open as a group.")


func _validate_switching_and_partial_reset(
	presenter: TrainingPagePresenter, warrior_id: String
) -> void:
	presenter.preview_lineage_by_raider[warrior_id] = "hollow_anvil"
	var request: Dictionary = presenter.request_lineage_lock("hollow_anvil")
	_expect(request.get("status") == "confirmation_required", "Lineage switch skipped its loss warning.")
	var switched: Dictionary = presenter.confirm_pending_action()
	_expect(switched.get("status") == "lineage_changed", "Free lineage change failed.")
	_expect(String(switched.get("consumed_token_id", "")).is_empty(), "Lineage switch consumed another token.")
	_expect(CampaignState.get_member(warrior_id).get("class_roles") == ["tank"], "Incoming lineage role was not applied.")
	_record_victory("ogre", warrior_id, {})
	var hollow := CampaignState.get_raider_specialization_status(warrior_id, "hollow_anvil")
	_expect(_objective_current(hollow, "entry", "unique_bosses") == 1, "Hollow Anvil did not gain partial entry progress.")
	_switch_with_presenter(presenter, warrior_id, "sunder_clerk")
	var restored := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(restored.get("advanced_class_id") == "sunder_clerk", "Returning did not restore class identity.")
	_expect(_node_state(restored, "tier_1_left") == "completed", "Returning did not restore completed nodes.")
	_switch_with_presenter(presenter, warrior_id, "hollow_anvil")
	hollow = CampaignState.get_raider_specialization_status(warrior_id, "hollow_anvil")
	_expect(_objective_current(hollow, "entry", "unique_bosses") == 0, "Abandoned partial entry progress was not reset.")
	_switch_with_presenter(presenter, warrior_id, "sunder_clerk")


func _validate_weapon_return(presenter: TrainingPagePresenter, warrior_id: String) -> void:
	var grants := CampaignState.debug_grant_progression_materials({
		"earthgnasher_heartstone": 1,
		"quake_marrow": 2,
		"rage_slick_hide": 2,
	})
	_expect(bool(grants.get("ok", false)), "Weapon return fixture could not grant materials.")
	_expect(CampaignState.craft("craft_faultline_cudgel").get("status") == "crafted", "Weapon return fixture could not craft its cudgel.")
	_expect(CampaignState.equip_weapon(warrior_id, "faultline_cudgel").get("status") == "equipped", "Sunder Clerk could not equip the fixture weapon.")
	_switch_with_presenter(presenter, warrior_id, "gravelord_proxy")
	_record_victory("ogre", warrior_id, {
		"successful_boss_taunt_swap": 30,
		"shared_region_low_ally_direct_hit": 30,
	})
	_record_victory("chainmaster", warrior_id, {})
	_record_victory("twin_maulers", warrior_id, {})
	var state := CampaignState.get_raider_campaign_state(warrior_id)
	_expect(String(state.get("equipped_weapon_id", "")).is_empty(), "Incompatible weapon was not returned when identity unlocked.")
	_switch_with_presenter(presenter, warrior_id, "sunder_clerk")
	_expect(CampaignState.equip_weapon(warrior_id, "faultline_cudgel").get("status") == "equipped", "Restored Sunder Clerk could not re-equip its weapon.")
	var check := CampaignState.check_lock_raider_lineage(warrior_id, "gravelord_proxy")
	_expect(bool(check.get("weapon_return", {}).get("required", false)), "Switch warning omitted the incompatible weapon return.")
	presenter.preview_lineage_by_raider[warrior_id] = "gravelord_proxy"
	var request: Dictionary = presenter.request_lineage_lock("gravelord_proxy")
	_expect(String(presenter._confirmation_dialog.dialog_text).contains("returned to the Armory"), "Weapon-return popup did not explain the armory return.")
	_expect(request.get("status") == "confirmation_required", "Weapon-return switch skipped confirmation.")
	var changed: Dictionary = presenter.confirm_pending_action()
	_expect(changed.get("returned_weapon_id") == "faultline_cudgel", "Switch did not report the returned weapon.")
	_switch_with_presenter(presenter, warrior_id, "sunder_clerk")


func _validate_capstone_and_victory_banking(warrior_id: String) -> void:
	for tier_number in [2, 3]:
		var credits := {}
		for suffix in ["left", "center", "right"]:
			credits["sunder_clerk_tier_%d_%s" % [tier_number, suffix]] = 1
		_record_victory("ogre", warrior_id, credits)
	var before := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(_node_state(before, "capstone") == "available", "Capstone did not open after all three tiers.")
	_record_attempt("defeat", "ogre", warrior_id, {"sunder_clerk_capstone": 1})
	var after_wipe := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(_node_state(after_wipe, "capstone") == "available", "A defeat banked capstone quest credit.")
	_record_victory("ogre", warrior_id, {"sunder_clerk_capstone": 1})
	var complete := CampaignState.get_raider_specialization_status(warrior_id, "sunder_clerk")
	_expect(_node_state(complete, "capstone") == "completed", "Capstone did not auto-award on victory.")
	_expect(complete.get("advanced_class_completed_id") == "sunder_clerk", "Capstone did not complete the advanced class.")


func _validate_projection_and_persistence(warrior_id: String) -> void:
	var member := CampaignState.get_member(warrior_id)
	_expect(member.get("advanced_class_id") == "sunder_clerk", "Roster omitted class identity.")
	_expect(member.get("advanced_class_completed_id") == "sunder_clerk", "Roster omitted full-class completion.")
	_expect(member.get("role") == "dps", "Advanced lineage role was not projected.")
	if not CampaignState.write_campaign(SAVE_PATH, {"kind": "training_contract"}):
		failures.append("Training state could not be saved.")
		return
	if not CampaignState.load_campaign(SAVE_PATH):
		failures.append("Training state could not be reloaded.")
		return
	var reloaded := CampaignState.get_raider_campaign_state(warrior_id)
	_expect(reloaded.get("secondary_lineage_id") == "sunder_clerk", "Reload lost active lineage.")
	_expect(reloaded.get("advanced_class_completed_id") == "sunder_clerk", "Reload lost capstone completion.")


func _validate_drawer_detachment(
	journal: CampJournal, drawer: CampRaidDrawer,
	presenter: TrainingPagePresenter, warrior_id: String
) -> void:
	journal.open_facility("training")
	await _wait_frames(3)
	var frame := drawer.find_child("CampRaidFrame_" + warrior_id, true, false) as CampRaidFrame
	_expect(frame != null, "Active raider is missing from the ordinary camp raid drawer.")
	if frame == null:
		return
	_expect(frame.context.is_empty(), "Training still assigns a raid-frame context.")
	_expect(frame.custom_minimum_size == CampRaidFrame.BASE_SIZE, "Training still adds a raid-frame accessory slot.")
	_expect(not frame.has_signal("training_info_requested"), "Training information signal remains on raid frames.")
	_expect(not drawer.is_locked_open(), "Training still forces the camp raid drawer open.")
	_expect(drawer.find_child("TrainingBenefitsPopout", true, false) == null, "Training drawer popout remains.")
	_expect(presenter.selected_raider_id == warrior_id, "Opening Training lost its selected raider.")


func _validate_reserve_tab(presenter: TrainingPagePresenter) -> void:
	var future_ids := CampaignState.get_future_recruit_ids()
	_expect(not future_ids.is_empty(), "Training fixture lacks a future recruit.")
	if future_ids.is_empty():
		return
	var reserve_id := String(future_ids[0])
	_expect(CampaignState.recruit_raider(reserve_id, "training_contract"), "Reserve fixture could not be recruited.")
	_expect(presenter.select_tab("reserve"), "Training could not open the Reserve tab.")
	await _wait_frames(2)
	var model := presenter.build_view_model()
	var reserve_ids: Array[String] = []
	for entry_value in model.get("members", []):
		reserve_ids.append(String(Dictionary(entry_value).get("raider_id", "")))
	_expect(reserve_ids.has(reserve_id), "Recruited reserve raider was absent from Training.")
	var drawer := get_tree().get_first_node_in_group("camp_raid_drawer") as CampRaidDrawer
	_expect(drawer.find_child("CampRaidFrame_" + reserve_id, true, false) == null, "Reserve raider appeared in the active camp raid drawer.")


func _switch_with_presenter(
	presenter: TrainingPagePresenter, warrior_id: String, lineage_id: String
) -> void:
	presenter.preview_lineage_by_raider[warrior_id] = lineage_id
	var request: Dictionary = presenter.request_lineage_lock(lineage_id)
	_expect(request.get("status") == "confirmation_required", "Switch to %s skipped confirmation." % lineage_id)
	var result: Dictionary = presenter.confirm_pending_action()
	_expect(result.get("status") == "lineage_changed", "Switch to %s failed." % lineage_id)


func _record_victory(encounter_id: String, raider_id: String, credits: Dictionary) -> void:
	_record_attempt("victory", encounter_id, raider_id, credits)


func _record_attempt(
	outcome: String, encounter_id: String, raider_id: String, credits: Dictionary
) -> void:
	attempt_sequence += 1
	var result := CampaignState.record_attempt({
		"attempt_id": "training_contract_%d" % attempt_sequence,
		"encounter_id": encounter_id,
		"outcome": outcome,
		"observed_ability_ids": [],
		"observed_phase_ids": [],
		"observed_phase_names": [],
		"deaths": [],
		"training_quest_credit": {raider_id: credits},
	})
	_expect(bool(result.get("ok", false)), "Attempt %d could not be recorded: %s" % [attempt_sequence, result])


func _node_state(status: Dictionary, node_id: String) -> String:
	for node_value in status.get("node_statuses", []):
		var node: Dictionary = node_value
		if String(node.get("node_id", "")) == node_id:
			return String(node.get("status", ""))
	return ""


func _objective_current(status: Dictionary, node_id: String, objective_id: String) -> int:
	for node_value in status.get("node_statuses", []):
		var node: Dictionary = node_value
		if String(node.get("node_id", "")) != node_id:
			continue
		for objective_value in node.get("objectives", []):
			var objective: Dictionary = objective_value
			if String(objective.get("objective_id", "")) == objective_id:
				return int(objective.get("current", 0))
	return 0


func _first_active_member_of_class(unit_class: String) -> String:
	for member in CampaignState.get_active_members():
		if String(member.get("unit_class", "")) == unit_class:
			return String(member.get("member_id", ""))
	return ""


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(camp: Node) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if is_instance_valid(camp):
		camp.queue_free()
	if failures.is_empty():
		print("RAID_TEST_PASS:training_progression_contract | Quest-driven lineage talent progression passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
