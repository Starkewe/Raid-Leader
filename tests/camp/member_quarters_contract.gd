extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")
const PROFILE_HEADINGS := [
	"Biography and personality",
	"Close connections",
	"Memories",
	"Recent experiences",
	"Personal themes",
	"Recent social memories",
]
const NON_BIOGRAPHY_CATEGORIES := [
	"close_connections",
	"memories",
	"recent_experiences",
	"personal_themes",
	"recent_social_memories",
]


func _ready() -> void:
	var failures: Array[String] = []
	get_window().size = Vector2i(1920, 1080)
	await _wait_frames(2)
	CampaignState.reset_campaign(false, 828282)

	var active_fixture := CampaignState.get_active_members_for_roster()
	if active_fixture.is_empty():
		failures.append("The quarters contract fixture did not expose an active raider.")
	else:
		var first_id := String(active_fixture[0].get("member_id", ""))
		var event := CampaignState.emit_notable_event(
			{
				"event_type": "boss_attempt_completed",
				"source_system": "member_quarters_contract",
				"participants": [first_id],
				"memory_category": "combat",
				"subject_key": "contract:profile_development",
				"significance": 72,
				"structured_data": {"contract": true},
			},
			false
		)
		if event.is_empty():
			failures.append("The quarters contract could not create an unseen profile development.")

	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(5)
	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	if journal == null:
		failures.append("Camp Journal was unavailable.")
		_finish(camp, failures)
		return

	journal.open_facility("quarters")
	await _wait_frames(5)
	var panel := journal.member_quarters_panel
	if panel == null or not is_instance_valid(panel):
		failures.append("Member Quarters panel was unavailable.")
		_finish(camp, failures)
		return

	_validate_layout(panel, failures)
	_validate_tabs(panel, failures)
	_validate_roster_tab(panel, "active", CampaignState.get_active_members_for_roster(), failures)
	_validate_roster_ui(panel, failures)
	_validate_profile(panel, failures)
	await _validate_narrative_accordion(panel, failures)
	await _validate_unseen_star_and_explicit_click(panel, failures)

	var reserve_tab := panel.reserve_tab_button
	if reserve_tab != null:
		reserve_tab.emit_signal("pressed")
		await _wait_frames(3)
		if panel.get_selected_tab_id() != "reserve":
			failures.append("Reserve tab did not become selected when pressed.")
		_validate_roster_tab(
			panel, "reserve", CampaignState.get_reserve_members_for_roster(), failures
		)
		if panel.active_tab_button.disabled != false:
			failures.append("Active tab remained disabled after switching to Reserve.")

	_finish(camp, failures)


func _validate_layout(panel: MemberQuartersPanel, failures: Array[String]) -> void:
	var tabs := panel.find_child("QuartersTabs", true, false) as Control
	var roster := panel.find_child("QuartersRosterSection", true, false) as Control
	var profile := panel.find_child("QuartersProfileSection", true, false) as Control
	if tabs == null or roster == null or profile == null:
		failures.append("Quarters did not expose its roster/profile layout controls.")
		return
	if tabs.get_parent() != roster:
		failures.append("QuartersTabs was not placed inside QuartersRosterSection.")
	if tabs.get_index() >= panel.find_child("QuartersRosterPanel", true, false).get_index():
		failures.append("QuartersTabs was not above the roster list.")
	if roster.get_global_rect().end.x >= profile.get_global_rect().position.x:
		failures.append("Quarters roster and profile columns overlap.")


func _validate_tabs(panel: MemberQuartersPanel, failures: Array[String]) -> void:
	var tabs := panel.find_child("QuartersTabs", true, false) as HBoxContainer
	if tabs == null:
		failures.append("QuartersTabs was not rendered.")
		return
	if panel.active_tab_button == null or panel.reserve_tab_button == null:
		failures.append("Active and Reserve tab buttons were not both rendered.")
		return
	if panel.active_tab_button.text != "Active" or panel.reserve_tab_button.text != "Reserve":
		failures.append("Quarters tab labels were not exactly Active and Reserve.")
	if panel.get_selected_tab_id() != "active":
		failures.append("Active was not the default quarters tab.")
	if not panel.active_tab_button.disabled or panel.reserve_tab_button.disabled:
		failures.append("Default Active tab did not have the disabled selected state.")
	if not bool(panel.active_tab_button.get_meta("quarters_tab_selected", false)):
		failures.append("Default Active tab did not expose its highlighted selected state.")
	if bool(panel.reserve_tab_button.get_meta("quarters_tab_selected", false)):
		failures.append("Reserve tab was highlighted before it was selected.")


func _validate_roster_tab(
	panel: MemberQuartersPanel,
	tab_id: String,
	expected_members: Array[Dictionary],
	failures: Array[String]
) -> void:
	if panel.get_selected_tab_id() != tab_id:
		return
	if panel.row_by_id.size() != expected_members.size():
		failures.append(
			"%s roster rendered %d entries instead of %d."
			% [tab_id, panel.row_by_id.size(), expected_members.size()]
		)
	for member in expected_members:
		var raider_id := String(member.get("member_id", ""))
		if not panel.row_by_id.has(raider_id):
			failures.append("%s roster omitted %s." % [tab_id, raider_id])
	var scroll := panel.find_child("QuartersRosterScroll", true, false) as ScrollContainer
	if scroll == null:
		failures.append("QuartersRosterScroll was not rendered.")
	else:
		if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			failures.append("QuartersRosterScroll did not retain vertical scrolling.")
		if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			failures.append("QuartersRosterScroll retained horizontal scrolling.")


func _validate_roster_ui(panel: MemberQuartersPanel, failures: Array[String]) -> void:
	if panel.find_children("*", "Tree", true, false).size() > 0:
		failures.append("The production quarters roster still uses a Tree.")
	for line_edit_value in panel.find_children("*", "LineEdit", true, false):
		var line_edit := line_edit_value as Control
		if line_edit != null and line_edit.is_visible_in_tree():
			failures.append("The production quarters roster still renders search input controls.")
	for node in panel.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null:
			continue
		var lowered := control.name.to_lower()
		if lowered.contains("search") or lowered.contains("filter") or lowered.contains("sort"):
			failures.append("Removed roster control '%s' was still rendered." % control.name)
	if panel.find_child("QuartersRosterHint", true, false) != null:
		failures.append("The removed roster instruction hint was still rendered.")

	for raider_id_value in panel.row_by_id:
		var raider_id := String(raider_id_value)
		var row := panel.row_by_id[raider_id_value] as Button
		var member := CampaignState.get_member(raider_id)
		if row == null:
			failures.append("A roster entry was not button-style.")
			continue
		var roster_text := String(row.get_meta("roster_text", ""))
		if roster_text.is_empty() or not roster_text.contains("\n"):
			failures.append("A roster button did not show name and class on separate lines.")
		if not row.text.is_empty():
			failures.append("A roster button retained duplicate semantic text over its labels.")
		if roster_text.contains("Working at") or roster_text.contains("Available in camp") or roster_text.contains("Taking a quiet"):
			failures.append("Roster entry %s still exposed current activity text." % raider_id)
		if not row.tooltip_text.is_empty():
			failures.append("Roster entry %s still exposed mouseover text." % raider_id)
		var name_label := row.find_child("QuartersRosterEntryName", true, false) as Label
		var class_label := row.find_child("QuartersRosterEntryClass", true, false) as Label
		if name_label == null or class_label == null:
			failures.append("Roster entry %s did not render separate name and class labels." % raider_id)
		else:
			if not name_label.text.contains(String(member.get("display_name", "Unknown Raider"))):
				failures.append("Roster entry %s did not render the raider name." % raider_id)
			if class_label.text != String(member.get("unit_class", "Unknown")):
				failures.append("Roster entry %s did not render the class label." % raider_id)
		var class_id := String(member.get("advanced_class_id", ""))
		if class_id.is_empty():
			class_id = String(member.get("unit_class", "Unknown"))
		var expected_color := RaiderClassCatalog.get_camp_color(class_id)
		if row.get_meta("class_color", Color("000000")) != expected_color:
			failures.append("Roster entry %s did not expose its catalog class color." % raider_id)
		if class_label != null and class_label.get_theme_color("font_color") != expected_color:
			failures.append("Roster entry %s did not use its catalog class color on the class label." % raider_id)
		if name_label != null and name_label.get_theme_color("font_color") == expected_color:
			failures.append("Roster entry %s incorrectly used its catalog class color on the raider name." % raider_id)


func _validate_profile(panel: MemberQuartersPanel, failures: Array[String]) -> void:
	var profile := panel.find_child("QuartersProfileSection", true, false) as Control
	if profile == null:
		failures.append("QuartersProfileSection was not rendered.")
		return
	var narrative_scroll := profile.find_child("QuartersProfileNarrativeScroll", true, false) as ScrollContainer
	if narrative_scroll == null:
		failures.append("Profile narrative did not render its dedicated scroll region.")
	else:
		if narrative_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			failures.append("Profile narrative scroll did not retain vertical scrolling.")
		if narrative_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			failures.append("Profile narrative scroll retained horizontal scrolling.")
	var profile_content := panel.find_child("QuartersProfileContent", true, false) as VBoxContainer
	var artwork := profile.find_child("QuartersRaiderArtwork", true, false)
	if profile_content == null or artwork == null or profile_content.get_child(0) != artwork:
		failures.append("Raider artwork was not the first element of the fixed profile column.")
	var profile_header := profile.find_child("QuartersProfileHeader", true, false) as HBoxContainer
	var identity := profile.find_child("QuartersProfileIdentity", true, false) as VBoxContainer
	var room_column := profile.find_child("QuartersProfileRoomColumn", true, false) as VBoxContainer
	if profile_header == null or identity == null or room_column == null:
		failures.append("Profile identity and room controls did not render in a shared header.")
	else:
		if identity.get_parent() != profile_header or room_column.get_parent() != profile_header:
			failures.append("Profile identity and room controls were not arranged in the profile header.")
		if identity.get_global_rect().position.x >= room_column.get_global_rect().position.x:
			failures.append("Room selection was not positioned to the right of the profile identity.")
	if profile.find_child("QuartersProfileName", true, false) == null:
		failures.append("Raider name was not rendered below the artwork.")
	if profile.find_child("QuartersProfileClass", true, false) == null:
		failures.append("Raider class was not rendered below the artwork.")
	if profile.find_child("QuartersProfileVictoryCount", true, false) == null:
		failures.append("Raider victory count was not rendered below the artwork.")
	var room_selector := profile.find_child("QuartersRoomSelector", true, false) as OptionButton
	if room_selector == null:
		failures.append("Editable room selector was not rendered.")
	else:
		var room_text := room_selector.get_item_text(room_selector.selected)
		if not room_text.contains("/"):
			failures.append("Closed room selector did not show room capacity.")
		if room_selector.get_parent().name != "QuartersRoomAssignment":
			failures.append("Room selector was not placed in the compact assignment row.")
		elif room_column != null and room_selector.get_parent().get_parent() != room_column:
			failures.append("Room assignment was not kept in the top-right profile column.")
	var activity := profile.find_child("QuartersProfileCurrentActivity", true, false) as Label
	if activity == null:
		failures.append("Current profile activity was not rendered.")
	else:
		if profile_content != null and activity.get_parent() != profile_content:
			failures.append("Current profile activity was not a full-width profile content row.")
		elif profile_content != null and activity.size.x + 2.0 < profile_content.size.x:
			failures.append("Current profile activity did not use the available profile width.")
		if activity.autowrap_mode != TextServer.AUTOWRAP_OFF:
			failures.append("Current profile activity was not fixed to one line.")
		if activity.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
			failures.append("Current profile activity did not use ellipsis overrun behavior.")
		if activity.tooltip_text != String(activity.get_meta("full_activity_text", "")):
			failures.append("Current profile activity tooltip did not retain the full text.")
	if profile.find_child("QuartersProfilePreferredSeparator", true, false) == null:
		failures.append("Preferred-activity separator was not rendered.")
	if profile.find_child("QuartersProfileNarrativeSeparator", true, false) == null:
		failures.append("Narrative separator was not rendered.")
	var preferred := profile.find_child("QuartersProfilePreferredActivities", true, false) as Control
	if preferred == null:
		failures.append("Preferred activities were not rendered in their own profile block.")
	else:
		var heading := preferred.find_child("QuartersPreferredActivitiesHeading", true, false) as Label
		if heading == null or heading.get_theme_color("font_color") != Color("dc9149"):
			failures.append("Preferred activities were not orange-highlighted.")
		if preferred.find_children("QuartersPreferredActivity_*", "Label", true, false).is_empty():
			failures.append("Preferred activities did not render bullet entries.")
	var rendered_art := profile.find_child("QuartersRaiderArtworkTexture", true, false)
	var rendered_fallback := profile.find_child("QuartersRaiderArtworkFallback", true, false)
	if rendered_art == null and rendered_fallback == null:
		failures.append("Raider artwork had neither a texture nor a safe fallback.")
	var fallback_visual := panel._build_visual(
		{"display_name": "Fallback Raider", "visual": {"path": "res://missing/quarters_portrait.png"}}
	) as Control
	if fallback_visual == null or fallback_visual.find_child("QuartersRaiderArtworkFallback", true, false) == null:
		failures.append("Missing raider artwork did not render the initials fallback.")
	if fallback_visual != null:
		fallback_visual.queue_free()


func _validate_narrative_accordion(panel: MemberQuartersPanel, failures: Array[String]) -> void:
	var profile := panel.find_child("QuartersProfileSection", true, false) as Control
	if profile == null:
		return
	for heading in PROFILE_HEADINGS:
		var category := _category_for_heading(heading)
		var toggle := profile.find_child(
			"QuartersNarrativeToggle_%s" % category, true, false
		) as Button
		if toggle == null or toggle.text != heading:
			failures.append("Narrative accordion heading '%s' was missing." % heading)
	if profile.find_child("QuartersNarrativeToggle_combat_history", true, false) != null:
		failures.append("Combat history was still rendered in the profile narrative.")
	var biography_body := profile.find_child("QuartersNarrativeBody_biography", true, false) as Control
	if biography_body == null or not biography_body.visible:
		failures.append("Biography and personality was not expanded by default.")
	for category in NON_BIOGRAPHY_CATEGORIES:
		var body := profile.find_child(
			"QuartersNarrativeBody_%s" % category, true, false
		) as Control
		if body == null:
			continue
		if body.visible:
			failures.append("Non-biography category %s was open by default." % category)
		var toggle := profile.find_child(
			"QuartersNarrativeToggle_%s" % category, true, false
		) as Button
		if toggle == null:
			continue
		toggle.emit_signal("pressed")
		await _wait_frames(1)
		if not body.visible or biography_body.visible:
			failures.append("Opening %s did not close Biography and personality." % category)
		for other_category in NON_BIOGRAPHY_CATEGORIES:
			if other_category == category:
				continue
			var other_body := profile.find_child(
				"QuartersNarrativeBody_%s" % other_category, true, false
			) as Control
			if other_body != null and other_body.visible:
				failures.append("Opening %s left %s open too." % [category, other_category])
		var content := body.find_child("QuartersNarrativeBodyContent", true, false) as Control
		if content != null:
			for text_node in content.find_children("*", "Label", true, false):
				var label := text_node as Label
				if label != null and label.clip_text:
					failures.append("Narrative category %s clipped its body text." % category)
		toggle.emit_signal("pressed")
		await _wait_frames(1)
		if body.visible or not biography_body.visible:
			failures.append("Closing %s did not restore the default Biography and personality section." % category)


func _validate_unseen_star_and_explicit_click(
	panel: MemberQuartersPanel, failures: Array[String]
) -> void:
	var starred_id := ""
	for raider_id_value in panel.row_by_id.keys():
		var row := panel.row_by_id[raider_id_value] as Button
		if row != null and bool(row.get_meta("has_unseen_profile_development", false)):
			starred_id = String(raider_id_value)
			break
	if starred_id.is_empty():
		failures.append("Unseen profile development did not render a leading star.")
		return
	var starred_row := panel.row_by_id[starred_id] as Button
	var roster_text := String(starred_row.get_meta("roster_text", ""))
	if not roster_text.begins_with("★"):
		failures.append("Unseen profile star was not placed at the leading edge of the roster entry.")
	if starred_id == panel.get_selected_raider_id() and not CampaignState.has_unseen_profile_development(starred_id):
		failures.append("Automatic profile selection cleared the unseen profile star.")
	starred_row.emit_signal("pressed")
	await _wait_frames(1)
	if CampaignState.has_unseen_profile_development(starred_id):
		failures.append("Explicit roster click did not mark the selected profile seen.")
	if String(starred_row.get_meta("roster_text", "")).begins_with("★"):
		failures.append("Explicit roster click did not clear the roster star.")


func _category_for_heading(heading: String) -> String:
	for category in ["biography"] + NON_BIOGRAPHY_CATEGORIES:
		if String(MemberQuartersPanel.NARRATIVE_TITLES.get(category, "")) == heading:
			return category
	return heading.to_snake_case()


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _finish(camp: Node, failures: Array[String]) -> void:
	if camp != null and is_instance_valid(camp):
		camp.queue_free()
	CampaignState.reset_campaign(false, 828282)
	if failures.is_empty():
		print("RAID_TEST_PASS:member_quarters_contract | Member Quarters layout, profile metadata, accordion, and scrolling contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
