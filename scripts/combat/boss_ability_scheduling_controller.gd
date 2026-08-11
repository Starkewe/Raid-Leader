extends RefCounted
class_name BossAbilitySchedulingController

var next_ability_index: int = 0
var special_timer: float = 0.0
var cooldown_remaining: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var rng_initialized: bool = false
var last_ability_id: String = ""


func reset() -> void:
	next_ability_index = 0
	special_timer = 0.0
	cooldown_remaining.clear()
	rng_initialized = false
	last_ability_id = ""
