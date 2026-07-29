extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not InputMap.has_action("toggle_raid_debug"):
		_fail("The raid debug toggle input action is missing.")
		return

	var has_f12_event := false

	for event in InputMap.action_get_events("toggle_raid_debug"):
		if event is InputEventKey and event.physical_keycode == KEY_F12:
			has_f12_event = true
			break

	if not has_f12_event:
		_fail("The raid debug toggle input action is not bound to F12.")
		return

	GameState.set_raid_debug_visibility(false)

	var debug_visual := Node2D.new()
	var unavailable_debug_visual := Control.new()
	var gameplay_visual := Node2D.new()
	root.add_child(debug_visual)
	root.add_child(unavailable_debug_visual)
	root.add_child(gameplay_visual)

	GameState.register_raid_debug_content(debug_visual)
	GameState.register_raid_debug_content(unavailable_debug_visual, false)

	if debug_visual.visible:
		_fail("Registered raid debug content was visible by default.")
		return

	GameState.toggle_raid_debug_visibility()

	if not debug_visual.visible:
		_fail("Registered raid debug content did not become visible.")
		return

	if unavailable_debug_visual.visible:
		_fail("Unavailable raid debug content ignored its availability gate.")
		return

	if not gameplay_visual.visible:
		_fail("The raid debug toggle changed an unregistered gameplay visual.")
		return

	var late_debug_visual := Node2D.new()
	root.add_child(late_debug_visual)
	GameState.register_raid_debug_content(late_debug_visual)

	if not late_debug_visual.visible:
		_fail("New raid debug content did not inherit the current visible state.")
		return

	GameState.set_raid_debug_visibility(false)

	if debug_visual.visible or late_debug_visual.visible:
		_fail("Registered raid debug content did not become hidden.")
		return

	print("Raid debug visibility regression test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
