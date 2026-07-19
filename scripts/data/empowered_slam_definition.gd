extends BossAbilityDefinition
class_name EmpoweredSlamDefinition

@export_group("Empowered Slam")
@export var affected_ranges: Array[String] = ["close"]
@export var fissure_ranges: Array[String] = ["close", "mid", "far"]
@export var fissure_definition: HazardDefinition = null
@export var maximum_fissure_lines_per_region: int = 3
