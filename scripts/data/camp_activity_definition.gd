extends Resource
class_name CampActivityDefinition

@export var activity_id: String = ""
@export var display_name: String = ""
@export var facility_id: String = ""
@export var base_weight: float = 1.0
@export var active_multiplier: float = 1.0
@export var reserve_multiplier: float = 1.0
@export var minimum_duration: float = 5.0
@export var maximum_duration: float = 10.0
@export var cooldown: float = 8.0
@export var favored_classes: Array[String] = []
@export var favored_attributes: Array[String] = []
@export var eligible_visit_contexts: Array[String] = []
@export var feedback_lines: Array[String] = []
