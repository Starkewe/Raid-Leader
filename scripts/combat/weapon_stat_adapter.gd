extends RefCounted
class_name WeaponStatAdapter

const IDENTITY_PROFILE := {
	"power_multiplier": 1.0,
	"speed_multiplier": 1.0,
	"range_additive": 0.0,
}


static func sanitize_profile(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return IDENTITY_PROFILE.duplicate()
	var source: Dictionary = value
	var power := float(source.get("power_multiplier", 1.0))
	var speed := float(source.get("speed_multiplier", 1.0))
	var range_additive := float(source.get("range_additive", 0.0))
	if power <= 0.0 or speed <= 0.0:
		return IDENTITY_PROFILE.duplicate()
	return {
		"power_multiplier": power,
		"speed_multiplier": speed,
		"range_additive": range_additive,
	}


static func apply_power(base_amount: int, profile: Dictionary) -> int:
	var sanitized := sanitize_profile(profile)
	return int(round(float(base_amount) * float(sanitized["power_multiplier"])))


static func apply_timing(base_duration: float, profile: Dictionary) -> float:
	var sanitized := sanitize_profile(profile)
	return base_duration / float(sanitized["speed_multiplier"])


static func apply_range(base_range: float, profile: Dictionary) -> float:
	var sanitized := sanitize_profile(profile)
	return maxf(base_range + float(sanitized["range_additive"]), 0.0)

