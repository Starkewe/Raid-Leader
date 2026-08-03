extends RefCounted
class_name CombatAutoPositioner

const CombatHazardScript := preload("res://scripts/combat/combat_hazard.gd")
const MovementSlotResolverScript := preload(
	"res://scripts/combat/movement_slot_resolver.gd"
)

const PERSONAL_REACTION_OWNER := "raider_personal"
const AVOID_AREA_RESPONSE := "avoid_area"
const ROUTE_ARRIVAL_DISTANCE := 10.0
const CANDIDATE_RADIAL_STEP := 64.0
const CANDIDATE_DIRECTIONS := 24

var support_transition: Dictionary = {}
var support_target_instance_id: int = 0
var support_target_key: String = ""
var escape_transition: Dictionary = {}


func cancel_all() -> void:
	cancel_support_route()
	cancel_hazard_escape()


func cancel_support_route() -> void:
	support_transition.clear()
	support_target_instance_id = 0
	support_target_key = ""


func cancel_hazard_escape() -> void:
	escape_transition.clear()


func get_support_movement_step(
	unit: Node2D,
	boss_node: Node,
	target: Node2D,
	clearance_pixels: float,
	action_range_pixels: float = 0.0
) -> Dictionary:
	if unit == null or target == null:
		cancel_support_route()
		return {}

	if boss_node == null or not is_instance_valid(boss_node):
		cancel_support_route()
		return {
			"handled": true,
			"destination": target.global_position,
			"uses_direct_fallback": false
		}

	var hazards := get_active_avoidable_hazards(boss_node)
	var target_radius := _get_node_combat_radius(target)
	var maximum_center_distance := maxf(action_range_pixels + target_radius, 0.0)
	var goal := find_nearest_safe_position_in_range(
		boss_node,
		unit.global_position,
		target.global_position,
		maximum_center_distance,
		clearance_pixels,
		0.0,
		hazards
	)

	if goal.is_empty():
		cancel_support_route()
		return {
			"handled": true,
			"wait_safe": true,
			"uses_direct_fallback": false
		}

	return _get_route_step(
		unit,
		boss_node,
		goal["position"],
		clearance_pixels,
		hazards,
		false,
		Dictionary(goal.get("route", {}))
	)


func get_position_movement_step(
	unit: Node2D,
	boss_node: Node,
	destination: Vector2,
	clearance_pixels: float
) -> Dictionary:
	if unit == null:
		return {}

	var hazards := get_active_avoidable_hazards(boss_node)

	if not is_position_safe(destination, boss_node, clearance_pixels, hazards):
		return {"handled": true, "wait_safe": true}

	return _get_route_step(
		unit,
		boss_node,
		destination,
		clearance_pixels,
		hazards,
		false
	)


func get_action_movement_step(
	unit: Node2D,
	boss_node: Node,
	target: Node2D,
	action_range_pixels: float,
	clearance_pixels: float
) -> Dictionary:
	if unit == null or target == null:
		return {}

	var hazards := get_active_avoidable_hazards(boss_node)
	var target_radius := _get_node_combat_radius(target)
	var goal := find_nearest_safe_position_in_range(
		boss_node,
		unit.global_position,
		target.global_position,
		target_radius + maxf(action_range_pixels, 0.0),
		clearance_pixels,
		target_radius + clearance_pixels,
		hazards
	)

	if goal.is_empty():
		return {"handled": true, "wait_safe": true}

	return _get_route_step(
		unit,
		boss_node,
		goal["position"],
		clearance_pixels,
		hazards,
		false,
		Dictionary(goal.get("route", {}))
	)


func _get_route_step(
	unit: Node2D,
	boss_node: Node,
	destination: Vector2,
	clearance_pixels: float,
	hazards: Array,
	is_escape: bool,
	prebuilt_route: Dictionary = {}
) -> Dictionary:
	var route := prebuilt_route.duplicate(true)

	if route.is_empty():
		route = build_safe_route_to_position(
			boss_node,
			unit.global_position,
			destination,
			clearance_pixels,
			hazards,
			is_escape
		)

	if not bool(route.get("found", false)):
		return {
			"handled": true,
			"wait_safe": true,
			"uses_direct_fallback": false
		}

	var waypoints: Array = route.get("waypoints", [])
	var mini_regions: Array = route.get("mini_regions", [])
	var next_destination := destination
	var next_region: Dictionary = {}

	if not waypoints.is_empty():
		next_destination = waypoints[0]

	if not mini_regions.is_empty():
		next_region = Dictionary(mini_regions[0]).duplicate(true)

	var transition := {
		"destination": next_destination,
		"waypoints": waypoints.duplicate(true),
		"mini_regions": mini_regions.duplicate(true),
		"uses_direct_fallback": false
	}

	if not next_region.is_empty():
		transition.merge(next_region, true)

	if is_escape:
		escape_transition = transition
	else:
		support_transition = transition

	return {
		"handled": true,
		"destination": next_destination,
		"mini_region": next_region,
		"uses_direct_fallback": false
	}


func get_ground_hazard_escape_step(
	unit: Node2D,
	boss_node: Node,
	clearance_pixels: float
) -> Dictionary:
	if unit == null or boss_node == null or not is_instance_valid(boss_node):
		cancel_hazard_escape()
		return {}

	var hazards := get_active_avoidable_hazards(boss_node)
	var overlapping := get_hazards_overlapping_position(
		unit.global_position,
		boss_node,
		clearance_pixels,
		hazards
	)

	if overlapping.is_empty():
		cancel_hazard_escape()
		return {"hazard_active": false, "handled": false}

	var hazard_signature := _get_hazard_state_signature(hazards)

	if not escape_transition.is_empty():
		var cached_step := _get_cached_hazard_escape_step(
			unit,
			boss_node,
			clearance_pixels,
			hazards,
			hazard_signature
		)

		if not cached_step.is_empty():
			cached_step["hazard_active"] = true
			return cached_step

	var step := _create_ground_hazard_escape_plan(
		unit,
		boss_node,
		clearance_pixels,
		hazards,
		overlapping,
		hazard_signature
	)
	step["hazard_active"] = true
	return step


func _create_ground_hazard_escape_plan(
	unit: Node2D,
	boss_node: Node,
	clearance_pixels: float,
	hazards: Array,
	overlapping_hazards: Array,
	hazard_signature: String
) -> Dictionary:
	var escape := find_nearest_safe_escape_position(
		unit.global_position,
		boss_node,
		clearance_pixels,
		hazards,
		overlapping_hazards
	)

	if escape.is_empty():
		_cache_failed_hazard_escape(unit.global_position, hazard_signature)
		return {"handled": false}

	var destination_value: Variant = escape.get("position", null)

	if not destination_value is Vector2:
		_cache_failed_hazard_escape(unit.global_position, hazard_signature)
		return {"handled": false}

	var step := _get_route_step(
		unit,
		boss_node,
		destination_value,
		clearance_pixels,
		hazards,
		true,
		Dictionary(escape.get("route", {}))
	)

	if bool(step.get("wait_safe", false)) or escape_transition.is_empty():
		_cache_failed_hazard_escape(unit.global_position, hazard_signature)
		return {"handled": false}

	escape_transition["waypoint_index"] = 0
	escape_transition["hazard_signature"] = hazard_signature
	escape_transition["clearance_pixels"] = clearance_pixels
	return step


func _get_cached_hazard_escape_step(
	unit: Node2D,
	boss_node: Node,
	clearance_pixels: float,
	hazards: Array,
	hazard_signature: String
) -> Dictionary:
	if bool(escape_transition.get("blocked", false)):
		var blocked_position_value: Variant = escape_transition.get(
			"source_position",
			null
		)
		var same_blocked_position := (
			blocked_position_value is Vector2
			and unit.global_position.distance_to(blocked_position_value)
			<= ROUTE_ARRIVAL_DISTANCE
		)

		if (
			String(escape_transition.get("hazard_signature", ""))
			== hazard_signature
			and same_blocked_position
		):
			return {"handled": false}

		cancel_hazard_escape()
		return {}

	var hazard_geometry_changed := (
		String(escape_transition.get("hazard_signature", ""))
		!= hazard_signature
		or not is_equal_approx(
			float(escape_transition.get("clearance_pixels", -1.0)),
			clearance_pixels
		)
	)

	if hazard_geometry_changed:
		if not _is_cached_hazard_escape_valid(
			unit.global_position,
			boss_node,
			clearance_pixels,
			hazards
		):
			cancel_hazard_escape()
			return {}

		escape_transition["hazard_signature"] = hazard_signature
		escape_transition["clearance_pixels"] = clearance_pixels

	_advance_cached_hazard_escape(unit.global_position)
	return _get_cached_hazard_escape_response()


func _advance_cached_hazard_escape(unit_position: Vector2) -> void:
	var waypoints: Array = escape_transition.get("waypoints", [])
	var waypoint_index := maxi(int(escape_transition.get("waypoint_index", 0)), 0)

	if waypoints.is_empty() or waypoint_index >= waypoints.size():
		cancel_hazard_escape()
		return

	# The final waypoint remains authoritative until the unit is actually clear
	# of every avoidable hazard. This prevents the arrival tolerance from causing
	# a search loop just inside the expanded hazard radius.
	while waypoint_index < waypoints.size() - 1:
		var waypoint_value: Variant = waypoints[waypoint_index]

		if (
			not waypoint_value is Vector2
			or unit_position.distance_to(waypoint_value) > ROUTE_ARRIVAL_DISTANCE
		):
			break

		waypoint_index += 1

	escape_transition["waypoint_index"] = waypoint_index
	escape_transition["destination"] = waypoints[waypoint_index]


func _get_cached_hazard_escape_response() -> Dictionary:
	if escape_transition.is_empty():
		return {}

	var waypoints: Array = escape_transition.get("waypoints", [])
	var waypoint_index := maxi(int(escape_transition.get("waypoint_index", 0)), 0)

	if waypoints.is_empty() or waypoint_index >= waypoints.size():
		cancel_hazard_escape()
		return {}

	var destination_value: Variant = waypoints[waypoint_index]

	if not destination_value is Vector2:
		cancel_hazard_escape()
		return {}

	var mini_regions: Array = escape_transition.get("mini_regions", [])
	var next_region: Dictionary = {}

	if waypoint_index < mini_regions.size():
		var region_value: Variant = mini_regions[waypoint_index]

		if region_value is Dictionary:
			next_region = Dictionary(region_value).duplicate(true)

	return {
		"handled": true,
		"destination": destination_value,
		"mini_region": next_region,
		"uses_direct_fallback": false
	}


func _is_cached_hazard_escape_valid(
	unit_position: Vector2,
	boss_node: Node,
	clearance_pixels: float,
	hazards: Array
) -> bool:
	var waypoints: Array = escape_transition.get("waypoints", [])
	var waypoint_index := maxi(int(escape_transition.get("waypoint_index", 0)), 0)

	if waypoints.is_empty() or waypoint_index >= waypoints.size():
		return false

	var segment_start := unit_position

	for index in range(waypoint_index, waypoints.size()):
		var waypoint_value: Variant = waypoints[index]

		if not waypoint_value is Vector2:
			return false

		var waypoint: Vector2 = waypoint_value

		if not is_position_safe(waypoint, boss_node, clearance_pixels, hazards):
			return false

		if not _is_route_segment_safe(
			segment_start,
			waypoint,
			clearance_pixels,
			hazards,
			index == waypoint_index
		):
			return false

		segment_start = waypoint

	return true


func _cache_failed_hazard_escape(
	source_position: Vector2,
	hazard_signature: String
) -> void:
	escape_transition = {
		"blocked": true,
		"source_position": source_position,
		"hazard_signature": hazard_signature
	}


static func find_nearest_safe_escape_position(
	source_position: Vector2,
	boss_node: Node,
	clearance_pixels: float,
	hazards: Array,
	overlapping_hazards: Array
) -> Dictionary:
	var candidates: Array[Vector2] = []
	var maximum_radius := CANDIDATE_RADIAL_STEP

	for hazard_value in overlapping_hazards:
		var hazard := hazard_value as Node2D

		if hazard == null:
			continue

		maximum_radius = maxf(
			maximum_radius,
			source_position.distance_to(hazard.global_position)
			+ _get_hazard_radius(hazard)
			+ clearance_pixels
			+ CANDIDATE_RADIAL_STEP
		)

	var radial_distance := CANDIDATE_RADIAL_STEP

	while radial_distance <= maximum_radius + CANDIDATE_RADIAL_STEP * 4.0:
		for direction_index in range(CANDIDATE_DIRECTIONS):
			var direction := Vector2.from_angle(
				TAU * float(direction_index) / float(CANDIDATE_DIRECTIONS)
			)
			candidates.append(source_position + direction * radial_distance)

		radial_distance += CANDIDATE_RADIAL_STEP

	var best := _select_nearest_reachable_safe_candidate(
		source_position,
		candidates,
		boss_node,
		clearance_pixels,
		hazards,
		true
	)

	if not best.is_empty():
		return best

	# Dense overlaps can require leaving the current mini-region before a clear
	# line exists. Search all authored region anchors as a second-stage route.
	for region in MovementSlotResolverScript.REGION_ORDER:
		for range_name in MovementSlotResolverScript.RANGE_ORDER:
			var candidate := _get_safe_point_in_mini_region(
				boss_node,
				source_position,
				String(region),
				String(range_name),
				clearance_pixels,
				hazards
			)

			if not candidate.is_empty():
				candidates.append(candidate["position"])

	return _select_nearest_reachable_safe_candidate(
		source_position,
		candidates,
		boss_node,
		clearance_pixels,
		hazards,
		true
	)


static func find_nearest_safe_position_in_range(
	boss_node: Node,
	source_position: Vector2,
	target_position: Vector2,
	maximum_center_distance: float,
	clearance_pixels: float,
	minimum_center_distance: float = 0.0,
	hazards_override: Array = []
) -> Dictionary:
	var hazards := (
		hazards_override
		if not hazards_override.is_empty()
		else get_active_avoidable_hazards(boss_node)
	)
	var candidates: Array[Vector2] = []
	var maximum_distance := maxf(maximum_center_distance, minimum_center_distance)

	if (
		source_position.distance_to(target_position) <= maximum_distance + 0.01
		and source_position.distance_to(target_position) >= minimum_center_distance - 0.01
	):
		candidates.append(source_position)

	if minimum_center_distance <= 0.01:
		candidates.append(target_position)

	var radii: Array[float] = []

	for fraction in [1.0, 0.75, 0.5, 0.25]:
		var radius := lerpf(minimum_center_distance, maximum_distance, fraction)

		if radius > 0.01 and not radii.has(radius):
			radii.append(radius)

	if minimum_center_distance > 0.01 and not radii.has(minimum_center_distance):
		radii.append(minimum_center_distance)

	for radius in radii:
		for direction_index in range(CANDIDATE_DIRECTIONS):
			candidates.append(
				target_position
				+ Vector2.from_angle(
					TAU * float(direction_index) / float(CANDIDATE_DIRECTIONS)
				) * radius
			)

	return _select_nearest_reachable_safe_candidate(
		source_position,
		candidates,
		boss_node,
		clearance_pixels,
		hazards,
		false
	)


static func _select_nearest_reachable_safe_candidate(
	source_position: Vector2,
	candidates: Array[Vector2],
	boss_node: Node,
	clearance_pixels: float,
	hazards: Array,
	allow_escape_from_source: bool
) -> Dictionary:
	var safe_candidates: Array[Vector2] = []

	for candidate in candidates:
		if not is_position_safe(candidate, boss_node, clearance_pixels, hazards):
			continue

		if not safe_candidates.has(candidate):
			safe_candidates.append(candidate)

	safe_candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var a_distance := source_position.distance_squared_to(a)
		var b_distance := source_position.distance_squared_to(b)

		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance

		return _position_sort_key(a) < _position_sort_key(b)
	)

	# Most movement has line of sight to one of the nearest candidates. Checking
	# those segments first keeps per-frame role initiative inexpensive.
	for candidate in safe_candidates:
		if _is_route_segment_safe(
			source_position,
			candidate,
			clearance_pixels,
			hazards,
			allow_escape_from_source
		):
			return {
				"position": candidate,
				"route": {
					"found": true,
					"mini_regions": [],
					"waypoints": [candidate],
					"uses_direct_fallback": false
				}
			}

	# If every direct segment is blocked, ask the mini-region graph for a detour.
	# Candidates are already distance ordered, so the first reachable one is the
	# stable nearest safe action position.
	for candidate_index in range(mini(safe_candidates.size(), 16)):
		var candidate := safe_candidates[candidate_index]
		var route := build_safe_route_to_position(
			boss_node,
			source_position,
			candidate,
			clearance_pixels,
			hazards,
			allow_escape_from_source
		)

		if not bool(route.get("found", false)):
			continue

		return {
			"position": candidate,
			"route": route.duplicate(true)
		}

	return {}


static func build_safe_support_route(
	boss_node: Node,
	source_position: Vector2,
	target_position: Vector2,
	safety_inset_pixels: float,
	_blocked_keys_override: Array[String] = []
) -> Dictionary:
	return build_safe_route_to_position(
		boss_node,
		source_position,
		target_position,
		safety_inset_pixels,
		get_active_avoidable_hazards(boss_node),
		false
	)


static func build_safe_route_to_position(
	boss_node: Node,
	source_position: Vector2,
	target_position: Vector2,
	clearance_pixels: float,
	hazards_override: Array = [],
	allow_escape_from_source: bool = false
) -> Dictionary:
	if boss_node == null or not is_instance_valid(boss_node):
		return {
			"found": true,
			"mini_regions": [],
			"waypoints": [target_position],
			"uses_direct_fallback": false
		}

	var hazards := (
		hazards_override
		if not hazards_override.is_empty()
		else get_active_avoidable_hazards(boss_node)
	)

	if not is_position_safe(target_position, boss_node, clearance_pixels, hazards):
		return {
			"found": false,
			"mini_regions": [],
			"waypoints": [],
			"uses_direct_fallback": false
		}

	if _is_route_segment_safe(
		source_position,
		target_position,
		clearance_pixels,
		hazards,
		allow_escape_from_source
	):
		return {
			"found": true,
			"mini_regions": [],
			"waypoints": [target_position],
			"uses_direct_fallback": false
		}

	var source_region := get_mini_region_for_position(boss_node, source_position)
	var target_region := get_mini_region_for_position(boss_node, target_position)
	var source_key := String(source_region.get("key", ""))
	var queue: Array[Dictionary] = [{
		"mini_region": source_region,
		"position": source_position,
		"mini_regions": [],
		"waypoints": []
	}]
	var visited := {source_key: 0.0}
	var queue_index := 0

	while queue_index < queue.size():
		var state := queue[queue_index]
		queue_index += 1
		var state_position: Vector2 = state["position"]

		if _is_route_segment_safe(
			state_position,
			target_position,
			clearance_pixels,
			hazards,
			allow_escape_from_source and state["waypoints"].is_empty()
		):
			var final_waypoints: Array = state["waypoints"].duplicate(true)
			final_waypoints.append(target_position)
			return {
				"found": true,
				"mini_regions": state["mini_regions"].duplicate(true),
				"waypoints": final_waypoints,
				"uses_direct_fallback": false
			}

		var neighbors := _get_ordered_orthogonal_neighbors(
			state["mini_region"],
			target_region
		)

		for neighbor_value in neighbors:
			var neighbor := Dictionary(neighbor_value)
			var neighbor_key := String(neighbor.get("key", ""))

			if visited.has(neighbor_key):
				continue

			var safe_point := _get_safe_point_in_mini_region(
				boss_node,
				state_position,
				String(neighbor.get("region", "")),
				String(neighbor.get("range", "")),
				clearance_pixels,
				hazards
			)

			if safe_point.is_empty():
				continue

			var next_position: Vector2 = safe_point["position"]

			if not _is_route_segment_safe(
				state_position,
				next_position,
				clearance_pixels,
				hazards,
				allow_escape_from_source and state["waypoints"].is_empty()
			):
				continue

			visited[neighbor_key] = true
			var next_regions: Array = state["mini_regions"].duplicate(true)
			var next_waypoints: Array = state["waypoints"].duplicate(true)
			next_regions.append(neighbor.duplicate(true))
			next_waypoints.append(next_position)
			queue.append({
				"mini_region": neighbor.duplicate(true),
				"position": next_position,
				"mini_regions": next_regions,
				"waypoints": next_waypoints
			})

	return {
		"found": false,
		"mini_regions": [],
		"waypoints": [],
		"uses_direct_fallback": false
	}


static func _get_safe_point_in_mini_region(
	boss_node: Node,
	reference_position: Vector2,
	region: String,
	range_name: String,
	clearance_pixels: float,
	hazards: Array
) -> Dictionary:
	var slot := MovementSlotResolverScript.get_slot_position(
		boss_node,
		region,
		range_name
	)
	var candidates: Array[Vector2] = [
		MovementSlotResolverScript.get_closest_point_in_mini_region(
			boss_node,
			reference_position,
			region,
			range_name,
			clearance_pixels
		),
		slot
	]

	for radius_value in [48.0, 96.0, 144.0]:
		var radius := float(radius_value)

		for direction_index in range(16):
			var sample: Vector2 = slot + Vector2.from_angle(
				TAU * float(direction_index) / 16.0
			) * radius
			candidates.append(
				MovementSlotResolverScript.get_closest_point_in_mini_region(
					boss_node,
					sample,
					region,
					range_name,
					clearance_pixels
				)
			)

	var best := Vector2.ZERO
	var best_distance := INF
	var found := false

	for candidate in candidates:
		if not is_position_safe(candidate, boss_node, clearance_pixels, hazards):
			continue

		var distance := reference_position.distance_to(candidate)

		if distance < best_distance - 0.001:
			best = candidate
			best_distance = distance
			found = true

	return {"position": best} if found else {}


static func get_active_avoidable_hazards(boss_node: Node) -> Array:
	var hazards: Array = []

	if boss_node == null or not is_instance_valid(boss_node):
		return hazards

	var encounter_objects_value: Variant = boss_node.get("encounter_objects")

	if not encounter_objects_value is Array:
		return hazards

	for encounter_object_value in encounter_objects_value:
		if typeof(encounter_object_value) != TYPE_OBJECT:
			continue

		if not is_instance_valid(encounter_object_value):
			continue

		if not encounter_object_value is CombatHazardScript:
			continue

		var hazard := encounter_object_value as Node

		if (
			hazard.is_queued_for_deletion()
			or bool(hazard.get("cleaned_up"))
			or hazard.get("definition") == null
		):
			continue

		var definition = hazard.get("definition")

		if (
			String(definition.get("reaction_owner")) != PERSONAL_REACTION_OWNER
			or String(definition.get("automatic_response")) != AVOID_AREA_RESPONSE
		):
			continue

		hazards.append(hazard)

	return hazards


static func _get_hazard_state_signature(hazards: Array) -> String:
	var entries: Array[String] = []

	for hazard_value in hazards:
		var hazard := hazard_value as Node2D

		if hazard == null or not is_instance_valid(hazard):
			continue

		entries.append(
			"%d:%.3f:%.3f:%s" % [
				hazard.get_instance_id(),
				hazard.global_position.x,
				hazard.global_position.y,
				_get_hazard_coverage_signature(hazard)
			]
		)

	entries.sort()
	return "|".join(entries)


static func get_active_hazard_mini_region_keys(boss_node: Node) -> Array[String]:
	var keys: Array[String] = []

	for hazard_value in get_active_avoidable_hazards(boss_node):
		var hazard := hazard_value as Node2D

		if hazard == null:
			continue

		var key := ""

		if hazard.has_method("get_coverage_mini_region_key"):
			key = String(hazard.get_coverage_mini_region_key())
		else:
			var mini_region := get_mini_region_for_position(
				boss_node,
				hazard.global_position
			)
			key = String(mini_region.get("key", ""))

		if not key.is_empty() and not keys.has(key):
			keys.append(key)

	return keys


static func get_hazards_overlapping_position(
	position: Vector2,
	_boss_node: Node,
	clearance_pixels: float,
	hazards_override: Array = []
) -> Array:
	var overlapping: Array = []

	for hazard_value in hazards_override:
		var hazard := hazard_value as Node2D

		if hazard == null or not is_instance_valid(hazard):
			continue

		if _hazard_contains_position(hazard, position, clearance_pixels):
			overlapping.append(hazard)

	return overlapping


static func is_position_safe(
	position: Vector2,
	_boss_node: Node,
	clearance_pixels: float,
	hazards_override: Array = []
) -> bool:
	for hazard_value in hazards_override:
		var hazard := hazard_value as Node2D

		if hazard == null or not is_instance_valid(hazard):
			continue

		if _hazard_contains_position(hazard, position, clearance_pixels):
			return false

	return true


static func is_route_segment_safe(
	start: Vector2,
	finish: Vector2,
	boss_node: Node,
	clearance_pixels: float,
	hazards_override: Array = []
) -> bool:
	var hazards := (
		hazards_override
		if not hazards_override.is_empty()
		else get_active_avoidable_hazards(boss_node)
	)
	return _is_route_segment_safe(
		start,
		finish,
		clearance_pixels,
		hazards,
		false
	)


static func _is_route_segment_safe(
	start: Vector2,
	finish: Vector2,
	clearance_pixels: float,
	hazards: Array,
	allow_escape_from_source: bool
) -> bool:
	for hazard_value in hazards:
		var hazard := hazard_value as Node2D

		if hazard == null or not is_instance_valid(hazard):
			continue

		if hazard.has_method("is_world_segment_safe"):
			if not bool(hazard.is_world_segment_safe(
				start,
				finish,
				clearance_pixels,
				allow_escape_from_source
			)):
				return false
			continue

		var radius := _get_hazard_radius(hazard) + maxf(clearance_pixels, 0.0)
		var start_distance := start.distance_to(hazard.global_position)

		if start_distance < radius and allow_escape_from_source:
			var finish_distance := finish.distance_to(hazard.global_position)
			var outward := start - hazard.global_position
			var travel := finish - start

			if (
				finish_distance >= radius
				and (outward.is_zero_approx() or outward.dot(travel) >= -0.001)
			):
				continue

		if _distance_from_point_to_segment(
			hazard.global_position,
			start,
			finish
		) < radius:
			return false

	return true


static func _distance_from_point_to_segment(
	point: Vector2,
	start: Vector2,
	finish: Vector2
) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()

	if length_squared <= 0.0001:
		return point.distance_to(start)

	var projection := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * projection)


static func _get_hazard_radius(hazard: Node) -> float:
	if hazard == null or not is_instance_valid(hazard):
		return 0.0

	if hazard.has_method("get_coverage_bounds_radius"):
		return maxf(float(hazard.get_coverage_bounds_radius()), 0.0)

	var definition = hazard.get("definition")

	if definition == null:
		return 0.0

	return maxf(float(definition.get("affected_radius")), 0.0)


static func _get_hazard_coverage_signature(hazard: Node) -> String:
	if hazard == null or not is_instance_valid(hazard):
		return "0.0"

	if hazard.has_method("get_coverage_signature"):
		return String(hazard.get_coverage_signature())

	return str(_get_hazard_radius(hazard))


static func _hazard_contains_position(
	hazard: Node,
	position: Vector2,
	clearance_pixels: float
) -> bool:
	if hazard == null or not is_instance_valid(hazard):
		return false

	if hazard.has_method("contains_world_position"):
		return bool(hazard.contains_world_position(position, clearance_pixels))

	return position.distance_to(hazard.global_position) < (
		_get_hazard_radius(hazard) + maxf(clearance_pixels, 0.0)
	)


static func _get_node_combat_radius(node: Node) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0

	if node.has_method("get_combat_radius"):
		return maxf(float(node.get_combat_radius()), 0.0)

	var radius_value: Variant = node.get("combat_radius")
	return 0.0 if radius_value == null else maxf(float(radius_value), 0.0)


static func _get_route_distance(source_position: Vector2, route: Dictionary) -> float:
	var distance := 0.0
	var previous := source_position

	for waypoint_value in route.get("waypoints", []):
		var waypoint := waypoint_value as Vector2
		distance += previous.distance_to(waypoint)
		previous = waypoint

	return distance


static func _position_sort_key(position: Vector2) -> String:
	return "%012.3f:%012.3f" % [position.x, position.y]


static func get_mini_region_for_position(
	boss_node: Node,
	position: Vector2
) -> Dictionary:
	if boss_node != null and boss_node.has_method("get_mini_region_for_position"):
		var mini_region_value: Variant = boss_node.call(
			"get_mini_region_for_position",
			position
		)

		if mini_region_value is Dictionary:
			return Dictionary(mini_region_value)

	return MovementSlotResolverScript.get_mini_region_from_position(
		boss_node,
		position
	)


static func _get_ordered_orthogonal_neighbors(
	current_mini_region: Dictionary,
	target_mini_region: Dictionary
) -> Array[Dictionary]:
	var current_region := String(current_mini_region.get("region", ""))
	var current_range := String(current_mini_region.get("range", ""))
	var candidates := MovementSlotResolverScript.get_adjacent_mini_regions(
		current_region,
		current_range
	)
	var neighbors: Array[Dictionary] = []

	for candidate_value in candidates:
		var candidate := Dictionary(candidate_value)
		var retains_region := String(candidate.get("region", "")) == current_region
		var retains_range := String(candidate.get("range", "")) == current_range

		if retains_region == retains_range:
			continue

		neighbors.append(candidate.duplicate(true))

	neighbors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := _get_transition_distance(a, target_mini_region)
		var b_distance := _get_transition_distance(b, target_mini_region)

		if a_distance != b_distance:
			return a_distance < b_distance

		return String(a.get("key", "")) < String(b.get("key", ""))
	)
	return neighbors


static func _get_transition_distance(
	mini_region: Dictionary,
	target_mini_region: Dictionary
) -> int:
	var region_index := MovementSlotResolverScript.REGION_ORDER.find(
		String(mini_region.get("region", ""))
	)
	var target_region_index := MovementSlotResolverScript.REGION_ORDER.find(
		String(target_mini_region.get("region", ""))
	)
	var range_index := MovementSlotResolverScript.RANGE_ORDER.find(
		String(mini_region.get("range", ""))
	)
	var target_range_index := MovementSlotResolverScript.RANGE_ORDER.find(
		String(target_mini_region.get("range", ""))
	)
	var region_count := MovementSlotResolverScript.REGION_ORDER.size()
	var clockwise_distance := (
		target_region_index - region_index + region_count
	) % region_count
	var counterclockwise_distance := (
		region_index - target_region_index + region_count
	) % region_count

	return mini(clockwise_distance, counterclockwise_distance) + abs(
		range_index - target_range_index
	)
