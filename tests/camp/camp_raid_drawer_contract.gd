extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignState.reset_campaign(false, 884422)
	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(5)

	var drawer := camp.get_node_or_null("CampHUD/CampRaidDrawer") as CampRaidDrawer
	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	var population := camp.get_node_or_null("CampPopulationController") as CampPopulationController
	_expect(drawer != null, "Camp did not instantiate its raid drawer.")
	_expect(journal != null, "Camp did not instantiate its Journal.")
	_expect(population != null, "Camp did not instantiate its population controller.")
	if drawer == null or journal == null or population == null:
		_finish(camp)
		return

	_validate_initial_drawer(drawer)
	_validate_gui_input_order(drawer, journal)
	_validate_hover_highlight(drawer, population)
	await _validate_lock_and_restore(drawer, journal)
	await _validate_live_refresh(drawer)
	_finish(camp)


func _validate_initial_drawer(drawer: CampRaidDrawer) -> void:
	_expect(not drawer.is_open(), "Raid drawer did not start retracted on camp entry.")
	_expect(not drawer.is_locked_open(), "Raid drawer started locked without a contextual menu.")
	var viewport_height := drawer.get_viewport_rect().size.y
	_expect(
		is_zero_approx(drawer.global_position.y) and is_equal_approx(drawer.size.y, viewport_height),
		"Raid drawer did not span the viewport vertically (y=%s, height=%s, viewport=%s)."
		% [drawer.global_position.y, drawer.size.y, viewport_height]
	)
	_expect(
		drawer.content_panel != null
		and is_zero_approx(drawer.content_panel.position.y)
		and is_equal_approx(drawer.content_panel.size.y, drawer.size.y),
		"Raid drawer panel did not cover the drawer's full height."
	)
	_expect(
		not drawer.content_panel is Panel,
		"Raid drawer retained its opaque full-height background panel."
	)
	var active_ids := CampaignState.get_active_member_ids()
	_expect(
		_frame_count(drawer) == active_ids.size(),
		"Raid drawer did not render every active raider exactly once."
	)
	_expect(
		drawer.find_children("*", "ScrollContainer", true, false).is_empty(),
		"Raid drawer retained a scroll container or mouse-wheel roster."
	)
	var group_size := maxi(TuningCatalogAccess.get_raid_campaign().raid_group_size, 1)
	var expected_groups := ceili(float(active_ids.size()) / float(group_size))
	_expect(
		_group_label_count(drawer) == expected_groups,
		"Raid drawer group labels did not follow active-party order and raid group size."
	)
	var first_frame := _frame(drawer, String(active_ids[0]))
	if first_frame != null:
		_expect(
			first_frame.custom_minimum_size == CampRaidFrame.BASE_SIZE,
			"Normal camp raid frame did not use the compact 154x45 footprint."
		)
		_expect(
			is_equal_approx(first_frame.size.y, CampRaidFrame.BASE_SIZE.y),
			"Raid-frame drawing covered only part of its allocated row (%s allocated, %s drawn)."
			% [first_frame.size.y, CampRaidFrame.BASE_SIZE.y]
		)
	_expect(
		drawer.stack.get_combined_minimum_size().y <= drawer.size.y,
		"The maximum active raid does not fit in the fixed-height drawer (%s required, %s available)."
		% [drawer.stack.get_combined_minimum_size().y, drawer.size.y]
	)
	var stack_children := drawer.stack.get_children()
	if not stack_children.is_empty():
		var first_child := stack_children[0] as Control
		var last_child := stack_children[-1] as Control
		if first_child != null and last_child != null:
			var top_gap := first_child.position.y
			var bottom_gap := drawer.stack.size.y - (last_child.position.y + last_child.size.y)
			_expect(
				is_equal_approx(top_gap, bottom_gap),
				"Raid-frame stack was not vertically centered (%s top, %s bottom)."
				% [top_gap, bottom_gap]
			)
	_expect(
		is_equal_approx(
			drawer.handle.position.y,
			(drawer.size.y - CampRaidDrawer.HANDLE_HEIGHT) * 0.5
		),
		"Raid drawer handle was not vertically centered."
	)

	drawer.set_open_for_test(true, false)
	_expect(drawer.is_open() and drawer.manual_open, "Raid drawer handle state did not open manually.")
	drawer.set_open_for_test(false, false)
	_expect(not drawer.is_open(), "Raid drawer did not retract manually.")


func _validate_gui_input_order(
	drawer: CampRaidDrawer, journal: CampJournal
) -> void:
	_expect(
		drawer.get_parent() == journal.get_parent()
		and drawer.get_index() > journal.get_index(),
		"Raid drawer is not after the full-screen Journal in GUI input order."
	)
	_expect(
		drawer.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and drawer.content_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and drawer.stack.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Raid drawer transparent shell intercepts Journal mouse input."
	)


func _validate_hover_highlight(
	drawer: CampRaidDrawer, population: CampPopulationController
) -> void:
	var member_id := String(CampaignState.get_active_member_ids()[0])
	var frame := _frame(drawer, member_id)
	var actor := population.actors_by_id.get(member_id) as CampMemberActor
	_expect(frame != null and actor != null, "Hover-highlight fixture could not resolve its frame and camp actor.")
	if frame == null or actor == null:
		return
	frame._on_mouse_entered()
	_expect(actor.raid_drawer_highlighted, "Hovering a raid frame did not highlight its camp actor.")
	frame._on_mouse_exited()
	_expect(not actor.raid_drawer_highlighted, "Leaving a raid frame did not clear its camp actor highlight.")


func _validate_lock_and_restore(
	drawer: CampRaidDrawer, journal: CampJournal
) -> void:
	drawer.set_open_for_test(true, false)
	journal.open_facility("smith")
	await _wait_frames(2)
	_expect(drawer.is_open() and drawer.is_locked_open(), "Smith did not force the raid drawer open and lock it.")
	_expect(drawer.get_menu_context() == "smith", "Smith did not set the drawer's Smith context.")
	var member_id := String(CampaignState.get_active_member_ids()[0])
	var smith_frame := _frame(drawer, member_id)
	if smith_frame != null:
		_expect(
			smith_frame.custom_minimum_size.x == CampRaidFrame.FULL_WIDTH,
			"Smith context did not add the square weapon slot beside the raid frame."
		)
		_expect(smith_frame.equipment_enabled, "Smith did not enable equipment dragging immediately.")
		_expect(
			drawer.get_smith_family_filter().is_empty()
			and smith_frame.smith_family_compatibility_state == "neutral"
			and not smith_frame.smith_drop_target_enabled,
			"Smith category gate did not leave all raid frames visible but non-targeting."
		)
		_expect(
			smith_frame.mouse_filter == Control.MOUSE_FILTER_STOP,
			"Interactive raid frames do not receive GUI input through the inert drawer shell."
		)
		_expect(
			RaiderClassCatalog.get_default_weapon_icon(smith_frame._effective_class_id()) != null,
			"Unarmed Smith frame could not resolve its class default weapon icon."
		)
	var smith_presenter := journal.page_presenters.get("smith") as SmithPagePresenter
	var reward := CampaignState.debug_process_seeded_reward("ogre", "drawer_smith_family_filter")
	_expect(bool(reward.get("ok", false)), "Drawer Smith fixture could not unlock a weapon family.")
	if smith_presenter != null and smith_presenter.select_family("heavy_arms"):
		await _wait_frames(3)
		var compatible_frame: CampRaidFrame = null
		var incompatible_frame: CampRaidFrame = null
		for child in drawer.stack.get_children():
			if not child is CampRaidFrame:
				continue
			var candidate := child as CampRaidFrame
			if candidate.family_compatible and compatible_frame == null:
				compatible_frame = candidate
			elif not candidate.family_compatible and incompatible_frame == null:
				incompatible_frame = candidate
		_expect(compatible_frame != null, "Smith family filter did not expose a compatible raid frame.")
		_expect(incompatible_frame != null, "Smith family filter did not expose a dimmed incompatible raid frame.")
		if compatible_frame != null:
			_expect(compatible_frame.smith_drop_target_enabled, "Compatible Smith frame was not an active target.")
		if incompatible_frame != null:
			_expect(not incompatible_frame.smith_drop_target_enabled, "Incompatible Smith frame remained an active target.")
			_expect(
				not incompatible_frame._can_drop_data(
					Vector2(90, 22), {"type": "smith_armory_weapon", "weapon_id": "earthgnasher_heartmaul"}
				),
				"Incompatible Smith frame accepted a weapon drop."
			)
	journal.close_journal()
	await _wait_frames(2)
	_expect(
		drawer.is_open() and not drawer.is_locked_open(),
		"Closing Smith did not restore the drawer's prior manual-open state."
	)

	drawer.set_open_for_test(false, false)
	journal.open_facility("formation_yard")
	await _wait_frames(2)
	_expect(
		drawer.is_open() and drawer.is_locked_open() and drawer.get_menu_context() == "formation_yard",
		"Formation Yard did not force the contextual raid drawer open."
	)
	var formation_frame := _frame(drawer, member_id)
	if formation_frame != null:
		var payload := formation_frame.get_drag_payload(Vector2(12, 20))
		_expect(
			payload.get("type") == "formation_member" and payload.get("member_id") == member_id,
			"Formation Yard raid frame did not expose the expected map-drag payload."
		)
		_expect(
			not formation_frame.placement.is_empty(),
			"Formation Yard frame did not receive its authored directional placement badge data."
		)
	_expect(
		journal.formation_editor != null and journal.formation_editor.roster_scroll == null,
		"Formation Yard retained its duplicate active-raider menu roster."
	)

	journal.close_journal()
	await _wait_frames(2)
	_expect(
		not drawer.is_open() and not drawer.is_locked_open(),
		"Closing Formation Yard did not restore the drawer's prior retracted state."
	)
	journal.open_facility("training")
	await _wait_frames(2)
	var training_frame := _frame(drawer, member_id)
	_expect(
		not drawer.is_locked_open()
		and not drawer.is_open()
		and drawer.get_menu_context().is_empty(),
		"Training still forced or claimed the contextual raid drawer."
	)
	if training_frame != null:
		_expect(
			training_frame.context.is_empty()
			and training_frame.custom_minimum_size == CampRaidFrame.BASE_SIZE,
			"Training still adds an accessory slot or context to raid frames."
		)
	_expect(
		drawer.find_child("TrainingBenefitsPopout", true, false) == null,
		"Training raid-frame benefits popout was not removed."
	)
	journal.close_journal()
	await _wait_frames(2)
	journal.open_facility("storage")
	await _wait_frames(2)
	_expect(
		not drawer.is_locked_open() and not drawer.is_open(),
		"A non-contextual Journal page forced the raid drawer open."
	)
	journal.close_journal()


func _validate_live_refresh(drawer: CampRaidDrawer) -> void:
	var active_ids := CampaignState.get_active_member_ids()
	if active_ids.size() < 2:
		failures.append("Raid drawer live-refresh fixture requires at least two active raiders.")
		return
	var removed_id := String(active_ids[-1])
	if not CampaignState.remove_active_member(removed_id):
		failures.append("Raid drawer live-refresh fixture could not move an active raider to reserve.")
		return
	await _wait_frames(3)
	_expect(
		_frame(drawer, removed_id) == null
		and _frame_count(drawer) == CampaignState.get_active_member_ids().size(),
		"Raid drawer did not refresh immediately after the active party changed."
	)


func _frame(drawer: CampRaidDrawer, member_id: String) -> CampRaidFrame:
	return drawer.find_child("CampRaidFrame_" + member_id, true, false) as CampRaidFrame


func _frame_count(drawer: CampRaidDrawer) -> int:
	var count := 0
	for child in drawer.stack.get_children():
		if child is CampRaidFrame:
			count += 1
	return count


func _group_label_count(drawer: CampRaidDrawer) -> int:
	var count := 0
	for child in drawer.stack.get_children():
		if child is Label and String(child.text).begins_with("Group "):
			count += 1
	return count


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(camp: Node) -> void:
	if camp != null and is_instance_valid(camp):
		camp.queue_free()
	CampaignState.reset_campaign(false, 884422)
	if failures.is_empty():
		print("RAID_TEST_PASS:camp_raid_drawer_contract | Camp raid drawer contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
