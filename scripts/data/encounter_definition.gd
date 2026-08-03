extends Resource
class_name EncounterDefinition

@export var encounter_id: String = ""
@export var display_name: String = "Encounter"
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String = "res://scenes/combat_scene.tscn"

@export_group("Boss")
@export var boss_display_name: String = "Boss"
@export var max_health: int = 3000
@export_enum("mobile", "anchored") var movement_mode: String = "mobile"
@export var movement_speed_range_units_per_second: float = 7.0
@export var attack_range_units: float = 5.0
## Negative values stop movement at attack range. Smaller values let a boss
## attack while continuing to close distance, without adding backpedaling.
@export var movement_stop_range_units: float = -1.0
@export var combat_radius: float = 128.0
@export var attack_damage: int = 20
@export var attack_cooldown: float = 1.5

@export_group("Basic Attack")
@export var basic_attack_id: String = "boss_auto_attack"
@export var basic_attack_display_name: String = "Attack"
@export var basic_attack_status_effect: StatusEffectDefinition = null
@export_enum("physical", "magic", "environmental") var basic_attack_damage_type: String = "physical"
@export_enum("single_target", "exact_mini_region") var basic_attack_targeting_mode: String = "single_target"
## Used by exact-mini-region attacks. Zero falls back to the chain multiplier.
@export var basic_attack_secondary_damage: int = 0

@export_group("Basic Attack Chain")
@export var basic_attack_secondary_target_count: int = 0
@export_range(0.0, 10.0, 0.01) var basic_attack_secondary_damage_multiplier: float = 1.0
## The next target is chosen by distance from the primary target.
@export var basic_attack_secondary_closest_to_primary: bool = true

@export_group("Basic Attack Raid Pulse")
## Zero disables the attack-count raid pulse.
@export var basic_attack_raidwide_every_n_attacks: int = 0
@export var basic_attack_raidwide_damage: int = 0
@export var basic_attack_raidwide_ability_id: String = ""
@export var basic_attack_raidwide_display_name: String = ""
@export_enum("physical", "magic", "environmental") var basic_attack_raidwide_damage_type: String = "physical"
@export var basic_attack_raidwide_delay: float = 0.0

@export_group("Basic Attack Triggered Ability")
@export var basic_attack_triggered_ability: BossAbilityDefinition = null
## Number of completed normal attacks before the next attack opportunity triggers the ability.
@export var basic_attack_trigger_threshold: int = 0
@export var basic_attack_trigger_when_target_outside_required_range: bool = false
@export_enum("close", "mid", "far") var basic_attack_required_range: String = "close"

@export_group("Loadout")
@export var abilities: Array[BossAbilityDefinition] = []
@export var phases: Array[BossPhaseDefinition] = []
## Minimum breathing room after a boss ability resolves before another can begin.
@export_range(0.0, 60.0, 0.1) var ability_base_gap: float = 4.0
## Bounded per-attempt variance applied to individual ability cooldowns.
@export_range(0.0, 1.0, 0.01) var ability_cooldown_variance: float = 0.05
## Zero chooses a fresh seed for each attempt; non-zero values make timing reproducible.
@export var ability_random_seed: int = 0
## Negative values use the encounter's base ability gap for the first cast.
@export var initial_ability_delay: float = -1.0

@export_group("Development Display")
@export var debug_logging_enabled: bool = true
@export var show_debug_region_guides: bool = true
@export var show_debug_range_rings: bool = true
@export var debug_max_range_units: float = 50.0


func get_ability_ids() -> Array[String]:
	var ids: Array[String] = []

	for ability in abilities:
		if ability != null and not ability.ability_id.is_empty():
			ids.append(ability.ability_id)

	if (
		basic_attack_triggered_ability != null
		and not basic_attack_triggered_ability.ability_id.is_empty()
		and not ids.has(basic_attack_triggered_ability.ability_id)
	):
		ids.append(basic_attack_triggered_ability.ability_id)

	return ids
