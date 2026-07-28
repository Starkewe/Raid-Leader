extends RefCounted
class_name DodgeTuning

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

const MOVEMENT_PHYSICAL := "physical"
const MOVEMENT_TELEPORT := "teleport"

const PHYSICAL_DASH_EASING_STRENGTH: float = 4.5
const ROGUE_SECOND_DASH_THRESHOLD_SPACINGS: float = 2.0

const DASH_TRAIL_LIFETIME: float = 0.12
const DASH_TRAIL_OPACITY: float = 0.22
const DASH_TRAIL_WIDTH: float = 5.0

const TELEPORT_PULSE_LIFETIME: float = 0.15
const TELEPORT_PULSE_SCALE: float = 22.0
const TELEPORT_PULSE_OPACITY: float = 0.32

const RAID_FRAME_FLASH_DURATION: float = 0.28
const RAID_FRAME_FLASH_STRENGTH: float = 0.55

const DESTINATION_LINE_THICKNESS: float = 1.5
const DESTINATION_LINE_DASH_LENGTH: float = 10.0
const DESTINATION_LINE_GAP_LENGTH: float = 7.0
const DESTINATION_LINE_OPACITY: float = 0.24
const DESTINATION_UPDATE_INTERVAL: float = 0.0
const DESTINATION_FLAG_SIZE: float = 9.0
const DESTINATION_FLAG_OPACITY: float = 0.48
const DESTINATION_ENDPOINT_SIZE: float = 3.5
const DESTINATION_ENDPOINT_OPACITY: float = 0.72

const PROFILES := {
	"warrior": {
		"charges": 1,
		"movement_type": MOVEMENT_PHYSICAL,
		"distance_spacings": 0.5,
		"duration": 0.225,
		"recharge": 8.0
	},
	"priest": {
		"charges": 1,
		"movement_type": MOVEMENT_PHYSICAL,
		"distance_spacings": 1.0,
		"duration": 0.30,
		"recharge": 8.0
	},
	"rogue": {
		"charges": 2,
		"movement_type": MOVEMENT_PHYSICAL,
		"distance_spacings": 1.0,
		"duration": 0.30,
		"recharge": 8.0
	},
	"mage": {
		"charges": 1,
		"movement_type": MOVEMENT_TELEPORT,
		"distance_spacings": 1.5,
		"duration": 0.15,
		"recharge": 12.0
	}
}


static func get_profile(base_class: String) -> Dictionary:
	var normalized := base_class.to_lower().strip_edges()
	var profile_value: Variant = PROFILES.get(normalized, {})

	if not profile_value is Dictionary:
		return {}

	return Dictionary(profile_value).duplicate(true)


static func get_mini_region_spacing_pixels() -> float:
	return MovementSlotResolverScript.get_mini_region_spacing_pixels()
