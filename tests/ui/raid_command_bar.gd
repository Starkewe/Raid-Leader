extends SceneTree

const BAR_SCENE := preload("res://scenes/ui/raid_command_bar.tscn")
const EXPECTED_PIECE_NAMES: Array[String] = [
	"LeftEndcap",
	"WhoBase",
	"WhatBase",
	"WhereBase",
	"WhenBase",
	"RightEndcap"
]
const EXPECTED_PIECE_WIDTHS: Array[float] = [64.0, 256.0, 256.0, 256.0, 256.0, 64.0]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Control.new()
	host.size = Vector2(1920.0, 1080.0)
	root.add_child(host)

	var bar := BAR_SCENE.instantiate() as RaidCommandBar
	host.add_child(bar)
	await process_frame

	if bar == null:
		_fail("The raid command bar scene did not instantiate.")
		return

	if not bar.size.is_equal_approx(Vector2(1152.0, 520.0)):
		_fail("The raid command bar root did not preserve its 1152-pixel width.")
		return

	if not bar.position.is_equal_approx(Vector2(384.0, 0.0)):
		_fail("The raid command bar was not centered at x=384 and flush to y=0.")
		return

	if bar.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		_fail("The raid command bar is not using nearest-neighbor texture filtering.")
		return

	if not _validate_structural_bar(bar):
		return

	if not _validate_mouse_filters(bar):
		return

	if not is_equal_approx(bar.STAGGER_DELAY_SECONDS, 0.125):
		_fail("The transcription stagger is not exactly 0.125 seconds.")
		return

	if not is_equal_approx(bar.HOLD_DURATION_SECONDS, 1.0):
		_fail("The transcription hold duration is not exactly 1.0 second.")
		return

	if not is_equal_approx(bar.FADE_DURATION_SECONDS, 0.25):
		_fail("The transcription fade duration is not exactly 0.25 seconds.")
		return

	if not _validate_reference_behavior(bar):
		return

	if not _validate_transcription_selection(bar):
		return

	await _validate_rapid_replacement(bar)

	if _failed:
		return

	print("Raid command bar regression test passed.")
	quit(0)


var _failed: bool = false


func _validate_structural_bar(bar: RaidCommandBar) -> bool:
	var structural_bar := bar.get_node("StructuralBar") as Control

	if structural_bar == null or not structural_bar.size.is_equal_approx(Vector2(1152.0, 64.0)):
		_fail("The structural bar is not exactly 1152x64.")
		return false

	var expected_left := 0.0

	for piece_index in range(EXPECTED_PIECE_NAMES.size()):
		var piece := structural_bar.get_node(EXPECTED_PIECE_NAMES[piece_index]) as TextureRect
		var expected_width := EXPECTED_PIECE_WIDTHS[piece_index]

		if piece == null:
			_fail("A structural command-bar piece is missing.")
			return false

		if not piece.position.is_equal_approx(Vector2(expected_left, 0.0)):
			_fail("A structural command-bar piece has a gap or fractional offset.")
			return false

		if not piece.size.is_equal_approx(Vector2(expected_width, 64.0)):
			_fail("A structural command-bar piece is not at native size.")
			return false

		if piece.stretch_mode != TextureRect.STRETCH_KEEP:
			_fail("A structural texture can be stretched at runtime.")
			return false

		expected_left += expected_width

	return is_equal_approx(expected_left, 1152.0)


func _validate_mouse_filters(bar: RaidCommandBar) -> bool:
	if bar.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("The command-bar root intercepts combat input.")
		return false

	for category_title in ["Who", "What", "Where", "When"]:
		var region := bar.get_node(
			"CategoryInteractionLayer/%sRegion" % category_title
		) as Control
		var button := region.get_node("HitRegion") as Button

		if region.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("A transparent category region intercepts input outside its button.")
			return false

		if button.mouse_filter != Control.MOUSE_FILTER_STOP:
			_fail("A category hit region does not intercept pointer input.")
			return false

	return true


func _validate_reference_behavior(bar: RaidCommandBar) -> bool:
	var was_paused := paused
	var who_overlay := bar.get_node(
		"CategoryInteractionLayer/WhoRegion/StateOverlay"
	) as TextureRect
	var when_overlay := bar.get_node(
		"CategoryInteractionLayer/WhenRegion/StateOverlay"
	) as TextureRect

	bar.call("_on_category_hover_changed", "who", true)

	if not who_overlay.visible or who_overlay.texture != bar.HOVER_OVERLAY:
		_fail("Who hover did not use the supplied hover overlay.")
		return false

	bar.open_reference_category("who")

	if not bar.is_open() or paused != was_paused:
		_fail("Opening the Who reference either failed or changed pause state.")
		return false

	if who_overlay.texture != bar.OPEN_OVERLAY:
		_fail("The open category did not take priority over hover.")
		return false

	bar.open_reference_category("what")

	if not bar.is_open():
		_fail("Opening What did not replace the existing reference category.")
		return false

	bar.open_reference_category("when")

	if not when_overlay.visible or when_overlay.texture != bar.MUTED_OVERLAY:
		_fail("When did not preserve muted-state priority while open.")
		return false

	bar.call("_on_category_pressed", "when")

	if bar.is_open():
		_fail("Clicking the currently open category did not close it.")
		return false

	bar.open_reference_category("who")
	var outside_click := InputEventMouseButton.new()
	outside_click.button_index = MOUSE_BUTTON_LEFT
	outside_click.pressed = true
	outside_click.position = Vector2(1800.0, 800.0)
	bar._input(outside_click)

	if bar.is_open():
		_fail("Clicking outside the bar and reference panel did not close it.")
		return false

	bar.open_reference_category("what")
	bar.close_for_escape()

	if bar.is_open():
		_fail("Escape-modal close did not close the reference panel.")
		return false

	if bar.has_signal("command_submitted"):
		_fail("The informational command bar exposes an executing command signal.")
		return false

	return true


func _validate_transcription_selection(bar: RaidCommandBar) -> bool:
	bar.display_parsed_command(_full_parse_result("Everyone except the warriors", "Move", "Southeast"))

	var who_label := bar.get_node("TranscriptionLayer/WhoTranscription") as Label
	var what_label := bar.get_node("TranscriptionLayer/WhatTranscription") as Label
	var where_label := bar.get_node("TranscriptionLayer/WhereTranscription") as Label

	if who_label.text != "Everyone except the warriors":
		_fail("The explicit Who phrase was not preserved for display.")
		return false

	if what_label.text != "Move" or where_label.text != "Southeast":
		_fail("The parsed What and Where values were not displayed canonically.")
		return false

	var active_tweens: Dictionary = bar.get("_transcription_tweens")

	if active_tweens.size() != 3:
		_fail("Recognized categories do not have independent lifecycle tweens.")
		return false

	bar.display_parsed_command(_missing_who_parse_result())

	if who_label.visible or not who_label.text.is_empty():
		_fail("A defaulted Who value was shown for a phrase that omitted Who.")
		return false

	if what_label.text != "Move" or where_label.text != "West":
		_fail("What and Where did not start immediately when Who was omitted.")
		return false

	if who_label.max_lines_visible != 2:
		_fail("Who transcription is not clamped to two visible lines.")
		return false

	if who_label.text_overrun_behavior != TextServer.OVERRUN_TRIM_WORD_ELLIPSIS:
		_fail("Long transcription text does not use word ellipsis.")
		return false

	return true


func _validate_rapid_replacement(bar: RaidCommandBar) -> void:
	bar.display_parsed_command(_full_parse_result("Old target", "Move", "North"))
	await create_timer(0.22).timeout
	bar.notify_transcription_started()
	bar.display_parsed_command(_replacement_parse_result())
	await create_timer(0.30).timeout

	var who_label := bar.get_node("TranscriptionLayer/WhoTranscription") as Label
	var what_label := bar.get_node("TranscriptionLayer/WhatTranscription") as Label
	var where_label := bar.get_node("TranscriptionLayer/WhereTranscription") as Label

	if not who_label.text.is_empty() or who_label.visible:
		_fail("A stale Who value survived rapid transcription replacement.")
		return

	if what_label.text != "Dodge" or where_label.text != "East":
		_fail("A stale callback replaced or hid the newest transcription values.")


func _full_parse_result(who_text: String, what_text: String, where_text: String) -> Dictionary:
	return {
		"ok": true,
		"command_data": {
			"what": what_text.to_lower(),
			"where": "movement_region",
			"movement_region": where_text.to_lower()
		},
		"who_resolution": {"who_text": who_text.to_lower()},
		"command_resolution": {
			"slot_states": {
				"who": "explicit",
				"what": "explicit",
				"where": "explicit",
				"when": "defaulted"
			},
			"slot_ownership": [
				{"slot": "Who", "text": who_text},
				{"slot": "What", "text": what_text, "canonical": what_text},
				{"slot": "Where", "text": where_text, "canonical": where_text}
			]
		}
	}


func _missing_who_parse_result() -> Dictionary:
	var result := _full_parse_result("Everyone", "Move", "West")
	var resolution: Dictionary = result["command_resolution"]
	var states: Dictionary = resolution["slot_states"]
	states["who"] = "defaulted"
	resolution["slot_states"] = states
	resolution["slot_ownership"] = [
		{"slot": "What", "text": "move", "canonical": "Move"},
		{"slot": "Where", "text": "west", "canonical": "West"}
	]
	result["command_resolution"] = resolution
	return result


func _replacement_parse_result() -> Dictionary:
	var result := _missing_who_parse_result()
	result["command_data"] = {
		"what": "dodge",
		"where": "movement_region",
		"movement_region": "east"
	}
	var resolution: Dictionary = result["command_resolution"]
	resolution["slot_ownership"] = [
		{"slot": "What", "text": "dodge", "canonical": "Dodge"},
		{"slot": "Where", "text": "east", "canonical": "East"}
	]
	result["command_resolution"] = resolution
	return result


func _fail(message: String) -> void:
	if _failed:
		return

	_failed = true
	push_error(message)
	quit(1)
