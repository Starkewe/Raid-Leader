extends Node

const CampScene := preload("res://scenes/camp/camp_scene.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignState.reset_campaign(false, 61059)
	_test_position_migration()

	var camp := CampScene.instantiate()
	add_child(camp)
	await _wait_frames(4)

	var population := camp.get_node_or_null("CampPopulationController") as CampPopulationController
	_expect(population != null, "The camp population controller did not load.")
	if population == null:
		_finish()
		return

	var active_ids := CampaignState.get_active_member_ids()
	_expect(population.actors_by_id.size() == CampaignState.get_roster_members().size(), "The camp did not spawn the full recruited roster.")
	_test_fallback_positions(camp, population)

	var retained_id := String(active_ids[0])
	var retained_actor := population.actors_by_id.get(retained_id) as CampMemberActor
	_expect(retained_actor != null, "The first active raider did not receive a camp actor.")
	if retained_actor != null:
		retained_actor.set_process(false)
		var retained_position := Vector2(900, 1800)
		retained_actor.global_position = retained_position
		CampaignState.set_member_placement(retained_id, "north", "far")
		await _wait_frames(2)
		_expect(
			population.actors_by_id.get(retained_id) == retained_actor,
			"A formation edit recreated a retained camp actor."
		)
		_expect(
			retained_actor.global_position == retained_position,
			"A formation edit moved a retained camp actor."
		)

		population.persist_current_positions()
		var saved_position := CampaignState.get_raider_camp_position(retained_id)
		_expect(bool(saved_position.get("valid", false)), "The camp position was not persisted.")

	camp.queue_free()
	await _wait_frames(2)

	var restored_camp := CampScene.instantiate()
	add_child(restored_camp)
	await _wait_frames(4)
	var restored_population := restored_camp.get_node_or_null("CampPopulationController") as CampPopulationController
	var restored_actor := (
		restored_population.actors_by_id.get(retained_id) as CampMemberActor
		if restored_population != null
		else null
	)
	_expect(restored_actor != null, "The retained raider did not return to camp.")
	if restored_actor != null:
		_expect(
			restored_actor.global_position.distance_to(Vector2(900, 1800)) <= 1.0,
			"The retained raider did not return to its saved camp position."
		)

	if restored_population != null and retained_actor != null:
		var retained_after_restore := restored_population.actors_by_id.get(retained_id) as CampMemberActor
		if retained_after_restore != null:
			retained_after_restore.set_process(false)

		var first_other_id := String(active_ids[1])
		var first_other_actor := restored_population.actors_by_id.get(first_other_id) as CampMemberActor
		if first_other_actor != null:
			first_other_actor.set_process(false)

		var first_conversation := restored_population.begin_conversation_channels(
			"regression_focused",
			{"first": retained_id, "second": first_other_id},
			"focused",
			""
		)
		_expect(first_conversation, "A focused conversation could not be started.")
		if first_conversation and restored_actor != null and first_other_actor != null:
			restored_actor.global_position = Vector2(400, 1800)
			first_other_actor.global_position = Vector2(1700, 1800)
			# Re-start after placing the actors far apart so the anchor calculation is exercised.
			restored_population.end_conversation_channels(
				"regression_focused", [retained_id, first_other_id], "focused", ""
			)
			first_conversation = restored_population.begin_conversation_channels(
				"regression_focused_2",
				{"first": retained_id, "second": first_other_id},
				"focused",
				""
			)
			_expect(first_conversation, "A focused conversation could not restart after cleanup.")
			for _index in range(60):
				restored_actor._process(0.1)
				first_other_actor._process(0.1)
			_expect(
				restored_actor.global_position.distance_to(first_other_actor.global_position) <= 120.0,
				"Focused conversation participants did not converge to a shared radius."
			)
			restored_population.end_conversation_channels(
				"regression_focused_2", [retained_id, first_other_id], "focused", ""
			)
		if restored_actor != null:
			_expect(
				restored_actor.state != "focused_conversation"
				and restored_actor.state != "conversation_approaching",
				"Ending a focused conversation left the raider movement-locked."
			)

		CampaignState.ensure_debug_reserves()
		await _wait_frames(3)
		_expect(
			restored_population.actors_by_id.get(retained_id) == retained_after_restore,
			"Recruiting reserves recreated a retained camp actor."
		)

		var outgoing_id := String(active_ids[0])
		var incoming_id := String(CampaignState.get_future_recruit_ids()[0])
		var swap_result := CampaignState.swap_active_member(outgoing_id, incoming_id)
		_expect(swap_result, "The roster swap regression setup failed.")
		await _wait_frames(3)
		_expect(
			not restored_population.actors_by_id.has(outgoing_id),
			"A removed raider remained in the camp population."
		)
		_expect(
			restored_population.actors_by_id.has(incoming_id),
			"A newly added raider did not receive a camp actor."
		)

	restored_camp.queue_free()
	await _wait_frames(2)
	CampaignState.reset_campaign(false, 61059)
	_finish()


func _test_position_migration() -> void:
	var source := CampaignState.campaign.duplicate(true)
	source["schema_version"] = 8
	for state_value in source.get("raider_states", {}).values():
		if state_value is Dictionary:
			state_value.erase("last_camp_position")

	var migrated := CampaignState._migrate_campaign(source)
	_expect(
		int(migrated.get("schema_version", 0)) == CampaignState.SCHEMA_VERSION,
		"An older campaign did not migrate to the current schema."
	)
	for state_value in migrated.get("raider_states", {}).values():
		if state_value is Dictionary:
			_expect(
				Array(state_value.get("last_camp_position", [])).is_empty(),
				"An older campaign received an invalid fabricated camp position."
			)

	CampaignState.reset_campaign(false, 61059)


func _test_fallback_positions(camp: Node, population: CampPopulationController) -> void:
	var fire := camp.call("get_facility", "communal_fire") as CampFacility
	for actor_value in population.actors_by_id.values():
		var actor := actor_value as CampMemberActor
		if actor == null:
			continue
		_expect(
			bool(camp.call("is_valid_population_position", actor.global_position)),
			"A fallback camp position overlaps camp geometry."
		)
		if fire != null:
			_expect(
				actor.global_position.distance_to(fire.global_position) > 300.0,
				"A fallback raider spawned immediately south of the campfire."
			)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
		return

	print("Camp population, position, roster, and conversation regressions passed.")
	get_tree().quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
