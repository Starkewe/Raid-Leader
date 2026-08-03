extends Resource
class_name PositioningCheckpointDefinition

## Authored lifecycle events used by the boss runtime. Keeping these values in
## data lets future mechanics opt in without adding ability-name checks to
## raider movement code.
@export_enum("none", "basic_attack_trigger_ready", "cast_queued")
var planning_window_opens: String = "none"
@export_enum("on_cast_start", "on_cast_resolve")
var positions_lock: String = "on_cast_start"
@export_enum("after_positions_lock", "on_cast_resolve")
var commitment_releases: String = "after_positions_lock"
