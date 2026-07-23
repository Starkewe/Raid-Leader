extends SceneTree

const AUDIO_BLOCK_FRAMES := 512
const PADDED_ZERO_FRAMES := 1536
const KEPT_ZERO_FRAMES := 16


func _init() -> void:
	var controller := VoiceCaptureController.new()
	controller.hard_zero_threshold = 0.000001
	controller.max_hard_zero_run_kept = KEPT_ZERO_FRAMES

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

	print("Voice capture padding regression test passed.")
	quit(0)


func _append_repeated_frame(frames: PackedVector2Array, frame: Vector2, count: int) -> void:
	for _index in range(count):
		frames.append(frame)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
