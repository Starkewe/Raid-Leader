extends RefCounted
class_name HealingTargetSelector

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const CommandTargetResolverScript := preload(
	"res://scripts/commands/command_target_resolver.gd"
)

const SCOPE_ACTIVE_TANK := CommandSchemaScript.HEAL_SCOPE_ACTIVE_TANK
const SCOPE_RAID := CommandSchemaScript.HEAL_SCOPE_RAID
const CAST_START_INTERRUPTION_ABILITIES: Array[String] = [
	"twin_sweeping_pull"
]
const CAST_END_INTERRUPTION_ABILITIES: Array[String] = [
	"earthshaker_stomp",
	"boulder_toss",
	"barbed_recall"
]

var party_members: Array = []
var enemy_threat_sources: Array = []
var target_resolver = null


func setup(new_party_members: Array, new_enemy_threat_sources: Array = []) -> void:
	party_members = new_party_members.duplicate()
	enemy_threat_sources = new_enemy_threat_sources.duplicate()
	target_resolver = CommandTargetResolverScript.new()
	target_resolver.setup(party_members)


func is_valid_scope(scope: Dictionary) -> bool:
	var scope_type := String(scope.get("type", ""))

	if scope_type in [SCOPE_ACTIVE_TANK, SCOPE_RAID]:
		return true

	if scope_type not in CommandSchemaScript.HEAL_SCOPE_SELECTOR_TYPES:
		return false

	if target_resolver == null:
		return false

	return not target_resolver.get_units_for_selector(scope).is_empty()


func get_living_units_in_scope(scope: Dictionary) -> Array:
	var scope_type := String(scope.get("type", ""))

	match scope_type:
		SCOPE_ACTIVE_TANK:
			return get_active_tanks()

		SCOPE_RAID:
			var active_tanks := get_active_tanks()
			var raid_targets: Array = []

			for party_member in party_members:
				if is_unit_alive(party_member) and not active_tanks.has(party_member):
					raid_targets.append(party_member)

			return raid_targets

		_:
			if target_resolver == null:
				return []

			return target_resolver.get_units_for_selector(scope)


func get_active_tanks() -> Array:
	var active_tanks: Array = []

	for enemy in _get_current_enemy_threat_sources():
		if not is_valid_node(enemy) or not enemy.has_method("get_current_target"):
			continue

		var threat_holder = enemy.get_current_target()

		if (
			threat_holder is Node
			and is_unit_alive(threat_holder)
			and party_members.has(threat_holder)
			and not active_tanks.has(threat_holder)
		):
			active_tanks.append(threat_holder)

	return active_tanks


func is_active_tank(target: Node) -> bool:
	return target != null and get_active_tanks().has(target)


func get_projected_tank_damage(
	target: Node,
	horizon_seconds: float,
	fallback_damage_per_second: float
) -> int:
	var horizon := maxf(horizon_seconds, 0.0)
	var fallback_damage := maxi(
		int(round(maxf(fallback_damage_per_second, 0.0) * horizon)),
		0
	)
	var projected_damage := 0
	var found_targeting_source := false

	for enemy in _get_current_enemy_threat_sources():
		if (
			not is_valid_node(enemy)
			or not enemy.has_method("get_current_target")
			or enemy.get_current_target() != target
		):
			continue

		found_targeting_source = true

		if enemy.has_method("estimate_scheduled_basic_attack_damage"):
			projected_damage += maxi(
				int(enemy.estimate_scheduled_basic_attack_damage(target, horizon)),
				0
			)
		else:
			projected_damage += fallback_damage

	if not found_targeting_source:
		return fallback_damage

	return projected_damage


func get_raid_pressure_multiplier() -> float:
	var pressure_multiplier := 0.0
	var found_source := false

	for enemy in _get_current_enemy_threat_sources():
		if not is_valid_node(enemy):
			continue

		found_source = true

		var damage_multiplier := (
			float(enemy.get_ability_damage_multiplier())
			if enemy.has_method("get_ability_damage_multiplier")
			else 1.0
		)
		var speed_multiplier := (
			float(enemy.get_ability_speed_multiplier())
			if enemy.has_method("get_ability_speed_multiplier")
			else 1.0
		)
		var cooldown_multiplier := (
			float(enemy.get_ability_cooldown_multiplier())
			if enemy.has_method("get_ability_cooldown_multiplier")
			else 1.0
		)
		var source_pressure := (
			maxf(damage_multiplier, 0.0)
			* maxf(speed_multiplier, 0.01)
			/ maxf(cooldown_multiplier, 0.01)
		)
		pressure_multiplier = maxf(pressure_multiplier, source_pressure)

	return pressure_multiplier if found_source else 1.0


func get_upcoming_cast_interruption_seconds() -> float:
	var earliest_seconds := INF

	for enemy in _get_current_enemy_threat_sources():
		if not is_valid_node(enemy):
			continue

		var is_casting := bool(_get_property_value(enemy, "is_casting", false))
		var seconds_until_next_cast := maxf(
			float(_get_property_value(enemy, "special_timer", 0.0)),
			0.0
		)

		if is_casting:
			var current_ability = _get_property_value(enemy, "current_ability", null)
			var current_ability_id := _get_ability_id(current_ability)
			var current_cast_remaining := maxf(
				float(_get_property_value(enemy, "cast_timer", 0.0)),
				0.0
			)

			if CAST_END_INTERRUPTION_ABILITIES.has(current_ability_id):
				earliest_seconds = minf(
					earliest_seconds,
					current_cast_remaining
				)

			# Cast-start displacement has already happened once the ability is active.
			# The unit's forced-movement state remains the cancellation fallback.
			var current_is_basic_attack_trigger := bool(_get_property_value(
				enemy,
				"current_ability_is_basic_attack_trigger",
				false
			))
			var recovery_seconds := seconds_until_next_cast

			if (
				not current_is_basic_attack_trigger
				and enemy.has_method("get_ability_recovery_time")
			):
				recovery_seconds = maxf(
					float(enemy.get_ability_recovery_time(current_ability)),
					0.0
				)

			seconds_until_next_cast = current_cast_remaining + recovery_seconds

		var next_ability = _get_property_value(enemy, "next_ability", null)
		var next_ability_id := _get_ability_id(next_ability)

		if not (
			CAST_START_INTERRUPTION_ABILITIES.has(next_ability_id)
			or CAST_END_INTERRUPTION_ABILITIES.has(next_ability_id)
		):
			continue

		var seconds_until_interruption := seconds_until_next_cast

		if CAST_END_INTERRUPTION_ABILITIES.has(next_ability_id):
			var ability_speed := (
				maxf(float(enemy.get_ability_speed_multiplier()), 0.01)
				if enemy.has_method("get_ability_speed_multiplier")
				else 1.0
			)
			seconds_until_interruption += (
				maxf(float(_get_property_value(next_ability, "cast_time", 0.0)), 0.0)
				/ ability_speed
			)

		earliest_seconds = minf(earliest_seconds, seconds_until_interruption)

	return -1.0 if is_inf(earliest_seconds) else earliest_seconds


func _get_current_enemy_threat_sources() -> Array:
	var current_sources := enemy_threat_sources.duplicate()

	for known_source in enemy_threat_sources:
		if not is_valid_node(known_source) or known_source.get_tree() == null:
			continue

		for grouped_source in known_source.get_tree().get_nodes_in_group(
			"enemy_threat_source"
		):
			if not current_sources.has(grouped_source):
				current_sources.append(grouped_source)

		break

	return current_sources


func _get_ability_id(ability: Variant) -> String:
	if not ability is Object:
		return ""

	return String(_get_property_value(ability as Object, "ability_id", ""))


func _get_property_value(object: Object, property_name: String, fallback: Variant) -> Variant:
	if object == null or not is_instance_valid(object):
		return fallback

	for property_data in object.get_property_list():
		if String(property_data.get("name", "")) == property_name:
			return object.get(property_name)

	return fallback


func select_target(
	scope: Dictionary,
	healer: Node,
	allow_fallback: bool = true,
	fallback_range_units: float = 0.0
) -> Dictionary:
	var scoped_target := _select_best_target(
		get_living_units_in_scope(scope),
		healer
	)

	if scoped_target != null:
		return {"target": scoped_target, "is_fallback": false}

	if not allow_fallback:
		return {"target": null, "is_fallback": false}

	var fallback_candidates: Array = []

	for party_member in party_members:
		if not _is_injured_projected_candidate(party_member, healer):
			continue

		if not _is_fallback_in_range(healer, party_member, fallback_range_units):
			continue

		fallback_candidates.append(party_member)

	return {
		"target": _select_best_target(fallback_candidates, healer),
		"is_fallback": not fallback_candidates.is_empty()
	}


func is_target_eligible(
	scope: Dictionary,
	target: Node,
	healer: Node,
	is_fallback: bool = false,
	fallback_range_units: float = 0.0
) -> bool:
	if not _is_injured_projected_candidate(target, healer):
		return false

	if not is_fallback:
		return get_living_units_in_scope(scope).has(target)

	if _select_best_target(get_living_units_in_scope(scope), healer) != null:
		return false

	return _is_fallback_in_range(healer, target, fallback_range_units)


func get_scope_label(scope: Dictionary) -> String:
	match String(scope.get("type", "")):
		SCOPE_ACTIVE_TANK:
			return "the active tank"
		SCOPE_RAID:
			return "the raid"
		CommandSchemaScript.SELECTOR_CLASS:
			return String(scope.get("value", "")) + "s"
		CommandSchemaScript.SELECTOR_GROUP:
			return "Group " + str(int(scope.get("value", 0)))
		CommandSchemaScript.SELECTOR_UNIT_IDENTITY:
			return (
				String(scope.get("class", "Raider"))
				+ " "
				+ str(int(scope.get("number", 0)))
			)
		CommandSchemaScript.SELECTOR_UNIT:
			var unit_value = scope.get("unit", null)

			if unit_value is Node and is_instance_valid(unit_value):
				if unit_value.has_method("get_display_name"):
					return String(unit_value.get_display_name())

				return String(unit_value.name)

	return "assigned targets"


func _select_best_target(candidates: Array, healer: Node) -> Node:
	var eligible: Array = []

	for candidate in candidates:
		if _is_injured_projected_candidate(candidate, healer):
			eligible.append(candidate)

	if eligible.is_empty():
		return null

	eligible.sort_custom(func(a: Node, b: Node) -> bool:
		var a_percent := _get_projected_health_percent(a, healer)
		var b_percent := _get_projected_health_percent(b, healer)

		if not is_equal_approx(a_percent, b_percent):
			return a_percent < b_percent

		var a_missing := _get_missing_health(a)
		var b_missing := _get_missing_health(b)

		if a_missing != b_missing:
			return a_missing > b_missing

		return _get_roster_order(a) < _get_roster_order(b)
	)

	return eligible[0] as Node


func _is_injured_projected_candidate(target: Node, healer: Node) -> bool:
	if not is_unit_alive(target):
		return false

	if not target.has_method("get_current_health") or not target.has_method("get_max_health"):
		return false

	var current_health := int(target.get_current_health())
	var max_health := int(target.get_max_health())

	if max_health <= 0 or current_health >= max_health:
		return false

	return current_health + _get_incoming_healing_from_others(target, healer) < max_health


func _get_projected_health_percent(target: Node, healer: Node) -> float:
	var max_health := int(target.get_max_health())

	if max_health <= 0:
		return 1.0

	var projected_health := (
		int(target.get_current_health())
		+ _get_incoming_healing_from_others(target, healer)
	)
	return clampf(float(projected_health) / float(max_health), 0.0, 1.0)


func _get_incoming_healing_from_others(target: Node, healer: Node) -> int:
	if not target.has_method("get_incoming_healing_total"):
		return 0

	return int(target.get_incoming_healing_total(healer))


func _get_missing_health(target: Node) -> int:
	return maxi(
		int(target.get_max_health()) - int(target.get_current_health()),
		0
	)


func _get_roster_order(target: Node) -> int:
	var roster_index := party_members.find(target)
	return roster_index if roster_index >= 0 else party_members.size()


func _is_fallback_in_range(
	healer: Node,
	target: Node,
	range_units: float
) -> bool:
	if healer == target:
		return true

	if range_units <= 0.0:
		return false

	if healer.has_method("is_node_in_range_units"):
		return bool(healer.is_node_in_range_units(target, range_units))

	return false


func is_unit_alive(unit: Node) -> bool:
	if not is_valid_node(unit):
		return false

	if unit.has_method("is_alive"):
		return bool(unit.is_alive())

	return true


func is_valid_node(node: Node) -> bool:
	return node != null and is_instance_valid(node)
