extends EncounterDefinition
class_name TwinMaulersDefinition

@export_group("Twin Maulers: Combatants")
@export var mauler_max_health: int = 30000
@export var mauler_attack_damage: int = 14
@export var mauler_attack_cooldown: float = 2.4
@export var mauler_combat_radius: float = 92.0
@export var west_offset_pixels: float = -180.0
@export var east_offset_pixels: float = 180.0

@export_group("Twin Maulers: Rage")
@export var base_exhaustion_threshold: float = 100.0
@export var exhaustion_threshold_step: float = 50.0
@export var rage_attack_speed_percent_per_stack: float = 0.005
@export var rage_floor_max: float = 90.0
@export var rage_floor_exponent: float = 1.0
@export var rage_stable_min_attackers: int = 6
@export var rage_stable_max_attackers: int = 9
@export var rage_decay_per_missing_attacker: float = 3.0
@export var rage_gain_per_extra_attacker: float = 3.333333
@export var rage_max_gain_rate: float = 20.0

@export_group("Twin Maulers: Exhaustion")
@export var exhaustion_duration: float = 10.0
@export var exhaustion_rage_decay_per_second: float = 40.0
@export var exhaustion_damage_multiplier: float = 2.0

@export_group("Twin Maulers: Rampage")
@export var rampage_initial_delay_min: float = 28.0
@export var rampage_initial_delay_max: float = 34.0
@export var rampage_interval_min: float = 28.0
@export var rampage_interval_max: float = 34.0
@export var rampage_warning_duration: float = 10.0
@export var rampage_cast_duration: float = 2.0
@export_range(0.0, 1.0, 0.01) var rampage_damage_max_health_percent: float = 0.80
@export var maximum_rampage_same_target_streak: int = 3

@export_group("Twin Maulers: Survivor Enrage")
@export var survivor_threshold: float = 100.0
@export var survivor_floor_bonus: float = 40.0
@export var survivor_attack_damage_multiplier: float = 1.35
@export var survivor_rampage_interval_multiplier: float = 0.55

@export_group("Twin Maulers: Telemetry")
@export var telemetry_sample_interval: float = 0.5
@export var random_seed: int = 0


func get_rage_floor(missing_health_ratio: float) -> float:
	var normalized_missing := clampf(missing_health_ratio, 0.0, 1.0)
	return rage_floor_max * pow(normalized_missing, maxf(rage_floor_exponent, 0.01))


func get_rage_rate(active_attackers: int) -> float:
	var attacker_count := maxi(active_attackers, 0)

	if attacker_count < rage_stable_min_attackers:
		return -float(rage_stable_min_attackers - attacker_count) * rage_decay_per_missing_attacker

	if attacker_count <= rage_stable_max_attackers:
		return 0.0

	var rate := float(attacker_count - rage_stable_max_attackers) * rage_gain_per_extra_attacker
	return minf(rate, rage_max_gain_rate)


func get_rampage_interval(rng: RandomNumberGenerator, survivor_enraged: bool) -> float:
	var minimum := rampage_interval_min
	var maximum := rampage_interval_max
	if survivor_enraged:
		minimum *= survivor_rampage_interval_multiplier
		maximum *= survivor_rampage_interval_multiplier

	if rng == null:
		return (minimum + maximum) * 0.5

	return rng.randf_range(minimum, maximum)
