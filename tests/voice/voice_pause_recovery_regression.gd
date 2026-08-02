extends Node


class TestCaptureController extends VoiceCaptureController:
	var finish_calls: int = 0


	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_tree_was_paused = _is_scene_tree_paused()


	func _finish_recording_and_transcribe() -> void:
		if not _is_recording:
			return

		finish_calls += 1
		_reset_recording_state()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	if not await _test_capture_pause_rules():
		return

	if not _test_transcription_pause_rules():
		return

	print("Voice pause recovery regression test passed.")
	get_tree().quit(0)


func _test_capture_pause_rules() -> bool:
	var controller := TestCaptureController.new()
	var failures: Array[String] = []
	controller.recording_failed.connect(func(reason: String) -> void:
		failures.append(reason)
	)
	add_child(controller)

	controller._is_recording = true
	controller._capture_ready = true
	get_tree().paused = true
	controller._update_tree_pause_state()

	if controller._is_recording or controller._capture_ready:
		return _fail("Opening the raid menu did not cancel a held-V recording.")

	if failures.size() != 1 or controller.finish_calls != 0:
		return _fail("A held-V recording was finalized instead of cancelled once.")

	get_tree().paused = false
	controller._update_tree_pause_state()
	controller._capture_rearm_pending = false

	controller._is_recording = true
	controller.stop_recording_and_transcribe()

	if not controller._stop_requested:
		return _fail("Releasing V did not commit the active recording.")

	get_tree().paused = true
	controller._update_tree_pause_state()

	if controller.finish_calls != 1 or failures.size() != 1:
		return _fail("Escape cancelled a recording that was released first.")

	get_tree().paused = false
	controller._update_tree_pause_state()
	await get_tree().process_frame

	if controller.finish_calls != 1:
		return _fail("Deferred finalization ran twice after the raid menu opened.")

	controller._capture_rearm_pending = false
	controller._is_recording = true
	get_tree().paused = true
	var release_event := InputEventAction.new()
	release_event.action = controller.push_to_talk_action
	release_event.pressed = false
	controller._unhandled_input(release_event)

	if controller._is_recording or failures.size() != 2:
		return _fail("Releasing V inside the raid menu did not cancel the input.")

	controller._update_tree_pause_state()
	controller._application_has_focus = false
	controller._capture_rearm_pending = false
	controller._handle_application_focus_regained()

	if controller._capture_rearm_pending:
		return _fail("Microphone capture rearmed while the raid menu was open.")

	get_tree().paused = false
	controller._update_tree_pause_state()

	if not controller._capture_rearm_pending:
		return _fail("Closing the raid menu did not schedule a fresh microphone rearm.")

	controller.queue_free()
	return true


func _test_transcription_pause_rules() -> bool:
	var transcriber := VoiceTranscriberClient.new()
	var transcripts: Array[String] = []
	var failures: Array[String] = []
	transcriber.transcript_received.connect(func(text: String) -> void:
		transcripts.append(text)
	)
	transcriber.transcription_failed.connect(func(reason: String) -> void:
		failures.append(reason)
	)
	add_child(transcriber)

	_prepare_active_transcription(transcriber, 2.0)
	get_tree().paused = true
	transcriber._complete_or_hold_transcription(0, "move west", "", true)
	transcriber._process(5.0)

	if not transcripts.is_empty() or not transcriber._is_transcribing:
		return _fail("A completed command escaped while the raid menu was open.")

	get_tree().paused = false
	transcriber._process(1.0)

	if not transcripts.is_empty():
		return _fail("Pause-time transcription work was not paid back after resume.")

	transcriber._process(1.01)

	if transcripts != ["move west"]:
		return _fail("The held command was not delivered after its full recovery delay.")

	_prepare_active_transcription(transcriber, 2.0)
	transcriber._complete_or_hold_transcription(0, "spread", "", false)
	transcriber._process(0.75)
	get_tree().paused = true
	transcriber._process(8.0)
	get_tree().paused = false
	transcriber._process(1.24)

	if transcripts.size() != 1:
		return _fail("A second menu pause advanced the held delivery timer.")

	transcriber._process(0.02)

	if transcripts != ["move west", "spread"]:
		return _fail("The held delivery timer did not resume with gameplay.")

	_prepare_active_transcription(transcriber, 3.0)
	get_tree().paused = true
	transcriber._complete_or_hold_transcription(-1, "", "test failure", true)
	transcriber._process(10.0)

	if not failures.is_empty():
		return _fail("A transcription failure was reported while the menu was open.")

	get_tree().paused = false
	transcriber._process(0.01)

	if failures.size() != 1:
		return _fail("A held failure was not reported immediately after resume.")

	transcriber.transcription_ttl_seconds = 2.0
	transcriber._gameplay_clock_seconds = 0.0
	transcriber._pending_transcriptions = [{
		"wav_path": "user://voice/nonexistent_pause_test.wav",
		"queued_at_gameplay_seconds": 0.0
	}]
	get_tree().paused = true
	transcriber._process(20.0)
	transcriber._prune_stale_transcriptions()

	if transcriber._pending_transcriptions.size() != 1:
		return _fail("Menu time incorrectly expired a queued voice command.")

	get_tree().paused = false
	transcriber._process(2.1)
	transcriber._prune_stale_transcriptions()

	if not transcriber._pending_transcriptions.is_empty():
		return _fail("Unpaused gameplay time did not expire a stale voice command.")

	transcriber.queue_free()
	return true


func _prepare_active_transcription(
	transcriber: VoiceTranscriberClient,
	paused_processing_seconds: float
) -> void:
	transcriber._is_transcribing = true
	transcriber._active_process_id = 1
	transcriber._active_queued_at_gameplay_seconds = transcriber._gameplay_clock_seconds
	transcriber._active_paused_processing_seconds = paused_processing_seconds
	transcriber._held_completion.clear()
	transcriber._held_delivery_remaining_seconds = 0.0


func _fail(message: String) -> bool:
	push_error(message)
	get_tree().paused = false
	get_tree().quit(1)
	return false
