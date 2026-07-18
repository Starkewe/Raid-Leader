extends Resource
class_name HazardDefinition

@export var hazard_id: String = "hazard"
@export var display_name: String = "Hazard"

@export_group("Lifetime")
@export var duration: float = 5.0
@export var tick_interval: float = 1.0

@export_group("Effects")
@export var damage_per_tick: int = 0
@export var status_effect: StatusEffectDefinition = null
