extends Resource
class_name CampActivityDefinition

@export var activity_id: String = ""
@export var display_name: String = ""
@export_enum("Work", "Study", "Training", "Rest", "Social", "Reflection")
var category: String = "Work"
@export var facility_id: String = ""
@export var compatible_station_ids: Array[String] = []
@export var base_weight: float = 1.0
@export var active_multiplier: float = 1.0
@export var reserve_multiplier: float = 1.0
@export var minimum_duration: float = 5.0
@export var maximum_duration: float = 10.0
@export var cooldown: float = 8.0
@export_range(1, 4, 1) var minimum_participants: int = 1
@export_range(1, 4, 1) var maximum_participants: int = 1
@export var conversation_compatible: bool = false
@export var allowed_secondary_interactions: Array[String] = []
@export var favored_classes: Array[String] = []
@export var favored_roles: Array[String] = []
@export var favored_attributes: Array[String] = []
@export var personality_preferences: Array[String] = []
@export var memory_context_requirements: Array[String] = []
@export var eligible_visit_contexts: Array[String] = []
@export var completion_outcomes: Array[String] = []
@export var feedback_lines: Array[String] = []
