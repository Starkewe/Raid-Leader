extends RefCounted
class_name VoiceCommandCoordinator

const VoiceCommandParserScript := preload("res://scripts/voice/voice_command_parser.gd")

var owner_node: Node = null
var voice_transcriber: VoiceTranscriberClient = null
var voice_command_parser: VoiceCommandParser = null
var voice_capture: Node = null

var submit_command_callable: Callable = Callable()
var update_debug_callable: Callable = Callable()
var set_status_callable: Callable = Callable()


func setup(
	new_owner_node: Node,
	transcriber_path: NodePath,
	parser_path: NodePath,
	new_submit_command_callable: Callable,
	new_update_debug_callable: Callable,
	new_set_status_callable: Callable
) -> void:
	owner_node = new_owner_node
	submit_command_callable = new_submit_command_callable
	update_debug_callable = new_update_debug_callable
	set_status_callable = new_set_status_callable

	voice_transcriber = _find_transcriber(transcriber_path)
	voice_command_parser = _find_parser(parser_path)
	voice_capture = owner_node.get_node_or_null("../VoicePipeline/VoiceCaptureController")

	if voice_transcriber == null:
		push_warning("VoiceTranscriberClient is missing. Voice commands are disabled.")
		return

	if voice_command_parser == null:
		push_warning("VoiceCommandParser is missing. Voice commands are disabled.")
		return

	if not voice_transcriber.transcript_received.is_connected(_on_transcript_received):
		voice_transcriber.transcript_received.connect(_on_transcript_received)

	if not voice_transcriber.transcription_failed.is_connected(_on_transcription_failed):
		voice_transcriber.transcription_failed.connect(_on_transcription_failed)

	_connect_capture_signals()


func _find_transcriber(path: NodePath) -> VoiceTranscriberClient:
	if not path.is_empty():
		var configured := owner_node.get_node_or_null(path) as VoiceTranscriberClient

		if configured != null:
			return configured

	var pipeline_node := owner_node.get_node_or_null(
		"../VoicePipeline/VoiceTranscriberClient"
	) as VoiceTranscriberClient

	if pipeline_node != null:
		return pipeline_node

	return owner_node.get_node_or_null("../VoiceTranscriberClient") as VoiceTranscriberClient


func _find_parser(path: NodePath) -> VoiceCommandParser:
	if not path.is_empty():
		var configured := owner_node.get_node_or_null(path) as VoiceCommandParser

		if configured != null:
			return configured

	var pipeline_node := owner_node.get_node_or_null(
		"../VoicePipeline/VoiceCommandParser"
	) as VoiceCommandParser

	if pipeline_node != null:
		return pipeline_node

	var sibling := owner_node.get_node_or_null("../VoiceCommandParser") as VoiceCommandParser
	return sibling if sibling != null else VoiceCommandParserScript.new()


func _connect_capture_signals() -> void:
	if voice_capture == null or not is_instance_valid(voice_capture):
		return

	if voice_capture.has_signal("recording_started") and not voice_capture.is_connected(
		"recording_started", _on_recording_started
	):
		voice_capture.connect("recording_started", _on_recording_started)

	if voice_capture.has_signal("recording_finished") and not voice_capture.is_connected(
		"recording_finished", _on_recording_finished
	):
		voice_capture.connect("recording_finished", _on_recording_finished)

	if voice_capture.has_signal("recording_failed") and not voice_capture.is_connected(
		"recording_failed", _on_recording_failed
	):
		voice_capture.connect("recording_failed", _on_recording_failed)


func _on_transcript_received(transcript: String) -> void:
	_set_status("Recognized command")
	var parse_result := voice_command_parser.parse(transcript)
	var normalized_text := String(parse_result.get("normalized_text", ""))

	if not bool(parse_result.get("ok", false)):
		var reason := String(parse_result.get("reason", "Could not parse voice command."))
		_set_status("Rejected - " + reason, true)
		_update_debug({
			"source": "Voice",
			"transcript": transcript,
			"normalized": normalized_text,
			"who": "-",
			"what": "-",
			"where": "-",
			"result": "Rejected - " + reason,
			"command_data": "-"
		})
		return

	var command_data: Dictionary = parse_result.get("command_data", {})
	var command_executed := bool(submit_command_callable.call(
		command_data,
		"voice",
		{"transcript": transcript, "normalized_text": normalized_text}
	))
	_set_status("Command executed" if command_executed else "Command rejected", not command_executed)


func _on_transcription_failed(reason: String) -> void:
	_set_status(reason, true)
	_update_debug({
		"source": "Voice",
		"transcript": "-",
		"normalized": "-",
		"who": "-",
		"what": "-",
		"where": "-",
		"result": "Transcription failed - " + reason,
		"command_data": "-"
	})


func _on_recording_started() -> void:
	_set_status("Listening...")
	_update_debug(_voice_state_debug("Listening...", "Recording"))


func _on_recording_finished(_wav_path: String) -> void:
	_set_status("Transcribing...")
	_update_debug(_voice_state_debug("Processing...", "Queued for transcription"))


func _on_recording_failed(reason: String) -> void:
	_set_status(reason, true)


func _voice_state_debug(transcript: String, result: String) -> Dictionary:
	return {
		"source": "Voice",
		"transcript": transcript,
		"normalized": "-",
		"who": "-",
		"what": "-",
		"where": "-",
		"result": result,
		"command_data": "-"
	}


func _set_status(text: String, is_error: bool = false) -> void:
	if not set_status_callable.is_null():
		set_status_callable.call(text, is_error)


func _update_debug(data: Dictionary) -> void:
	if not update_debug_callable.is_null():
		update_debug_callable.call(data)
