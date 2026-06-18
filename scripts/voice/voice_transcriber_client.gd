extends Node
class_name VoiceTranscriberClient

signal transcript_received(text: String)
signal transcription_failed(message: String)

const VOICE_BUS_NAME := "VoiceRecord"
const RECORDING_PATH := "user://voice_command.wav"

@export var transcription_endpoint: String = "http://127.0.0.1:8765/transcribe"

var microphone_player: AudioStreamPlayer = null
var record_effect: AudioEffectRecord = null
var http_request: HTTPRequest = null
var is_recording: bool = false


func _ready() -> void:
	setup_microphone_recording()

	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)


func setup_microphone_recording() -> void:
	var bus_index := AudioServer.get_bus_index(VOICE_BUS_NAME)

	if bus_index == -1:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, VOICE_BUS_NAME)

	record_effect = get_or_create_record_effect(bus_index)

	microphone_player = AudioStreamPlayer.new()
	microphone_player.stream = AudioStreamMicrophone.new()
	microphone_player.bus = VOICE_BUS_NAME
	add_child(microphone_player)
	microphone_player.play()


func get_or_create_record_effect(bus_index: int) -> AudioEffectRecord:
	for i in range(AudioServer.get_bus_effect_count(bus_index)):
		var existing_effect := AudioServer.get_bus_effect(bus_index, i)

		if existing_effect is AudioEffectRecord:
			return existing_effect as AudioEffectRecord

	var effect := AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus_index, effect)

	return effect


func start_recording() -> void:
	if record_effect == null:
		transcription_failed.emit("Voice recording is not initialized.")
		return

	if is_recording:
		return

	print("Voice recording started.")
	record_effect.set_recording_active(false)
	record_effect.set_recording_active(true)
	is_recording = true


func stop_recording_and_transcribe() -> void:
	if record_effect == null:
		transcription_failed.emit("Voice recording is not initialized.")
		return

	if not is_recording:
		return

	print("Voice recording stopped.")
	record_effect.set_recording_active(false)
	is_recording = false

	var recording := record_effect.get_recording()

	if recording == null:
		transcription_failed.emit("No voice recording captured.")
		return

	if recording.get_length() < 0.15:
		transcription_failed.emit("Voice recording was too short.")
		return

	var save_result := recording.save_to_wav(RECORDING_PATH)

	if save_result != OK:
		transcription_failed.emit("Failed to save voice recording.")
		return

	send_recording_to_transcriber()


func send_recording_to_transcriber() -> void:
	if http_request == null:
		transcription_failed.emit("HTTPRequest node is missing.")
		return

	var file := FileAccess.open(RECORDING_PATH, FileAccess.READ)

	if file == null:
		transcription_failed.emit("Could not open saved voice recording.")
		return

	var bytes := file.get_buffer(file.get_length())
	file.close()

	var body := JSON.stringify({
		"filename": "voice_command.wav",
		"audio_base64": Marshalls.raw_to_base64(bytes),
		"speech_to_text_model": GameState.get_model_setting("speech_to_text_model")
	})

	var headers := [
		"Content-Type: application/json"
	]

	print("Sending voice recording to:", transcription_endpoint)

	var result := http_request.request(
		transcription_endpoint,
		headers,
		HTTPClient.METHOD_POST,
		body
	)

	if result != OK:
		transcription_failed.emit("Failed to send recording to transcriber.")


func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		transcription_failed.emit("Transcription request failed.")
		return

	if response_code < 200 or response_code >= 300:
		transcription_failed.emit("Transcription server returned HTTP " + str(response_code))
		return

	var response_text := body.get_string_from_utf8()
	var json := JSON.new()
	var parse_result := json.parse(response_text)

	if parse_result != OK:
		transcription_failed.emit("Transcription response was not valid JSON.")
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		transcription_failed.emit("Transcription response was not a dictionary.")
		return

	var transcript := String(data.get("text", "")).strip_edges()

	if transcript.is_empty():
		transcription_failed.emit("Transcription returned empty text.")
		return

	print("Voice transcript:", transcript)
	transcript_received.emit(transcript)
