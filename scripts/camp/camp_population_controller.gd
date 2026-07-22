extends Node
class_name CampPopulationController

const CampMemberScene := preload("res://scenes/camp/camp_member.tscn")
const RuntimeRaiderStateScript := preload("res://scripts/data/runtime_raider_state.gd")
const CampActivityStationScript := preload("res://scripts/data/camp_activity_station.gd")
const CampContentCatalogScript := preload("res://scripts/core/camp_content_catalog.gd")
const CampConversationDirectorScript := preload(
	"res://scripts/camp/camp_conversation_director.gd"
)
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
# Compatibility name retained for existing diagnostics; values are now stable station IDs.
var reservations_by_member: Dictionary = {}
var activity_by_member: Dictionary = {}
var cooldowns_by_member: Dictionary = {}
var runtime_states_by_id: Dictionary = {}
var stations_by_id: Dictionary = {}
var activity_instances: Dictionary = {}
var completion_outcomes_by_member: Dictionary = {}
var activity_instance_sequence: int = 0
var conversation_director: CampConversationDirector = null
var rng := RandomNumberGenerator.new()
var reaction_timer: float = 2.0
var visible_bubble_count: int = 0
var rebuild_queued: bool = false
var accelerated_timing: bool = false


func _ready() -> void:
	add_to_group("camp_population_controller")
	rng.seed = Time.get_ticks_usec()
	_build_station_registry()
	conversation_director = CampConversationDirectorScript.new() as CampConversationDirector
	conversation_director.name = "CampConversationDirector"
	add_child(conversation_director)
	conversation_director.configure(self)
	CampaignState.roster_changed.connect(_on_roster_changed)
	CampaignState.raid_plan_changed.connect(_on_plan_changed)
	call_deferred("rebuild_population")


func _process(delta: float) -> void:
	var scaled_delta := delta * (6.0 if accelerated_timing else 1.0)
	_update_cooldowns(scaled_delta)
	_sync_runtime_animation_states()
	reaction_timer -= scaled_delta

	if reaction_timer <= 0.0:
		reaction_timer = rng.randf_range(3.5, 6.5)
		_try_emit_visit_reaction()


func _exit_tree() -> void:
	if conversation_director != null and is_instance_valid(conversation_director):
		conversation_director.cancel_all("scene_exit")
	_release_all_reservations()


func rebuild_population() -> void:
	rebuild_queued = false
	if conversation_director != null:
		conversation_director.cancel_all("population_rebuild")
	_release_all_reservations()

	for actor in actors_by_id.values():
		if actor != null and is_instance_valid(actor):
			actor.free()

	actors_by_id.clear()
	activity_by_member.clear()
	cooldowns_by_member.clear()
	runtime_states_by_id.clear()
	activity_instances.clear()
	completion_outcomes_by_member.clear()
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
		actor.set_timing_multiplier(6.0 if accelerated_timing else 1.0)
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
	var station: CampActivityStation = selection["station"]
	var participant_ids: Array[String] = [member_id]
	var desired_max := mini(activity.maximum_participants, station.get_free_capacity())

	if (
		desired_max > 1
		and (activity.minimum_participants > 1 or rng.randf() <= 0.68)
	):
		participant_ids.append_array(
			_find_shared_participants(activity, member_id, desired_max - 1)
		)

	if participant_ids.size() < activity.minimum_participants:
		actor.interrupt_activity()
		return

	var reservation := station.reserve(participant_ids, "station_reserved")
	if not bool(reservation.get("ok", false)):
		actor.interrupt_activity()
		return

	activity_instance_sequence += 1
	var instance_id := "camp_activity_%06d" % activity_instance_sequence
	var shared_duration := rng.randf_range(activity.minimum_duration, activity.maximum_duration)
	activity_instances[instance_id] = {
		"instance_id": instance_id,
		"activity_id": activity.activity_id,
		"station_id": station.get_station_id(),
		"participant_ids": participant_ids.duplicate(),
		"started_camp_time": float(
			CampaignState.get_camp_conversation_debug_report().get("camp_time_seconds", 0.0)
		),
	}

	for participant_id in participant_ids:
		_start_reserved_activity(
			participant_id,
			activity,
			station,
			instance_id,
			Dictionary(reservation.get("assignments", {}).get(participant_id, {})),
			participant_ids,
			shared_duration
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
		if not _activity_requirements_met(member_id, activity):
			continue

		var visit_type := String(CampaignState.get_visit_context().get("type", "normal"))

		if (
			not activity.eligible_visit_contexts.is_empty()
			and not activity.eligible_visit_contexts.has(visit_type)
		):
			continue

		var available_stations := _available_stations_for_activity(activity)

		if available_stations.is_empty():
			continue

		var station: CampActivityStation = available_stations[
			rng.randi_range(0, available_stations.size() - 1)
		]
		var facility := _get_facility(station.get_facility_id())
		if facility == null:
			continue

		var weight := _activity_weight(
			activity, member, is_active, actor.global_position, facility.global_position
		)

		if activity.activity_id == actor.get_last_activity_id():
			weight *= 0.25

		if weight <= 0.0:
			continue

		total_weight += weight
		candidates.append({"activity": activity, "station": station, "weight": weight})

	if candidates.is_empty() or total_weight <= 0.0:
		return {}

	var roll := rng.randf_range(0.0, total_weight)
	var running := 0.0

	for candidate in candidates:
		running += float(candidate["weight"])

		if roll <= running:
			return candidate

	return candidates[-1]


func _available_stations_for_activity(
	activity: CampActivityDefinition
) -> Array[CampActivityStation]:
	var result: Array[CampActivityStation] = []

	for value in stations_by_id.values():
		var station := value as CampActivityStation
		if station == null or not station.supports_activity(activity.activity_id):
			continue
		if not activity.compatible_station_ids.is_empty() and not activity.compatible_station_ids.has(station.get_station_id()):
			continue
		if station.get_free_capacity() >= activity.minimum_participants:
			result.append(station)

	return result


func _find_shared_participants(
	activity: CampActivityDefinition, starter_id: String, maximum_additional: int
) -> Array[String]:
	var candidates: Array[Dictionary] = []

	for other_id_value in actors_by_id.keys():
		var other_id := String(other_id_value)
		if other_id == starter_id or reservations_by_member.has(other_id):
			continue
		var other_actor := actors_by_id.get(other_id) as CampMemberActor
		var runtime_state: Dictionary = runtime_states_by_id.get(other_id, {})
		if other_actor == null or not other_actor.is_available_for_shared_activity():
			continue
		if not Dictionary(runtime_state.get("social_interaction", {})).is_empty():
			continue
		var member := other_actor.get_member_data()
		var weight := 1.0
		if activity.favored_classes.has(String(member.get("unit_class", ""))):
			weight += 1.0
		if _arrays_intersect(member.get("attributes", []), activity.personality_preferences):
			weight += 0.75
		candidates.append({"raider_id": other_id, "weight": weight})

	var result: Array[String] = []
	while not candidates.is_empty() and result.size() < maximum_additional:
		var total_weight := 0.0
		for candidate in candidates:
			total_weight += float(candidate.get("weight", 1.0))
		var roll := rng.randf_range(0.0, total_weight)
		var running := 0.0
		var selected_index := 0
		for index in range(candidates.size()):
			running += float(candidates[index].get("weight", 1.0))
			if roll <= running:
				selected_index = index
				break
		result.append(String(candidates[selected_index].get("raider_id", "")))
		candidates.remove_at(selected_index)

	return result


func _start_reserved_activity(
	member_id: String,
	activity: CampActivityDefinition,
	station: CampActivityStation,
	instance_id: String,
	assignment: Dictionary,
	participant_ids: Array[String],
	duration: float
) -> void:
	var actor := actors_by_id.get(member_id) as CampMemberActor
	var facility := _get_facility(station.get_facility_id())
	if actor == null or facility == null:
		station.release(member_id)
		return

	reservations_by_member[member_id] = station.get_station_id()
	activity_by_member[member_id] = activity.activity_id
	var destination := facility.global_position + Vector2(assignment.get("position_offset", Vector2.ZERO))
	var context := _build_activity_context(member_id, activity, participant_ids)
	var runtime_state: Dictionary = runtime_states_by_id.get(
		member_id, RuntimeRaiderStateScript.create(member_id)
	)
	RuntimeRaiderStateScript.set_primary_activity(
		runtime_state,
		activity.activity_id,
		activity.category,
		station.get_station_id(),
		instance_id,
		destination,
		context
	)
	runtime_states_by_id[member_id] = runtime_state
	var waypoints: Array[Vector2] = [destination]
	var camp_root := get_parent()
	if camp_root.has_method("build_camp_path"):
		waypoints = camp_root.build_camp_path(
			actor.global_position, destination, station.get_facility_id()
		)
	var facing: Vector2 = assignment.get("facing", Vector2.DOWN)
	actor.start_activity(
		activity.activity_id, activity.display_name, waypoints, duration, facing
	)


func _build_activity_context(
	member_id: String, activity: CampActivityDefinition, participant_ids: Array[String]
) -> Dictionary:
	var visit_type := String(CampaignState.get_visit_context().get("type", "normal"))
	var context_id := "routine"
	if visit_type == "wipe" and activity.category in ["Study", "Training", "Reflection"]:
		context_id = "recent_failed_mechanic"
	elif visit_type in ["first_victory", "repeat_victory", "apex_victory"]:
		context_id = "recent_victory"
	elif visit_type == "roster_change" and CampaignState.is_member_active(member_id):
		context_id = "returning_to_active_roster"
	elif participant_ids.size() > 1:
		context_id = "spending_time_with_companion"
	elif activity.activity_id == "study_target" and not CampaignState.get_raider_lore_knowledge(member_id).is_empty():
		context_id = "studying_newly_learned_lore"

	return {
		"context_id": context_id,
		"visit_type": visit_type,
		"participant_ids": participant_ids.duplicate(),
		"selected_because": context_id,
	}


func _activity_requirements_met(
	member_id: String, activity: CampActivityDefinition
) -> bool:
	for requirement in activity.memory_context_requirements:
		if requirement == "known_lore" and CampaignState.get_raider_lore_knowledge(member_id).is_empty():
			return false
		if requirement == "existing_memory_thread" and Dictionary(CampaignState.get_raider_memories(member_id).get("threads", {})).is_empty():
			return false
		if requirement.begins_with("visit:") and String(CampaignState.get_visit_context().get("type", "normal")) != requirement.trim_prefix("visit:"):
			return false
	return true


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
	var role := String(member.get("role", ""))

	if activity.favored_classes.has(unit_class):
		weight *= 1.65
	if activity.favored_roles.has(role):
		weight *= 1.2

	for attribute in member.get("attributes", []):
		if activity.favored_attributes.has(String(attribute)):
			weight *= 1.3
		if activity.personality_preferences.has(String(attribute)):
			weight *= 1.15

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
	_remove_from_activity_instance(member_id)
	_reset_runtime_activity(member_id)
	var activity := _get_activity(activity_id)

	if activity != null:
		_set_cooldown(member_id, activity_id, activity.cooldown)
		_record_routine_completion(member_id, activity)

		if (
			visible_bubble_count < 3
			and rng.randf() <= 0.12
			and not activity.feedback_lines.is_empty()
		):
			var actor := actors_by_id.get(member_id) as CampMemberActor
			var runtime_state: Dictionary = runtime_states_by_id.get(member_id, {})

			if actor != null and Dictionary(runtime_state.get("social_interaction", {})).is_empty():
				actor.show_bubble(
					String(
						activity.feedback_lines[rng.randi_range(
							0, activity.feedback_lines.size() - 1
						)]
					)
				)


func _record_routine_completion(
	member_id: String, activity: CampActivityDefinition
) -> void:
	if activity.completion_outcomes.is_empty():
		return
	var outcome := String(
		activity.completion_outcomes[
			rng.randi_range(0, activity.completion_outcomes.size() - 1)
		]
	)
	completion_outcomes_by_member[member_id] = {
		"activity_id": activity.activity_id,
		"outcome": outcome,
		"camp_time_seconds": float(
			CampaignState.get_camp_conversation_debug_report().get("camp_time_seconds", 0.0)
		),
	}

	if outcome != "limited_memory_reinforcement" or rng.randf() > 0.08:
		return
	var memories := CampaignState.get_raider_memories(member_id)
	var threads: Dictionary = memories.get("threads", {})
	if threads.is_empty():
		return
	var thread: Dictionary = Dictionary(threads.values()[0])
	CampaignState.reinforce_memory_through_reflection(
		member_id,
		String(thread.get("category", "camp_life")),
		String(thread.get("subject_key", "")),
		false
	)


func _on_navigation_failed(member_id: String, activity_id: String) -> void:
	_release_reservation(member_id)
	activity_by_member.erase(member_id)
	_remove_from_activity_instance(member_id)
	_reset_runtime_activity(member_id)
	_set_cooldown(member_id, activity_id, 2.0)


func _on_bubble_visibility_changed(visible_now: bool) -> void:
	visible_bubble_count += 1 if visible_now else -1
	visible_bubble_count = maxi(visible_bubble_count, 0)


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
		var runtime_state: Dictionary = (
			runtime_states_by_id.get(actor.get_member_id(), {}) if actor != null else {}
		)

		if (
			actor != null
			and not actor.has_visible_bubble()
			and Dictionary(runtime_state.get("social_interaction", {})).is_empty()
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
	var station_id := String(reservations_by_member.get(member_id, ""))
	var station := stations_by_id.get(station_id) as CampActivityStation

	if station != null:
		station.release(member_id)

	reservations_by_member.erase(member_id)


func _release_all_reservations() -> void:
	for station_value in stations_by_id.values():
		var station := station_value as CampActivityStation
		if station != null:
			station.release_all()
	reservations_by_member.clear()


func _set_cooldown(member_id: String, activity_id: String, duration: float) -> void:
	var member_cooldowns: Dictionary = cooldowns_by_member.get(member_id, {})
	member_cooldowns[activity_id] = duration
	cooldowns_by_member[member_id] = member_cooldowns


func _reset_runtime_activity(member_id: String) -> void:
	if not runtime_states_by_id.has(member_id):
		return

	var runtime_state: Dictionary = runtime_states_by_id[member_id]
	RuntimeRaiderStateScript.clear_primary_activity(runtime_state)
	runtime_states_by_id[member_id] = runtime_state


func _is_on_cooldown(member_id: String, activity_id: String) -> bool:
	return float(cooldowns_by_member.get(member_id, {}).get(activity_id, 0.0)) > 0.0


func _update_cooldowns(delta: float) -> void:
	for member_id in cooldowns_by_member.keys():
		var member_cooldowns: Dictionary = cooldowns_by_member[member_id]

		for activity_id in member_cooldowns.keys():
			member_cooldowns[activity_id] = maxf(float(member_cooldowns[activity_id]) - delta, 0.0)


func _build_station_registry() -> void:
	stations_by_id.clear()
	for definition in CampContentCatalogScript.get_station_definitions():
		var station := CampActivityStationScript.create(definition)
		var station_id := station.get_station_id()
		if not station_id.is_empty():
			stations_by_id[station_id] = station


func _remove_from_activity_instance(member_id: String) -> void:
	var runtime_state: Dictionary = runtime_states_by_id.get(member_id, {})
	var instance_id := String(runtime_state.get("activity_instance_id", ""))
	if instance_id.is_empty() or not activity_instances.has(instance_id):
		return
	var instance: Dictionary = activity_instances[instance_id]
	var participants: Array = instance.get("participant_ids", [])
	participants.erase(member_id)
	if participants.is_empty():
		activity_instances.erase(instance_id)
	else:
		instance["participant_ids"] = participants
		activity_instances[instance_id] = instance


func _sync_runtime_animation_states() -> void:
	for member_id_value in runtime_states_by_id.keys():
		var member_id := String(member_id_value)
		var actor := actors_by_id.get(member_id) as CampMemberActor
		if actor == null or not is_instance_valid(actor):
			continue
		var runtime_state: Dictionary = runtime_states_by_id[member_id]
		runtime_state["animation_state"] = actor.get_activity_state()
		runtime_states_by_id[member_id] = runtime_state


func get_conversation_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member_id_value in actors_by_id.keys():
		var member_id := String(member_id_value)
		var actor := actors_by_id.get(member_id) as CampMemberActor
		var runtime_state: Dictionary = runtime_states_by_id.get(member_id, {})
		if actor == null or not is_instance_valid(actor) or actor.has_visible_bubble():
			continue
		if not Dictionary(runtime_state.get("social_interaction", {})).is_empty():
			continue
		if String(runtime_state.get("reservation_level", "free")) == "temporarily_unavailable":
			continue
		var member := actor.get_member_data()
		result.append(
			{
				"raider_id": member_id,
				"activity_id": String(runtime_state.get("current_activity_id", "")),
				"station_id": String(runtime_state.get("station_id", "")),
				"reservation_level": String(runtime_state.get("reservation_level", "free")),
				"attributes": Array(member.get("attributes", [])).duplicate(),
				"lore_knowledge_tags": Array(member.get("lore_knowledge_tags", [])).duplicate(),
				"unit_class": String(member.get("unit_class", "")),
				"role": String(member.get("role", "")),
			}
		)
	return result


func is_station_conversation_compatible(
	station_id: String, tone: String, category: String
) -> bool:
	var station := stations_by_id.get(station_id) as CampActivityStation
	return station != null and station.is_conversation_compatible(tone, category)


func begin_conversation_channels(
	conversation_id: String,
	participants_by_role: Dictionary,
	delivery: String,
	station_id: String
) -> bool:
	var participant_ids: Array[String] = []
	for role in participants_by_role.keys():
		var participant_id := String(participants_by_role[role])
		if participant_id.is_empty() or participant_ids.has(participant_id):
			return false
		participant_ids.append(participant_id)
	if participant_ids.size() != 2:
		return false
	var first_actor := actors_by_id.get(participant_ids[0]) as CampMemberActor
	var second_actor := actors_by_id.get(participant_ids[1]) as CampMemberActor
	if (
		first_actor == null
		or second_actor == null
		or not is_instance_valid(first_actor)
		or not is_instance_valid(second_actor)
	):
		return false

	var started_focused: Array[String] = []
	for index in range(participant_ids.size()):
		var participant_id := participant_ids[index]
		var actor := actors_by_id.get(participant_id) as CampMemberActor
		if actor == null or not is_instance_valid(actor):
			_end_partial_focused(started_focused)
			return false
		var other_actor := second_actor if index == 0 else first_actor
		if delivery == "focused" and not actor.begin_focused_conversation(other_actor.global_position):
			_end_partial_focused(started_focused)
			return false
		if delivery == "focused":
			started_focused.append(participant_id)

	for role in participants_by_role.keys():
		var participant_id := String(participants_by_role[role])
		var runtime_state: Dictionary = runtime_states_by_id.get(
			participant_id, RuntimeRaiderStateScript.create(participant_id)
		)
		RuntimeRaiderStateScript.set_social_interaction(
			runtime_state,
			conversation_id,
			String(role),
			"talking" if String(role) == String(participants_by_role.keys()[0]) else "listening",
			delivery
		)
		runtime_state["conversation_partner_id"] = participant_ids[1] if participant_id == participant_ids[0] else participant_ids[0]
		runtime_states_by_id[participant_id] = runtime_state
		if delivery == "focused":
			var participant_station := stations_by_id.get(String(runtime_state.get("station_id", ""))) as CampActivityStation
			if participant_station != null:
				participant_station.set_reservation_level(participant_id, "exclusively_reserved")

	var station := stations_by_id.get(station_id) as CampActivityStation
	if delivery == "embedded" and station != null:
		for participant_id in participant_ids:
			station.set_reservation_level(participant_id, "socially_or_partially_reserved")
	return true


func set_conversation_speaker(conversation_id: String, speaker_id: String) -> void:
	for member_id_value in runtime_states_by_id.keys():
		var member_id := String(member_id_value)
		var runtime_state: Dictionary = runtime_states_by_id[member_id]
		var social: Dictionary = runtime_state.get("social_interaction", {})
		if String(social.get("conversation_id", "")) != conversation_id:
			continue
		social["interaction"] = "talking" if member_id == speaker_id else "listening"
		runtime_state["social_interaction"] = social
		runtime_states_by_id[member_id] = runtime_state


func end_conversation_channels(
	conversation_id: String,
	participant_ids_value: Variant,
	delivery: String,
	station_id: String
) -> void:
	var participant_ids := _string_array(participant_ids_value)
	for participant_id in participant_ids:
		var actor := actors_by_id.get(participant_id) as CampMemberActor
		if actor != null and is_instance_valid(actor) and delivery == "focused":
			actor.end_focused_conversation()
		if not runtime_states_by_id.has(participant_id):
			continue
		var runtime_state: Dictionary = runtime_states_by_id[participant_id]
		var participant_station := stations_by_id.get(String(runtime_state.get("station_id", ""))) as CampActivityStation
		if participant_station != null:
			participant_station.set_reservation_level(participant_id, "station_reserved")
		var social: Dictionary = runtime_state.get("social_interaction", {})
		if String(social.get("conversation_id", "")) == conversation_id:
			RuntimeRaiderStateScript.clear_social_interaction(runtime_state)
			runtime_states_by_id[participant_id] = runtime_state

	var station := stations_by_id.get(station_id) as CampActivityStation
	if delivery == "embedded" and station != null:
		for participant_id in participant_ids:
			station.set_reservation_level(participant_id, "station_reserved")


func _end_partial_focused(participant_ids: Array[String]) -> void:
	for participant_id in participant_ids:
		var actor := actors_by_id.get(participant_id) as CampMemberActor
		if actor != null and is_instance_valid(actor):
			actor.end_focused_conversation()


func show_conversation_bubble(member_id: String, text: String, duration: float) -> bool:
	var actor := actors_by_id.get(member_id) as CampMemberActor
	return actor != null and is_instance_valid(actor) and actor.show_bubble(text, duration)


func hide_conversation_bubbles(participant_ids_value: Variant) -> void:
	for participant_id in _string_array(participant_ids_value):
		var actor := actors_by_id.get(participant_id) as CampMemberActor
		if actor != null and is_instance_valid(actor):
			actor.hide_bubble()


func is_conversation_participant_valid(member_id: String) -> bool:
	var actor := actors_by_id.get(member_id) as CampMemberActor
	return actor != null and is_instance_valid(actor) and runtime_states_by_id.has(member_id)


func force_conversation(frame_id: String = "") -> Dictionary:
	return conversation_director.force_conversation(frame_id) if conversation_director != null else {"ok": false, "reason": "director_missing"}


func force_lore_exchange() -> Dictionary:
	return conversation_director.force_lore_exchange() if conversation_director != null else {"ok": false, "reason": "director_missing"}


func cancel_active_conversations() -> int:
	return conversation_director.cancel_all("debug_cancel") if conversation_director != null else 0


func set_accelerated_activity_timing(enabled: bool) -> void:
	accelerated_timing = enabled
	for actor_value in actors_by_id.values():
		var actor := actor_value as CampMemberActor
		if actor != null:
			actor.set_timing_multiplier(6.0 if enabled else 1.0)
	if conversation_director != null:
		conversation_director.set_accelerated_timing(enabled)


func get_camp_v2_runtime_debug_report() -> Dictionary:
	var raiders: Dictionary = {}
	for member_id_value in runtime_states_by_id.keys():
		var member_id := String(member_id_value)
		var state: Dictionary = runtime_states_by_id[member_id]
		raiders[member_id] = {
			"current_activity": Dictionary(state.get("primary_activity", {})).duplicate(true),
			"current_station": String(state.get("station_id", "")),
			"primary_channel": Dictionary(state.get("primary_activity", {})).duplicate(true),
			"social_channel": Dictionary(state.get("social_interaction", {})).duplicate(true),
			"context_channel": Dictionary(state.get("context_channel", {})).duplicate(true),
			"reservation_state": String(state.get("reservation_level", "free")),
			"animation_state": String(state.get("animation_state", "idle")),
		}

	var stations: Dictionary = {}
	for station_id_value in stations_by_id.keys():
		var station_id := String(station_id_value)
		var station := stations_by_id[station_id] as CampActivityStation
		stations[station_id] = station.get_debug_data() if station != null else {}

	return {
		"raiders": raiders,
		"stations": stations,
		"activity_instances": activity_instances.duplicate(true),
		"recent_activity_completion_outcomes": completion_outcomes_by_member.duplicate(true),
		"activity_cooldowns": cooldowns_by_member.duplicate(true),
		"conversation": conversation_director.get_debug_report() if conversation_director != null else {},
		"accelerated_timing": accelerated_timing,
	}


func print_camp_v2_runtime_debug_report() -> void:
	print(
		"[Camp V2 Activities and Conversations]\n"
		+ JSON.stringify(get_camp_v2_runtime_debug_report(), "\t")
	)


func _arrays_intersect(first: Array, second: Array) -> bool:
	for value in first:
		if second.has(value):
			return true
	return false


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result


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
