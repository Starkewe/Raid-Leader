extends RefCounted
class_name HealingCoverageCoordinator

const CombatAutoPositionerScript := preload(
	"res://scripts/combat/combat_auto_positioner.gd"
)
const CombatMeasurementsScript := preload(
	"res://scripts/combat/combat_measurements.gd"
)
const MovementSlotResolverScript := preload(
	"res://scripts/combat/movement_slot_resolver.gd"
)

var anchors_by_healer_id: Dictionary = {}
var last_material_signature: String = ""


func clear() -> void:
	anchors_by_healer_id.clear()
	last_material_signature = ""


func get_anchor_for_healer(boss_node: Node, healer: Node2D) -> Dictionary:
	if boss_node == null or healer == null or not is_instance_valid(boss_node):
		return {}

	var party_members := _get_party_members(boss_node, healer)
	var broad_healers := _get_broad_scope_healers(party_members)

	if not broad_healers.has(healer):
		anchors_by_healer_id.erase(healer.get_instance_id())
		return {}

	var signature := _build_material_signature(
		boss_node,
		party_members,
		broad_healers
	)

	if signature != last_material_signature:
		_recompute_anchors(boss_node, party_members, broad_healers)
		last_material_signature = signature

	var anchor_value: Variant = anchors_by_healer_id.get(
		healer.get_instance_id(),
		{}
	)
	return Dictionary(anchor_value).duplicate(true) if anchor_value is Dictionary else {}


func _recompute_anchors(
	boss_node: Node,
	party_members: Array,
	healers: Array
) -> void:
	var previous_anchors := anchors_by_healer_id.duplicate(true)
	var next_anchors: Dictionary = {}
	var used_region_keys: Array[String] = []
	var globally_covered: Dictionary = {}

	for healer_value in healers:
		var healer := healer_value as Node2D

		if healer == null:
			continue

		var candidates := _get_anchor_candidates(boss_node, healer)

		if candidates.is_empty():
			continue

		var distinct_candidates: Array[Dictionary] = []

		for candidate_value in candidates:
			var candidate := Dictionary(candidate_value)

			if not used_region_keys.has(String(candidate.get("key", ""))):
				distinct_candidates.append(candidate)

		if not distinct_candidates.is_empty():
			candidates = distinct_candidates

		var scoped_units := _get_scoped_units(healer)
		var range_pixels := CombatMeasurementsScript.range_units_to_pixels(
			maxf(float(healer.get("cast_range_units")), 0.0)
		)
		var previous_value: Variant = previous_anchors.get(
			healer.get_instance_id(),
			{}
		)
		var previous_anchor := (
			Dictionary(previous_value)
			if previous_value is Dictionary
			else {}
		)
		var best: Dictionary = {}
		var best_score: Array = []

		for candidate_value in candidates:
			var candidate := Dictionary(candidate_value)
			var position: Vector2 = candidate["position"]
			var scoped_coverage := _count_covered_units(
				position,
				scoped_units,
				range_pixels
			)
			var new_scoped_coverage := 0

			for scoped_unit in scoped_units:
				if (
					_is_living_node_2d(scoped_unit)
					and position.distance_to(
						(scoped_unit as Node2D).global_position
					) <= range_pixels
					and not globally_covered.has(scoped_unit.get_instance_id())
				):
					new_scoped_coverage += 1

			var newly_covered := 0
			var total_covered := 0

			for party_member in party_members:
				if not _is_living_node_2d(party_member):
					continue

				if position.distance_to((party_member as Node2D).global_position) > range_pixels:
					continue

				total_covered += 1

				if not globally_covered.has(party_member.get_instance_id()):
					newly_covered += 1

			var key := String(candidate.get("key", ""))
			var preserved := 1 if (
				String(previous_anchor.get("key", "")) == key
				and _positions_close(
					position,
					previous_anchor.get("position", Vector2.INF)
				)
			) else 0
			var travel := healer.global_position.distance_to(position)
			var score := [
				new_scoped_coverage,
				scoped_coverage,
				newly_covered,
				total_covered,
				preserved,
				-travel
			]

			if best.is_empty() or _score_is_better(score, best_score, key, String(best.get("key", ""))):
				best = candidate.duplicate(true)
				best_score = score

		if best.is_empty():
			continue

		next_anchors[healer.get_instance_id()] = best
		var best_key := String(best.get("key", ""))

		if not used_region_keys.has(best_key):
			used_region_keys.append(best_key)

		var best_position: Vector2 = best["position"]

		for party_member in party_members:
			if (
				_is_living_node_2d(party_member)
				and best_position.distance_to(
					(party_member as Node2D).global_position
				) <= range_pixels
			):
				globally_covered[party_member.get_instance_id()] = true

	anchors_by_healer_id = next_anchors


func _get_anchor_candidates(boss_node: Node, healer: Node2D) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var clearance := maxf(float(healer.get("mini_region_footprint_radius")), 0.0)
	clearance += MovementSlotResolverScript.MINI_REGION_ENTRY_MARGIN_PIXELS
	var hazards := CombatAutoPositionerScript.get_active_avoidable_hazards(
		boss_node
	)

	for region in MovementSlotResolverScript.REGION_ORDER:
		for range_name in MovementSlotResolverScript.RANGE_ORDER:
			var key := MovementSlotResolverScript.get_mini_region_key(
				String(region),
				String(range_name)
			)
			var slot := MovementSlotResolverScript.get_slot_position(
				boss_node,
				String(region),
				String(range_name)
			)
			var safe_position: Dictionary = {}

			if CombatAutoPositionerScript.is_position_safe(
				slot,
				boss_node,
				clearance,
				hazards
			):
				var route := CombatAutoPositionerScript.build_safe_route_to_position(
					boss_node,
					healer.global_position,
					slot,
					clearance,
					hazards
				)

				if bool(route.get("found", false)):
					safe_position = {"position": slot}
			else:
				safe_position = CombatAutoPositionerScript.find_nearest_safe_position_in_range(
					boss_node,
					healer.global_position,
					slot,
					120.0,
					clearance,
					0.0,
					hazards
				)

			if safe_position.is_empty():
				continue

			var resolved_position: Vector2 = safe_position["position"]
			var resolved_region := MovementSlotResolverScript.get_mini_region_from_position(
				boss_node,
				resolved_position
			)
			key = String(resolved_region.get("key", key))

			candidates.append({
				"key": key,
				"region": String(resolved_region.get("region", region)),
				"range": String(resolved_region.get("range", range_name)),
				"position": resolved_position
			})

	return candidates


func _get_party_members(boss_node: Node, healer: Node) -> Array:
	var party_value: Variant = boss_node.get("party_members")

	if party_value is Array and not party_value.is_empty():
		return (party_value as Array).duplicate()

	var selector = healer.get("healing_target_selector")

	if selector != null:
		var selector_party: Variant = selector.get("party_members")

		if selector_party is Array:
			return (selector_party as Array).duplicate()

	return []


func _get_broad_scope_healers(party_members: Array) -> Array:
	var healers: Array = []

	for party_member in party_members:
		if (
			not _is_living_node_2d(party_member)
			or not party_member.has_method("has_healing_assignment")
			or not bool(party_member.has_healing_assignment())
		):
			continue

		var scope_value: Variant = party_member.get("healing_scope")

		if scope_value is Dictionary and _is_broad_scope(scope_value):
			healers.append(party_member)

	return healers


func _get_scoped_units(healer: Node) -> Array:
	var selector = healer.get("healing_target_selector")
	var scope_value: Variant = healer.get("healing_scope")

	if selector == null or not scope_value is Dictionary:
		return []

	return selector.get_living_units_in_scope(scope_value)


func _is_broad_scope(scope: Dictionary) -> bool:
	return String(scope.get("type", "")) in ["raid", "group", "class"]


func _count_covered_units(
	position: Vector2,
	units: Array,
	range_pixels: float
) -> int:
	var covered := 0

	for unit in units:
		if (
			_is_living_node_2d(unit)
			and position.distance_to((unit as Node2D).global_position) <= range_pixels
		):
			covered += 1

	return covered


func _build_material_signature(
	boss_node: Node,
	party_members: Array,
	healers: Array
) -> String:
	var parts: Array[String] = []

	for party_member in party_members:
		if not _is_living_node_2d(party_member):
			continue

		var mini_region := MovementSlotResolverScript.get_mini_region_from_position(
			boss_node,
			(party_member as Node2D).global_position
		)
		parts.append(
			"u:" + str(party_member.get_instance_id())
			+ ":" + String(mini_region.get("key", ""))
		)

	for healer in healers:
		parts.append(
			"h:" + str(healer.get_instance_id())
			+ ":" + str(healer.get("healing_scope"))
		)

	for hazard_value in CombatAutoPositionerScript.get_active_avoidable_hazards(
		boss_node
	):
		var hazard := hazard_value as Node2D

		if hazard == null:
			continue

		var definition = hazard.get("definition")
		parts.append(
			"z:" + str(hazard.get_instance_id())
			+ ":" + str(hazard.global_position.snapped(Vector2.ONE))
			+ ":" + str(definition.get("affected_radius"))
		)

	return "|".join(parts)


func _score_is_better(
	candidate: Array,
	best: Array,
	candidate_key: String,
	best_key: String
) -> bool:
	for index in range(candidate.size()):
		if is_equal_approx(float(candidate[index]), float(best[index])):
			continue

		return float(candidate[index]) > float(best[index])

	return candidate_key < best_key


func _positions_close(a_value: Variant, b_value: Variant) -> bool:
	return (
		a_value is Vector2
		and b_value is Vector2
		and (a_value as Vector2).distance_to(b_value as Vector2) <= 1.0
	)


func _is_living_node_2d(node: Variant) -> bool:
	if not node is Node2D or not is_instance_valid(node):
		return false

	if node.has_method("is_alive"):
		return bool(node.is_alive())

	return true
