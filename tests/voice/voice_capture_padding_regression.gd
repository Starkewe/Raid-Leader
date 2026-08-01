extends SceneTree

const AUDIO_BLOCK_FRAMES := 512
const PADDED_ZERO_FRAMES := 1536
const KEPT_ZERO_FRAMES := 16
const SAMPLE_RATE := 48000
const MINIMUM_RECORD_SECONDS := 0.25
const STALLED_CAPTURE_FRAMES := 720


func _init() -> void:
	var controller := VoiceCaptureController.new()
	controller.hard_zero_threshold = 0.000001
	controller.max_hard_zero_run_kept = KEPT_ZERO_FRAMES
	controller.min_record_seconds = MINIMUM_RECORD_SECONDS

	var padded_frames := PackedVector2Array()
	_append_repeated_frame(padded_frames, Vector2(0.25, 0.25), AUDIO_BLOCK_FRAMES)
	_append_repeated_frame(padded_frames, Vector2.ZERO, PADDED_ZERO_FRAMES)
	_append_repeated_frame(padded_frames, Vector2(-0.25, -0.25), AUDIO_BLOCK_FRAMES)

	var cleaned_frames: PackedVector2Array = controller._remove_hard_zero_padding(padded_frames)
	var expected_frame_count := (AUDIO_BLOCK_FRAMES * 2) + KEPT_ZERO_FRAMES

	if cleaned_frames.size() != expected_frame_count:
		_fail("Expected %d cleaned frames, got %d." % [expected_frame_count, cleaned_frames.size()])
		return

	if cleaned_frames[0] != Vector2(0.25, 0.25):
		_fail("The first audio block was not preserved.")
		return

	if cleaned_frames[AUDIO_BLOCK_FRAMES + KEPT_ZERO_FRAMES] != Vector2(-0.25, -0.25):
		_fail("The second audio block was not preserved after compacting padding.")
		return

	var silent_frames := PackedVector2Array()
	_append_repeated_frame(silent_frames, Vector2.ZERO, PADDED_ZERO_FRAMES)

	if not controller._remove_hard_zero_padding(silent_frames).is_empty():
		_fail("An all-zero capture should still be treated as silent.")
		return

	var stalled_capture := PackedVector2Array()
	_append_repeated_frame(stalled_capture, Vector2(0.00001, 0.00001), STALLED_CAPTURE_FRAMES)

	if controller._has_minimum_recording_duration(stalled_capture, SAMPLE_RATE):
		_fail("A 15 ms stalled capture must not be sent to Whisper.")
		return

	var minimum_capture := PackedVector2Array()
	_append_repeated_frame(
		minimum_capture,
		Vector2(0.25, 0.25),
		int(SAMPLE_RATE * MINIMUM_RECORD_SECONDS)
	)

	if not controller._has_minimum_recording_duration(minimum_capture, SAMPLE_RATE):
		_fail("A capture meeting the minimum duration should remain valid.")
		return

	var focus_failures: Array[String] = []
	controller.recording_failed.connect(func(reason: String) -> void:
		focus_failures.append(reason)
	)
	controller.set("_is_recording", true)
	controller.set("_capture_ready", true)
	controller._handle_application_focus_lost()
	controller._handle_application_focus_lost()

	if focus_failures.size() != 1:
		_fail("Repeated focus-loss notifications did not cancel recording idempotently.")
		return

	if bool(controller.get("_is_recording")) or bool(controller.get("_capture_ready")):
		_fail("Voice capture remained active or ready after focus was lost.")
		return

	controller._handle_application_focus_regained()

	if not bool(controller.get("_application_has_focus")) or not bool(
		controller.get("_capture_rearm_pending")
	):
		_fail("Voice capture did not schedule a rearm when focus returned.")
		return

	controller._handle_application_focus_lost()

	if bool(controller.get("_capture_rearm_pending")):
		_fail("A second focus loss did not invalidate the pending capture rearm.")
		return

	controller.free()
	print("Voice capture padding, duration, and focus regression test passed.")
	quit(0)


func _append_repeated_frame(frames: PackedVector2Array, frame: Vector2, count: int) -> void:
	for _index in range(count):
		frames.append(frame)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
