extends BossAbilityDefinition
class_name BarbedRecallDefinition

@export_group("Barbed Recall")
@export var source_ranges: Array[String] = ["far"]
@export var destination_range: String = "mid"
## Zero pulls every unit in the selected congested mini-region.
@export var target_count: int = 4
@export var pull_duration: float = 0.8
