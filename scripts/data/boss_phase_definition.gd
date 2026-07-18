extends Resource
class_name BossPhaseDefinition

@export var phase_id: String = "phase_1"
@export var display_name: String = "Phase 1"
@export_range(0.0, 100.0, 0.1) var starts_at_health_percent: float = 100.0

@export_group("Pacing")
@export_range(0.01, 10.0, 0.01) var attack_speed_multiplier: float = 1.0
@export_range(0.01, 10.0, 0.01) var ability_speed_multiplier: float = 1.0

@export_group("Ability Rules")
@export var enabled_ability_ids: Array[String] = []
@export var disabled_ability_ids: Array[String] = []


func allows_ability(ability_id: String) -> bool:
	if disabled_ability_ids.has(ability_id):
		return false

	if not enabled_ability_ids.is_empty():
		return enabled_ability_ids.has(ability_id)

	return true
