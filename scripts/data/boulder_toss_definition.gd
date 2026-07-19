extends BossAbilityDefinition
class_name BoulderTossDefinition

@export_group("Boulder Toss")
## Zero targets every living unit in the most congested mini-region.
@export var target_count: int = 0
@export var knockback_duration: float = 0.8
