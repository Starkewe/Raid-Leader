extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")
const DEBUG_BOUNDS := Rect2(-10, -17, 30, 36)

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignState.reset_campaign(false, 61059)
	GameState.set_raid_debug_visibility(false)

	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(4)

	var overlay := camp.get_node_or_null("CampDebugVisuals") as CampDebugVisuals
	_expect(overlay != null, "The camp did not create its debug overlay.")
	if overlay == null:
		_finish(camp)
		return

	_expect(not overlay.visible, "Camp debug visuals were visible by default.")

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

	var f12_event := InputEventKey.new()
	f12_event.physical_keycode = KEY_F12
	f12_event.pressed = true
	GameState._unhandled_input(f12_event)

	_expect(GameState.raid_debug_visible, "A synthetic F12 event did not toggle raid debug visibility.")
	_expect(overlay.visible, "F12 visibility did not propagate to the camp overlay.")
	_expect(actor.global_position == actor_position_before, "Toggling debug visuals moved a raider.")
	_expect(actor.path == actor_path_before, "Toggling debug visuals changed an actor path.")
	if collision_body != null:
		_expect(collision_body.collision_layer == collision_layer_before, "Debug visuals changed facility collision layers.")
		_expect(collision_body.collision_mask == collision_mask_before, "Debug visuals changed facility collision masks.")
	if shape != null:
		_expect(shape.size == collision_size_before, "Debug visuals changed facility collision shape size.")

	GameState.set_raid_debug_visibility(false)
	_expect(not overlay.visible, "The camp overlay did not hide when raid debug visibility was cleared.")
	_finish(camp)


func _find_record(records: Array[Dictionary], value: String, key: String) -> Dictionary:
	for record in records:
		if String(record.get(key, "")) == value:
			return record
	return {}


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


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
