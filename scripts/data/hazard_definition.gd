extends Resource
class_name HazardDefinition

@export var hazard_id: String = "hazard"
@export var display_name: String = "Hazard"

@export_group("Lifetime")
## A duration of zero keeps the hazard active until encounter cleanup.
@export var duration: float = 5.0
@export var tick_interval: float = 1.0

@export_group("Area")
@export var affected_radius: float = 72.0

@export_group("Effects")
@export var damage_per_tick: int = 0
@export var status_effect: StatusEffectDefinition = null

@export_group("Visual")
@export var show_visual: bool = true
@export var fill_color: Color = Color(0.35, 0.12, 0.04, 0.42)
@export var edge_color: Color = Color(0.95, 0.34, 0.08, 0.9)
