extends RefCounted
class_name AttemptSummaryBuilder


static func build(
	encounter_id: String,
	outcome: String,
	events: Array[Dictionary],
	boss_health: int,
	boss_max_health: int,
	current_phase_id: String,
	current_phase_name: String
) -> Dictionary:
	var duration := 0.0
	var damage_by_source: Dictionary = {}
	var healing_by_source: Dictionary = {}
	var deaths: Array[Dictionary] = []
	var ability_ids: Array[String] = []
	var phase_ids: Array[String] = []
	var phase_names: Array[String] = []
	var failures: Array[String] = []
	var timeline: Array[Dictionary] = []
	var last_damage_by_target: Dictionary = {}
	var successful_interrupts: Array[Dictionary] = []
	var exceptional_heals: Array[Dictionary] = []
	var mechanic_outcomes: Array[Dictionary] = []
	var grouped_mechanic_failures: Dictionary = {}

	for event in events:
		duration = maxf(duration, float(event.get("encounter_time_seconds", 0.0)))
		var event_type := String(event.get("type", ""))
		var ability_id := String(event.get("ability_id", ""))
		var source := _dictionary_or_empty(event.get("source"))
		var target := _dictionary_or_empty(event.get("target"))
		var metadata := _dictionary_or_empty(event.get("metadata"))
		var source_id := String(source.get("id", "environment"))
		var target_id := String(target.get("id", ""))
		var amount := int(event.get("amount", 0))

		if event_type == "damage":
			damage_by_source[source_id] = int(damage_by_source.get(source_id, 0)) + amount

			if not target_id.is_empty():
				last_damage_by_target[target_id] = {
					"ability_id": ability_id,
					"source_name": String(source.get("name", "Unknown")),
					"amount": amount,
					"time": float(event.get("encounter_time_seconds", 0.0)),
					"metadata": metadata.duplicate(true)
				}

		elif event_type == "healing":
			healing_by_source[source_id] = int(healing_by_source.get(source_id, 0)) + amount

			if bool(metadata.get("exceptional_heal", false)):
				exceptional_heals.append(
					{
						"healer_id": source_id,
						"target_id": target_id,
						"ability_id": ability_id,
						"amount": amount,
						"rescue": bool(metadata.get("rescue", false)),
						"previous_health_percent": float(
							metadata.get("previous_health_percent", 0.0)
						),
						"restored_health_percent": float(
							metadata.get("restored_health_percent", 0.0)
						),
						"time": float(event.get("encounter_time_seconds", 0.0)),
					}
				)

		elif event_type == "unit_defeated":
			var last_damage: Dictionary = last_damage_by_target.get(target_id, {})
			deaths.append(
				{
					"member_id": target_id,
					"member_name": String(target.get("name", "Unknown")),
					"time": float(event.get("encounter_time_seconds", 0.0)),
					"cause_ability_id": String(last_damage.get("ability_id", "unknown")),
					"source_name": String(last_damage.get("source_name", "Unknown")),
					"reliable": not last_damage.is_empty()
				}
			)

		if event_type in ["cast_started", "cast_resolved"] and not ability_id.is_empty():
			_append_unique(ability_ids, ability_id)

		if event_type == "phase_changed":
			_append_unique(phase_ids, ability_id)
			_append_unique(phase_names, String(metadata.get("display_name", ability_id)))

		if bool(metadata.get("iron_collar_failure", false)):
			_append_unique(failures, "Iron Collar tightened before its target escaped outward.")
			mechanic_outcomes.append(
				{
					"outcome": "failed",
					"ability_id": ability_id,
					"participant_ids": [target_id],
					"reliable": true,
					"time": float(event.get("encounter_time_seconds", 0.0)),
				}
			)

		if bool(metadata.get("stampede", false)) and event_type == "damage":
			_append_unique(failures, "The raid was struck by a stampede wave.")
			var wave := int(metadata.get("wave", 0))
			var group_key := "%s:%d" % [ability_id, wave]
			var grouped: Dictionary = grouped_mechanic_failures.get(
				group_key,
				{
					"outcome": "failed",
					"ability_id": ability_id,
					"wave": wave,
					"participant_ids": [],
					"reliable": true,
					"time": float(event.get("encounter_time_seconds", 0.0)),
				}
			)
			var participant_ids: Array = grouped.get("participant_ids", [])

			if not target_id.is_empty() and not participant_ids.has(target_id):
				participant_ids.append(target_id)

			grouped["participant_ids"] = participant_ids
			grouped_mechanic_failures[group_key] = grouped

		if event_type == "mechanic_resolved" and not target_id.is_empty():
			mechanic_outcomes.append(
				{
					"outcome": "resolved",
					"ability_id": ability_id,
					"participant_ids": [target_id],
					"reliable": true,
					"time": float(event.get("encounter_time_seconds", 0.0)),
				}
			)

		if event_type == "cast_interrupted" and source.get("kind", "") == "raid_member":
			successful_interrupts.append(
				{
					"member_id": source_id,
					"ability_id": ability_id,
					"interrupt_ability_id": String(
						metadata.get("interrupt_ability_id", "interrupt")
					),
					"time": float(event.get("encounter_time_seconds", 0.0)),
				}
			)

		if (
			event_type
			in [
				"unit_defeated",
				"phase_changed",
				"cast_started",
				"cast_interrupted",
				"boss_defeated"
			]
		):
			timeline.append(_timeline_entry(event))

	if not current_phase_id.is_empty():
		_append_unique(phase_ids, current_phase_id)
		_append_unique(phase_names, current_phase_name)

	for grouped_failure in grouped_mechanic_failures.values():
		if grouped_failure is Dictionary:
			mechanic_outcomes.append(Dictionary(grouped_failure).duplicate(true))

	if timeline.size() > 16:
		timeline = timeline.slice(timeline.size() - 16)

	var health_percent := 0.0

	if boss_max_health > 0:
		health_percent = clampf(float(boss_health) / float(boss_max_health) * 100.0, 0.0, 100.0)

	return {
		"attempt_id": "%s_%d" % [encounter_id, Time.get_ticks_usec()],
		"encounter_id": encounter_id,
		"outcome": outcome,
		"recorded_unix_time": int(Time.get_unix_time_from_system()),
		"duration_seconds": snappedf(duration, 0.1),
		"boss_health": boss_health,
		"boss_max_health": boss_max_health,
		"boss_health_percent": snappedf(health_percent, 0.1),
		"boss_progress_percent": snappedf(100.0 - health_percent, 0.1),
		"furthest_phase_id": current_phase_id,
		"furthest_phase_name": current_phase_name,
		"observed_ability_ids": ability_ids,
		"observed_phase_ids": phase_ids,
		"observed_phase_names": phase_names,
		"reliable_failures": failures,
		"deaths": deaths,
		"damage_by_source": damage_by_source,
		"healing_by_source": healing_by_source,
		"successful_interrupts": successful_interrupts,
		"exceptional_heals": exceptional_heals,
		"mechanic_outcomes": mechanic_outcomes,
		"timeline": timeline,
		"event_count": events.size()
	}


static func _timeline_entry(event: Dictionary) -> Dictionary:
	var target := _dictionary_or_empty(event.get("target"))
	var metadata := _dictionary_or_empty(event.get("metadata"))
	return {
		"time": snappedf(float(event.get("encounter_time_seconds", 0.0)), 0.1),
		"type": String(event.get("type", "")),
		"ability_id": String(event.get("ability_id", "")),
		"target_name": String(target.get("name", "")),
		"display_name": String(metadata.get("display_name", ""))
	}


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return Dictionary(value)

	return {}


static func _append_unique(target: Array[String], value: String) -> void:
	if not value.is_empty() and not target.has(value):
		target.append(value)
