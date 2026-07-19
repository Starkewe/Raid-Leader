extends BossAbilityDefinition
class_name IronCollarDefinition

@export_group("Iron Collar")
@export_enum("random", "random_non_tank") var target_behavior: String = "random_non_tank"
@export var target_count: int = 3
@export var eligible_ranges: Array[String] = ["close", "mid"]
@export var collar_duration: float = 6.0
@export var required_outward_steps: int = 1
@export var failure_destination_range: String = "close"
@export var failure_pull_duration: float = 0.75
@export var status_effect: StatusEffectDefinition = null
