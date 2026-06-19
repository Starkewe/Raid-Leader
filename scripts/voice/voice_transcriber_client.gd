extends Node
class_name VoiceTranscriberClient

signal transcript_received(text: String)
signal transcription_failed(reason: String)

@export_file("*.exe") var whisper_cli_path: String = "E:/Raid Leader/tools/whisper.cpp/build/bin/Release/whisper-cli.exe"

@export var use_settings_menu_model: bool = true
@export_file("*.bin") var fallback_model_path: String = "E:/Raid Leader/tools/whisper.cpp/models/ggml-base.en.bin"

@export var max_queued_transcriptions: int = 3

var _thread: Thread = null
var _is_transcribing: bool = false
var _pending_wav_paths: Array[String] = []
var _active_wav_path: String = ""


func is_busy() -> bool:
	return not can_accept_transcription()
func is_transcribing() -> bool:
	return _is_transcribing
func can_accept_transcription() -> bool:
	return _pending_wav_paths.size() < max_queued_transcriptions
	
func get_active_model_path() -> String:
	if use_settings_menu_model:
		return GameState.get_selected_speech_to_text_model_path()

	return fallback_model_path

func transcribe_wav(wav_path: String) -> void:
	if wav_path.is_empty():
		transcription_failed.emit("Missing WAV path.")
		return

	if not FileAccess.file_exists(wav_path):
		transcription_failed.emit("WAV file does not exist: %s" % wav_path)
		return

	if not FileAccess.file_exists(whisper_cli_path):
		transcription_failed.emit("whisper-cli.exe was not found: %s" % whisper_cli_path)
		return

	if _pending_wav_paths.size() >= max_queued_transcriptions:
		transcription_failed.emit("Transcription queue is full.")
		return

	var queued_wav_path := _copy_wav_to_queue_file(wav_path)

	if queued_wav_path.is_empty():
		transcription_failed.emit("Failed to copy WAV into transcription queue.")
		return

	_pending_wav_paths.append(queued_wav_path)

	print("Queued voice transcription:", queued_wav_path, "Queue size:", _pending_wav_paths.size())

	_start_next_transcription_if_needed()
func _start_next_transcription_if_needed() -> void:
	if _is_transcribing:
		return

	if _pending_wav_paths.is_empty():
		return

	var next_wav_path := String(_pending_wav_paths.pop_front())

	if not FileAccess.file_exists(next_wav_path):
		transcription_failed.emit("Queued WAV file does not exist: %s" % next_wav_path)
		call_deferred("_start_next_transcription_if_needed")
		return

	var active_model_path := get_active_model_path()

	if not FileAccess.file_exists(active_model_path):
		transcription_failed.emit("Whisper model was not found: %s" % active_model_path)
		call_deferred("_start_next_transcription_if_needed")
		return

	_is_transcribing = true
	_active_wav_path = next_wav_path

	_thread = Thread.new()
	_thread.start(_run_whisper.bind(next_wav_path, active_model_path))
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
func _run_whisper(wav_path: String, active_model_path: String) -> void:
	var global_wav_path := _globalize_if_needed(wav_path)

	var output_dir := "user://voice"
	var global_output_dir := ProjectSettings.globalize_path(output_dir)

	DirAccess.make_dir_recursive_absolute(global_output_dir)

	var output_prefix := output_dir + "/last_transcription"
	var global_output_prefix := ProjectSettings.globalize_path(output_prefix)
	var global_output_txt := global_output_prefix + ".txt"

	if FileAccess.file_exists(global_output_txt):
		DirAccess.remove_absolute(global_output_txt)

	var output: Array = []

	var args := PackedStringArray([
		"-m", active_model_path,
		"-f", global_wav_path,
		"-l", "en",
		"-nt",
		"-np",
		"-otxt",
		"-of", global_output_prefix
	])
	print("Running Whisper model: ", active_model_path)
	var exit_code := OS.execute(whisper_cli_path, args, output, true, false)
	var raw_output := "\n".join(output)

	var transcript := ""

	if exit_code == 0 and FileAccess.file_exists(global_output_txt):
		transcript = _read_text_file(global_output_txt)

	if transcript.strip_edges().is_empty():
		transcript = _clean_whisper_output(raw_output)

	call_deferred("_finish_transcription", exit_code, transcript, raw_output)


func _finish_transcription(exit_code: int, transcript: String, raw_output: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

	var finished_wav_path := _active_wav_path

	_active_wav_path = ""
	_is_transcribing = false

	_delete_file_if_exists(finished_wav_path)

	if exit_code != 0:
		transcription_failed.emit("whisper-cli failed with exit code %d: %s" % [exit_code, raw_output])
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


func _clean_whisper_output(raw_output: String) -> String:
	var text := raw_output.strip_edges()

	text = text.replace("\r", "\n")
	text = _strip_read_audio_data_prefix(text)

	var lines := text.split("\n", false)
	var transcript_parts: Array[String] = []

	for line in lines:
		var cleaned := line.strip_edges()

		if cleaned.is_empty():
			continue

		if _is_whisper_diagnostic_line(cleaned):
			continue

		transcript_parts.append(cleaned)

	return " ".join(transcript_parts).strip_edges()


func _strip_read_audio_data_prefix(text: String) -> String:
	var marker := "read_audio_data: trying to decode with miniaudio"
	var marker_index := text.rfind(marker)

	if marker_index == -1:
		return text

	var transcript_start := marker_index + marker.length()

	if transcript_start >= text.length():
		return ""

	return text.substr(transcript_start).strip_edges()


func _is_whisper_diagnostic_line(line: String) -> bool:
	if line.begins_with("whisper_"):
		return true

	if line.begins_with("system_info"):
		return true

	if line.begins_with("main:"):
		return true

	if line.begins_with("read_audio_data:"):
		return true

	if line.begins_with("ggml_"):
		return true

	if line.contains("load time"):
		return true

	if line.contains("sample time"):
		return true

	if line.contains("encode time"):
		return true

	if line.contains("decode time"):
		return true

	if line.contains("total time"):
		return true

	return false


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

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

	_delete_file_if_exists(_active_wav_path)
	_active_wav_path = ""

	for queued_wav_path in _pending_wav_paths:
		_delete_file_if_exists(String(queued_wav_path))

	_pending_wav_paths.clear()
	_is_transcribing = false
