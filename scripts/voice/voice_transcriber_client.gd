extends Node
class_name VoiceTranscriberClient

signal transcript_received(text: String)
signal transcription_failed(reason: String)

@export_file("*.exe") var whisper_cli_path := "E:/Raid Leader/tools/whisper.cpp/build/bin/Release/whisper-cli.exe"
@export_file("*.bin") var model_path := "E:/Raid Leader/tools/whisper.cpp/ggml-base.en.bin"

var _thread: Thread
var _is_transcribing := false


func transcribe_wav(wav_path: String) -> void:
	if _is_transcribing:
		transcription_failed.emit("Transcription is already running.")
		return

	if not FileAccess.file_exists(wav_path):
		transcription_failed.emit("WAV file does not exist: %s" % wav_path)
		return

	if not FileAccess.file_exists(whisper_cli_path):
		transcription_failed.emit("whisper-cli.exe was not found.")
		return

	if not FileAccess.file_exists(model_path):
		transcription_failed.emit("Whisper model was not found.")
		return

	_is_transcribing = true
	_thread = Thread.new()
	_thread.start(_run_whisper.bind(wav_path))


func _run_whisper(wav_path: String) -> void:
	var output := []
	var args := PackedStringArray([
		"-m", model_path,
		"-f", wav_path,
		"-nt"
	])

	var exit_code := OS.execute(whisper_cli_path, args, output, true, false)
	var raw_output := "\n".join(output)

	call_deferred("_finish_transcription", exit_code, raw_output)


func _finish_transcription(exit_code: int, raw_output: String) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null

	_is_transcribing = false

	if exit_code != 0:
		transcription_failed.emit("whisper-cli failed with exit code %d: %s" % [exit_code, raw_output])
		return

	var text := _clean_whisper_output(raw_output)

	if text.is_empty():
		transcription_failed.emit("Whisper returned empty transcript.")
		return

	transcript_received.emit(text)


func _clean_whisper_output(raw_output: String) -> String:
	var lines := raw_output.split("\n", false)
	var transcript_parts: Array[String] = []

	for line in lines:
		var cleaned := line.strip_edges()

		if cleaned.is_empty():
			continue

		# Skip common whisper.cpp diagnostic lines.
		if cleaned.begins_with("whisper_"):
			continue
		if cleaned.begins_with("system_info"):
			continue
		if cleaned.begins_with("main:"):
			continue

		transcript_parts.append(cleaned)

	return " ".join(transcript_parts).strip_edges()
