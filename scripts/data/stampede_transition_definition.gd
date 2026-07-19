extends BossAbilityDefinition
class_name StampedeTransitionDefinition

@export_group("Stampede Waves")
@export var clear_existing_encounter_objects: bool = true
@export var wave_telegraph_durations: Array[float] = [4.0, 3.25]
@export var wave_recovery_duration: float = 1.25
@export var intermission_mechanic_delay: float = 0.45
@export var affected_ranges: Array[String] = ["close", "mid", "far"]
@export var tremor_damage: int = 6
@export_enum("physical", "magic", "environmental") var tremor_damage_type: String = "environmental"

@export_group("Intermission Mechanics")
## One-based wave number. Zero disables the insertion.
@export var barbed_recall_after_wave: int = 0
@export var barbed_recall_definition: BarbedRecallDefinition = null
## One-based wave number. Zero disables the insertion.
@export var iron_collar_after_wave: int = 0
@export var iron_collar_definition: IronCollarDefinition = null
