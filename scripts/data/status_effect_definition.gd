extends Resource
class_name StatusEffectDefinition

@export var effect_id: String = "status_effect"
@export var display_name: String = "Status Effect"

@export_group("Duration and Stacking")
@export var duration: float = 5.0
@export var max_stacks: int = 1
@export var refresh_duration_on_stack: bool = true
@export var unique_per_source: bool = false

@export_group("Removal")
@export var dispellable: bool = false
@export var dispel_category: String = ""

@export_group("Periodic Effect")
@export var tick_interval: float = 0.0
@export var damage_per_tick: int = 0

@export_group("Movement")
@export_range(0.0, 10.0, 0.01) var movement_speed_multiplier_per_stack: float = 1.0

@export_group("Incoming Damage")
@export_range(0.0, 10.0, 0.01) var incoming_damage_percent_per_stack: float = 0.0
