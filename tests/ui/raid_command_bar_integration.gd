extends Node

const COMBAT_SCENE := preload("res://scenes/combat_scene.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var combat_scene := COMBAT_SCENE.instantiate()
	get_tree().root.add_child(combat_scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var ui := combat_scene.get_node("UI")
	var command_bar := ui.get_node("RaidCommandBar") as RaidCommandBar
	var legacy_panel := ui.get_node("CommandPanel") as Control
	var boss := combat_scene.get_node("Boss") as Node2D
	var boss_frame := ui.get_node("BossFramePanel") as Control
	var boss_cast_bar := ui.get_node(
		"BossFramePanel/VBoxContainer/BossCastBar"
	) as ProgressBar
	var boss_name_label := ui.get_node(
		"BossFramePanel/VBoxContainer/BossNameLabel"
	) as Label
	var combat_manager := combat_scene.get_node("CombatManager")
	var voice_capture := combat_scene.get_node("VoicePipeline/VoiceCaptureController")
	var voice_transcriber := combat_scene.get_node(
		"VoicePipeline/VoiceTranscriberClient"
	) as VoiceTranscriberClient

	if command_bar == null or not command_bar.visible:
		_fail("The new raid command bar is not visible in combat.")
		return

	if legacy_panel == null or legacy_panel.visible:
		_fail("The legacy command panel is visible during normal raid play.")
		return

	if not command_bar.position.is_equal_approx(Vector2(384.0, 0.0)):
		_fail("The combat command bar is not centered and flush to the top edge.")
		return

	if boss == null or boss_frame == null or not boss_frame.visible:
		_fail("The sprite-anchored boss overlay is not visible in combat.")
		return

	if boss_name_label == null or not boss_name_label.text.contains("/"):
		_fail("The boss overlay does not display numeric health.")
		return

	var original_boss_position := boss.global_position
	var original_boss_scale := boss.scale
	var original_overlay_position := boss_frame.position
	var original_overlay_size := boss_frame.size
	boss.global_position += Vector2(72.0, 38.0)
	await get_tree().process_frame

	if not boss_frame.position.is_equal_approx(
		original_overlay_position + Vector2(72.0, 38.0)
	):
		_fail("The boss overlay did not remain locked to boss movement.")
		return

	boss.scale = Vector2(2.5, 2.5)
	await get_tree().process_frame

	if not boss_frame.size.is_equal_approx(original_overlay_size) or not boss_frame.scale.is_equal_approx(Vector2.ONE):
		_fail("The boss overlay scaled with the boss sprite.")
		return

	boss.set("is_casting", true)
	ui.refresh_boss_frame()

	if boss_cast_bar == null or not boss_cast_bar.visible:
		_fail("The boss overlay did not reveal cast information while casting.")
		return

	boss.set("is_casting", false)
	ui.refresh_boss_frame()

	if boss_cast_bar.visible:
		_fail("The boss overlay kept cast information visible after casting ended.")
		return

	var target_indicator := boss.get_node_or_null("TargetDirectionIndicator") as Node2D

	if target_indicator == null or target_indicator.get_parent() != boss:
		_fail("The boss targeting ring and arrow left world space.")
		return

	boss.global_position = original_boss_position
	boss.scale = original_boss_scale
	await get_tree().process_frame
	var party_members: Array = combat_manager.get("party_members")

	if not await _validate_manual_reference_flow(command_bar, party_members):
		return

	command_bar.display_parsed_command(_old_result())
	await get_tree().create_timer(0.22).timeout
	voice_capture.emit_signal("recording_finished", "user://voice/test.wav")
	await get_tree().create_timer(0.10).timeout

	var who_label := command_bar.get_node("TranscriptionLayer/WhoTranscription") as Label
	var what_label := command_bar.get_node("TranscriptionLayer/WhatTranscription") as Label
	var where_label := command_bar.get_node("TranscriptionLayer/WhereTranscription") as Label

	if who_label.modulate.a >= 1.0 or what_label.modulate.a >= 1.0:
		_fail("A new Whisper submission did not begin simultaneous cleanup.")
		return

	voice_transcriber.transcript_received.emit("move west")
	await get_tree().create_timer(0.22).timeout

	if who_label.visible or not who_label.text.is_empty():
		_fail("The parser's defaulted Who value leaked into transcription display.")
		return

	if what_label.text != "Move" or where_label.text != "West":
		_fail("Completed parse callbacks did not reach the raid command bar.")
		return

	var movement_was_issued := false

	for member_value in party_members:
		var member := member_value as Node

		if member != null and bool(member.get("has_manual_move_order")):
			movement_was_issued = true
			break

	if not movement_was_issued:
		_fail("The voice command stopped reaching normal combat execution.")
		return

	print("Raid command bar combat integration test passed.")
	get_tree().quit(0)


func _validate_manual_reference_flow(
	command_bar: RaidCommandBar,
	party_members: Array
) -> bool:
	command_bar.open_reference_category("who")
	var everyone_button := _find_reference_button(command_bar, "Everyone")

	if everyone_button == null:
		_fail("The combat command bar did not expose Everyone under Who.")
		return false

	everyone_button.pressed.emit()
	await get_tree().create_timer(command_bar.ENTRANCE_DURATION_SECONDS + 0.06).timeout

	var who_label := command_bar.get_node("TranscriptionLayer/WhoTranscription") as Label

	if who_label.text != "Everyone" or String(command_bar.get("_open_category")) != "what":
		_fail("The combat command bar did not animate Everyone and auto-open What.")
		return false

	var move_button := _find_reference_button(command_bar, "Move")

	if move_button == null:
		_fail("The Everyone selection did not expose Move in combat.")
		return false

	move_button.pressed.emit()
	await get_tree().create_timer(command_bar.ENTRANCE_DURATION_SECONDS + 0.06).timeout

	if String(command_bar.get("_open_category")) != "where":
		_fail("The combat command bar did not auto-open Where after Move.")
		return false

	var west_close_button := _find_compact_range_button(command_bar, "West", "Close")

	if west_close_button == null:
		_fail("The Move destinations did not expose West - Close in combat.")
		return false

	west_close_button.pressed.emit()
	await get_tree().create_timer(command_bar.ENTRANCE_DURATION_SECONDS + 0.06).timeout

	var where_label := command_bar.get_node("TranscriptionLayer/WhereTranscription") as Label

	if command_bar.is_open() or where_label.text != "West - Close":
		_fail("The completed manual selection did not persist and close its browser.")
		return false

	for member_value in party_members:
		var member := member_value as Node

		if member != null and bool(member.get("has_manual_move_order")):
			_fail("Browsing a manual command unexpectedly issued a combat order.")
			return false

	command_bar.notify_transcription_started()
	await get_tree().create_timer(command_bar.FADE_DURATION_SECONDS + 0.06).timeout
	return true


func _find_reference_button(command_bar: RaidCommandBar, button_text: String) -> Button:
	var entries := command_bar.get("_reference_entries") as VBoxContainer

	for child in entries.find_children("*", "Button", true, false):
		var button := child as Button

		if button != null and button.text == button_text:
			return button

	return null


func _find_compact_range_button(
	command_bar: RaidCommandBar,
	direction_text: String,
	range_text: String
) -> Button:
	var entries := command_bar.get("_reference_entries") as VBoxContainer

	for child in entries.get_children():
		var row := child as HBoxContainer

		if row == null or row.get_child_count() < 2:
			continue

		var direction := row.get_child(0) as Label

		if direction == null or direction.text != direction_text + " -":
			continue

		for row_child in row.get_children():
			var button := row_child as Button

			if button != null and button.text == range_text:
				return button

	return null


func _old_result() -> Dictionary:
	return {
		"ok": true,
		"command_data": {
			"what": "move",
			"where": "movement_region",
			"movement_region": "south"
		},
		"who_resolution": {"who_text": "everyone"},
		"command_resolution": {
			"slot_states": {
				"who": "explicit",
				"what": "explicit",
				"where": "explicit",
				"when": "defaulted"
			},
			"slot_ownership": [
				{"slot": "Who", "text": "everyone"},
				{"slot": "What", "text": "move", "canonical": "Move"},
				{"slot": "Where", "text": "south", "canonical": "South"}
			]
		}
	}


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
