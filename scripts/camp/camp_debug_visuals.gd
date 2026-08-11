extends Node2D
class_name CampDebugVisuals

const FACILITY_FILL_COLOR := Color(0.92, 0.12, 0.10, 0.24)
const FACILITY_OUTLINE_COLOR := Color(1.0, 0.20, 0.16, 0.95)
const CLEARANCE_COLOR := Color(1.0, 0.70, 0.18, 0.95)
const RAIDER_BOUNDS_COLOR := Color(0.24, 0.92, 0.96, 0.95)
const PATH_LINE_COLOR := Color(0.28, 0.56, 1.0, 0.92)
const PATH_WAYPOINT_COLOR := Color(0.64, 0.38, 0.98, 0.98)
const STATIC_ROUTE_LINE_COLOR := Color(0.42, 0.51, 0.58, 0.68)
const ACTIVITY_SLOT_SEGMENT_COLOR := Color(0.38, 0.46, 0.50, 0.52)
const ROUTE_NODE_COLOR := Color(0.54, 0.72, 0.78, 0.96)
const BLOCKED_ROUTE_NODE_COLOR := Color(1.0, 0.26, 0.18, 0.98)
const ACTIVITY_SLOT_FREE_COLOR := Color(0.72, 0.82, 0.68, 0.92)
const ACTIVITY_SLOT_OCCUPIED_COLOR := Color(0.92, 0.67, 0.30, 0.98)
const ACTIVITY_SLOT_TARGET_COLOR := Color(0.32, 0.96, 0.78, 1.0)
const BLOCKED_ACTIVITY_SLOT_COLOR := Color(1.0, 0.26, 0.18, 0.98)
const LABEL_SHADOW_COLOR := Color(0.02, 0.04, 0.06, 0.94)
const LABEL_FONT_COLOR := Color(0.88, 0.96, 1.0, 1.0)
const CLEARANCE_DASH_LENGTH := 12.0
const ROUTE_DASH_LENGTH := 14.0
const DEBUG_LINE_WIDTH := 2.0
const PATH_LINE_WIDTH := 3.0
const WAYPOINT_RADIUS := 5.0
const ROUTE_NODE_RADIUS := 7.0
const ACTIVITY_SLOT_RADIUS := 4.5
const TARGET_MARKER_RADIUS := 10.0
const LABEL_FONT_SIZE := 14
const ACTIVE_PATH_STATES := ["walking", "conversation_approaching"]

var camp_root: Node = null
var population_controller: CampPopulationController = null
var geometry_visible: bool = false
var labels_visible: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 2000
	# Regression scenes can instantiate this overlay without going through
	# SceneFlow, so establish the same camp context here as well.
	GameState.set_raid_debug_context(GameState.RAID_DEBUG_CONTEXT_CAMP)
	GameState.set_raid_debug_mode(GameState.RAID_DEBUG_MODE_OFF)
	GameState.raid_debug_mode_changed.connect(_on_raid_debug_mode_changed)
	if camp_root == null:
		camp_root = get_parent()
	_resolve_population_controller()
	_refresh_render_layers()
	GameState.register_raid_debug_content(self)
	queue_redraw()


func setup(camp: Node, population: CampPopulationController = null) -> void:
	camp_root = camp
	population_controller = population
	_resolve_population_controller()
	_refresh_render_layers()
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _on_raid_debug_mode_changed(_mode: String) -> void:
	_refresh_render_layers()
	queue_redraw()


func _refresh_render_layers() -> void:
	var mode := GameState.get_raid_debug_mode()
	geometry_visible = mode in [
		GameState.RAID_DEBUG_MODE_ALL,
		GameState.RAID_DEBUG_MODE_GEOMETRY,
	]
	labels_visible = mode in [
		GameState.RAID_DEBUG_MODE_ALL,
		GameState.RAID_DEBUG_MODE_LABELS,
	]


func is_geometry_layer_visible() -> bool:
	return geometry_visible


func is_label_layer_visible() -> bool:
	return labels_visible


func get_facility_debug_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for facility in _get_facilities():
		var collision_rect := facility.get_collision_world_rect()
		var clearance_rect := facility.get_population_clearance_world_rect(
			_get_population_collision_margin()
		)
		result.append({
			"facility_id": facility.facility_id,
			"display_name": facility.display_name,
			"label": "%s [%s]" % [facility.display_name, facility.facility_id],
			"collision_rect": collision_rect,
			"clearance_rect": clearance_rect,
		})

	return result


func get_raider_debug_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for actor in _get_actors():
		var local_bounds := actor.get_debug_sprite_bounds()
		var world_bounds := Rect2(actor.global_position + local_bounds.position, local_bounds.size)
		result.append({
			"member_id": actor.get_member_id(),
			"identity": _get_actor_identity(actor),
			"state": actor.get_activity_state(),
			"activity": _get_actor_activity(actor),
			"label": _get_actor_label(actor),
			"local_bounds": local_bounds,
			"world_bounds": world_bounds,
		})

	return result


func get_active_path_debug_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for actor in _get_actors():
		if not _has_active_path(actor):
			continue

		var points: Array[Vector2] = [actor.global_position]
		for waypoint in actor.path:
			if waypoint is Vector2:
				points.append(waypoint)

		if points.size() < 2:
			continue

		var target_data := (
			_get_actor_activity_target_debug_data(actor)
			if actor.get_activity_state() == "walking"
			else {}
		)
		var target_position: Vector2 = points[-1]
		var target_slot_id := String(target_data.get("target_slot_id", ""))
		var target_position_value: Variant = target_data.get("target_position", Vector2.ZERO)
		if target_position_value is Vector2 and not target_slot_id.is_empty():
			target_position = target_position_value
		var station_id := String(target_data.get("station_id", ""))
		var activity_id := String(
			target_data.get("activity_id", actor.get_current_activity_id())
		)
		var point_metadata := _build_path_point_metadata(
			points, target_position, target_slot_id, actor.get_activity_state()
		)
		var waypoint_roles: Array[String] = []
		var waypoint_node_ids: Array[String] = []
		var waypoint_kinds: Array[String] = []
		for point_data in point_metadata:
			waypoint_roles.append(String(point_data.get("role", "waypoint")))
			waypoint_node_ids.append(String(point_data.get("node_id", "")))
			waypoint_kinds.append(String(point_data.get("kind", "waypoint")))

		result.append({
			"member_id": actor.get_member_id(),
			"points": points,
			"line_color": PATH_LINE_COLOR,
			"waypoint_color": PATH_WAYPOINT_COLOR,
			"target_position": target_position,
			"target_slot_id": target_slot_id,
			"station_id": station_id,
			"activity_id": activity_id,
			"waypoints": point_metadata,
			"point_metadata": point_metadata,
			"waypoint_metadata": point_metadata,
			"waypoint_roles": waypoint_roles,
			"point_roles": waypoint_roles,
			"waypoint_node_ids": waypoint_node_ids,
			"point_node_ids": waypoint_node_ids,
			"waypoint_kinds": waypoint_kinds,
			"point_kinds": waypoint_kinds,
		})

	return result


func get_activity_slot_debug_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var target_by_slot := _get_active_slot_targets()

	if population_controller == null or not is_instance_valid(population_controller):
		return result

	var slot_value: Variant = null
	if population_controller.has_method("get_activity_slot_debug_data"):
		slot_value = population_controller.call("get_activity_slot_debug_data")
	elif population_controller.has_method("get_activity_slots_debug_data"):
		slot_value = population_controller.call("get_activity_slots_debug_data")
	if not slot_value is Array:
		return result

	for slot_value_entry in slot_value:
		if not slot_value_entry is Dictionary:
			continue
		var slot: Dictionary = Dictionary(slot_value_entry).duplicate(true)
		var world_position_value: Variant = slot.get("world_position", slot.get("position", Vector2.ZERO))
		if not world_position_value is Vector2:
			continue
		var world_position: Vector2 = world_position_value
		var blocked_by := _get_route_node_blockers(world_position)
		var slot_id := String(slot.get("slot_id", ""))
		var targeted_by := String(target_by_slot.get(slot_id, ""))
		var blocked := not blocked_by.is_empty()
		slot["world_position"] = world_position
		slot["position"] = world_position
		slot["blocked"] = blocked
		slot["clearance_blocked"] = blocked
		slot["blocked_by_facility_ids"] = blocked_by
		slot["targeted"] = not targeted_by.is_empty()
		slot["targeted_by_member"] = targeted_by
		slot["targeted_by_member_id"] = targeted_by
		var label := slot_id
		var supported := Array(slot.get("supported_activity_ids", slot.get("supported_activities", [])))
		if not supported.is_empty():
			label += " [%s]" % ",".join(supported)
		if not String(slot.get("occupying_member", "")).is_empty():
			label += " [occupied]"
		if not targeted_by.is_empty():
			label += " [target:%s]" % targeted_by
		if blocked:
			label += " [BLOCKED]"
		slot["label"] = label
		result.append(slot)

	return result


func get_activity_slots_debug_data() -> Array[Dictionary]:
	return get_activity_slot_debug_data()


func get_activity_slot_catalog_debug_data() -> Array[Dictionary]:
	return get_activity_slot_debug_data()


func get_activity_slot_segment_debug_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog := _get_route_node_catalog()
	for slot in get_activity_slot_debug_data():
		var facility_id := String(slot.get("facility_id", ""))
		var approach_node_id := _get_approach_node_id(facility_id)
		if approach_node_id.is_empty() or not catalog.has(approach_node_id):
			continue
		var from_position := _get_catalog_node_position(catalog, approach_node_id)
		var to_position_value: Variant = slot.get("world_position", Vector2.ZERO)
		if not to_position_value is Vector2:
			continue
		var to_position: Vector2 = to_position_value
		var blocked_by := Array(slot.get("blocked_by_facility_ids", []))
		result.append({
			"from_node_id": approach_node_id,
			"to_node_id": String(slot.get("slot_id", "")),
			"from_approach_node_id": approach_node_id,
			"to_slot_id": String(slot.get("slot_id", "")),
			"activity_slot_id": String(slot.get("slot_id", "")),
			"start_node_id": approach_node_id,
			"end_node_id": String(slot.get("slot_id", "")),
			"approach_node_id": approach_node_id,
			"slot_id": String(slot.get("slot_id", "")),
			"station_id": String(slot.get("station_id", "")),
			"facility_id": facility_id,
			"from_position": from_position,
			"to_position": to_position,
			"points": [from_position, to_position],
			"line_color": ACTIVITY_SLOT_SEGMENT_COLOR,
			"dashed": true,
			"blocked": not blocked_by.is_empty(),
			"clearance_blocked": not blocked_by.is_empty(),
			"blocked_by_facility_ids": blocked_by,
		})

	return result


func get_activity_slot_segments_debug_data() -> Array[Dictionary]:
	return get_activity_slot_segment_debug_data()


func get_route_debug_data() -> Dictionary:
	var nodes := get_route_node_debug_data()
	var segments := get_static_route_segment_debug_data()
	var activity_slots := get_activity_slot_debug_data()
	var activity_slot_segments := get_activity_slot_segment_debug_data()
	return {
		"nodes": nodes,
		"segments": segments,
		"activity_slots": activity_slots,
		"activity_slot_segments": activity_slot_segments,
		"slot_segments": activity_slot_segments,
	}


func get_camp_route_debug_data() -> Dictionary:
	return get_route_debug_data()


func get_route_node_debug_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog := _get_route_node_catalog()

	for node_id_value in catalog.keys():
		var node_id := String(node_id_value)
		var node_value: Variant = catalog.get(node_id, {})
		if not node_value is Dictionary:
			continue

		var node_data: Dictionary = node_value
		var world_position_value: Variant = node_data.get("world_position", Vector2.ZERO)
		if not world_position_value is Vector2:
			continue

		var world_position: Vector2 = world_position_value
		var node_type := String(node_data.get("node_type", "route"))
		var facility_id := String(node_data.get("facility_id", ""))
		var blocked_by := _get_route_node_blockers(world_position)
		var blocked := not blocked_by.is_empty()
		var label := node_id
		if not facility_id.is_empty():
			label += " [%s]" % facility_id
		if blocked:
			label += " [BLOCKED]"

		result.append({
			"node_id": node_id,
			"world_position": world_position,
			"position": world_position,
			"node_type": node_type,
			"type": node_type,
			"facility_id": facility_id,
			"associated_facility_id": facility_id,
			"associated_facility": facility_id,
			"blocked": blocked,
			"clearance_blocked": blocked,
			"blocked_by_facility_ids": blocked_by,
			"label": label,
		})

	return result


func get_static_route_segment_debug_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog := _get_route_node_catalog()

	for segment in _get_route_segments():
		var from_node_id := String(segment.get("from_node_id", segment.get("start_node_id", "")))
		var to_node_id := String(segment.get("to_node_id", segment.get("end_node_id", "")))
		var from_position := _get_catalog_node_position(catalog, from_node_id)
		var to_position := _get_catalog_node_position(catalog, to_node_id)
		if from_node_id.is_empty() or to_node_id.is_empty():
			continue
		if not catalog.has(from_node_id) or not catalog.has(to_node_id):
			continue

		var points: Array[Vector2] = [from_position, to_position]
		result.append({
			"from_node_id": from_node_id,
			"to_node_id": to_node_id,
			"start_node_id": from_node_id,
			"end_node_id": to_node_id,
			"from_position": from_position,
			"to_position": to_position,
			"points": points,
			"line_color": STATIC_ROUTE_LINE_COLOR,
			"dashed": true,
		})

	return result


func get_route_segment_debug_data() -> Array[Dictionary]:
	return get_static_route_segment_debug_data()


func get_static_route_segments_debug_data() -> Array[Dictionary]:
	return get_static_route_segment_debug_data()


func _draw() -> void:
	_refresh_render_layers()
	if not geometry_visible and not labels_visible:
		return

	for facility_data in get_facility_debug_data():
		var collision_rect: Rect2 = facility_data.get("collision_rect", Rect2())
		var clearance_rect: Rect2 = facility_data.get("clearance_rect", Rect2())
		if _has_area(collision_rect):
			var local_collision := _world_rect_to_local(collision_rect)
			if geometry_visible:
				draw_rect(local_collision, FACILITY_FILL_COLOR, true)
				draw_rect(local_collision, FACILITY_OUTLINE_COLOR, false, DEBUG_LINE_WIDTH)
			if labels_visible:
				_draw_world_label(
					String(facility_data.get("label", "Facility")),
					collision_rect.position + Vector2(0, -6),
					FACILITY_OUTLINE_COLOR
				)
		if geometry_visible and _has_area(clearance_rect):
			_draw_dashed_rect(_world_rect_to_local(clearance_rect), CLEARANCE_COLOR)

	if geometry_visible:
		for segment_data in get_static_route_segment_debug_data():
			_draw_static_route_segment(segment_data)

		for segment_data in get_activity_slot_segment_debug_data():
			_draw_activity_slot_segment(segment_data)

	for node_data in get_route_node_debug_data():
		_draw_route_node(node_data)

	for slot_data in get_activity_slot_debug_data():
		_draw_activity_slot(slot_data)

	for path_data in get_active_path_debug_data():
		_draw_path(path_data)
		_draw_target_marker(path_data)

	for raider_data in get_raider_debug_data():
		var world_bounds: Rect2 = raider_data.get("world_bounds", Rect2())
		if not _has_area(world_bounds):
			continue

		if geometry_visible:
			draw_rect(_world_rect_to_local(world_bounds), RAIDER_BOUNDS_COLOR, false, DEBUG_LINE_WIDTH)
		if labels_visible:
			_draw_world_label(
				String(raider_data.get("label", "Raider")),
				world_bounds.position + Vector2(0, -6),
				RAIDER_BOUNDS_COLOR
			)


func _draw_static_route_segment(segment_data: Dictionary) -> void:
	if not geometry_visible:
		return

	var from_position_value: Variant = segment_data.get("from_position", Vector2.ZERO)
	var to_position_value: Variant = segment_data.get("to_position", Vector2.ZERO)
	if not from_position_value is Vector2 or not to_position_value is Vector2:
		return

	draw_dashed_line(
		to_local(from_position_value),
		to_local(to_position_value),
		STATIC_ROUTE_LINE_COLOR,
		DEBUG_LINE_WIDTH,
		ROUTE_DASH_LENGTH,
		true
	)


func _draw_activity_slot_segment(segment_data: Dictionary) -> void:
	if not geometry_visible:
		return

	var from_position_value: Variant = segment_data.get("from_position", Vector2.ZERO)
	var to_position_value: Variant = segment_data.get("to_position", Vector2.ZERO)
	if not from_position_value is Vector2 or not to_position_value is Vector2:
		return

	var color: Color = ACTIVITY_SLOT_SEGMENT_COLOR
	if bool(segment_data.get("blocked", false)):
		color = BLOCKED_ACTIVITY_SLOT_COLOR.darkened(0.2)
	draw_dashed_line(
		to_local(from_position_value),
		to_local(to_position_value),
		color,
		DEBUG_LINE_WIDTH,
		ROUTE_DASH_LENGTH,
		true
	)


func _draw_route_node(node_data: Dictionary) -> void:
	var world_position_value: Variant = node_data.get("world_position", Vector2.ZERO)
	if not world_position_value is Vector2:
		return

	var world_position: Vector2 = world_position_value
	var local_position := to_local(world_position)
	var color := (
		BLOCKED_ROUTE_NODE_COLOR
		if bool(node_data.get("blocked", false))
		else ROUTE_NODE_COLOR
	)
	if geometry_visible:
		draw_circle(local_position, ROUTE_NODE_RADIUS, color)
		draw_arc(local_position, ROUTE_NODE_RADIUS, 0.0, TAU, 16, LABEL_SHADOW_COLOR, 1.0, true)
	_draw_world_label(
		String(node_data.get("label", node_data.get("node_id", "Route Node"))),
		world_position + Vector2(ROUTE_NODE_RADIUS + 4.0, -ROUTE_NODE_RADIUS - 2.0),
		color
	)


func _draw_activity_slot(slot_data: Dictionary) -> void:
	var world_position_value: Variant = slot_data.get("world_position", Vector2.ZERO)
	if not world_position_value is Vector2:
		return

	var world_position: Vector2 = world_position_value
	var color := ACTIVITY_SLOT_FREE_COLOR
	if bool(slot_data.get("blocked", false)):
		color = BLOCKED_ACTIVITY_SLOT_COLOR
	elif bool(slot_data.get("targeted", false)):
		color = ACTIVITY_SLOT_TARGET_COLOR
	elif bool(slot_data.get("occupied", slot_data.get("is_occupied", false))):
		color = ACTIVITY_SLOT_OCCUPIED_COLOR

	var local_position := to_local(world_position)
	if geometry_visible:
		draw_circle(local_position, ACTIVITY_SLOT_RADIUS, color)
		draw_arc(local_position, ACTIVITY_SLOT_RADIUS, 0.0, TAU, 12, LABEL_SHADOW_COLOR, 1.0, true)
		if bool(slot_data.get("targeted", false)):
			draw_arc(
				local_position,
				ACTIVITY_SLOT_RADIUS + 3.0,
				0.0,
				TAU,
				16,
				ACTIVITY_SLOT_TARGET_COLOR,
				2.0,
				true
			)
	_draw_world_label(
		String(slot_data.get("label", slot_data.get("slot_id", "Activity Slot"))),
		world_position + Vector2(ACTIVITY_SLOT_RADIUS + 4.0, -ACTIVITY_SLOT_RADIUS - 2.0),
		color
	)


func _draw_path(path_data: Dictionary) -> void:
	if not geometry_visible:
		return

	var points: Array = path_data.get("points", [])
	if points.size() < 2:
		return

	for index in range(points.size() - 1):
		var from_point: Variant = points[index]
		var to_point: Variant = points[index + 1]
		if not from_point is Vector2 or not to_point is Vector2:
			continue
		draw_line(
			to_local(from_point),
			to_local(to_point),
			PATH_LINE_COLOR,
			PATH_LINE_WIDTH,
			true
		)

	for index in range(1, points.size()):
		var waypoint: Variant = points[index]
		if not waypoint is Vector2:
			continue
		var local_waypoint := to_local(waypoint)
		draw_circle(local_waypoint, WAYPOINT_RADIUS, PATH_WAYPOINT_COLOR)
		draw_arc(local_waypoint, WAYPOINT_RADIUS, 0.0, TAU, 16, LABEL_SHADOW_COLOR, 1.0, true)


func _draw_target_marker(path_data: Dictionary) -> void:
	var target_slot_id := String(path_data.get("target_slot_id", ""))
	if target_slot_id.is_empty():
		return
	var target_position_value: Variant = path_data.get("target_position", Vector2.ZERO)
	if not target_position_value is Vector2:
		return
	var target_position: Vector2 = target_position_value
	var local_position := to_local(target_position)
	if geometry_visible:
		draw_arc(
			local_position,
			TARGET_MARKER_RADIUS,
			0.0,
			TAU,
			24,
			ACTIVITY_SLOT_TARGET_COLOR,
			2.5,
			true
		)
		draw_line(
			local_position + Vector2(-TARGET_MARKER_RADIUS - 3.0, 0),
			local_position + Vector2(TARGET_MARKER_RADIUS + 3.0, 0),
			ACTIVITY_SLOT_TARGET_COLOR,
			1.5,
			true
		)
		draw_line(
			local_position + Vector2(0, -TARGET_MARKER_RADIUS - 3.0),
			local_position + Vector2(0, TARGET_MARKER_RADIUS + 3.0),
			ACTIVITY_SLOT_TARGET_COLOR,
			1.5,
			true
		)
	_draw_world_label(
		"TARGET %s" % target_slot_id,
		target_position + Vector2(TARGET_MARKER_RADIUS + 5.0, TARGET_MARKER_RADIUS + 4.0),
		ACTIVITY_SLOT_TARGET_COLOR
	)


func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]

	for index in range(corners.size()):
		var from_point: Vector2 = corners[index]
		var to_point: Vector2 = corners[(index + 1) % corners.size()]
		draw_dashed_line(
			from_point,
			to_point,
			color,
			DEBUG_LINE_WIDTH,
			CLEARANCE_DASH_LENGTH,
			true
		)


func _draw_world_label(text: String, world_position: Vector2, color: Color) -> void:
	if not labels_visible:
		return

	var font := ThemeDB.fallback_font
	if font == null or text.is_empty():
		return

	var local_position := to_local(world_position)
	draw_string(
		font,
		local_position + Vector2(1, 1),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		LABEL_FONT_SIZE,
		LABEL_SHADOW_COLOR
	)
	draw_string(
		font,
		local_position,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		LABEL_FONT_SIZE,
		color if color.a > 0.0 else LABEL_FONT_COLOR
	)


func _get_route_node_catalog() -> Dictionary:
	var root := camp_root
	if root == null or not is_instance_valid(root):
		return {}

	if root.has_method("get_camp_route_node_catalog"):
		var catalog_value: Variant = root.call("get_camp_route_node_catalog")
		if catalog_value is Dictionary:
			return catalog_value

	if root.has_method("get_route_node_catalog"):
		var catalog_value: Variant = root.call("get_route_node_catalog")
		if catalog_value is Dictionary:
			return catalog_value

	return {}


func _get_route_segments() -> Array[Dictionary]:
	var root := camp_root
	if root == null or not is_instance_valid(root):
		return []

	var segment_value: Variant = null
	if root.has_method("get_camp_route_segments"):
		segment_value = root.call("get_camp_route_segments")
	elif root.has_method("get_route_segments"):
		segment_value = root.call("get_route_segments")

	var result: Array[Dictionary] = []
	if not segment_value is Array:
		return result

	for value in segment_value:
		if value is Dictionary:
			result.append(value)

	return result


func _get_approach_node_id(facility_id: String) -> String:
	var root := camp_root
	if root == null or not is_instance_valid(root):
		return ""
	if root.has_method("get_camp_route_approach_node_id"):
		return String(root.call("get_camp_route_approach_node_id", facility_id))
	if root.has_method("get_route_approach_node_id"):
		return String(root.call("get_route_approach_node_id", facility_id))
	var fallback := facility_id + "_approach"
	return fallback if _get_route_node_catalog().has(fallback) else ""


func _get_active_slot_targets() -> Dictionary:
	var result: Dictionary = {}
	for actor in _get_actors():
		if not _has_active_path(actor) or actor.get_activity_state() != "walking":
			continue
		var target_data := _get_actor_activity_target_debug_data(actor)
		var target_slot_id := String(target_data.get("target_slot_id", ""))
		if not target_slot_id.is_empty():
			result[target_slot_id] = actor.get_member_id()
	return result


func _get_actor_activity_target_debug_data(actor: CampMemberActor) -> Dictionary:
	var controller := _resolve_population_controller()
	if controller == null or not is_instance_valid(controller):
		return {}
	if controller.has_method("get_activity_target_debug_data"):
		var value: Variant = controller.call(
			"get_activity_target_debug_data", actor.get_member_id()
		)
		if value is Dictionary:
			return value
	if controller.has_method("get_member_activity_target_debug_data"):
		var value: Variant = controller.call(
			"get_member_activity_target_debug_data", actor.get_member_id()
		)
		if value is Dictionary:
			return value
	return {}


func _build_path_point_metadata(
	points: Array,
	target_position: Vector2,
	target_slot_id: String,
	state: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var route_nodes := get_route_node_debug_data()
	for index in range(points.size()):
		var point_value: Variant = points[index]
		if not point_value is Vector2:
			continue
		var point: Vector2 = point_value
		var role := "waypoint"
		var node_id := ""
		var node_type := ""
		var facility_id := ""
		var slot_id := ""
		var is_target := false
		if index == 0:
			role = "actor_position"
		elif (
			state == "walking"
			and not target_slot_id.is_empty()
			and (index == points.size() - 1 or point.distance_to(target_position) <= 0.01)
		):
			role = "activity_slot"
			slot_id = target_slot_id
			is_target = true
		else:
			for node_value in route_nodes:
				var route_node: Dictionary = node_value
				var route_position_value: Variant = route_node.get("world_position", Vector2.ZERO)
				if route_position_value is Vector2 and point.distance_to(route_position_value) <= 0.01:
					role = "route_node"
					node_id = String(route_node.get("node_id", ""))
					node_type = String(route_node.get("node_type", ""))
					facility_id = String(route_node.get("facility_id", ""))
					break
		var kind := role
		if role == "route_node" and not node_type.is_empty():
			kind = node_type

		result.append({
			"index": index,
			"waypoint_index": index,
			"position": point,
			"world_position": point,
			"role": role,
			"waypoint_role": role,
			"kind": kind,
			"waypoint_kind": kind,
			"node_id": node_id,
			"waypoint_node_id": node_id,
			"node_type": node_type,
			"facility_id": facility_id,
			"slot_id": slot_id,
			"is_target": is_target,
		})
	return result


func _get_catalog_node_position(catalog: Dictionary, node_id: String) -> Vector2:
	var node_value: Variant = catalog.get(node_id, {})
	if not node_value is Dictionary:
		return Vector2.ZERO

	var node_data: Dictionary = node_value
	var position_value: Variant = node_data.get("world_position", Vector2.ZERO)
	return position_value if position_value is Vector2 else Vector2.ZERO


func _get_route_node_blockers(world_position: Vector2) -> Array[String]:
	var result: Array[String] = []

	for facility in _get_facilities():
		var clearance_rect := facility.get_population_clearance_world_rect(
			_get_population_collision_margin()
		)
		if _has_area(clearance_rect) and clearance_rect.has_point(world_position):
			result.append(facility.facility_id)

	return result


func _get_facilities() -> Array[CampFacility]:
	var result: Array[CampFacility] = []
	var root := camp_root
	if root == null or not is_instance_valid(root):
		return result

	for child in root.get_children():
		if child is CampFacility and is_instance_valid(child):
			result.append(child as CampFacility)

	return result


func _get_actors() -> Array[CampMemberActor]:
	var result: Array[CampMemberActor] = []
	var controller := _resolve_population_controller()
	if controller == null or not is_instance_valid(controller):
		return result

	for actor_value in controller.actors_by_id.values():
		var actor := actor_value as CampMemberActor
		if actor != null and is_instance_valid(actor):
			result.append(actor)

	return result


func _resolve_population_controller() -> CampPopulationController:
	if population_controller != null and is_instance_valid(population_controller):
		return population_controller

	if camp_root == null or not is_instance_valid(camp_root):
		return null

	var candidate := camp_root.get_node_or_null("CampPopulationController")
	if candidate is CampPopulationController:
		population_controller = candidate as CampPopulationController
		return population_controller

	for child in camp_root.get_children():
		if child is CampPopulationController:
			population_controller = child as CampPopulationController
			return population_controller

	return null


func _get_population_collision_margin() -> float:
	if camp_root != null and camp_root.has_method("get_population_collision_margin"):
		return float(camp_root.call("get_population_collision_margin"))

	return 26.0


func _get_actor_identity(actor: CampMemberActor) -> String:
	var member := actor.get_member_data()
	var display_name := String(member.get("display_name", "")).strip_edges()
	if not display_name.is_empty():
		if not String(member.get("unit_class", "")).strip_edges().is_empty():
			return CampaignState.format_member_label(member)
		return display_name

	return actor.get_member_id()


func _get_actor_activity(actor: CampMemberActor) -> String:
	if not actor.current_activity_name.is_empty():
		return actor.current_activity_name
	return actor.current_activity_id


func _get_actor_label(actor: CampMemberActor) -> String:
	var activity := _get_actor_activity(actor)
	var state_text := actor.get_activity_state()
	if not activity.is_empty():
		state_text += " / " + activity
	return "%s [%s] | %s" % [_get_actor_identity(actor), actor.get_member_id(), state_text]


func _has_active_path(actor: CampMemberActor) -> bool:
	return (
		actor.path.size() > 0
		and ACTIVE_PATH_STATES.has(actor.get_activity_state())
	)


func _has_area(rect: Rect2) -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0


func _world_rect_to_local(rect: Rect2) -> Rect2:
	var local_position := to_local(rect.position)
	var local_end := to_local(rect.end)
	return Rect2(local_position, local_end - local_position)
