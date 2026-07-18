extends Resource
class_name EncounterDefinition

@export var encounter_id: String = ""
@export var display_name: String = "Encounter"
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String = "res://scenes/combat_scene.tscn"

@export_group("Boss")
@export var boss_display_name: String = "Boss"
@export var max_health: int = 3000
@export var movement_speed_range_units_per_second: float = 7.0
@export var attack_range_units: float = 5.0
@export var combat_radius: float = 128.0
@export var attack_damage: int = 20
@export var attack_cooldown: float = 1.5

@export_group("Loadout")
@export var abilities: Array[BossAbilityDefinition] = []
@export var phases: Array[BossPhaseDefinition] = []

@export_group("Development Display")
@export var show_debug_region_guides: bool = true
@export var show_debug_range_rings: bool = true
@export var debug_max_range_units: float = 50.0


func get_ability_ids() -> Array[String]:
	var ids: Array[String] = []

	for ability in abilities:
		if ability != null and not ability.ability_id.is_empty():
			ids.append(ability.ability_id)

	return ids
