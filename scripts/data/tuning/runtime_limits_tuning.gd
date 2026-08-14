extends Resource
class_name RuntimeLimitsTuning

@export var combat_log_entries: int
@export var combat_event_queue_compaction_threshold: int
@export var projectile_pool_capacity: int
@export var impact_pool_capacity: int


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		["combat_log_entries", combat_log_entries],
		["combat_event_queue_compaction_threshold", combat_event_queue_compaction_threshold],
		["projectile_pool_capacity", projectile_pool_capacity],
		["impact_pool_capacity", impact_pool_capacity],
	]:
		if int(field[1]) <= 0:
			errors.append("%s must be greater than zero." % String(field[0]))
	return errors
