extends Node
class_name VoiceCaptureController

signal recording_started()
signal recording_finished(wav_path: String)
signal recording_failed(reason: String)

@export var remove_capture_padding: bool = true
@export var hard_zero_threshold: float = 0.000001
@export var max_hard_zero_run_kept: int = 16

@export var push_to_talk_action: String = "voice_push_to_talk"
@export var capture_bus_name: String = "VoiceCapture"
@export var mic_player_path: NodePath
@export var transcriber_path: NodePath

@export var min_record_seconds: float = 0.25
@export var max_record_seconds: float = 6.0

@export var normalize_output: bool = true
@export var target_peak: float = 0.85

@export var trim_silence: bool = false
@export var silence_threshold: float = 0.0025
@export var keep_silence_seconds: float = 0.15

var _capture_effect: AudioEffectCapture = null
var _is_recording: bool = false
var _stop_requested: bool = false
var _record_started_at_msec: int = 0
var _recorded_frames: PackedVector2Array = PackedVector2Array()

@onready var _mic_player: AudioStreamPlayer = get_node_or_null(mic_player_path) as AudioStreamPlayer
@onready var _transcriber: VoiceTranscriberClient = get_node_or_null(transcriber_path) as VoiceTranscriberClient


func _ready() -> void:
	ensure_voice_input_action()

	if _mic_player == null:
		recording_failed.emit("VoiceCaptureController is missing a valid AudioStreamPlayer.")
		return

	if _transcriber == null:
		recording_failed.emit("VoiceCaptureController is missing a valid VoiceTranscriberClient.")
		return

	_capture_effect = _get_capture_effect()

	if _capture_effect == null:
		recording_failed.emit("No AudioEffectCapture found on bus '%s'." % capture_bus_name)
		return

	_capture_effect.buffer_length = max_record_seconds + 1.0
	_capture_effect.clear_buffer()

	if _mic_player.stream == null:
		_mic_player.stream = AudioStreamMicrophone.new()

	_mic_player.bus = capture_bus_name

	if not _mic_player.playing:
		_mic_player.play()

	print("Voice mic player actual bus: ", _mic_player.bus)
	print("Voice capture bus name: ", capture_bus_name)
	print("Voice capture bus index: ", AudioServer.get_bus_index(capture_bus_name))
	print("Voice capture bus effect count: ", AudioServer.get_bus_effect_count(AudioServer.get_bus_index(capture_bus_name)))


func _process(_delta: float) -> void:
	if _capture_effect == null:
		return

	var frames_available := _capture_effect.get_frames_available()

	if frames_available <= 0:
		return

	var frames := _capture_effect.get_buffer(frames_available)

	if not _is_recording:
		return

	_recorded_frames.append_array(frames)

	var sample_rate := int(AudioServer.get_mix_rate())
	var max_frames := int(max_record_seconds * sample_rate)

	var elapsed_seconds: float = float(Time.get_ticks_msec() - _record_started_at_msec) / 1000.0

	if elapsed_seconds >= max_record_seconds:
		print("Voice recording hit max duration. Stopping.")
		stop_recording_and_transcribe()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(push_to_talk_action):
		start_recording()

	if event.is_action_released(push_to_talk_action):
		stop_recording_and_transcribe()


func ensure_voice_input_action() -> void:
	if InputMap.has_action(push_to_talk_action):
		return

	InputMap.add_action(push_to_talk_action)

	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	InputMap.action_add_event(push_to_talk_action, event)


func start_recording() -> void:
	if _capture_effect == null:
		recording_failed.emit("Missing capture effect.")
		return

	if _transcriber == null:
		recording_failed.emit("Missing transcriber.")
		return

	if _is_recording:
		return

	if _transcriber.is_busy():
		recording_failed.emit("Transcriber is busy.")
		return

	_stop_requested = false
	_recorded_frames.clear()

	# Flush old frames so we do not save stale buffer data.
	_capture_effect.clear_buffer()
	_discard_capture_buffer()

	_is_recording = true
	_record_started_at_msec = Time.get_ticks_msec()

	recording_started.emit()
	print("Voice recording started.")


func stop_recording_and_transcribe() -> void:
	if not _is_recording:
		return

	if _stop_requested:
		return

	_stop_requested = true
	call_deferred("_finish_recording_and_transcribe")


func _finish_recording_and_transcribe() -> void:
	if not _is_recording:
		return

	_drain_capture_buffer()

	_is_recording = false
	_stop_requested = false

	var elapsed_seconds := float(Time.get_ticks_msec() - _record_started_at_msec) / 1000.0

	if elapsed_seconds < min_record_seconds:
		recording_failed.emit("Recording was too short.")
		return

	if _recorded_frames.is_empty():
		recording_failed.emit("No audio frames were captured.")
		return

	var sample_rate: int = int(AudioServer.get_mix_rate())
	var inferred_capture_rate: int = int(float(_recorded_frames.size()) / elapsed_seconds)

	print("Voice project sample rate: ", sample_rate)
	print("Voice inferred capture rate: ", inferred_capture_rate)

	var frames_to_save: PackedVector2Array = _recorded_frames

	if remove_capture_padding:
		var padded_frame_count: int = frames_to_save.size()
		var cleaned_frames: PackedVector2Array = _remove_hard_zero_padding(frames_to_save)

		print("Voice padding cleanup frames before: ", padded_frame_count)
		print("Voice padding cleanup frames after: ", cleaned_frames.size())
		print("Voice padding cleanup seconds after: ", float(cleaned_frames.size()) / float(sample_rate))

		if cleaned_frames.is_empty():
			recording_failed.emit("Captured audio was silent.")
			return
		else:
			frames_to_save = cleaned_frames

	if trim_silence:
		frames_to_save = _trim_silence(frames_to_save, sample_rate)

	if frames_to_save.is_empty():
		recording_failed.emit("Captured audio was silent after trimming.")
		return

	var voice_dir := "user://voice"
	var global_voice_dir := ProjectSettings.globalize_path(voice_dir)
	DirAccess.make_dir_recursive_absolute(global_voice_dir)

	var wav_path := voice_dir + "/latest_command.wav"
	var save_error := _save_mono_wav(wav_path, frames_to_save, sample_rate)

	if save_error != OK:
		recording_failed.emit("Failed to save recording. Error: %s" % save_error)
		return

	var recording_seconds := float(frames_to_save.size()) / float(sample_rate)

	recording_finished.emit(wav_path)

	print("Voice elapsed seconds: ", elapsed_seconds)
	print("Voice saved frames: ", frames_to_save.size())
	print("Voice saved seconds: ", recording_seconds)
	print("Voice sample rate: ", sample_rate)
	print("Voice recording saved: ", wav_path)
	print("Voice recording global path: ", ProjectSettings.globalize_path(wav_path))

	_transcriber.transcribe_wav(wav_path)
func _remove_hard_zero_padding(frames: PackedVector2Array) -> PackedVector2Array:
	if frames.is_empty():
		return frames

	var cleaned_frames := PackedVector2Array()
	var hard_zero_run: int = 0
	var zero_frames_to_keep: int = maxi(max_hard_zero_run_kept, 0)
	var found_audio: bool = false

	for frame in frames:
		if _is_hard_zero_frame(frame):
			if hard_zero_run < zero_frames_to_keep:
				cleaned_frames.append(frame)
			hard_zero_run += 1
			continue

		hard_zero_run = 0
		found_audio = true
		cleaned_frames.append(frame)

	if not found_audio:
		return PackedVector2Array()

	return cleaned_frames


func _is_hard_zero_frame(frame: Vector2) -> bool:
	return absf(frame.x) <= hard_zero_threshold and absf(frame.y) <= hard_zero_threshold

func _discard_capture_buffer() -> void:
	if _capture_effect == null:
		return

	var frames_available := _capture_effect.get_frames_available()

	if frames_available > 0:
		_capture_effect.get_buffer(frames_available)


func _drain_capture_buffer() -> void:
	if _capture_effect == null:
		return

	var frames_available := _capture_effect.get_frames_available()

	if frames_available <= 0:
		return

	var frames := _capture_effect.get_buffer(frames_available)
	_recorded_frames.append_array(frames)


func _trim_silence(frames: PackedVector2Array, sample_rate: int) -> PackedVector2Array:
	if frames.is_empty():
		return frames

	var first_active: int = -1
	var last_active: int = -1

	for i in range(frames.size()):
		var frame: Vector2 = frames[i]
		var mono: float = absf((frame.x + frame.y) * 0.5)

		if mono >= silence_threshold:
			if first_active == -1:
				first_active = i

			last_active = i

	if first_active == -1 or last_active == -1:
		return PackedVector2Array()

	var padding: int = int(keep_silence_seconds * float(sample_rate))
	var start_index: int = maxi(0, first_active - padding)
	var end_index: int = mini(frames.size(), last_active + padding)

	return _copy_frame_range(frames, start_index, end_index)


func _copy_frame_range(frames: PackedVector2Array, start_index: int, end_index: int) -> PackedVector2Array:
	var result := PackedVector2Array()

	for i in range(start_index, end_index):
		result.append(frames[i])

	return result


func _get_capture_effect() -> AudioEffectCapture:
	var bus_index := AudioServer.get_bus_index(capture_bus_name)

	if bus_index == -1:
		return null

	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)

		if effect is AudioEffectCapture:
			return effect

	return null


func _save_mono_wav(path: String, frames: PackedVector2Array, sample_rate: int) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return FileAccess.get_open_error()

	file.big_endian = false

	var channel_count := 1
	var bits_per_sample := 16
	var bytes_per_sample := bits_per_sample / 8
	var data_size := frames.size() * channel_count * bytes_per_sample
	var byte_rate := sample_rate * channel_count * bytes_per_sample
	var block_align := channel_count * bytes_per_sample

	var gain := 1.0

	if normalize_output:
		var peak := _get_peak_mono_amplitude(frames)

		if peak > 0.001:
			gain = target_peak / peak

	_write_ascii(file, "RIFF")
	file.store_32(36 + data_size)
	_write_ascii(file, "WAVE")

	_write_ascii(file, "fmt ")
	file.store_32(16)
	file.store_16(1) # PCM
	file.store_16(channel_count)
	file.store_32(sample_rate)
	file.store_32(byte_rate)
	file.store_16(block_align)
	file.store_16(bits_per_sample)

	_write_ascii(file, "data")
	file.store_32(data_size)

	for frame in frames:
		var mono_sample := (frame.x + frame.y) * 0.5
		mono_sample *= gain

		var clamped_sample: float = clamp(mono_sample, -1.0, 1.0)
		var int_sample := int(clamped_sample * 32767.0)

		if int_sample < 0:
			int_sample = 65536 + int_sample

		file.store_16(int_sample)

	file.close()

	return OK


func _get_peak_mono_amplitude(frames: PackedVector2Array) -> float:
	var peak: float = 0.0

	for i in range(frames.size()):
		var frame: Vector2 = frames[i]
		var mono: float = absf((frame.x + frame.y) * 0.5)

		if mono > peak:
			peak = mono

	return peak


func _write_ascii(file: FileAccess, text: String) -> void:
	file.store_buffer(text.to_ascii_buffer())
func fail_recording(reason: String) -> void:
	print("Voice recording failed: ", reason)
	recording_failed.emit(reason)
