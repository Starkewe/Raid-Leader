extends Resource
class_name WeaponStatProfile

@export var power_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0
@export var range_additive: float = 0.0


func to_dictionary() -> Dictionary:
	return {
		"power_multiplier": power_multiplier,
		"speed_multiplier": speed_multiplier,
		"range_additive": range_additive,
	}
