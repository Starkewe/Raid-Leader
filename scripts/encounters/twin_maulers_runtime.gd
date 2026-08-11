extends EncounterRuntime
class_name TwinMaulersRuntime

const TwinMaulerScript := preload("res://scripts/encounters/twin_mauler.gd")
const AttemptSummaryBuilderScript := preload(
	"res://scripts/combat/attempt_summary_builder.gd"
)

var twin_definition: TwinMaulersDefinition = null
var maulers: Dictionary = {}
var encounter_active: bool = false
var elapsed_seconds: float = 0.0
var rampage_timer: float = -1.0
var active_rampage: TwinMauler = null
var last_rampage_side: String = ""
var rampage_same_target_streak: int = 0
var survivor_enraged: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var telemetry_timer: float = 0.0
var finalization_queued: bool = false
var command_assignment_count: int = 0


func configure(
	new_boss: Node, new_definition: EncounterDefinition,
	new_session: EncounterSession = null
) -> void:
	super.configure(new_boss, new_definition, new_session)
	twin_definition = new_definition as TwinMaulersDefinition
	if twin_definition == null:
		return

	if twin_definition.random_seed == 0:
		rng.randomize()
	else:
		rng.seed = twin_definition.random_seed

	_connect_target_registry()

	if boss != null and is_instance_valid(boss):
		var boss_sprite := boss.get_node_or_null("Sprite2D") as CanvasItem
		if boss_sprite != null:
			boss_sprite.visible = false

	_create_maulers()
	_sync_boss_health()


func set_party_members(new_party_members: Array) -> void:
	party_members = new_party_members
	for mauler in _get_all_maulers():
		mauler.set_party_members(party_members)

	_assign_initial_tanks()


func set_encounter_active(active: bool) -> void:
	encounter_active = active and _has_living_mauler()
	for mauler in _get_all_maulers():
		mauler.set_encounter_active(encounter_active)

	if encounter_active:
		if rampage_timer < 0.0:
			rampage_timer = rng.randf_range(
				twin_definition.rampage_initial_delay_min,
				twin_definition.rampage_initial_delay_max
			)
	else:
		_cancel_active_rampage("encounter_stopped", false)
		rampage_timer = -1.0

	_publish_state()


func uses_custom_combat_loop() -> bool:
	return twin_definition != null


func get_boss_damage_multiplier() -> float:
	# The canonical Boss node is an encounter coordinator for this fight. All
	# player damage must resolve against one of the two registered Maulers.
	return 0.0


func get_primary_encounter_targets(include_defeated: bool = false) -> Array[Node]:
	return target_registry.get_primary_targets(include_defeated)


func get_target_registry() -> EncounterTargetRegistry:
	return target_registry


func build_attempt_metrics(events: Array[Dictionary]) -> Dictionary:
	return {
		"twin_maulers": AttemptSummaryBuilderScript.build_twin_maulers_metrics(events)
	}


func _on_target_registry_changed(
	previous_registry: EncounterTargetRegistry,
	_new_registry: EncounterTargetRegistry
) -> void:
	var callback := Callable(self, "_on_target_defeated")
	if previous_registry != null and previous_registry.target_defeated.is_connected(callback):
		previous_registry.target_defeated.disconnect(callback)
	_connect_target_registry()


func _connect_target_registry() -> void:
	var callback := Callable(self, "_on_target_defeated")
	if target_registry != null and not target_registry.target_defeated.is_connected(callback):
		target_registry.target_defeated.connect(callback)


func tick(delta: float) -> void:
	if twin_definition == null or not encounter_active or not _has_living_mauler():
		return

	var safe_delta := maxf(delta, 0.0)
	elapsed_seconds += safe_delta

	_process_rampage(safe_delta)

	for mauler in _get_all_maulers():
		if mauler == null or not is_instance_valid(mauler):
			continue

		var pressure := _get_pressure_data(mauler)
		mauler.tick_combat(
			safe_delta,
			int(pressure.get("attacker_count", 0)),
			int(pressure.get("group_count", 0))
		)

	_sync_boss_health()
	telemetry_timer -= safe_delta
	if telemetry_timer <= 0.0:
		telemetry_timer = maxf(twin_definition.telemetry_sample_interval, 0.1)
		_emit_rage_sample()

	_publish_state()


func request_target_exhaustion(target: Node) -> void:
	var mauler := target as TwinMauler
	if mauler == null or not is_instance_valid(mauler) or mauler.is_dead or mauler.is_exhausted():
		return

	var reactive := active_rampage == mauler and mauler.is_casting_ability()
	var threshold_before := mauler.get_exhaustion_threshold()
	var rampage_remaining := _get_rampage_remaining(mauler)
	if reactive:
		_cancel_active_rampage("exhaustion", true)

	mauler.start_exhaustion(twin_definition.exhaustion_duration, reactive)

	var sibling := _get_sibling(mauler)
	if sibling != null and not sibling.is_dead:
		sibling.exhaustion_level = maxi(sibling.exhaustion_level - 1, 0)
		sibling.state_changed.emit()
		if (
			not sibling.is_exhausted()
			and sibling.rage >= sibling.get_exhaustion_threshold() - 0.0001
		):
			request_target_exhaustion(sibling)

	_emit_runtime_event(
		"twin_mauler_exhaustion_resolution",
		mauler,
		"twin_mauler_exhaustion",
		0,
		{
			"encounter": "twin_maulers",
			"side": mauler.side,
			"reactive": reactive,
			"proactive": not reactive,
			"threshold_before": threshold_before,
			"threshold_after": mauler.get_exhaustion_threshold(),
			"rampage_remaining_seconds": rampage_remaining,
			"rage": mauler.rage,
			"attack_speed_multiplier": mauler.get_attack_speed_multiplier()
		}
	)
	_publish_state()


func on_target_damage(
	target: Node,
	amount: int,
	source: Node,
	ability_id: String,
	metadata: Dictionary
) -> void:
	if amount <= 0:
		return

	var mauler := target as TwinMauler
	_sync_boss_health()
	if mauler != null and is_instance_valid(mauler):
		mauler.state_changed.emit()


func on_command_issued(command_data: Dictionary) -> void:
	if String(command_data.get("what", "")) != "attack" and String(command_data.get("what", "")) != "taunt":
		return

	var where := String(command_data.get("where", ""))
	if where != "encounter_target":
		return

	command_assignment_count += 1
	_emit_runtime_event(
		"twin_mauler_target_reassignment",
		null,
		"twin_mauler_target_reassignment",
		0,
		{
			"encounter": "twin_maulers",
			"action": String(command_data.get("what", "")),
			"target": Dictionary(command_data.get("encounter_target", {})).duplicate(true),
			"who_type": String(command_data.get("who_type", "")),
			"who_value": command_data.get("who_value", ""),
			"who_selectors": command_data.get("who_selectors", [])
		}
	)


func get_status_text() -> String:
	if twin_definition == null:
		return ""

	if active_rampage != null and is_instance_valid(active_rampage):
		return active_rampage.get_display_name() + " " + active_rampage.get_cast_name()

	var west := _get_mauler("west")
	var east := _get_mauler("east")
	if west == null or east == null:
		return "Twin Maulers initializing"

	return "West Rage %d/%d | East Rage %d/%d" % [
		int(round(west.rage)),
		int(round(west.get_exhaustion_threshold())),
		int(round(east.rage)),
		int(round(east.get_exhaustion_threshold()))
	]


func is_casting() -> bool:
	return active_rampage != null and is_instance_valid(active_rampage) and active_rampage.is_casting_ability()


func get_cast_progress_percent() -> float:
	return active_rampage.get_cast_progress_percent() if is_casting() else 0.0


func get_cast_name() -> String:
	return active_rampage.get_cast_name() if is_casting() else ""


func get_current_cast_time() -> float:
	return active_rampage.get_current_cast_time() if is_casting() else 0.0


func get_current_cast_bar_value() -> float:
	return active_rampage.get_current_cast_bar_value() if is_casting() else 0.0


func reset_attempt() -> void:
	_cleanup_maulers()
	elapsed_seconds = 0.0
	rampage_timer = -1.0
	active_rampage = null
	last_rampage_side = ""
	rampage_same_target_streak = 0
	survivor_enraged = false
	telemetry_timer = 0.0
	finalization_queued = false
	command_assignment_count = 0
	if twin_definition != null:
		if twin_definition.random_seed == 0:
			rng.randomize()
		else:
			rng.seed = twin_definition.random_seed
	_create_maulers()
	_sync_boss_health()
	encounter_active = false


func cleanup_encounter() -> void:
	encounter_active = false
	_cancel_active_rampage("cleanup", false)
	_cleanup_maulers()
	if target_registry != null:
		target_registry.clear()


func _create_maulers() -> void:
	if twin_definition == null or boss == null or not is_instance_valid(boss):
		return

	var parent := boss as Node2D
	if parent == null:
		return

	var west := TwinMaulerScript.new() as TwinMauler
	parent.add_child(west)
	west.configure(
		self,
		twin_definition,
		"west",
		"West Mauler",
		parent.global_position + Vector2(twin_definition.west_offset_pixels, 0.0)
	)
	west.position = Vector2(twin_definition.west_offset_pixels, 0.0)

	var east := TwinMaulerScript.new() as TwinMauler
	parent.add_child(east)
	east.configure(
		self,
		twin_definition,
		"east",
		"East Mauler",
		parent.global_position + Vector2(twin_definition.east_offset_pixels, 0.0)
	)
	east.position = Vector2(twin_definition.east_offset_pixels, 0.0)

	maulers["west"] = west
	maulers["east"] = east
	if not party_members.is_empty():
		west.set_party_members(party_members)
		east.set_party_members(party_members)
	target_registry.register_target(west)
	target_registry.register_target(east)
	if boss.has_method("register_encounter_object"):
		boss.register_encounter_object(west)
		boss.register_encounter_object(east)


func _cleanup_maulers() -> void:
	for mauler in _get_all_maulers():
		if mauler == null or not is_instance_valid(mauler):
			continue

		if target_registry != null:
			target_registry.unregister_target(mauler)
		if mauler.is_inside_tree():
			mauler.cleanup()

	maulers.clear()


func _process_rampage(delta: float) -> void:
	if active_rampage != null:
		if (
			not is_instance_valid(active_rampage)
			or active_rampage.is_dead
			or active_rampage.is_exhausted()
		):
			_cancel_active_rampage("target_unavailable", true)
		else:
			var rampage_phase := active_rampage.tick_rampage(delta)
			if rampage_phase == "warning_finished":
				active_rampage.set_rampage_cast(twin_definition.rampage_cast_duration)
				_emit_runtime_event(
					"cast_started",
					active_rampage,
					"twin_mauler_rampage",
					0,
					{
						"encounter": "twin_maulers",
						"side": active_rampage.side,
						"display_name": "Rampage",
						"cast_time": twin_definition.rampage_cast_duration,
						"warning_duration": twin_definition.rampage_warning_duration,
						"interruptible": false
					}
				)
			elif rampage_phase == "cast_finished":
				_resolve_rampage(active_rampage)

		return

	if rampage_timer < 0.0:
		return

	rampage_timer = maxf(rampage_timer - maxf(delta, 0.0), 0.0)
	if rampage_timer > 0.0:
		return

	var selected := _select_rampage_target()
	if selected == null:
		return

	active_rampage = selected
	active_rampage.set_rampage_warning(twin_definition.rampage_warning_duration)
	_emit_runtime_event(
		"twin_mauler_rampage_warning",
		selected,
		"twin_mauler_rampage",
		0,
		{
			"encounter": "twin_maulers",
			"side": selected.side,
			"rage": selected.rage,
			"rage_floor": selected.get_rage_floor(),
			"exhaustion_threshold": selected.get_exhaustion_threshold(),
			"active_attackers": selected.active_attacker_count,
			"active_groups": selected.active_group_count,
			"warning_duration": twin_definition.rampage_warning_duration,
			"selection_streak": rampage_same_target_streak
		}
	)
	selected.queue_redraw()


func _resolve_rampage(mauler: TwinMauler) -> void:
	if mauler == null or not is_instance_valid(mauler) or mauler.is_dead:
		_cancel_active_rampage("target_unavailable", true)
		return

	var damage_total := 0
	for party_member in party_members:
		if not _is_living(party_member):
			continue

		var maximum_health := _get_max_health(party_member)
		var damage := ceili(float(maximum_health) * twin_definition.rampage_damage_max_health_percent)
		party_member.take_damage(
			damage,
			mauler,
			"twin_mauler_rampage",
			{
				"encounter": "twin_maulers",
				"side": mauler.side,
				"rampage_failure": true,
				"damage_percent_of_max_health": twin_definition.rampage_damage_max_health_percent
			}
		)
		damage_total += damage

	_emit_runtime_event(
		"twin_mauler_rampage_failed",
		mauler,
		"twin_mauler_rampage",
		damage_total,
		{
			"encounter": "twin_maulers",
			"side": mauler.side,
			"rampage_failure": true,
			"damage_percent_of_max_health": twin_definition.rampage_damage_max_health_percent,
			"living_party_count": _get_living_party_count()
		}
	)
	_emit_runtime_event(
		"cast_resolved",
		mauler,
		"twin_mauler_rampage",
		damage_total,
		{
			"encounter": "twin_maulers",
			"side": mauler.side,
			"rampage_failure": true,
			"interruptible": false
		}
	)
	mauler.clear_rampage_state()
	active_rampage = null
	rampage_timer = twin_definition.get_rampage_interval(rng, survivor_enraged)


func _cancel_active_rampage(reason: String, reschedule: bool) -> void:
	if active_rampage == null or not is_instance_valid(active_rampage):
		return

	var canceled := active_rampage
	var was_casting := canceled.is_casting_ability()
	if was_casting:
		_emit_runtime_event(
			"cast_cancelled",
			canceled,
			"twin_mauler_rampage",
			0,
			{
				"encounter": "twin_maulers",
				"side": canceled.side,
				"reason": reason,
				"interruptible": false,
				"rampage_canceled": true
			}
		)

	canceled.clear_rampage_state()
	active_rampage = null
	if reschedule and encounter_active:
		rampage_timer = twin_definition.get_rampage_interval(rng, survivor_enraged)


func _select_rampage_target() -> TwinMauler:
	var candidates: Array[TwinMauler] = []
	for mauler in _get_all_maulers():
		if mauler != null and is_instance_valid(mauler) and not mauler.is_dead and not mauler.is_exhausted():
			candidates.append(mauler)

	if candidates.is_empty():
		return null

	if (
		not last_rampage_side.is_empty()
		and rampage_same_target_streak >= twin_definition.maximum_rampage_same_target_streak
		and candidates.size() > 1
	):
		var filtered: Array[TwinMauler] = []
		for candidate in candidates:
			if candidate.side != last_rampage_side:
				filtered.append(candidate)
		if not filtered.is_empty():
			candidates = filtered

	var selected := candidates[rng.randi_range(0, candidates.size() - 1)]
	if selected.side == last_rampage_side:
		rampage_same_target_streak += 1
	else:
		last_rampage_side = selected.side
		rampage_same_target_streak = 1

	return selected


func _on_target_defeated(target: Node) -> void:
	var defeated_mauler := target as TwinMauler
	if defeated_mauler == null:
		return

	_sync_boss_health()
	if active_rampage == defeated_mauler:
		_cancel_active_rampage("target_defeated", true)

	var living := _get_living_maulers()
	if living.size() == 1 and not survivor_enraged:
		survivor_enraged = true
		living[0].set_survivor_enraged()
		if rampage_timer > 0.0:
			rampage_timer *= twin_definition.survivor_rampage_interval_multiplier
		if not living[0].is_exhausted() and living[0].rage >= living[0].get_exhaustion_threshold() - 0.0001:
			request_target_exhaustion(living[0])
	elif living.is_empty() and not finalization_queued:
		finalization_queued = true
		call_deferred("_finish_encounter")

	_publish_state()


func _finish_encounter() -> void:
	finalization_queued = false
	if boss == null or not is_instance_valid(boss):
		return

	if not _has_living_mauler():
		boss.die()


func _assign_initial_tanks() -> void:
	var tanks: Array[Node] = []
	for party_member in party_members:
		if _is_living(party_member) and party_member.has_method("has_role") and party_member.has_role("tank"):
			tanks.append(party_member)

	var west := _get_mauler("west")
	var east := _get_mauler("east")
	if west != null and not tanks.is_empty():
		west.set_initial_target(tanks[0])
	if east != null and tanks.size() > 1:
		east.set_initial_target(tanks[1])
	elif east != null and not tanks.is_empty():
		east.set_initial_target(tanks[0])


func _get_pressure_data(mauler: TwinMauler) -> Dictionary:
	var attacker_count := 0
	var groups: Dictionary = {}
	for index in range(party_members.size()):
		var party_member = party_members[index]
		if not _is_living(party_member) or not party_member.has_method("get_active_attack_target"):
			continue

		if party_member.get_active_attack_target() != mauler:
			continue

		attacker_count += 1
		groups[int(index / 5) + 1] = true

	return {
		"attacker_count": attacker_count,
		"group_count": groups.size()
	}


func _emit_rage_sample() -> void:
	var sample: Array[Dictionary] = []
	for mauler in _get_all_maulers():
		if mauler == null or not is_instance_valid(mauler):
			continue
		var pressure := _get_pressure_data(mauler)
		sample.append({
			"side": mauler.side,
			"health": mauler.health,
			"max_health": mauler.max_health,
			"rage": mauler.rage,
			"rage_floor": mauler.get_rage_floor(),
			"exhaustion_threshold": mauler.get_exhaustion_threshold(),
			"exhaustion_level": mauler.exhaustion_level,
			"exhausted": mauler.is_exhausted(),
			"attack_speed_multiplier": mauler.get_attack_speed_multiplier(),
			"active_attackers": int(pressure.get("attacker_count", 0)),
			"active_groups": int(pressure.get("group_count", 0)),
			"rage_rate": twin_definition.get_rage_rate(int(pressure.get("attacker_count", 0)))
		})

	_emit_runtime_event(
		"twin_mauler_rage_sample",
		null,
		"twin_mauler_rage_sample",
		0,
		{
			"encounter": "twin_maulers",
			"time_seconds": elapsed_seconds,
			"maulers": sample,
			"raid_health": _get_raid_health_snapshot()
		}
	)


func _publish_state() -> void:
	if boss == null or not is_instance_valid(boss) or not boss.has_method("set_mechanic_state"):
		return

	boss.set_mechanic_state("twin_maulers", {
		"encounter": "twin_maulers",
		"elapsed_seconds": elapsed_seconds,
		"rampage_timer": rampage_timer,
		"active_rampage_side": active_rampage.side if active_rampage != null and is_instance_valid(active_rampage) else "",
		"survivor_enraged": survivor_enraged,
		"command_assignment_count": command_assignment_count
	})


func _sync_boss_health() -> void:
	if boss == null or not is_instance_valid(boss):
		return

	var total_health := 0
	for mauler in _get_all_maulers():
		if mauler != null and is_instance_valid(mauler):
			total_health += maxi(mauler.health, 0)

	boss.health = total_health
	if boss.has_method("update_health_bar"):
		boss.update_health_bar()


func _get_mauler(side_name: String) -> TwinMauler:
	return maulers.get(side_name, null) as TwinMauler


func _get_sibling(mauler: TwinMauler) -> TwinMauler:
	if mauler == null:
		return null

	return _get_mauler("east" if mauler.side == "west" else "west")


func _get_all_maulers() -> Array[TwinMauler]:
	var result: Array[TwinMauler] = []
	for side_name in ["west", "east"]:
		var mauler := _get_mauler(side_name)
		if mauler != null and is_instance_valid(mauler):
			result.append(mauler)
	return result


func _get_living_maulers() -> Array[TwinMauler]:
	var result: Array[TwinMauler] = []
	for mauler in _get_all_maulers():
		if not mauler.is_dead:
			result.append(mauler)
	return result


func _has_living_mauler() -> bool:
	return not _get_living_maulers().is_empty()


func _get_rampage_remaining(mauler: TwinMauler) -> float:
	if mauler == null:
		return 0.0
	if mauler.rampage_warning_remaining > 0.0:
		return mauler.rampage_warning_remaining
	if mauler.rampage_cast_remaining > 0.0:
		return mauler.rampage_cast_remaining
	return 0.0


func _get_living_party_count() -> int:
	var count := 0
	for party_member in party_members:
		if _is_living(party_member):
			count += 1
	return count


func _get_max_health(target: Node) -> int:
	if target == null or not is_instance_valid(target):
		return 1
	if target.has_method("get_max_health"):
		return maxi(int(target.get_max_health()), 1)
	return maxi(int(target.get("max_health")), 1)


func _get_raid_health_snapshot() -> Dictionary:
	var current := 0
	var maximum := 0
	for party_member in party_members:
		if party_member == null or not is_instance_valid(party_member):
			continue
		current += int(party_member.get("health"))
		maximum += _get_max_health(party_member)

	return {
		"current": current,
		"max": maximum,
		"percent": float(current) / float(maximum) * 100.0 if maximum > 0 else 0.0
	}


func _is_living(target: Node) -> bool:
	return target != null and is_instance_valid(target) and (not target.has_method("is_alive") or bool(target.is_alive()))


func _emit_runtime_event(
	event_type: String,
	source: Node,
	ability_id: String,
	amount: int,
	metadata: Dictionary
) -> void:
	if boss == null or not is_instance_valid(boss) or not boss.has_method("emit_combat_event"):
		return

	var event_metadata := metadata.duplicate(true)
	event_metadata["encounter"] = "twin_maulers"
	boss.emit_combat_event(event_type, source, ability_id, amount, event_metadata)
