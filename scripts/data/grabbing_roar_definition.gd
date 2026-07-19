extends BossAbilityDefinition
class_name GrabbingRoarDefinition

@export_group("Grabbing Roar")
@export_enum("random", "current_target", "all") var target_behavior: String = "random"
@export var target_count: int = 4
@export var slow_effect: StatusEffectDefinition = null
