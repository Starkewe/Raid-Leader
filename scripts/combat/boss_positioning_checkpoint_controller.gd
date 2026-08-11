extends RefCounted
class_name BossPositioningCheckpointController

var active_checkpoint: Dictionary = {}
var next_token: int = 1


func clear() -> void:
	active_checkpoint.clear()


func reset() -> void:
	active_checkpoint.clear()
	next_token = 1
