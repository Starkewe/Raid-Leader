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

	var party_members: Array = combat_manager.get("party_members")
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
