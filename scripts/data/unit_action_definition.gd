extends Resource
class_name UnitActionDefinition

@export var action_id: String = "action"
@export var display_name: String = "Action"

@export_group("Targeting")
@export var range_units: float = 5.0
@export var stop_distance_units: float = 5.0

@export_group("Timing and Power")
@export var amount: int = 0
@export var cooldown: float = 1.0
@export var cast_time: float = 0.0
