extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignState.reset_campaign(false, 61059)
	_expect(CampaignState.save_current_formation("Saved Draft"), "The saved formation setup failed.")

	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(4)

	var journal := camp.get_node_or_null("CampHUD/CampJournal") as CampJournal
	_expect(journal != null, "The camp journal did not load.")
	if journal == null:
		_finish()
		return

	journal.open_facility("formation_yard")
	await _wait_frames(3)
	var dropdown := journal.formation_preset_dropdown
	var editor := journal.formation_editor
	_expect(dropdown != null, "The Formation Yard did not create its preset dropdown.")
	_expect(editor != null, "The Formation Yard did not create its editor.")
	if dropdown == null or editor == null:
		_finish()
		return

	_expect(
		String(dropdown.get_item_metadata(dropdown.selected)) == "Saved Draft",
		"The Formation Yard did not select the active saved formation."
	)

	var member_id := String(CampaignState.get_active_member_ids()[0])
	if editor.roster_scroll != null:
		editor.roster_scroll.scroll_vertical = 120
	var scroll_before := editor.roster_scroll.scroll_vertical if editor.roster_scroll != null else 0
	editor._on_member_dropped(member_id, "north", "far")
	await _wait_frames(3)

	_expect(
		String(dropdown.get_item_metadata(dropdown.selected)) == "Saved Draft",
		"Editing a saved formation changed the dropdown selection."
	)
	_expect(
		String(CampaignState.get_formation().get("preset_name", "")) == "Saved Draft",
		"The displayed formation name and active formation diverged."
	)
	if editor.roster_scroll != null:
		_expect(
			abs(editor.roster_scroll.scroll_vertical - scroll_before) <= 1,
			"Editing a formation reset the active roster table scroll position."
		)

	var default_index := _dropdown_index(dropdown, CampaignState.DEFAULT_FORMATION_NAME)
	if default_index >= 0:
		journal._on_saved_formation_selected(default_index, dropdown)
		await _wait_frames(3)
		_expect(
			String(dropdown.get_item_metadata(dropdown.selected))
				== CampaignState.DEFAULT_FORMATION_NAME,
			"Explicitly selecting Default did not update the dropdown."
		)
		_expect(
			String(CampaignState.get_formation().get("preset_name", ""))
				== CampaignState.DEFAULT_FORMATION_NAME,
			"Explicitly selecting Default did not update the active formation."
		)

	camp.queue_free()
	await _wait_frames(2)
	CampaignState.reset_campaign(false, 61059)
	_finish()


func _dropdown_index(dropdown: OptionButton, metadata: String) -> int:
	for index in range(dropdown.item_count):
		if String(dropdown.get_item_metadata(index)) == metadata:
			return index
	return -1


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
		return

	print("Formation editor state regressions passed.")
	get_tree().quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
