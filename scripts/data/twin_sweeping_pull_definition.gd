extends BossAbilityDefinition
class_name TwinSweepingPullDefinition

@export_group("Twin Sweeping Pull")
@export var pull_duration: float = 1.5
@export var first_sweep_cast_duration: float = 2.5
@export var second_sweep_cast_duration: float = 4.0
@export var pull_range: String = "close"
@export var affected_ranges: Array[String] = ["close", "mid"]
@export var random_pull_regions: Array[String] = [
	"north",
	"northeast",
	"east",
	"southeast",
	"south",
	"southwest",
	"west",
	"northwest"
]
