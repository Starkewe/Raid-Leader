extends Node2D
class_name CampDebugVisuals

const FACILITY_FILL_COLOR := Color(0.92, 0.12, 0.10, 0.24)
const FACILITY_OUTLINE_COLOR := Color(1.0, 0.20, 0.16, 0.95)
const CLEARANCE_COLOR := Color(1.0, 0.70, 0.18, 0.95)
const RAIDER_BOUNDS_COLOR := Color(0.24, 0.92, 0.96, 0.95)
const PATH_LINE_COLOR := Color(0.28, 0.56, 1.0, 0.92)
const PATH_WAYPOINT_COLOR := Color(0.64, 0.38, 0.98, 0.98)
const LABEL_SHADOW_COLOR := Color(0.02, 0.04, 0.06, 0.94)
const LABEL_FONT_COLOR := Color(0.88, 0.96, 1.0, 1.0)
const CLEARANCE_DASH_LENGTH := 12.0
const DEBUG_LINE_WIDTH := 2.0
const PATH_LINE_WIDTH := 3.0
const WAYPOINT_RADIUS := 5.0
const LABEL_FONT_SIZE := 14
const ACTIVE_PATH_STATES := ["walking", "conversation_approaching"]

var camp_root: Node = null
var population_controller: CampPopulationController = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 2000
	if camp_root == null:
		camp_root = get_parent()
	_resolve_population_controller()
	GameState.register_raid_debug_content(self)
	queue_redraw()


func setup(camp: Node, population: CampPopulationController = null) -> void:
	camp_root = camp
	population_controller = population
	_resolve_population_controller()
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


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

		result.append({
			"member_id": actor.get_member_id(),
			"points": points,
			"line_color": PATH_LINE_COLOR,
			"waypoint_color": PATH_WAYPOINT_COLOR,
		})

	return result


func _draw() -> void:
	for facility_data in get_facility_debug_data():
		var collision_rect: Rect2 = facility_data.get("collision_rect", Rect2())
		var clearance_rect: Rect2 = facility_data.get("clearance_rect", Rect2())
		if _has_area(collision_rect):
			var local_collision := _world_rect_to_local(collision_rect)
			draw_rect(local_collision, FACILITY_FILL_COLOR, true)
			draw_rect(local_collision, FACILITY_OUTLINE_COLOR, false, DEBUG_LINE_WIDTH)
			_draw_world_label(
				String(facility_data.get("label", "Facility")),
				collision_rect.position + Vector2(0, -6),
				FACILITY_OUTLINE_COLOR
			)
		if _has_area(clearance_rect):
			_draw_dashed_rect(_world_rect_to_local(clearance_rect), CLEARANCE_COLOR)

	for path_data in get_active_path_debug_data():
		_draw_path(path_data.get("points", []))

	for raider_data in get_raider_debug_data():
		var world_bounds: Rect2 = raider_data.get("world_bounds", Rect2())
		if not _has_area(world_bounds):
			continue

		draw_rect(_world_rect_to_local(world_bounds), RAIDER_BOUNDS_COLOR, false, DEBUG_LINE_WIDTH)
		_draw_world_label(
			String(raider_data.get("label", "Raider")),
			world_bounds.position + Vector2(0, -6),
			RAIDER_BOUNDS_COLOR
		)


func _draw_path(points: Array) -> void:
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
