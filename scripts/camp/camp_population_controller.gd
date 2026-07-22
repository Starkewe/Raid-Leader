extends Node
class_name CampPopulationController

const CampMemberScene := preload("res://scenes/camp/camp_member.tscn")
const RuntimeRaiderStateScript := preload("res://scripts/data/runtime_raider_state.gd")
const ACTIVITIES := [
	preload("res://data/camp/activities/prepare_plan.tres"),
	preload("res://data/camp/activities/rehearse.tres"),
	preload("res://data/camp/activities/study_target.tres"),
	preload("res://data/camp/activities/smith_work.tres"),
	preload("res://data/camp/activities/apothecary_work.tres"),
	preload("res://data/camp/activities/train.tres"),
	preload("res://data/camp/activities/socialize.tres"),
	preload("res://data/camp/activities/rest.tres"),
	preload("res://data/camp/activities/victory_gather.tres")
]

var actors_by_id: Dictionary = {}
var reservations_by_member: Dictionary = {}
var activity_by_member: Dictionary = {}
var cooldowns_by_member: Dictionary = {}
var runtime_states_by_id: Dictionary = {}
var rng := RandomNumberGenerator.new()
var reaction_timer: float = 2.0
var visible_bubble_count: int = 0
var rebuild_queued: bool = false


func _ready() -> void:
	rng.seed = Time.get_ticks_usec()
	CampaignState.roster_changed.connect(_on_roster_changed)
	CampaignState.raid_plan_changed.connect(_on_plan_changed)
	call_deferred("rebuild_population")


func _process(delta: float) -> void:
	_update_cooldowns(delta)
	reaction_timer -= delta

	if reaction_timer <= 0.0:
		reaction_timer = rng.randf_range(3.5, 6.5)
		_try_emit_visit_reaction()


func rebuild_population() -> void:
	rebuild_queued = false
	_release_all_reservations()

	for actor in actors_by_id.values():
		if actor != null and is_instance_valid(actor):
			actor.free()

	actors_by_id.clear()
	activity_by_member.clear()
	cooldowns_by_member.clear()
	runtime_states_by_id.clear()
	visible_bubble_count = 0

	var roster := CampaignState.get_roster_members()
	var active_ids := CampaignState.get_active_member_ids()
	var visit_type := String(CampaignState.get_visit_context().get("type", "normal"))

	for index in range(roster.size()):
		var member: Dictionary = roster[index]
		var member_id := String(member.get("member_id", ""))
		member["active"] = active_ids.has(member_id)
		var actor := CampMemberScene.instantiate() as CampMemberActor

		if actor == null:
			continue

		get_parent().add_child(actor)
		actor.configure(
			member, _spawn_position(index, roster.size(), visit_type), rng.randf_range(0.4, 4.0)
		)
		actor.ready_for_activity.connect(_on_actor_ready_for_activity)
		actor.activity_completed.connect(_on_activity_completed)
		actor.navigation_failed.connect(_on_navigation_failed)
		actor.bubble_visibility_changed.connect(_on_bubble_visibility_changed)
		actors_by_id[member_id] = actor
		var runtime_state := RuntimeRaiderStateScript.create(member_id)
		runtime_state["temporary_scene_reference"] = actor
		runtime_states_by_id[member_id] = runtime_state


func get_actor_count() -> int:
	return actors_by_id.size()


func _on_actor_ready_for_activity(member_id: String) -> void:
	var actor := actors_by_id.get(member_id) as CampMemberActor

	if actor == null or not is_instance_valid(actor):
		return

	var selection := _select_activity(actor)

	if selection.is_empty():
		actor.interrupt_activity()
		return

	var activity: CampActivityDefinition = selection["activity"]
	var facility: CampFacility = selection["facility"]
	var reservation := facility.reserve_activity_slot(member_id)

	if not bool(reservation.get("ok", false)):
		actor.interrupt_activity()
		return

	reservations_by_member[member_id] = facility.facility_id
	activity_by_member[member_id] = activity.activity_id
	var destination: Vector2 = reservation.get("position", actor.global_position)
	var runtime_state: Dictionary = runtime_states_by_id.get(
		member_id, RuntimeRaiderStateScript.create(member_id)
	)
	runtime_state["current_activity_id"] = activity.activity_id
	runtime_state["destination"] = destination
	runtime_state["animation_state"] = "walking"
	runtime_state["activity_reservation_id"] = facility.facility_id
	runtime_states_by_id[member_id] = runtime_state
	var camp_root := get_parent()
	var waypoints: Array[Vector2] = [destination]

	if camp_root.has_method("build_camp_path"):
		waypoints = camp_root.build_camp_path(
			actor.global_position, destination, facility.facility_id
		)

	actor.start_activity(
		activity.activity_id,
		activity.display_name,
		waypoints,
		rng.randf_range(activity.minimum_duration, activity.maximum_duration)
	)


func _select_activity(actor: CampMemberActor) -> Dictionary:
	var member := actor.get_member_data()
	var member_id := actor.get_member_id()
	var is_active := bool(member.get("active", false))
	var candidates: Array[Dictionary] = []
	var total_weight := 0.0

	for activity_value in ACTIVITIES:
		var activity := activity_value as CampActivityDefinition

		if activity == null:
			continue

		if _is_on_cooldown(member_id, activity.activity_id):
			continue

		var visit_type := String(CampaignState.get_visit_context().get("type", "normal"))

		if (
			not activity.eligible_visit_contexts.is_empty()
			and not activity.eligible_visit_contexts.has(visit_type)
		):
			continue

		var facility := _get_facility(activity.facility_id)

		if facility == null or facility.get_free_slot_count() <= 0:
			continue

		var weight := _activity_weight(
			activity, member, is_active, actor.global_position, facility.global_position
		)

		if activity.activity_id == actor.get_last_activity_id():
			weight *= 0.25

		if weight <= 0.0:
			continue

		total_weight += weight
		candidates.append({"activity": activity, "facility": facility, "weight": weight})

	if candidates.is_empty() or total_weight <= 0.0:
		return {}

	var roll := rng.randf_range(0.0, total_weight)
	var running := 0.0

	for candidate in candidates:
		running += float(candidate["weight"])

		if roll <= running:
			return candidate

	return candidates[-1]


func _activity_weight(
	activity: CampActivityDefinition,
	member: Dictionary,
	is_active: bool,
	from_position: Vector2,
	destination: Vector2
) -> float:
	var weight := activity.base_weight
	weight *= activity.active_multiplier if is_active else activity.reserve_multiplier
	var unit_class := String(member.get("unit_class", ""))

	if activity.favored_classes.has(unit_class):
		weight *= 1.65

	for attribute in member.get("attributes", []):
		if activity.favored_attributes.has(String(attribute)):
			weight *= 1.3

	if member.get("preferred_activity_tags", []).has(activity.activity_id):
		weight *= 1.25

	var visit_type := String(CampaignState.get_visit_context().get("type", "normal"))

	if visit_type == "wipe" and activity.activity_id in ["rehearse", "study_target"]:
		weight *= 1.8
	elif (
		visit_type in ["first_victory", "repeat_victory", "apex_victory"]
		and activity.activity_id == "socialize"
	):
		weight *= 2.3
	elif (
		visit_type in ["recruitment", "roster_change"]
		and activity.activity_id in ["socialize", "train"]
	):
		weight *= 1.7

	if activity.activity_id == String(member.get("last_activity_id", "")):
		weight *= 0.25

	var distance := from_position.distance_to(destination)
	weight *= clampf(1.15 - distance / 4200.0, 0.55, 1.15)
	return weight


func _on_activity_completed(member_id: String, activity_id: String) -> void:
	_release_reservation(member_id)
	activity_by_member.erase(member_id)
	_reset_runtime_activity(member_id)
	var activity := _get_activity(activity_id)

	if activity != null:
		_set_cooldown(member_id, activity_id, activity.cooldown)

		if activity_id == "socialize" and visible_bubble_count <= 1:
			_try_two_person_exchange(member_id, activity)
			return

		if (
			visible_bubble_count < 3
			and rng.randf() <= 0.16
			and not activity.feedback_lines.is_empty()
		):
			var actor := actors_by_id.get(member_id) as CampMemberActor

			if actor != null:
				actor.show_bubble(
					String(
						activity.feedback_lines[rng.randi_range(
							0, activity.feedback_lines.size() - 1
						)]
					)
				)


func _on_navigation_failed(member_id: String, activity_id: String) -> void:
	_release_reservation(member_id)
	activity_by_member.erase(member_id)
	_reset_runtime_activity(member_id)
	_set_cooldown(member_id, activity_id, 2.0)


func _on_bubble_visibility_changed(visible_now: bool) -> void:
	visible_bubble_count += 1 if visible_now else -1
	visible_bubble_count = maxi(visible_bubble_count, 0)


func _try_two_person_exchange(member_id: String, activity: CampActivityDefinition) -> void:
	var actor := actors_by_id.get(member_id) as CampMemberActor

	if actor == null or activity.feedback_lines.is_empty():
		return

	var nearest_actor: CampMemberActor = null
	var nearest_distance := 170.0

	for other_actor_value in actors_by_id.values():
		var other_actor := other_actor_value as CampMemberActor

		if other_actor == null or other_actor == actor:
			continue

		var distance := actor.global_position.distance_to(other_actor.global_position)

		if distance < nearest_distance:
			nearest_actor = other_actor
			nearest_distance = distance

	if nearest_actor == null:
		return

	var partner_id := nearest_actor.get_member_id()
	var actor_runtime: Dictionary = runtime_states_by_id.get(
		member_id, RuntimeRaiderStateScript.create(member_id)
	)
	actor_runtime["conversation_partner_id"] = partner_id
	actor_runtime["pending_interaction"] = {"type": "ambient_exchange"}
	runtime_states_by_id[member_id] = actor_runtime
	var partner_runtime: Dictionary = runtime_states_by_id.get(
		partner_id, RuntimeRaiderStateScript.create(partner_id)
	)
	partner_runtime["conversation_partner_id"] = member_id
	partner_runtime["pending_interaction"] = {"type": "ambient_exchange"}
	runtime_states_by_id[partner_id] = partner_runtime

	actor.show_bubble(
		String(activity.feedback_lines[rng.randi_range(0, activity.feedback_lines.size() - 1)])
	)
	nearest_actor.show_bubble(
		String(
			["Agreed.", "I saw it too.", "Again tomorrow.", "Keep your voice down."][
				rng.randi_range(0, 3)
			]
		)
	)


func _try_emit_visit_reaction() -> void:
	if visible_bubble_count >= 3 or actors_by_id.is_empty():
		return

	if not CampaignState.consume_visit_reaction():
		return

	var actor_values: Array = actors_by_id.values()
	actor_values.shuffle()
	var context_type := String(CampaignState.get_visit_context().get("type", "normal"))
	var lines := _reaction_lines(context_type)

	for actor_value in actor_values:
		var actor := actor_value as CampMemberActor

		if (
			actor != null
			and actor.show_bubble(String(lines[rng.randi_range(0, lines.size() - 1)]), 5.5)
		):
			return


func _reaction_lines(context_type: String) -> Array[String]:
	match context_type:
		"wipe":
			return [
				"We saw more this time.",
				"Check the archive before we go again.",
				"The plan held until it did not.",
				"Same raid, better opening."
			]
		"first_victory":
			return [
				"First head on the spike.",
				"The Writ held.",
				"That one will be remembered.",
				"Let the fire burn late."
			]
		"repeat_victory":
			return [
				"Cleaner than the first.", "The plan still works.", "Another mark in the archive."
			]
		"recruitment":
			return [
				"New bedrolls by the quarters.",
				"Learn their names before the pull.",
				"The camp feels larger already."
			]
		"roster_change":
			return [
				"The active list changed again.",
				"Check your marker at the yard.",
				"Reserves today, raiders tomorrow."
			]
		"apex_victory":
			return [
				"The road beyond the Crucible is open.",
				"The liaison has new maps.",
				"That was the region's last word."
			]
		_:
			return [
				"The fire is holding.", "Maps are dry enough to read.", "Another dusk in the Writ."
			]


func _get_facility(facility_id: String) -> CampFacility:
	var camp_root := get_parent()

	if camp_root.has_method("get_facility"):
		return camp_root.get_facility(facility_id) as CampFacility

	return null


func _get_activity(activity_id: String) -> CampActivityDefinition:
	for activity_value in ACTIVITIES:
		var activity := activity_value as CampActivityDefinition

		if activity != null and activity.activity_id == activity_id:
			return activity

	return null


func _release_reservation(member_id: String) -> void:
	var facility_id := String(reservations_by_member.get(member_id, ""))
	var facility := _get_facility(facility_id)

	if facility != null:
		facility.release_activity_slot(member_id)

	reservations_by_member.erase(member_id)


func _release_all_reservations() -> void:
	for member_id in reservations_by_member.keys():
		_release_reservation(String(member_id))


func _set_cooldown(member_id: String, activity_id: String, duration: float) -> void:
	var member_cooldowns: Dictionary = cooldowns_by_member.get(member_id, {})
	member_cooldowns[activity_id] = duration
	cooldowns_by_member[member_id] = member_cooldowns


func _reset_runtime_activity(member_id: String) -> void:
	if not runtime_states_by_id.has(member_id):
		return

	var runtime_state: Dictionary = runtime_states_by_id[member_id]
	runtime_state["current_activity_id"] = ""
	runtime_state["destination"] = Vector2.ZERO
	runtime_state["animation_state"] = "idle"
	runtime_state["activity_reservation_id"] = ""
	runtime_states_by_id[member_id] = runtime_state


func _is_on_cooldown(member_id: String, activity_id: String) -> bool:
	return float(cooldowns_by_member.get(member_id, {}).get(activity_id, 0.0)) > 0.0


func _update_cooldowns(delta: float) -> void:
	for member_id in cooldowns_by_member.keys():
		var member_cooldowns: Dictionary = cooldowns_by_member[member_id]

		for activity_id in member_cooldowns.keys():
			member_cooldowns[activity_id] = maxf(float(member_cooldowns[activity_id]) - delta, 0.0)


func _spawn_position(index: int, total: int, visit_type: String) -> Vector2:
	if index < 4 and visit_type != "normal":
		return Vector2(1390 + index * 70, 1510 + (index % 2) * 45)

	var local_index := index - 4 if visit_type != "normal" else index
	var columns := 8 if total > 24 else 6
	return Vector2(480 + (local_index % columns) * 74, 1540 + (local_index / columns) * 64)


func _on_roster_changed() -> void:
	_queue_rebuild()


func _on_plan_changed() -> void:
	_queue_rebuild()


func _queue_rebuild() -> void:
	if rebuild_queued:
		return

	rebuild_queued = true
	call_deferred("rebuild_population")
