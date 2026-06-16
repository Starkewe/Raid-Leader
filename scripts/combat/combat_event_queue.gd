extends RefCounted

class_name CombatEventQueue

const COMPACT_THRESHOLD: int = 32

var event_queue: Array[Dictionary] = []
var read_index: int = 0
var processing_events: bool = false
var event_handler: Callable = Callable()


func setup(new_event_handler: Callable) -> void:
	event_handler = new_event_handler


func queue_event(event_type: String, data: Dictionary = {}) -> void:
	event_queue.append({
		"type": event_type,
		"data": data
	})

	if not processing_events:
		call_deferred("process_events")


func has_events() -> bool:
	return read_index < event_queue.size()


func process_events() -> void:
	if event_handler.is_null():
		print("CombatEventQueue has no event handler.")
		return

	processing_events = true

	while has_events():
		var event: Dictionary = event_queue[read_index]
		read_index += 1

		event_handler.call(event)

	compact_queue_if_needed()

	processing_events = false


func compact_queue_if_needed() -> void:
	if read_index < COMPACT_THRESHOLD:
		return

	event_queue = event_queue.slice(read_index)
	read_index = 0


func clear() -> void:
	event_queue.clear()
	read_index = 0
	processing_events = false
