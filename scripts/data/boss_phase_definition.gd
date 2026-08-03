extends Resource
class_name BossPhaseDefinition

@export var phase_id: String = "phase_1"
@export var display_name: String = "Phase 1"
@export_range(0.0, 100.0, 0.1) var starts_at_health_percent: float = 100.0

@export_group("Pacing")
@export_range(0.01, 10.0, 0.01) var attack_speed_multiplier: float = 1.0
@export_range(0.01, 10.0, 0.01) var ability_speed_multiplier: float = 1.0
@export_range(0.01, 10.0, 0.01) var ability_cooldown_multiplier: float = 1.0
@export_range(0.01, 10.0, 0.01) var ability_base_gap_multiplier: float = 1.0

@export_group("Power")
@export_range(0.0, 10.0, 0.01) var attack_damage_multiplier: float = 1.0
@export_range(0.0, 10.0, 0.01) var ability_damage_multiplier: float = 1.0
@export var ability_target_count_bonus: int = 0

@export_group("Basic Attack Weapon")
@export_enum("club", "fists") var basic_attack_weapon_mode: String = "club"
@export_range(0.0, 10.0, 0.01) var basic_attack_weapon_damage_multiplier: float = 1.0
@export_range(0.01, 10.0, 0.01) var basic_attack_weapon_speed_multiplier: float = 1.0

@export_group("Basic Attack Rules")
## Negative values retain the encounter-level threshold.
@export_range(-1, 100, 1) var basic_attack_trigger_threshold_override: int = -1

@export_group("Ability Rules")
@export var enabled_ability_ids: Array[String] = []
@export var disabled_ability_ids: Array[String] = []

@export_group("Transition")
## Runs once when this phase begins. Phase 1 normally leaves this empty.
@export var transition_ability: BossAbilityDefinition = null
## When enabled, this phase's effects begin only after its transition cast resolves.
@export var defer_phase_effects_until_transition: bool = false


func allows_ability(ability_id: String) -> bool:
	if disabled_ability_ids.has(ability_id):
		return false

	if not enabled_ability_ids.is_empty():
		return enabled_ability_ids.has(ability_id)

	return true
