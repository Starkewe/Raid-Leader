extends Resource
class_name HealingDecisionPolicy

@export_group("Decision Window")
@export_range(0.1, 10.0, 0.1) var decision_horizon_seconds: float = 2.0
@export_range(0.0, 1.0, 0.01) var required_deficit_coverage: float = 0.7

@export_group("Emergency Thresholds")
@export_range(0.0, 1.0, 0.01) var tank_emergency_health_percent: float = 0.45
@export_range(0.0, 1.0, 0.01) var raid_emergency_health_percent: float = 0.30

@export_group("Expected Damage")
@export_range(0.0, 100.0, 0.1) var fallback_tank_damage_per_second: float = 10.0
@export_range(0.0, 100.0, 0.1) var baseline_raid_damage_per_second: float = 2.0

@export_group("Healing Tiers")
@export var healing_tiers: Array[UnitActionDefinition] = []


func get_sorted_healing_tiers() -> Array[UnitActionDefinition]:
	var sorted_tiers: Array[UnitActionDefinition] = []

	for tier in healing_tiers:
		if tier != null and tier.amount > 0:
			sorted_tiers.append(tier)

	sorted_tiers.sort_custom(func(a: UnitActionDefinition, b: UnitActionDefinition) -> bool:
		if a.amount != b.amount:
			return a.amount < b.amount

		return a.cast_time < b.cast_time
	)
	return sorted_tiers
