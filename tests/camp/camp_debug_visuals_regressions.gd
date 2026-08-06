extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")
const DEBUG_BOUNDS := Rect2(-10, -17, 30, 36)

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignState.reset_campaign(false, 61059)
	# Start from a previous combat overlay to verify that direct camp scene
	# instantiation establishes camp context and resets the mode.
	GameState.set_raid_debug_context(GameState.RAID_DEBUG_CONTEXT_COMBAT)
	GameState.set_raid_debug_mode(GameState.RAID_DEBUG_MODE_ALL)

	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(4)
	_expect(
		GameState.get_raid_debug_context() == GameState.RAID_DEBUG_CONTEXT_CAMP
			and GameState.get_raid_debug_mode() == GameState.RAID_DEBUG_MODE_OFF,
		"Entering camp did not establish camp context and reset raid debug mode."
	)

	var overlay := camp.get_node_or_null("CampDebugVisuals") as CampDebugVisuals
	_expect(overlay != null, "The camp did not create its debug overlay.")
	if overlay == null:
		_finish(camp)
		return

	_expect(not overlay.visible, "Camp debug visuals were visible by default.")

	# Static route data must be available even before a raider has an active path.
	var route_debug_data := overlay.get_route_debug_data()
	var route_nodes := overlay.get_route_node_debug_data()
	var route_segments := overlay.get_static_route_segment_debug_data()
	var activity_slots := overlay.get_activity_slot_debug_data()
	var activity_slot_segments := overlay.get_activity_slot_segment_debug_data()
	_expect(route_debug_data.has("nodes"), "Camp route debug data omitted static nodes.")
	_expect(route_debug_data.has("segments"), "Camp route debug data omitted static segments.")
	_expect(
		route_debug_data.has("activity_slots"),
		"Camp route debug data omitted authored activity slots."
	)
	_expect(
		route_debug_data.has("activity_slot_segments"),
		"Camp route debug data omitted approach-to-slot connectors."
	)
	_expect(route_nodes.size() == 11, "The authored camp route node catalog is incomplete.")
	_expect(route_segments.size() == 10, "The authored camp route segment catalog is incomplete.")
	_expect(
		activity_slots.size() == 49,
		"The live activity-slot catalog did not include every authored station slot."
	)
	_expect(
		activity_slot_segments.size() == 46,
		"Approach-to-slot connectors did not match facilities with known approach nodes."
	)

	var command_slot := _find_record(
		activity_slots, "command_strategy_table_slot_0", "slot_id"
	)
	var command_facility := camp.call("get_facility", "command_tent") as CampFacility
	_expect(
		command_slot.get("world_position", Vector2.ZERO)
			== command_facility.global_position + command_slot.get("offset", Vector2.ZERO),
		"A station slot did not use facility position plus its authored offset."
	)
	_expect(
		Array(command_slot.get("supported_activity_ids", [])).has("prepare_plan"),
		"A live station slot omitted its supported activity."
	)
	_expect(
		not bool(command_slot.get("occupied", true))
			and String(command_slot.get("reservation_state", "")) == "free"
			and String(command_slot.get("occupying_member", "")) == "",
		"Idle station slots did not expose free occupancy and reservation state."
	)

	var communal_slot := _find_record(
		activity_slots, "communal_fire_ring_slot_0", "slot_id"
	)
	_expect(
		String(communal_slot.get("facility_id", "")) == "communal_fire"
			and String(communal_slot.get("station_id", "")) == "communal_fire_ring",
		"Communal-fire station slots were not present in the live catalog."
	)
	_expect(
		communal_slot.has("blocked")
			and communal_slot.has("blocked_by_facility_ids"),
		"Activity slots did not expose population-clearance blocked status."
	)
	var communal_slot_segment := _find_segment(
		activity_slot_segments, "communal_fire_approach", String(communal_slot.get("slot_id", ""))
	)
	_expect(
		communal_slot_segment.has("points"),
		"The communal-fire approach did not connect to its live activity slot."
	)
	var victory_slot_connector_found := false
	for segment in activity_slot_segments:
		if String(segment.get("facility_id", "")) == "victory_spike":
			victory_slot_connector_found = true
			break
	_expect(
		not victory_slot_connector_found,
		"A direct-target facility received an invented static approach connector."
	)

	var expected_positions := {
		"south_transition": Vector2(1500, 1410),
		"central_crossroads": Vector2(1500, 1125),
		"command_tent_approach": Vector2(1500, 690),
		"formation_yard_approach": Vector2(1030, 1080),
		"archive_approach": Vector2(2010, 1080),
		"smith_approach": Vector2(760, 1160),
		"apothecary_approach": Vector2(2250, 1160),
		"communal_fire_approach": Vector2(1500, 1310),
		"quarters_approach": Vector2(850, 1570),
		"training_approach": Vector2(1110, 1280),
		"liaison_approach": Vector2(2230, 1500),
	}
	for node_id in expected_positions.keys():
		var node_data := _find_record(route_nodes, String(node_id), "node_id")
		_expect(
			node_data.get("world_position", Vector2.ZERO) == expected_positions[node_id],
			"The route node position changed for " + String(node_id) + "."
		)

	var central_node := _find_record(route_nodes, "central_crossroads", "node_id")
	_expect(
		String(central_node.get("node_type", "")) == "crossroads",
		"The central route node did not report its crossroads type."
	)
	_expect(
		bool(central_node.get("blocked", false)),
		"The central crossroads did not report its communal-fire clearance block."
	)
	_expect(
		Array(central_node.get("blocked_by_facility_ids", [])).has("communal_fire"),
		"The central crossroads did not identify the communal fire as its blocker."
	)

	var central_segment := _find_segment(
		route_segments, "south_transition", "central_crossroads"
	)
	_expect(
		central_segment.has("points"),
		"The static route data omitted the south-to-central route segment."
	)
	var central_points: Array = central_segment.get("points", [])
	_expect(
		central_points.size() == 2
			and central_points[0] == Vector2(1500, 1410)
			and central_points[1] == Vector2(1500, 1125),
		"The south-to-central route segment coordinates changed."
	)
	var communal_approach := _find_record(
		route_nodes, "communal_fire_approach", "node_id"
	)
	_expect(
		String(communal_approach.get("facility_id", "")) == "communal_fire"
			and String(communal_approach.get("node_type", "")) == "facility_approach",
		"The communal-fire approach node lost its facility association."
	)

	var facility := camp.call("get_facility", "communal_fire") as CampFacility
	_expect(facility != null, "The communal fire facility was not available to the debug test.")
	if facility == null:
		_finish(camp)
		return

	var collision_rect := facility.get_collision_world_rect()
	var expected_collision := Rect2(
		facility.global_position + facility.collision_offset - facility.footprint * 0.5,
		facility.footprint
	)
	_expect(collision_rect == expected_collision, "Facility collision geometry changed unexpectedly.")

	var margin := float(camp.call("get_population_collision_margin"))
	_expect(
		facility.get_population_clearance_world_rect(margin) == collision_rect.grow(margin),
		"Facility population clearance geometry does not expand its collision footprint."
	)

	var facility_data := _find_record(
		overlay.get_facility_debug_data(), facility.facility_id, "facility_id"
	)
	_expect(
		String(facility_data.get("label", "")).contains(facility.display_name),
		"Facility debug labels do not include the display name."
	)
	_expect(
		String(facility_data.get("label", "")).contains(facility.facility_id),
		"Facility debug labels do not include the facility ID."
	)

	var population := camp.get_node_or_null("CampPopulationController") as CampPopulationController
	_expect(population != null, "The camp population controller was not available to the debug test.")
	if population == null or population.actors_by_id.is_empty():
		_finish(camp)
		return

	var member_id := String(population.actors_by_id.keys()[0])
	var actor := population.actors_by_id.get(member_id) as CampMemberActor
	_expect(actor != null, "The debug test could not find a camp raider actor.")
	if actor == null:
		_finish(camp)
		return

	actor.set_process(false)
	var path: Array[Vector2] = [Vector2(1120, 1780), Vector2(1240, 1780)]
	actor.start_activity("debug_path", "Debug Path", path, 60.0)

	var actor_position_before := actor.global_position
	var actor_path_before := actor.path.duplicate()
	var collision_body := facility.get_node_or_null("FootprintCollision") as StaticBody2D
	var collision_shape := (
		collision_body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision_body != null
		else null
	)
	var shape := collision_shape.shape as RectangleShape2D if collision_shape != null else null
	var collision_layer_before := collision_body.collision_layer if collision_body != null else -1
	var collision_mask_before := collision_body.collision_mask if collision_body != null else -1
	var collision_size_before := shape.size if shape != null else Vector2.ZERO

	_expect(actor.get_debug_sprite_bounds() == DEBUG_BOUNDS, "Raider debug bounds changed from the fixed envelope.")
	var raider_data := _find_record(
		overlay.get_raider_debug_data(), member_id, "member_id"
	)
	var member := actor.get_member_data()
	var identity := String(member.get("display_name", member_id))
	_expect(
		String(raider_data.get("label", "")).contains(identity),
		"Raider debug labels do not include member identity."
	)
	_expect(
		String(raider_data.get("label", "")).contains(member_id),
		"Raider debug labels do not include member ID."
	)
	_expect(
		String(raider_data.get("label", "")).contains("walking")
			and String(raider_data.get("label", "")).contains("Debug Path"),
		"Raider debug labels do not include current state and activity."
	)
	_expect(
		Rect2(raider_data.get("local_bounds", Rect2())) == DEBUG_BOUNDS,
		"Raider debug data did not expose the fixed local bounds."
	)

	var path_data := _find_record(
		overlay.get_active_path_debug_data(), member_id, "member_id"
	)
	var rendered_points: Array = path_data.get("points", [])
	_expect(rendered_points.size() == 3, "The active raider path did not expose all waypoints.")
	if rendered_points.size() == 3:
		_expect(rendered_points[0] == actor_position_before, "The active path did not start at the actor.")
		_expect(rendered_points[1] == path[0], "The active path omitted its first waypoint.")
		_expect(rendered_points[2] == path[1], "The active path omitted its final waypoint.")
	var synthetic_roles: Array = path_data.get("waypoint_roles", [])
	var synthetic_node_ids: Array = path_data.get("waypoint_node_ids", [])
	_expect(
		synthetic_roles.size() == rendered_points.size()
			and synthetic_roles[0] == "actor_position"
			and synthetic_roles[-1] == "waypoint",
		"Active path metadata did not classify actor and ordinary waypoints."
	)
	_expect(
		synthetic_node_ids.size() == rendered_points.size(),
		"Active path metadata did not expose a node ID for every point."
	)

	var f12_event := InputEventKey.new()
	f12_event.physical_keycode = KEY_F12
	f12_event.pressed = true
	GameState._unhandled_input(f12_event)

	_expect(
		GameState.get_raid_debug_mode() == GameState.RAID_DEBUG_MODE_ALL,
		"The first synthetic F12 event did not select all camp debug layers."
	)
	_expect(GameState.raid_debug_visible, "A synthetic F12 event did not toggle raid debug visibility.")
	_expect(overlay.visible, "F12 visibility did not propagate to the camp overlay.")
	_expect(
		overlay.is_geometry_layer_visible() and overlay.is_label_layer_visible(),
		"All camp debug mode did not enable both render layers."
	)
	_expect(actor.global_position == actor_position_before, "Toggling debug visuals moved a raider.")
	_expect(actor.path == actor_path_before, "Toggling debug visuals changed an actor path.")
	if collision_body != null:
		_expect(collision_body.collision_layer == collision_layer_before, "Debug visuals changed facility collision layers.")
		_expect(collision_body.collision_mask == collision_mask_before, "Debug visuals changed facility collision masks.")
	if shape != null:
		_expect(shape.size == collision_size_before, "Debug visuals changed facility collision shape size.")

	_press_f12()
	_expect(
		GameState.get_raid_debug_mode() == GameState.RAID_DEBUG_MODE_GEOMETRY,
		"The second synthetic F12 event did not select geometry-only mode."
	)
	_expect(overlay.visible, "Geometry-only camp debug mode unexpectedly hid the overlay.")
	_expect(
		overlay.is_geometry_layer_visible() and not overlay.is_label_layer_visible(),
		"Geometry-only camp mode did not gate the render layers correctly."
	)

	_press_f12()
	_expect(
		GameState.get_raid_debug_mode() == GameState.RAID_DEBUG_MODE_LABELS,
		"The third synthetic F12 event did not select labels-only mode."
	)
	_expect(overlay.visible, "Labels-only camp debug mode unexpectedly hid the overlay.")
	_expect(
		not overlay.is_geometry_layer_visible() and overlay.is_label_layer_visible(),
		"Labels-only camp mode did not gate the render layers correctly."
	)

	_press_f12()
	_expect(
		GameState.get_raid_debug_mode() == GameState.RAID_DEBUG_MODE_OFF,
		"The fourth synthetic F12 event did not turn camp debug mode off."
	)
	_expect(not overlay.visible, "Camp debug mode did not hide after completing its cycle.")
	_expect(
		not overlay.is_geometry_layer_visible() and not overlay.is_label_layer_visible(),
		"Off camp debug mode left a render layer enabled."
	)
	await _wait_frames(1)

	GameState.set_raid_debug_visibility(false)
	_expect(not overlay.visible, "The camp overlay did not hide when raid debug visibility was cleared.")

	# Reserve a real authored station slot so the active-path view proves that
	# the final point is the exact slot, after any route/approach waypoints.
	var station := population.stations_by_id.get("communal_fire_ring") as CampActivityStation
	var activity := population._get_activity("socialize") as CampActivityDefinition
	_expect(station != null and activity != null, "The debug test could not load the communal activity station.")
	if station != null and activity != null:
		actor.interrupt_activity()
		var reservation := station.reserve([member_id], "station_reserved")
		_expect(bool(reservation.get("ok", false)), "The debug test could not reserve a communal-fire slot.")
		if bool(reservation.get("ok", false)):
			var assignment := Dictionary(reservation.get("assignments", {}).get(member_id, {}))
			population._start_reserved_activity(
				member_id,
				activity,
				station,
				"debug_activity",
				assignment,
				[member_id],
				60.0
			)
			var active_slot_path := _find_record(
				overlay.get_active_path_debug_data(), member_id, "member_id"
			)
			var target_slot_id := String(active_slot_path.get("target_slot_id", ""))
			var target_slot := _find_record(activity_slots, target_slot_id, "slot_id")
			_expect(
				not target_slot_id.is_empty() and not target_slot.is_empty(),
				"An active reservation did not resolve to a live target slot."
			)
			_expect(
				active_slot_path.get("target_position", Vector2.ZERO)
					== target_slot.get("world_position", Vector2.ZERO),
				"Active path data did not expose the exact reserved slot position."
			)
			_expect(
				String(active_slot_path.get("station_id", "")) == "communal_fire_ring"
					and String(active_slot_path.get("activity_id", "")) == "socialize",
				"Active path data lost its station or activity identity."
			)
			var active_waypoints: Array = active_slot_path.get("waypoints", [])
			var has_route_node := false
			for waypoint_data_value in active_waypoints:
				var waypoint_data: Dictionary = waypoint_data_value
				if String(waypoint_data.get("role", "")) == "route_node":
					has_route_node = true
			_expect(has_route_node, "The active path omitted its authored route-node waypoint classification.")
			if not active_waypoints.is_empty():
				var final_waypoint: Dictionary = active_waypoints[-1]
				_expect(
					String(final_waypoint.get("role", "")) == "activity_slot"
						and String(final_waypoint.get("slot_id", "")) == target_slot_id,
					"The active path did not classify its final point as the exact activity slot."
				)
			var targeted_slot := _find_record(
				overlay.get_activity_slot_debug_data(), target_slot_id, "slot_id"
			)
			_expect(
				bool(targeted_slot.get("targeted", false))
					and bool(targeted_slot.get("occupied", false))
					and String(targeted_slot.get("targeted_by_member", "")) == member_id
					and String(targeted_slot.get("occupying_member", "")) == member_id
					and String(targeted_slot.get("reservation_state", "")) == "station_reserved",
				"The live target slot was not marked as currently targeted."
			)
			population._release_reservation(member_id)
			population._reset_runtime_activity(member_id)

	# Arrival behavior remains exact at the shared threshold and continues to
	# advance toward a farther point.
	actor.global_position = Vector2(1120, 1780)
	actor.start_activity(
		"arrival_threshold_debug", "Arrival Threshold", [Vector2(1123, 1784)], 60.0
	)
	actor._update_walking(0.0)
	_expect(
		actor.global_position == Vector2(1123, 1784) and actor.path.is_empty(),
		"A waypoint within the 5-pixel arrival threshold did not snap exactly."
	)
	actor.global_position = Vector2(1120, 1780)
	actor.start_activity(
		"far_waypoint_debug", "Far Waypoint", [Vector2(1126, 1780)], 60.0
	)
	actor._update_walking(0.01)
	_expect(
		actor.global_position != Vector2(1126, 1780)
			and actor.global_position.x > 1120.0
			and not actor.path.is_empty(),
		"A farther waypoint did not continue normal movement."
	)
	_finish(camp)


func _find_record(records: Array[Dictionary], value: String, key: String) -> Dictionary:
	for record in records:
		if String(record.get(key, "")) == value:
			return record
	return {}


func _find_segment(
	records: Array[Dictionary], from_node_id: String, to_node_id: String
) -> Dictionary:
	for record in records:
		if (
			String(record.get("from_node_id", "")) == from_node_id
			and String(record.get("to_node_id", "")) == to_node_id
		):
			return record
	return {}


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _press_f12() -> void:
	var f12_event := InputEventKey.new()
	f12_event.physical_keycode = KEY_F12
	f12_event.pressed = true
	GameState._unhandled_input(f12_event)


func _finish(camp: Node) -> void:
	if camp != null and is_instance_valid(camp):
		camp.queue_free()
	await _wait_frames(2)
	CampaignState.reset_campaign(false, 61059)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
		return

	print("Camp debug visuals regressions passed.")
	get_tree().quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
