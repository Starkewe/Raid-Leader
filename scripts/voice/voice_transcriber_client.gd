extends Node
class_name VoiceTranscriberClient

signal transcript_received(text: String)
signal transcription_failed(reason: String)

@export_file var whisper_cli_path_override: String = ""

@export var use_settings_menu_model: bool = true
@export_file("*.bin") var fallback_model_path: String = "res://tools/whisper.cpp/models/ggml-base.en.bin"

@export var max_queued_transcriptions: int = 3
@export var transcription_ttl_seconds: float = 8.0
@export var transcription_process_timeout_seconds: float = 15.0

var _is_transcribing: bool = false
var _pending_transcriptions: Array[Dictionary] = []
var _active_wav_path: String = ""
var _active_queued_at_msec: int = 0
var _active_process_started_at_msec: int = 0
var _active_process_id: int = 0
var _active_output_txt_path: String = ""


func _process(_delta: float) -> void:
	if _active_process_id <= 0:
		return

	if OS.is_process_running(_active_process_id):
		var process_age := float(
			Time.get_ticks_msec() - _active_process_started_at_msec
		) / 1000.0

		if transcription_process_timeout_seconds > 0.0 and process_age > transcription_process_timeout_seconds:
			OS.kill(_active_process_id)
			_finish_transcription(-1, "", "Whisper process timed out.")

		return

	var transcript := ""

	if FileAccess.file_exists(_active_output_txt_path):
		transcript = _read_text_file(_active_output_txt_path)

	var result_code := 0 if not transcript.strip_edges().is_empty() else 1
	_finish_transcription(result_code, transcript, "Whisper did not create a transcript file.")


func is_busy() -> bool:
	return not can_accept_transcription()
func is_transcribing() -> bool:
	return _is_transcribing
func can_accept_transcription() -> bool:
	_prune_stale_transcriptions()
	return _pending_transcriptions.size() < max_queued_transcriptions

func get_active_model_path() -> String:
	if use_settings_menu_model:
		return GameState.get_selected_speech_to_text_model_path()

	return fallback_model_path


func get_active_cli_path() -> String:
	if not whisper_cli_path_override.strip_edges().is_empty():
		return whisper_cli_path_override

	return GameState.get_whisper_cli_path()

func transcribe_wav(wav_path: String) -> void:
	if wav_path.is_empty():
		transcription_failed.emit("Missing WAV path.")
		return

	if not FileAccess.file_exists(wav_path):
		transcription_failed.emit("WAV file does not exist: %s" % wav_path)
		return

	var active_cli_path := get_active_cli_path()

	if not FileAccess.file_exists(active_cli_path):
		transcription_failed.emit("Whisper CLI was not found: %s" % active_cli_path)
		return

	_prune_stale_transcriptions()

	if _pending_transcriptions.size() >= max_queued_transcriptions:
		transcription_failed.emit("Transcription queue is full.")
		return

	var queued_wav_path := _copy_wav_to_queue_file(wav_path)

	if queued_wav_path.is_empty():
		transcription_failed.emit("Failed to copy WAV into transcription queue.")
		return

	_pending_transcriptions.append({
		"wav_path": queued_wav_path,
		"queued_at_msec": Time.get_ticks_msec()
	})

	print("Queued voice transcription:", queued_wav_path, "Queue size:", _pending_transcriptions.size())

	_start_next_transcription_if_needed()
func _start_next_transcription_if_needed() -> void:
	if _is_transcribing:
		return

	_prune_stale_transcriptions()

	if _pending_transcriptions.is_empty():
		return

	var next_request: Dictionary = _pending_transcriptions.pop_front()
	var next_wav_path := String(next_request.get("wav_path", ""))
	var queued_at_msec := int(next_request.get("queued_at_msec", 0))

	if not FileAccess.file_exists(next_wav_path):
		transcription_failed.emit("Queued WAV file does not exist: %s" % next_wav_path)
		call_deferred("_start_next_transcription_if_needed")
		return

	var active_model_path := get_active_model_path()

	if not FileAccess.file_exists(active_model_path):
		transcription_failed.emit("Whisper model was not found: %s" % active_model_path)
		_delete_file_if_exists(next_wav_path)
		call_deferred("_start_next_transcription_if_needed")
		return

	var process_id := _start_whisper_process(
		next_wav_path,
		active_model_path,
		get_active_cli_path()
	)

	if process_id <= 0:
		_delete_file_if_exists(next_wav_path)
		_delete_file_if_exists(_active_output_txt_path)
		_active_output_txt_path = ""
		transcription_failed.emit("Could not start the Whisper process.")
		call_deferred("_start_next_transcription_if_needed")
		return

	_is_transcribing = true
	_active_wav_path = next_wav_path
	_active_queued_at_msec = queued_at_msec
	_active_process_started_at_msec = Time.get_ticks_msec()
	_active_process_id = process_id
func _copy_wav_to_queue_file(wav_path: String) -> String:
	var global_source_path := _globalize_if_needed(wav_path)

	if not FileAccess.file_exists(global_source_path):
		return ""

	var source_file := FileAccess.open(global_source_path, FileAccess.READ)

	if source_file == null:
		return ""

	var wav_data := source_file.get_buffer(source_file.get_length())
	source_file.close()

	var queue_dir := "user://voice/queued"
	var global_queue_dir := ProjectSettings.globalize_path(queue_dir)

	DirAccess.make_dir_recursive_absolute(global_queue_dir)

	var queued_path := queue_dir + "/voice_command_%d.wav" % Time.get_ticks_usec()
	var global_queued_path := ProjectSettings.globalize_path(queued_path)

	var queued_file := FileAccess.open(global_queued_path, FileAccess.WRITE)

	if queued_file == null:
		return ""

	queued_file.store_buffer(wav_data)
	queued_file.close()

	return queued_path
func _start_whisper_process(
	wav_path: String,
	active_model_path: String,
	active_cli_path: String
) -> int:
	var global_wav_path := _globalize_if_needed(wav_path)
	var global_model_path := _globalize_if_needed(active_model_path)
	var global_cli_path := _globalize_if_needed(active_cli_path)

	var output_dir := "user://voice"
	var global_output_dir := ProjectSettings.globalize_path(output_dir)

	DirAccess.make_dir_recursive_absolute(global_output_dir)

	var output_prefix := output_dir + "/transcription_%d" % Time.get_ticks_usec()
	var global_output_prefix := ProjectSettings.globalize_path(output_prefix)
	var global_output_txt := global_output_prefix + ".txt"
	_active_output_txt_path = global_output_txt

	if FileAccess.file_exists(global_output_txt):
		DirAccess.remove_absolute(global_output_txt)

	var args := PackedStringArray([
		"-m", global_model_path,
		"-f", global_wav_path,
		"-l", "en",
		"-nt",
		"-np",
		"-otxt",
		"-of", global_output_prefix
	])
	print("Running Whisper model: ", active_model_path)
	return OS.create_process(global_cli_path, args, false)


func _finish_transcription(exit_code: int, transcript: String, raw_output: String) -> void:
	var finished_wav_path := _active_wav_path
	var active_age_seconds := float(Time.get_ticks_msec() - _active_queued_at_msec) / 1000.0

	_active_wav_path = ""
	_active_queued_at_msec = 0
	_active_process_started_at_msec = 0
	_active_process_id = 0
	_is_transcribing = false

	_delete_file_if_exists(finished_wav_path)
	_delete_file_if_exists(_active_output_txt_path)
	_active_output_txt_path = ""

	if exit_code != 0:
		transcription_failed.emit("Whisper transcription failed: " + raw_output)
		_start_next_transcription_if_needed()
		return

	if active_age_seconds > transcription_ttl_seconds:
		transcription_failed.emit("Discarded stale voice command after %.1f seconds." % active_age_seconds)
		_start_next_transcription_if_needed()
		return

	var text := transcript.strip_edges()

	if text.is_empty():
		transcription_failed.emit("Whisper returned empty transcript.")
		_start_next_transcription_if_needed()
		return

	print("Voice transcript: ", text)
	transcript_received.emit(text)

	_start_next_transcription_if_needed()

func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return ""

	var text := file.get_as_text()
	file.close()

	return text


func _globalize_if_needed(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)

	return path

func _delete_file_if_exists(path: String) -> void:
	if path.is_empty():
		return

	var global_path := _globalize_if_needed(path)

	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)


func _prune_stale_transcriptions() -> void:
	if transcription_ttl_seconds <= 0.0:
		return

	var now_msec := Time.get_ticks_msec()
	var fresh_requests: Array[Dictionary] = []

	for request in _pending_transcriptions:
		var age_seconds := float(now_msec - int(request.get("queued_at_msec", 0))) / 1000.0

		if age_seconds > transcription_ttl_seconds:
			_delete_file_if_exists(String(request.get("wav_path", "")))
			continue

		fresh_requests.append(request)

	_pending_transcriptions = fresh_requests

func _exit_tree() -> void:
	if _active_process_id > 0 and OS.is_process_running(_active_process_id):
		OS.kill(_active_process_id)

	_active_process_id = 0

	_delete_file_if_exists(_active_wav_path)
	_delete_file_if_exists(_active_output_txt_path)
	_active_wav_path = ""
	_active_output_txt_path = ""

	for request in _pending_transcriptions:
		_delete_file_if_exists(String(request.get("wav_path", "")))

	_pending_transcriptions.clear()
	_is_transcribing = false
