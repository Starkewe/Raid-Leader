extends Resource
class_name UnitDefinition

@export var unit_class: String = ""
@export var display_name: String = ""
@export_file("*.tscn") var scene_path: String = ""

@export_group("Combat")
@export var max_health: int = 100
@export var movement_speed_range_units_per_second: float = 7.0
@export var actions: Array[UnitActionDefinition] = []

@export_group("Command Metadata")
@export var roles: Array[String] = []
@export var voice_aliases: Array[String] = []


func has_role(role_name: String) -> bool:
	return roles.has(role_name.to_lower().strip_edges())


func get_all_voice_aliases() -> Array[String]:
	var aliases: Array[String] = voice_aliases.duplicate()
	var canonical := unit_class.to_lower().strip_edges()

	if not canonical.is_empty() and not aliases.has(canonical):
		aliases.append(canonical)

	return aliases


func get_action(action_id: String) -> UnitActionDefinition:
	for action in actions:
		if action != null and action.action_id == action_id:
			return action

	return null
