extends SceneTree

const GameStateScript := preload("res://scripts/core/game_state.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state := root.get_node_or_null("GameState")
	if game_state == null:
		game_state = GameStateScript.new()
		root.add_child(game_state)

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

	if game_state.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail("GameState does not process input while the tree is paused.")
		return

	game_state.set_raid_debug_context(GameStateScript.RAID_DEBUG_CONTEXT_CAMP)
	game_state.set_raid_debug_mode(GameStateScript.RAID_DEBUG_MODE_OFF)

	var debug_visual := Node2D.new()
	var unavailable_debug_visual := Control.new()
	var gameplay_visual := Node2D.new()
	root.add_child(debug_visual)
	root.add_child(unavailable_debug_visual)
	root.add_child(gameplay_visual)

	game_state.register_raid_debug_content(debug_visual)
	game_state.register_raid_debug_content(unavailable_debug_visual, false)

	if debug_visual.visible:
		_fail("Registered raid debug content was visible by default.")
		return

	_press_f12(game_state)

	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_ALL:
		_fail("The first camp F12 press did not select all debug content.")
		return

	if not debug_visual.visible:
		_fail("Registered raid debug content did not become visible.")
		return

	if unavailable_debug_visual.visible:
		_fail("Unavailable raid debug content ignored its availability gate.")
		return

	if not gameplay_visual.visible:
		_fail("The raid debug toggle changed an unregistered gameplay visual.")
		return

	_press_f12(game_state)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_GEOMETRY:
		_fail("The second camp F12 press did not select geometry-only mode.")
		return
	if not debug_visual.visible or not gameplay_visual.visible:
		_fail("Geometry-only mode did not preserve registered/gameplay visibility.")
		return

	_press_f12(game_state)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_LABELS:
		_fail("The third camp F12 press did not select labels-only mode.")
		return

	_press_f12(game_state)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_OFF:
		_fail("The fourth camp F12 press did not turn debug content off.")
		return
	if debug_visual.visible or unavailable_debug_visual.visible:
		_fail("Camp off mode did not hide registered debug content.")
		return

	game_state.set_raid_debug_context(GameStateScript.RAID_DEBUG_CONTEXT_CAMP)
	game_state.set_raid_debug_mode(GameStateScript.RAID_DEBUG_MODE_LABELS)
	game_state.set_raid_debug_context(GameStateScript.RAID_DEBUG_CONTEXT_COMBAT)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_OFF:
		_fail("Entering combat did not clear a camp-only debug mode.")
		return
	game_state.set_raid_debug_context(GameStateScript.RAID_DEBUG_CONTEXT_CAMP)
	game_state.set_raid_debug_mode(GameStateScript.RAID_DEBUG_MODE_OFF)

	var late_debug_visual := Node2D.new()
	root.add_child(late_debug_visual)
	game_state.register_raid_debug_content(late_debug_visual)

	if late_debug_visual.visible:
		_fail("New raid debug content did not inherit the current hidden state.")
		return

	# Combat retains the binary off/on behavior even when the same F12 action is
	# used by the camp overlay.
	game_state.set_raid_debug_context(GameStateScript.RAID_DEBUG_CONTEXT_COMBAT)
	game_state.set_raid_debug_mode(GameStateScript.RAID_DEBUG_MODE_OFF)
	_press_f12(game_state)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_ALL:
		_fail("The first combat F12 press did not select all debug content.")
		return
	_press_f12(game_state)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_OFF:
		_fail("The second combat F12 press did not turn debug content off.")
		return
	_press_f12(game_state)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_ALL:
		_fail("The third combat F12 press did not select all debug content.")
		return

	# Legacy boolean callers continue to map directly to complete-overlay/all
	# and off states, regardless of the current combat context.
	game_state.set_raid_debug_visibility(false)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_OFF:
		_fail("Legacy false visibility did not map to off mode.")
		return
	game_state.set_raid_debug_visibility(true)
	if game_state.get_raid_debug_mode() != GameStateScript.RAID_DEBUG_MODE_ALL:
		_fail("Legacy true visibility did not map to all mode.")
		return
	game_state.set_raid_debug_visibility(false)

	if debug_visual.visible or late_debug_visual.visible:
		_fail("Registered raid debug content did not become hidden.")
		return

	print("Raid debug visibility regression test passed.")
	quit(0)


func _press_f12(game_state: Node) -> void:
	var f12_event := InputEventKey.new()
	f12_event.physical_keycode = KEY_F12
	f12_event.pressed = true
	game_state._unhandled_input(f12_event)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
