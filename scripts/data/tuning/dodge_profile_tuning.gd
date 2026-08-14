extends Resource
class_name DodgeProfileTuning

@export var base_class: String
@export var charges: int
@export_enum("physical", "teleport") var movement_type: String
@export var distance_spacings: float
@export var duration_seconds: float
@export var recharge_seconds: float


func to_dictionary() -> Dictionary:
	return {
		"charges": charges,
		"movement_type": movement_type,
		"distance_spacings": distance_spacings,
		"duration": duration_seconds,
		"recharge": recharge_seconds,
	}


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if base_class.strip_edges().is_empty():
		errors.append("base_class must not be empty.")
	if charges <= 0:
		errors.append("charges must be greater than zero.")
	if movement_type not in ["physical", "teleport"]:
		errors.append("movement_type must be 'physical' or 'teleport'.")
	if distance_spacings <= 0.0:
		errors.append("distance_spacings must be greater than zero.")
	if duration_seconds <= 0.0:
		errors.append("duration_seconds must be greater than zero.")
	if recharge_seconds <= 0.0:
		errors.append("recharge_seconds must be greater than zero.")
	return errors
