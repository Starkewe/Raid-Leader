extends EncounterDefinition
class_name CarrionRocDefinition

@export_group("Carrion Roc: Stagger")
@export var stagger_threshold: int = 2800
@export var melee_stagger_weight: float = 1.0
@export var ranged_stagger_weight: float = 0.20
@export var grounded_duration: float = 16.0
@export var grounded_damage_multiplier: float = 2.25

@export_group("Carrion Roc: Cadence")
@export var peck_damage: int = 18
@export var cadence_interval: float = 2.0
@export var cadence_special_every: int = 3
@export var peck_flurry_hit_damage: int = 10
@export var peck_flurry_hit_count: int = 3
@export var peck_flurry_duration: float = 1.2
@export var wing_swipe_damage: int = 8
@export var tail_swipe_damage: int = 8
@export var cyclone_damage: int = 6
@export var displacement_duration: float = 0.65

@export_group("Carrion Roc: Ruptures")
@export var rupture_delay_after_grounding: float = 2.5
@export var rupture_telegraph_duration: float = 6.5
@export var rupture_health_threshold: int = 350
@export var rupture_damage_pool: int = 320
@export var rupture_candidate_ranges: Array[String] = ["mid", "far"]
@export var east_rupture_regions: Array[String] = ["northeast", "east", "southeast"]
@export var west_rupture_regions: Array[String] = ["northwest", "west", "southwest"]

@export_group("Carrion Roc: Growths")
@export var growth_max_health: int = 1000
@export var growth_pulse_damage: int = 3
@export var growth_pulse_interval: float = 2.0

@export_group("Carrion Roc: Timing")
@export var initial_cadence_delay: float = 2.0
@export var random_seed: int = 7331
