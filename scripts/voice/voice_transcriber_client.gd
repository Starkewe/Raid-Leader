extends Node
class_name VoiceTranscriberClient

signal transcription_started()
signal transcription_completed(text: String)
signal transcript_received(transcript: String)
signal transcription_failed(reason: String)

@export var whisper_exe_path: String = "E:/Raid Leader/tools/whisper.cpp/build/bin/Release/whisper-cli.exe"
@export var whisper_model_path: String = "E:/Raid Leader/tools/whisper.cpp/ggml-base.en.bin"

var _thread: Thread = null
var _busy: bool = false


func is_busy() -> bool:
	return _busy


func transcribe_wav(wav_path: String) -> void:
	if _busy:
		transcription_failed.emit("Transcriber is already busy.")
		return

	if wav_path.is_empty():
		transcription_failed.emit("Missing WAV path.")
		return

	_busy = true
	transcription_started.emit()

	_thread = Thread.new()
	_thread.start(_transcribe_thread.bind(wav_path))


func _transcribe_thread(wav_path: String) -> void:
	var global_wav_path := _globalize_if_needed(wav_path)

	var global_voice_dir := ProjectSettings.globalize_path("user://voice")
	DirAccess.make_dir_recursive_absolute(global_voice_dir)

	var output_prefix := ProjectSettings.globalize_path("user://voice/last_transcription")
	var output_txt_path := output_prefix + ".txt"

	if FileAccess.file_exists(output_txt_path):
		DirAccess.remove_absolute(output_txt_path)

	var args := PackedStringArray([
		"-m", whisper_model_path,
		"-f", global_wav_path,
		"-l", "en",
		"-nt",
		"-np",
		"-otxt",
		"-of", output_prefix
	])

	var output: Array = []
	var exit_code := OS.execute(whisper_exe_path, args, output, true, false)

	var text := ""

	if exit_code == 0 and FileAccess.file_exists(output_txt_path):
		var file := FileAccess.open(output_txt_path, FileAccess.READ)

		if file != null:
			text = file.get_as_text().strip_edges()

	call_deferred("_finish_transcription", exit_code, text)


func _finish_transcription(exit_code: int, text: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

	_busy = false

	if exit_code != 0:
		transcription_failed.emit("whisper.cpp failed with exit code %s." % exit_code)
		return

	if text.is_empty():
		transcription_failed.emit("Whisper returned empty transcription.")
		return

	print("Voice transcript received: ", text)

	transcription_completed.emit(text)
	transcript_received.emit(text)


func _globalize_if_needed(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)

	return path
