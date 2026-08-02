extends RefCounted
class_name HealingSpellSelector

var policy: HealingDecisionPolicy = null


func setup(new_policy: HealingDecisionPolicy) -> void:
	policy = new_policy


func select_spell(
	target: Node,
	healer: Node = null,
	healing_target_selector = null
) -> UnitActionDefinition:
	var tiers := get_healing_tiers()

	if tiers.is_empty():
		return null

	if not _has_health_data(target):
		return tiers.back()

	var max_health := maxi(int(target.get_max_health()), 0)
	var current_health := clampi(int(target.get_current_health()), 0, max_health)
	var is_tank := _is_active_tank(target, healing_target_selector)
	var emergency_threshold := (
		policy.tank_emergency_health_percent
		if is_tank
		else policy.raid_emergency_health_percent
	)
	var current_health_percent := (
		float(current_health) / float(max_health) if max_health > 0 else 0.0
	)

	# The shortest cast is the safest response when the target is already in
	# emergency territory, even if a slower spell would cover more of the deficit.
	if current_health_percent <= emergency_threshold:
		return tiers.front()

	var horizon := maxf(policy.decision_horizon_seconds, 0.0)
	var incoming_healing := _get_incoming_healing(
		target,
		healer,
		horizon
	)
	var expected_damage := _get_expected_damage(
		target,
		is_tank,
		healing_target_selector,
		horizon
	)
	var projected_health := current_health + incoming_healing - expected_damage
	var projected_deficit := maxi(max_health - projected_health, 0)
	var required_healing := ceili(
		float(projected_deficit)
		* clampf(policy.required_deficit_coverage, 0.0, 1.0)
	)

	for tier in tiers:
		if tier.amount >= required_healing:
			return tier

	return tiers.back()


func get_healing_tiers() -> Array[UnitActionDefinition]:
	if policy == null:
		return []

	return policy.get_sorted_healing_tiers()


func get_action(action_id: String) -> UnitActionDefinition:
	for tier in get_healing_tiers():
		if tier.action_id == action_id:
			return tier

	return null


func _get_incoming_healing(target: Node, healer: Node, horizon: float) -> int:
	if not target.has_method("get_incoming_healing_total"):
		return 0

	if _method_supports_argument_count(target, "get_incoming_healing_total", 2):
		return int(target.get_incoming_healing_total(healer, horizon))

	return int(target.get_incoming_healing_total(healer))


func _get_expected_damage(
	target: Node,
	is_tank: bool,
	healing_target_selector,
	horizon: float
) -> int:
	if is_tank:
		if (
			healing_target_selector != null
			and healing_target_selector.has_method("get_projected_tank_damage")
		):
			return maxi(
				int(healing_target_selector.get_projected_tank_damage(
					target,
					horizon,
					policy.fallback_tank_damage_per_second
				)),
				0
			)

		return maxi(
			int(round(policy.fallback_tank_damage_per_second * horizon)),
			0
		)

	var pressure_multiplier := 1.0

	if (
		healing_target_selector != null
		and healing_target_selector.has_method("get_raid_pressure_multiplier")
	):
		pressure_multiplier = maxf(
			float(healing_target_selector.get_raid_pressure_multiplier()),
			0.0
		)

	return maxi(
		int(round(
			policy.baseline_raid_damage_per_second
			* horizon
			* pressure_multiplier
		)),
		0
	)


func _is_active_tank(target: Node, healing_target_selector) -> bool:
	return (
		healing_target_selector != null
		and healing_target_selector.has_method("is_active_tank")
		and bool(healing_target_selector.is_active_tank(target))
	)


func _has_health_data(target: Node) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and target.has_method("get_current_health")
		and target.has_method("get_max_health")
		and int(target.get_max_health()) > 0
	)


func _method_supports_argument_count(
	target: Object,
	method_name: String,
	argument_count: int
) -> bool:
	for method_data in target.get_method_list():
		if String(method_data.get("name", "")) != method_name:
			continue

		var arguments: Array = method_data.get("args", [])
		return arguments.size() >= argument_count

	return false
