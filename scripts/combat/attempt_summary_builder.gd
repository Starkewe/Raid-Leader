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
	var healing_casts: Array[Dictionary] = []
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

		if (
			event_type in ["cast_started", "cast_resolved"]
			and not ability_id.is_empty()
			and not bool(metadata.get("healing_spell", false))
		):
			_append_unique(ability_ids, ability_id)

		if event_type == "cast_started" and bool(metadata.get("healing_spell", false)):
			healing_casts.append(
				{
					"healer_id": source_id,
					"target_id": target_id,
					"ability_id": ability_id,
					"display_name": String(
						metadata.get("display_name", metadata.get("cast_name", ability_id))
					),
					"amount": int(metadata.get("healing_amount", amount)),
					"cast_time": float(metadata.get("cast_time", 0.0)),
					"time": float(event.get("encounter_time_seconds", 0.0)),
				}
			)

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

		if event_type == "twin_mauler_rampage_failed":
			_append_unique(failures, "Rampage struck the raid for near-wipe damage.")

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
				"boss_defeated",
				"twin_mauler_rampage_failed",
				"twin_mauler_exhaustion_resolution",
				"twin_mauler_defeated",
				"twin_mauler_survivor_enrage"
			]
			and not (
				event_type == "cast_started"
				and bool(metadata.get("healing_spell", false))
			)
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

	var summary := {
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
		"healing_casts": healing_casts,
		"mechanic_outcomes": mechanic_outcomes,
		"timeline": timeline,
		"event_count": events.size()
	}

	return summary


static func build_carrion_roc_metrics(events: Array[Dictionary]) -> Dictionary:
	var cycle_intervals: Array[float] = []
	var stagger_breaks: Array[Dictionary] = []
	var rupture_locations: Array[Dictionary] = []
	var rupture_outcomes: Dictionary = {
		"success": 0,
		"ignored": 0,
		"failed": 0
	}
	var rupture_assignments: Array[Dictionary] = []
	var growth_records: Array[Dictionary] = []
	var movement_commands: Array[Dictionary] = []
	var composition: Dictionary = {}
	var stagger_contribution: Dictionary = {"melee": 0.0, "ranged": 0.0, "other": 0.0}
	var boss_damage: Dictionary = {"normal": 0, "vulnerability": 0}
	var growth_damage := 0
	var growth_raid_damage := 0
	var cleanup_damage := 0
	var uptime_lost_seconds := 0.0

	for event in events:
		var event_type := String(event.get("type", ""))
		var metadata := _dictionary_or_empty(event.get("metadata"))
		var amount := int(event.get("amount", 0))

		if event_type == "roc_stagger_pressure":
			var source_type := String(metadata.get("stagger_source_type", "other"))
			stagger_contribution[source_type] = float(
				stagger_contribution.get(source_type, 0.0)
			) + float(metadata.get("stagger_weight", 0.0)) * float(metadata.get("raw_damage", 0))

		if event_type == "roc_stagger_broken":
			var break_record := metadata.duplicate(true)
			stagger_breaks.append(break_record)
			cycle_intervals.append(float(metadata.get("cycle_interval_seconds", 0.0)))
			uptime_lost_seconds += float(metadata.get("grounded_duration", 16.0))
			var formation: Array = metadata.get("formation", [])
			for member_value in formation:
				var member := _dictionary_or_empty(member_value)
				var member_identity := _dictionary_or_empty(member.get("member"))
				var class_label := String(member.get(
					"unit_class",
					member_identity.get("unit_class", "unknown")
				))
				composition[class_label] = int(composition.get(class_label, 0)) + 1

		if event_type == "roc_rupture_spawned":
			rupture_locations.append({
				"rupture_id": int(metadata.get("rupture_id", 0)),
				"side": String(metadata.get("side", "")),
				"region": String(metadata.get("region", "")),
				"range": String(metadata.get("range", "")),
				"cycle_index": int(metadata.get("cycle_index", 0))
			})

		if event_type == "roc_growth_assignment":
			rupture_assignments.append(metadata.duplicate(true))

		if event_type == "roc_rupture_resolved":
			var outcome := String(metadata.get("outcome", "ignored"))
			rupture_outcomes[outcome] = int(rupture_outcomes.get(outcome, 0)) + 1

		if event_type == "roc_boss_damage_window":
			var window := String(metadata.get("boss_damage_window", "normal"))
			boss_damage[window] = int(boss_damage.get(window, 0)) + amount

		if event_type == "roc_growth_lifespan_recorded":
			growth_records.append(metadata.duplicate(true))
			growth_damage += int(metadata.get("damage_taken", 0))
			growth_raid_damage += int(metadata.get("raid_damage", 0))

		if event_type == "roc_growth_cleanup":
			cleanup_damage += int(metadata.get("cleanup_damage", 0))
			growth_records.append(metadata.duplicate(true))
			growth_raid_damage += int(metadata.get("raid_damage", 0))

		if event_type == "roc_growth_pulse":
			growth_raid_damage += amount

		if event_type == "roc_movement_command":
			movement_commands.append(metadata.duplicate(true))

	return {
		"cycle_count": stagger_breaks.size(),
		"cycle_intervals_seconds": cycle_intervals,
		"stagger_contribution": stagger_contribution,
		"composition": composition,
		"stagger_breaks": stagger_breaks,
		"rupture_locations": rupture_locations,
		"rupture_outcomes": rupture_outcomes,
		"rupture_assignments": rupture_assignments,
		"soak_deaths": _count_roc_soak_deaths(events),
		"growths": growth_records,
		"growth_damage": growth_damage,
		"growth_raid_damage": growth_raid_damage,
		"growth_cleanup_damage": cleanup_damage,
		"boss_damage": boss_damage,
		"boss_uptime_lost_seconds": uptime_lost_seconds,
		"movement_commands_during_vulnerability": movement_commands,
		"movement_command_count_during_vulnerability": movement_commands.size()
	}


static func build_twin_maulers_metrics(events: Array[Dictionary]) -> Dictionary:
	var rage_samples: Array[Dictionary] = []
	var rampage_warnings: Array[Dictionary] = []
	var rampage_failures: Array[Dictionary] = []
	var exhaustion_sequence: Array[Dictionary] = []
	var exhaustion_records: Array[Dictionary] = []
	var reassignment_events: Array[Dictionary] = []
	var proactive_exhaustions := 0
	var reactive_exhaustions := 0
	var high_rage_raid_health: Array[Dictionary] = []
	var boss_damage_during_exhaustion: Dictionary = {"west": 0, "east": 0}
	var static_allocation_seconds := 0.0
	var static_allocation_fingerprint := ""
	var static_allocation_started := -1.0
	var last_sample_time := 0.0
	var rampage_failure_count := 0
	var exhaustion_counts: Dictionary = {"west": 0, "east": 0}
	var same_target_streak := 0
	var longest_same_target_streak := 0
	var last_exhaustion_side := ""

	for event in events:
		var event_type := String(event.get("type", ""))
		var metadata := _dictionary_or_empty(event.get("metadata"))
		var event_time := float(event.get("encounter_time_seconds", 0.0))

		if event_type == "twin_mauler_rage_sample":
			var sample := metadata.duplicate(true)
			rage_samples.append(sample)
			last_sample_time = event_time
			var mauler_samples: Array = sample.get("maulers", [])
			var fingerprints: Array[String] = []
			var high_rage := false
			for mauler_value in mauler_samples:
				var mauler := _dictionary_or_empty(mauler_value)
				var side := String(mauler.get("side", ""))
				fingerprints.append("%s:%d" % [side, int(mauler.get("active_attackers", 0))])
				if float(mauler.get("rage", 0.0)) >= 100.0:
					high_rage = true
			if high_rage:
				high_rage_raid_health.append({
					"time": event_time,
					"raid_health": Dictionary(sample.get("raid_health", {})).duplicate(true),
					"maulers": mauler_samples.duplicate(true)
				})

			var fingerprint := "|".join(fingerprints)
			if static_allocation_fingerprint.is_empty():
				static_allocation_fingerprint = fingerprint
				static_allocation_started = event_time
			elif fingerprint != static_allocation_fingerprint:
				static_allocation_seconds = maxf(
					static_allocation_seconds,
					event_time - static_allocation_started
				)
				static_allocation_fingerprint = fingerprint
				static_allocation_started = event_time

		if event_type == "twin_mauler_rampage_warning":
			rampage_warnings.append(metadata.duplicate(true))

		if event_type == "twin_mauler_rampage_failed":
			rampage_failures.append(metadata.duplicate(true))
			rampage_failure_count += 1

		if event_type == "twin_mauler_target_reassignment":
			reassignment_events.append(metadata.duplicate(true))

		if event_type == "twin_mauler_exhaustion_resolution":
			var exhaustion := metadata.duplicate(true)
			exhaustion["time"] = event_time
			exhaustion_sequence.append(exhaustion)
			exhaustion_records.append(exhaustion)
			var side := String(exhaustion.get("side", ""))
			exhaustion_counts[side] = int(exhaustion_counts.get(side, 0)) + 1
			if bool(exhaustion.get("reactive", false)):
				reactive_exhaustions += 1
			else:
				proactive_exhaustions += 1
			if side == last_exhaustion_side:
				same_target_streak += 1
			else:
				last_exhaustion_side = side
				same_target_streak = 1
			longest_same_target_streak = maxi(longest_same_target_streak, same_target_streak)

		if event_type == "damage" and bool(metadata.get("exhausted", false)):
			var target := _dictionary_or_empty(event.get("target"))
			var target_name := String(target.get("name", "")).to_lower()
			var side := "west" if target_name.contains("west") else "east" if target_name.contains("east") else ""
			if not side.is_empty():
				boss_damage_during_exhaustion[side] = int(boss_damage_during_exhaustion.get(side, 0)) + int(event.get("amount", 0))

	if not static_allocation_fingerprint.is_empty() and static_allocation_started >= 0.0:
		static_allocation_seconds = maxf(
			static_allocation_seconds,
			last_sample_time - static_allocation_started
		)

	return {
		"rage_samples": rage_samples,
		"rampage_warnings": rampage_warnings,
		"rampage_failures": rampage_failures,
		"rampage_failure_count": rampage_failure_count,
		"exhaustion_sequence": exhaustion_sequence,
		"exhaustion_records": exhaustion_records,
		"exhaustion_counts": exhaustion_counts,
		"reactive_exhaustions": reactive_exhaustions,
		"proactive_exhaustions": proactive_exhaustions,
		"longest_same_target_exhaustion_streak": longest_same_target_streak,
		"boss_damage_during_exhaustion": boss_damage_during_exhaustion,
		"reassignment_events": reassignment_events,
		"reassignment_count": reassignment_events.size(),
		"high_rage_raid_health_samples": high_rage_raid_health,
		"longest_static_allocation_seconds": snappedf(static_allocation_seconds, 0.1)
	}


static func _count_roc_soak_deaths(events: Array[Dictionary]) -> int:
	var count := 0
	for event in events:
		if String(event.get("type", "")) == "roc_soak_death":
			count += 1

	return count


static func _timeline_entry(event: Dictionary) -> Dictionary:
	var target := _dictionary_or_empty(event.get("target"))
	var metadata := _dictionary_or_empty(event.get("metadata"))
	return {
		"time": snappedf(float(event.get("encounter_time_seconds", 0.0)), 0.1),
		"type": String(event.get("type", "")),
		"ability_id": String(event.get("ability_id", "")),
		"amount": int(event.get("amount", 0)),
		"target_name": String(target.get("name", "")),
		"display_name": String(metadata.get("display_name", "")),
		"cast_time": float(metadata.get("cast_time", 0.0))
	}


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return Dictionary(value)

	return {}


static func _append_unique(target: Array[String], value: String) -> void:
	if not value.is_empty() and not target.has(value):
		target.append(value)
