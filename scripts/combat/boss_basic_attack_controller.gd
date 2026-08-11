extends RefCounted
class_name BossBasicAttackController

var attack_timer: float = 0.0
var sequence_count: int = 0
var trigger_count: int = 0
var pending_raidwide_timer: float = -1.0


func reset() -> void:
	attack_timer = 0.0
	sequence_count = 0
	trigger_count = 0
	pending_raidwide_timer = -1.0
