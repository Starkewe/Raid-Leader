extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")

const FACILITY_PRIMARY_CONTROLS := {
	"command_tent": [
		"CommandEncounterSelector", "CommandRoster_active", "CommandRoster_reserve",
		"CommandEmbarkButton",
	],
	"formation_yard": ["FormationPresetSelector", "FormationYardEditor"],
	"archive": [
		"ArchiveEncounterControls", "ArchiveIntelligence", "ArchiveHistoryScroll",
	],
	"quarters": ["QuartersTabs", "QuartersRosterSection", "QuartersProfileSection"],
	"storage": ["StorageTabs", "StorageInventoryContent"],
	"smith": [
		"SmithCategoryGrid",
	],
}


func _ready() -> void:
	var failures: Array[String] = []
	get_window().size = Vector2i(1920, 1080)
	await _wait_frames(2)
	CampaignState.reset_campaign(false, 919191)
	var reward := CampaignState.debug_process_seeded_reward(
		"ogre", "half_screen_layout_first_clear"
	)
	if not bool(reward.get("ok", false)):
		failures.append("Layout fixture could not unlock Smith recipes.")
	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(4)
	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	if journal == null:
		failures.append("Camp Journal was unavailable.")
		_finish(camp, failures)
		return
	var viewport_size := journal.get_viewport_rect().size
	if not viewport_size.is_equal_approx(Vector2(1920, 1080)):
		failures.append(
			"Layout contract did not run at the 1920x1080 reference resolution (actual %s)."
			% viewport_size
		)
	var right_half_left := viewport_size.x * 0.5
	for facility_id in FACILITY_PRIMARY_CONTROLS:
		journal.open_facility(facility_id)
		await _wait_frames(4)
		_validate_facility(
			journal, facility_id, right_half_left, viewport_size.x, failures
		)
	_validate_smith_confirmation(journal, right_half_left, viewport_size.x, failures)
	_finish(camp, failures)


func _validate_facility(
	journal: CampJournal,
	facility_id: String,
	right_half_left: float,
	viewport_right: float,
	failures: Array[String]
) -> void:
	var shell := journal.find_child("CampJournalRightHalfShell", true, false) as Control
	var dim := journal.find_child("CampJournalRightHalfDim", true, false) as Control
	if shell == null or dim == null:
		failures.append("%s did not render the right-half shell and dim." % facility_id)
		return
	for named_control in [shell, dim]:
		var checked_control := named_control as Control
		var rect: Rect2 = checked_control.get_global_rect()
		if rect.position.x < right_half_left - 1.0 or rect.end.x > viewport_right + 1.0:
			failures.append("%s escaped the right half in %s." % [checked_control.name, facility_id])
	var shell_rect: Rect2 = shell.get_global_rect()
	for node in shell.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree() or control.size.x <= 0.0:
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.position.x < shell_rect.position.x - 1.0 or rect.end.x > shell_rect.end.x + 1.0:
			failures.append(
				"%s horizontally overflowed %s (%.1f..%.1f outside %.1f..%.1f)."
				% [
					control.name, facility_id, rect.position.x, rect.end.x,
					shell_rect.position.x, shell_rect.end.x,
				]
			)
			break
		if control is ScrollContainer:
			var scroll := control as ScrollContainer
			if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				failures.append("%s retained horizontal scrolling in %s." % [control.name, facility_id])
	for control_name in FACILITY_PRIMARY_CONTROLS[facility_id]:
		var primary := journal.find_child(control_name, true, false) as Control
		if primary == null or not primary.is_visible_in_tree():
			failures.append("%s primary control '%s' was not reachable." % [facility_id, control_name])
			continue
		var primary_rect: Rect2 = primary.get_global_rect()
		if (
			primary_rect.position.x < shell_rect.position.x - 1.0
			or primary_rect.end.x > shell_rect.end.x + 1.0
		):
			failures.append("%s primary control '%s' overflowed horizontally." % [facility_id, control_name])


func _validate_smith_confirmation(
	journal: CampJournal,
	right_half_left: float,
	viewport_right: float,
	failures: Array[String]
) -> void:
	journal.open_facility("smith")
	await _wait_frames(3)
	var presenter := journal.page_presenters.get("smith") as SmithPagePresenter
	if presenter == null:
		failures.append("Smith presenter was unavailable for tab layout validation.")
		return
	var categories: Array = presenter.build_view_model().get("categories", [])
	var selected_family_id := ""
	for category_value in categories:
		var category: Dictionary = category_value
		if bool(category.get("unlocked", false)):
			selected_family_id = String(category.get("family_id", ""))
			break
	if selected_family_id.is_empty():
		failures.append("Smith layout fixture did not expose an unlocked weapon family.")
		return
	presenter.select_family(selected_family_id)
	await _wait_frames(3)
	_validate_smith_tab_controls(journal, ["SmithRecipeList", "SmithCraftButton"], failures)
	var model: Dictionary = presenter.build_forge_view_model()
	var recipe: Dictionary = model.get("selected_recipe", {})
	if recipe.is_empty():
		failures.append("Smith Forge tab did not expose a selected recipe for confirmation layout.")
		return
	var grants: Dictionary = {}
	for component_value in recipe.get("components", []):
		var component: Dictionary = component_value
		grants[String(component.get("material_id", ""))] = int(
			component.get("required", 0)
		)
	CampaignState.debug_grant_progression_materials(grants)
	await _wait_frames(2)
	var request: Dictionary = presenter.request_craft_confirmation(
		String(recipe.get("recipe_id", ""))
	)
	await _wait_frames(2)
	var dialog := journal.find_child("SmithCraftConfirmation", true, false) as Window
	if request.get("status") != "confirmation_required" or dialog == null:
		failures.append("Smith confirmation was unavailable for right-half positioning.")
	else:
		if (
			float(dialog.position.x) < right_half_left - 1.0
			or float(dialog.position.x + dialog.size.x) > viewport_right + 1.0
		):
			failures.append("Smith confirmation escaped the right half.")
	presenter.cancel_pending_craft()
	presenter.select_tab("armory")
	await _wait_frames(3)
	_validate_smith_tab_controls(journal, ["SmithArmorySection", "SmithReturnToArmory"], failures)


func _validate_smith_tab_controls(
	journal: CampJournal, control_names: Array, failures: Array[String]
) -> void:
	var shell := journal.find_child("CampJournalRightHalfShell", true, false) as Control
	if shell == null:
		return
	var shell_rect := shell.get_global_rect()
	var geometry_controls: Array = ["SmithItemSection", "SmithDetailSection"]
	geometry_controls.append_array(control_names)
	for control_name in geometry_controls:
		var control := journal.find_child(String(control_name), true, false) as Control
		if control == null or not control.is_visible_in_tree():
			failures.append("Smith tab control '%s' was not rendered." % control_name)
			continue
		var rect := control.get_global_rect()
		if rect.position.x < shell_rect.position.x - 1.0 or rect.end.x > shell_rect.end.x + 1.0:
			failures.append("Smith tab control '%s' overflowed the right-half shell." % control_name)
	var item_section := journal.find_child("SmithItemSection", true, false) as Control
	var detail_section := journal.find_child("SmithDetailSection", true, false) as Control
	if item_section != null and detail_section != null:
		if item_section.get_global_rect().end.x >= detail_section.get_global_rect().position.x:
			failures.append("Smith item and detail columns overlap horizontally.")
		if detail_section.get_global_rect().position.y > item_section.get_global_rect().position.y + 2.0:
			failures.append("Smith detail column did not start at the item column boundary.")
		var artwork := journal.find_child("SmithWeaponArtFrame", true, false) as Control
		if artwork != null and artwork.get_global_rect().position.y > detail_section.get_global_rect().position.y + 2.0:
			failures.append("Smith artwork retained a blank gap above the detail column.")
	for scroll_name in ["SmithRecipeListScroll", "SmithArmoryListScroll"]:
		var scroll := journal.find_child(scroll_name, true, false) as ScrollContainer
		if scroll == null or not scroll.is_visible_in_tree():
			continue
		if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			failures.append("%s retained horizontal scrolling." % scroll_name)
		if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			failures.append("%s did not retain vertical list scrolling." % scroll_name)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _finish(camp: Node, failures: Array[String]) -> void:
	if camp != null and is_instance_valid(camp):
		camp.queue_free()
	if failures.is_empty():
		print("RAID_TEST_PASS:camp_journal_half_screen_layout | Every Camp Journal facility fits the responsive right half.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
