extends EncounterRuntime
class_name CarrionRocRuntime

const AttemptSummaryBuilderScript := preload(
	"res://scripts/combat/attempt_summary_builder.gd"
)

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const CarrionGrowthScript := preload("res://scripts/encounters/carrion_growth.gd")
const CarrionRocVisualsScript := preload("res://scripts/effects/carrion_roc_visuals.gd")

const SPECIAL_ATTACKS: Array[String] = [
	"peck_flurry",
	"left_wing_swipe",
	"right_wing_swipe",
	"tail_swipe",
	"cyclone"
]

var roc_definition: CarrionRocDefinition = null
var visuals: CarrionRocVisuals = null
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var encounter_active: bool = false
var elapsed_seconds: float = 0.0
var cadence_timer: float = 0.0
var cadence_opportunity_count: int = 0
var special_attack_bag: Array[String] = []
var last_special_attack: String = ""
var active_special_attack: String = ""
var special_cast_remaining: float = 0.0
var special_cast_elapsed: float = 0.0
var special_cast_duration: float = 0.0
var flurry_target: Node = null
var flurry_hit_count: int = 0

var stagger_pressure: float = 0.0
var grounded: bool = false
var vulnerable_remaining: float = 0.0
var rupture_spawn_remaining: float = -1.0
var next_rupture_id: int = 1
var active_ruptures: Array[Dictionary] = []
var growths: Array[Node] = []
var next_growth_id: int = 1
var rupture_bags: Dictionary = {"east": [], "west": []}
var last_rupture_candidates: Dictionary = {"east": "", "west": ""}

var cycle_count: int = 0
var last_grounding_time: float = -1.0
var last_cycle_interval: float = 0.0


func configure(
	new_boss: Node, new_definition: EncounterDefinition,
	new_session: EncounterSession = null
) -> void:
	super.configure(new_boss, new_definition, new_session)
	roc_definition = new_definition as CarrionRocDefinition
	if roc_definition == null:
		return

	rng.seed = roc_definition.random_seed
	_reset_shuffle_state()
	_reset_runtime_state()
	_connect_target_registry()

	visuals = CarrionRocVisualsScript.new()
	visuals.name = "CarrionRocVisuals"
	visuals.z_index = 1
	if boss is Node2D:
		boss.add_child(visuals)
		visuals.setup(self, boss as Node2D)

	var boss_sprite: CanvasItem = null
	if boss != null:
		boss_sprite = boss.get_node_or_null("Sprite2D") as CanvasItem
	if boss_sprite != null:
		boss_sprite.visible = false

	set_process(false)


func set_party_members(new_party_members: Array) -> void:
	party_members = new_party_members


func set_encounter_active(active: bool) -> void:
	encounter_active = active and _boss_is_alive()

	if encounter_active and cadence_timer <= 0.0 and cadence_opportunity_count == 0:
		cadence_timer = roc_definition.initial_cadence_delay

	if not encounter_active:
		_cancel_special_cast("encounter_stopped")

	_publish_state()


func uses_custom_combat_loop() -> bool:
	return roc_definition != null


func blocks_boss_actions() -> bool:
	return grounded or special_cast_remaining > 0.0


func tick(delta: float) -> void:
	if roc_definition == null or not encounter_active or not _boss_is_alive():
		return

	var safe_delta := maxf(delta, 0.0)
	elapsed_seconds += safe_delta

	_tick_growths(safe_delta)

	if grounded:
		_tick_grounded_state(safe_delta)
		_publish_state()
		return

	if special_cast_remaining > 0.0:
		_tick_special_cast(safe_delta)
	else:
		cadence_timer = maxf(cadence_timer - safe_delta, 0.0)
		if cadence_timer <= 0.0:
			cadence_timer = roc_definition.cadence_interval
			_start_cadence_opportunity()

	_publish_state()


func get_boss_damage_multiplier() -> float:
	if grounded:
		return roc_definition.grounded_damage_multiplier

	return 1.0


func before_boss_damage(
	amount: int,
	source: Node,
	ablitity_id: String,
	metadata: Dictionary
) -> void:
	if roc_definition == null or amount <= 0:
		return

	metadata["roc_grounded_before_damage"] = grounded
	var weighted_pressure := _get_stagger_weight(source) * float(amount)
	if not grounded and weighted_pressure > 0.0:
		stagger_pressure += weighted_pressure
		emit_roc_event(
			"roc_stagger_pressure",
			source,
			ablitity_id,
			int(round(weighted_pressure)),
			{
				"encounter": "carrion_roc",
				"raw_damage": amount,
				"stagger_weight": _get_stagger_weight(source),
				"stagger_source_type": _get_stagger_source_type(source),
				"stagger_total": stagger_pressure
			}
		)

		if stagger_pressure >= float(roc_definition.stagger_threshold):
			_begin_grounding()


func after_boss_damage(
	amount: int,
	source: Node,
	ablitity_id: String,
	metadata: Dictionary
) -> void:
	if amount <= 0:
		return

	var event_metadata := metadata.duplicate(true)
	var grounded_before_damage := bool(metadata.get("roc_grounded_before_damage", grounded))
	event_metadata["encounter"] = "carrion_roc"
	event_metadata["roc_vulnerability"] = grounded_before_damage
	event_metadata["boss_damage_window"] = "vulnerability" if grounded_before_damage else "normal"
	emit_roc_event("roc_boss_damage_window", source, ablitity_id, amount, event_metadata)


func on_command_issued(command_data: Dictionary) -> void:
	if not grounded:
		return

	var action := String(command_data.get("what", ""))
	if action in ["move", "dodge", "rotate"]:
		emit_roc_event(
			"roc_movement_command",
			null,
			"",
			0,
			{
				"encounter": "carrion_roc",
				"during_vulnerability": true,
				"what": action,
				"where": String(command_data.get("where", "")),
				"movement_region": String(command_data.get("movement_region", "")),
				"movement_range": String(command_data.get("movement_range", "")),
				"movement_direction": String(command_data.get("movement_direction", ""))
			}
		)

	if action == "attack" and String(command_data.get("where", "")) == "encounter_target":
		emit_roc_event(
			"roc_growth_assignment",
			null,
			"carrion_growth_assignment",
			0,
			{
				"encounter": "carrion_roc",
				"encounter_target": Dictionary(command_data.get("encounter_target", {})),
				"who_type": String(command_data.get("who_type", "")),
				"who_value": command_data.get("who_value", ""),
				"who_selectors": command_data.get("who_selectors", [])
			}
		)


func get_status_text() -> String:
	if roc_definition == null:
		return ""

	if special_cast_remaining > 0.0:
		return "Casting " + _special_attack_display_name(active_special_attack)

	if grounded:
		var status := "Grounded %.1fs | %.2fx Vulnerable" % [
			vulnerable_remaining,
			roc_definition.grounded_damage_multiplier
		]

		if not active_ruptures.is_empty():
			status += " | " + _format_rupture_status()

		return status

	return "Stagger %d/%d | Cadence %d/%d" % [
		int(round(stagger_pressure)),
		roc_definition.stagger_threshold,
		cadence_opportunity_count % maxi(roc_definition.cadence_special_every, 1),
		maxi(roc_definition.cadence_special_every, 1)
	]


func is_casting() -> bool:
	return special_cast_remaining > 0.0


func get_cast_progress_percent() -> float:
	if special_cast_duration <= 0.0:
		return 0.0

	return clampf(special_cast_elapsed / special_cast_duration * 100.0, 0.0, 100.0)


func get_cast_name() -> String:
	return _special_attack_display_name(active_special_attack) if is_casting() else ""


func get_current_cast_time() -> float:
	return special_cast_duration


func get_current_cast_bar_value() -> float:
	return special_cast_elapsed


func get_active_ruptures() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rupture in active_ruptures:
		result.append(rupture.duplicate(true))
	return result


func get_growth_visual_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for growth in growths:
		if not _is_living(growth) or not growth is Node2D:
			continue

		result.append({
			"position": (growth as Node2D).global_position,
			"side": String(growth.get("side")),
			"region": String(growth.get("region")),
			"range": String(growth.get("range_name")),
			"health": int(growth.get("health")),
			"max_health": int(growth.get("max_health"))
		})

	return result


func get_presentation_state() -> Dictionary:
	return {
		"ruptures": get_active_ruptures(),
		"growths": get_growth_visual_data(),
	}


func get_target_registry() -> EncounterTargetRegistry:
	return target_registry


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


func get_target_entries() -> Array[Dictionary]:
	return target_registry.get_target_entries({"kind": "carrion_growth"})


func build_attempt_metrics(events: Array[Dictionary]) -> Dictionary:
	return {
		"carrion_roc": AttemptSummaryBuilderScript.build_carrion_roc_metrics(events)
	}


func reset_attempt() -> void:
	_cancel_special_cast("retry")
	_clear_growths()
	target_registry.clear()
	_reset_shuffle_state()
	_reset_runtime_state()
	rng.seed = roc_definition.random_seed


func cleanup_encounter() -> void:
	_cancel_special_cast("cleanup")
	active_ruptures.clear()
	target_registry.clear()
	_clear_growths()
	grounded = false
	vulnerable_remaining = 0.0
	rupture_spawn_remaining = -1.0
	_publish_state()


func _start_cadence_opportunity() -> void:
	cadence_opportunity_count += 1
	var special_every := maxi(roc_definition.cadence_special_every, 1)

	if cadence_opportunity_count % special_every != 0:
		_resolve_peck()
		return

	active_special_attack = _pop_special_attack()
	special_cast_elapsed = 0.0
	special_cast_duration = (
		roc_definition.peck_flurry_duration
		if active_special_attack == "peck_flurry"
		else 0.9
	)
	special_cast_remaining = special_cast_duration
	flurry_target = _get_current_or_first_living_target()
	flurry_hit_count = 0
	emit_roc_event(
		"cast_started",
		boss,
		active_special_attack,
		0,
		{
			"encounter": "carrion_roc",
			"cast_name": _special_attack_display_name(active_special_attack),
			"cast_time": special_cast_duration,
			"interruptible": false,
			"cadence_opportunity": cadence_opportunity_count
		}
	)


func _tick_special_cast(delta: float) -> void:
	if grounded:
		return

	var previous_elapsed := special_cast_elapsed
	special_cast_elapsed = minf(special_cast_elapsed + delta, special_cast_duration)
	special_cast_remaining = maxf(special_cast_duration - special_cast_elapsed, 0.0)

	if active_special_attack == "peck_flurry":
		var hit_count := maxi(roc_definition.peck_flurry_hit_count, 1)
		for hit_index in range(flurry_hit_count, hit_count):
			var hit_time := special_cast_duration * float(hit_index + 1) / float(hit_count)
			if previous_elapsed < hit_time and special_cast_elapsed >= hit_time:
				_resolve_flurry_hit()
				flurry_hit_count = hit_index + 1

	if special_cast_remaining > 0.0:
		return

	if active_special_attack != "peck_flurry":
		_resolve_special_attack(active_special_attack)

	emit_roc_event(
		"cast_resolved",
		boss,
		active_special_attack,
		0,
		{
			"encounter": "carrion_roc",
			"cast_name": _special_attack_display_name(active_special_attack),
			"cadence_opportunity": cadence_opportunity_count
		}
	)
	active_special_attack = ""
	special_cast_duration = 0.0
	special_cast_elapsed = 0.0
	flurry_target = null
	_publish_state()


func _resolve_peck() -> void:
	var target := _get_current_or_first_living_target()
	if target == null or not target.has_method("take_damage"):
		return

	target.take_damage(
		roc_definition.peck_damage,
		boss,
		"carrion_roc_basic_peck",
		{
			"encounter": "carrion_roc",
			"damage_type": "physical",
			"cadence_opportunity": cadence_opportunity_count
		}
	)
	emit_roc_event(
		"roc_cadence_attack",
		boss,
		"carrion_roc_basic_peck",
		roc_definition.peck_damage,
		{
			"encounter": "carrion_roc",
			"cadence_attack": "basic_peck",
			"target": target,
			"cadence_opportunity": cadence_opportunity_count
		}
	)


func _resolve_flurry_hit() -> void:
	if not _is_living(flurry_target):
		flurry_target = _get_current_or_first_living_target()

	if flurry_target == null or not flurry_target.has_method("take_damage"):
		return

	flurry_target.take_damage(
		roc_definition.peck_flurry_hit_damage,
		boss,
		"carrion_roc_peck_flurry",
		{
			"encounter": "carrion_roc",
			"damage_type": "physical",
			"flurry_hit": flurry_hit_count + 1,
			"flurry_target_locked": true
		}
	)


func _resolve_special_attack(attack_id: String) -> void:
	match attack_id:
		"left_wing_swipe":
			_resolve_wing_swipe(-1, "left")
		"right_wing_swipe":
			_resolve_wing_swipe(1, "right")
		"tail_swipe":
			_resolve_tail_swipe()
		"cyclone":
			_resolve_cyclone()


func _resolve_wing_swipe(side_direction: int, side_name: String) -> void:
	var front_region := _get_front_region()
	for party_member in party_members:
		if not _is_living(party_member) or not party_member is Node2D:
			continue

		var current_region := String(
			MovementSlotResolverScript.get_mini_region_from_position(
				boss,
				(party_member as Node2D).global_position
			).get("region", "south")
		)
		var relative := _get_relative_region_index(front_region, current_region)
		if relative not in [-1, -2, -3] and side_direction < 0:
			continue
		if relative not in [1, 2, 3] and side_direction > 0:
			continue

		var current_range := MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			(party_member as Node2D).global_position
		)
		var current_index := MovementSlotResolverScript.REGION_ORDER.find(current_region)
		var destination_index := posmod(current_index + side_direction, MovementSlotResolverScript.REGION_ORDER.size())
		var destination_region := String(MovementSlotResolverScript.REGION_ORDER[destination_index])
		_force_move(party_member, destination_region, current_range, "carrion_roc_%s_wing" % side_name)
		_damage_party_member(
			party_member,
			roc_definition.wing_swipe_damage,
			"carrion_roc_%s_wing_swipe" % side_name,
			{"wing_side": side_name, "front_region": front_region}
		)


func _resolve_tail_swipe() -> void:
	var front_region := _get_front_region()
	for party_member in party_members:
		if not _is_living(party_member) or not party_member is Node2D:
			continue

		var current_region := String(
			MovementSlotResolverScript.get_mini_region_from_position(
				boss,
				(party_member as Node2D).global_position
			).get("region", "south")
		)
		var relative := _get_relative_region_index(front_region, current_region)
		if relative not in [-3, 3, 4]:
			continue

		var current_range := MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			(party_member as Node2D).global_position
		)
		var destination_range := MovementSlotResolverScript.get_adjacent_range(
			current_range,
			MovementSlotResolverScript.RANGE_DIRECTION_OUT
		)
		if current_range != MovementSlotResolverScript.RANGE_FAR:
			_force_move(party_member, current_region, destination_range, "carrion_roc_tail_swipe")
		_damage_party_member(
			party_member,
			roc_definition.tail_swipe_damage,
			"carrion_roc_tail_swipe",
			{"front_region": front_region}
		)


func _resolve_cyclone() -> void:
	for party_member in party_members:
		if not _is_living(party_member) or not party_member is Node2D:
			continue

		var region_data := MovementSlotResolverScript.get_mini_region_from_position(
			boss,
			(party_member as Node2D).global_position
		)
		var current_range := String(region_data.get("range", "close"))
		if current_range == MovementSlotResolverScript.RANGE_CLOSE:
			continue

		var destination_range := MovementSlotResolverScript.get_adjacent_range(
			current_range,
			MovementSlotResolverScript.RANGE_DIRECTION_IN
		)
		_force_move(
			party_member,
			String(region_data.get("region", "south")),
			destination_range,
			"carrion_roc_cyclone"
		)
		_damage_party_member(
			party_member,
			roc_definition.cyclone_damage,
			"carrion_roc_cyclone",
			{"damage_type": "environmental"}
		)


func _force_move(unit: Node, region: String, range_name: String, ability_id: String) -> void:
	if not unit is Node2D:
		return

	var origin_position := (unit as Node2D).global_position
	var destination := MovementSlotResolverScript.get_closest_point_in_mini_region(
		boss,
		(unit as Node2D).global_position,
		region,
		range_name,
		2.0
	)
	if unit.has_method("start_forced_movement"):
		unit.start_forced_movement(destination, roc_definition.displacement_duration)
	else:
		(unit as Node2D).global_position = destination

	emit_roc_event(
		"roc_displacement",
		boss,
		ability_id,
		0,
		{
			"encounter": "carrion_roc",
			"target": unit,
			"destination_region": region,
			"destination_range": range_name,
			"displacement_duration": roc_definition.displacement_duration,
			"travel_distance_pixels": origin_position.distance_to(destination),
			"travel_time_seconds": roc_definition.displacement_duration
		}
	)


func _damage_party_member(
	party_member: Node,
	damage: int,
	ablitity_id: String,
	metadata: Dictionary
) -> void:
	if party_member == null or not party_member.has_method("take_damage"):
		return

	var event_metadata := metadata.duplicate(true)
	event_metadata["encounter"] = "carrion_roc"
	event_metadata["damage_type"] = event_metadata.get("damage_type", "physical")
	party_member.take_damage(damage, boss, ablitity_id, event_metadata)


func _begin_grounding() -> void:
	if grounded or roc_definition == null:
		return

	grounded = true
	stagger_pressure = 0.0
	vulnerable_remaining = roc_definition.grounded_duration
	rupture_spawn_remaining = roc_definition.rupture_delay_after_grounding
	cycle_count += 1

	if last_grounding_time >= 0.0:
		last_cycle_interval = elapsed_seconds - last_grounding_time
	last_grounding_time = elapsed_seconds

	_cancel_special_cast("stagger_broken")
	emit_roc_event(
		"roc_stagger_broken",
		boss,
		"carrion_roc_stagger",
		roc_definition.stagger_threshold,
		{
			"encounter": "carrion_roc",
			"cycle_index": cycle_count,
			"stagger_threshold": roc_definition.stagger_threshold,
			"cycle_interval_seconds": last_cycle_interval,
			"grounded_duration": roc_definition.grounded_duration,
			"formation": _get_formation_snapshot(),
			"boss_health": int(boss.get("health")) if boss != null else 0,
			"boss_max_health": int(boss.get("max_health")) if boss != null else 0
		}
	)
	_publish_state()


func _tick_grounded_state(delta: float) -> void:
	if rupture_spawn_remaining >= 0.0:
		rupture_spawn_remaining = maxf(rupture_spawn_remaining - delta, 0.0)
		if rupture_spawn_remaining <= 0.0:
			rupture_spawn_remaining = -1.0
			_spawn_rupture("east")
			_spawn_rupture("west")

	for rupture in active_ruptures.duplicate(true):
		var rupture_id := int(rupture.get("id", -1))
		for active_index in range(active_ruptures.size()):
			if int(active_ruptures[active_index].get("id", -2)) == rupture_id:
				active_ruptures[active_index]["remaining"] = maxf(
					float(active_ruptures[active_index].get("remaining", 0.0)) - delta,
					0.0
				)
				if float(active_ruptures[active_index].get("remaining", 0.0)) <= 0.0:
					_resolve_rupture(active_ruptures[active_index])
				break

	vulnerable_remaining = maxf(vulnerable_remaining - delta, 0.0)
	if vulnerable_remaining <= 0.0:
		_end_grounding()


func _spawn_rupture(side: String) -> void:
	var candidate := _next_rupture_candidate(side)
	if candidate.is_empty():
		return

	var rupture := {
		"id": next_rupture_id,
		"side": side,
		"region": String(candidate.get("region", "east")),
		"range": String(candidate.get("range", "mid")),
		"remaining": roc_definition.rupture_telegraph_duration,
		"spawned_at": elapsed_seconds,
		"assigned_unit_ids": []
	}
	next_rupture_id += 1
	active_ruptures.append(rupture)
	emit_roc_event(
		"roc_rupture_spawned",
		boss,
		"carrion_roc_rupture",
		0,
		{
			"encounter": "carrion_roc",
			"rupture_id": int(rupture.get("id", 0)),
			"side": side,
			"region": rupture.get("region", ""),
			"range": rupture.get("range", ""),
			"telegraph_duration": roc_definition.rupture_telegraph_duration,
			"cycle_index": cycle_count
		}
	)


func _resolve_rupture(rupture: Dictionary) -> void:
	var rupture_id := int(rupture.get("id", -1))
	var region := String(rupture.get("region", "east"))
	var range_name := String(rupture.get("range", "mid"))
	var side := String(rupture.get("side", "east"))
	var occupants: Array[Node] = []

	for party_member in party_members:
		if not _is_living(party_member) or not party_member is Node2D:
			continue

		if MovementSlotResolverScript.is_position_safely_inside_mini_region(
			boss,
			(party_member as Node2D).global_position,
			region,
			range_name,
			0.0
		):
			occupants.append(party_member)

	var outcome := "ignored"
	var combined_health := 0
	var soak_deaths := 0
	var growth: Node = null

	for occupant in occupants:
		combined_health += _get_current_health(occupant)

	if not occupants.is_empty():
		outcome = "failed"
		if combined_health >= roc_definition.rupture_health_threshold:
			var base_damage := int(roc_definition.rupture_damage_pool / occupants.size())
			var remainder := roc_definition.rupture_damage_pool % occupants.size()
			for occupant_index in range(occupants.size()):
				var damage := base_damage + (1 if occupant_index < remainder else 0)
				var previous_alive := _is_living(occupants[occupant_index])
				_damage_party_member(
					occupants[occupant_index],
					damage,
					"carrion_roc_crash_soak",
					{
						"damage_type": "environmental",
						"rupture_id": rupture_id,
						"rupture_side": side,
						"soak_distribution": true,
						"soak_damage_pool": roc_definition.rupture_damage_pool
					}
				)
				if previous_alive and not _is_living(occupants[occupant_index]):
					soak_deaths += 1
					emit_roc_event(
						"roc_soak_death",
						occupants[occupant_index],
						"carrion_roc_crash_soak",
						0,
						{
							"encounter": "carrion_roc",
							"rupture_id": rupture_id,
							"rupture_side": side,
							"soak_distribution": true
						}
					)

			if soak_deaths == 0:
				outcome = "success"

		if outcome == "failed":
			growth = _spawn_growth(side, region, range_name)

	var remaining_ruptures: Array[Dictionary] = []
	for candidate in active_ruptures:
		if int(candidate.get("id", -1)) != rupture_id:
			remaining_ruptures.append(candidate)
	active_ruptures = remaining_ruptures
	emit_roc_event(
		"roc_rupture_resolved",
		boss,
		"carrion_roc_rupture",
		0,
		{
			"encounter": "carrion_roc",
			"rupture_id": rupture_id,
			"side": side,
			"region": region,
			"range": range_name,
			"outcome": outcome,
			"occupant_ids": _get_node_ids(occupants),
			"combined_current_health": combined_health,
			"health_threshold": roc_definition.rupture_health_threshold,
			"damage_pool": roc_definition.rupture_damage_pool,
			"soak_deaths": soak_deaths,
			"growth_spawned": growth != null
		}
	)


func _spawn_growth(side: String, region: String, range_name: String) -> Node:
	var growth := CarrionGrowthScript.new()
	growth.configure(
		boss,
		next_growth_id,
		side,
		region,
		range_name,
		roc_definition.growth_max_health,
		roc_definition.growth_pulse_damage,
		roc_definition.growth_pulse_interval,
		Time.get_ticks_msec() / 1000.0
	)
	next_growth_id += 1

	if boss != null and is_instance_valid(boss) and boss.get_parent() != null:
		boss.get_parent().add_child(growth)
		growth.global_position = MovementSlotResolverScript.get_slot_position(
			boss,
			region,
			range_name
		)

	growths.append(growth)
	target_registry.register_target(growth)
	if boss != null and boss.has_method("register_encounter_object"):
		boss.register_encounter_object(growth)

	emit_roc_event(
		"roc_growth_spawned",
		boss,
		"carrion_growth",
		0,
		{
			"encounter": "carrion_roc",
			"growth_id": next_growth_id - 1,
			"side": side,
			"region": region,
			"range": range_name,
			"spawn_time": elapsed_seconds
		}
	)
	return growth


func _end_grounding() -> void:
	grounded = false
	vulnerable_remaining = 0.0
	rupture_spawn_remaining = -1.0
	active_ruptures.clear()
	stagger_pressure = 0.0
	emit_roc_event(
		"roc_vulnerability_ended",
		boss,
		"carrion_roc_vulnerability",
		0,
		{
			"encounter": "carrion_roc",
			"cycle_index": cycle_count,
			"growth_count": _get_living_growth_count()
		}
	)


func _cancel_special_cast(reason: String) -> void:
	if special_cast_remaining <= 0.0 and active_special_attack.is_empty():
		return

	emit_roc_event(
		"cast_cancelled",
		boss,
		active_special_attack,
		0,
		{
			"encounter": "carrion_roc",
			"reason": reason,
			"interruptible": false,
			"no_effect": true
		}
	)
	active_special_attack = ""
	special_cast_remaining = 0.0
	special_cast_elapsed = 0.0
	special_cast_duration = 0.0
	flurry_target = null
	flurry_hit_count = 0


func _pop_special_attack() -> String:
	if special_attack_bag.is_empty():
		_refill_special_attack_bag()

	var next_attack := String(special_attack_bag.pop_back())
	last_special_attack = next_attack
	return next_attack


func _refill_special_attack_bag() -> void:
	special_attack_bag = SPECIAL_ATTACKS.duplicate()
	for index in range(special_attack_bag.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary := special_attack_bag[index]
		special_attack_bag[index] = special_attack_bag[swap_index]
		special_attack_bag[swap_index] = temporary

	if not last_special_attack.is_empty() and special_attack_bag.size() > 1:
		var first_index := special_attack_bag.find(last_special_attack)
		if first_index == special_attack_bag.size() - 1:
			var replacement_index := rng.randi_range(0, special_attack_bag.size() - 2)
			var replacement := special_attack_bag[replacement_index]
			special_attack_bag[replacement_index] = special_attack_bag[first_index]
			special_attack_bag[first_index] = replacement


func _next_rupture_candidate(side: String) -> Dictionary:
	var bag: Array = rupture_bags.get(side, [])
	if bag.is_empty():
		bag = _build_rupture_candidates(side)
		_shuffle_array(bag)

	var last_candidate := String(last_rupture_candidates.get(side, ""))
	var selected_index := -1
	var fallback_index := -1

	for index in range(bag.size()):
		var candidate: Dictionary = bag[index]
		var key := String(candidate.get("key", ""))
		if key == last_candidate:
			continue

		if fallback_index == -1:
			fallback_index = index

		if not _growth_at_slot(String(candidate.get("region", "")), String(candidate.get("range", ""))):
			selected_index = index
			break

	if selected_index == -1:
		selected_index = fallback_index

	if selected_index == -1:
		bag = _build_rupture_candidates(side)
		_shuffle_array(bag)
		selected_index = 0 if not bag.is_empty() else -1

	if selected_index == -1:
		return {}

	var selected: Dictionary = bag[selected_index]
	bag.remove_at(selected_index)
	rupture_bags[side] = bag
	last_rupture_candidates[side] = String(selected.get("key", ""))
	return selected


func _build_rupture_candidates(side: String) -> Array:
	var candidates: Array = []
	var regions: Array = (
		roc_definition.east_rupture_regions
		if side == "east"
		else roc_definition.west_rupture_regions
	)
	for region_value in regions:
		var region := String(region_value)
		for range_value in roc_definition.rupture_candidate_ranges:
			var range_name := String(range_value)
			candidates.append({
				"side": side,
				"region": region,
				"range": range_name,
				"key": MovementSlotResolverScript.get_mini_region_key(region, range_name)
			})
	return candidates


func _shuffle_array(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary


func _reset_shuffle_state() -> void:
	special_attack_bag.clear()
	last_special_attack = ""
	rupture_bags = {"east": [], "west": []}
	last_rupture_candidates = {"east": "", "west": ""}


func _reset_runtime_state() -> void:
	encounter_active = false
	elapsed_seconds = 0.0
	cadence_timer = 0.0
	cadence_opportunity_count = 0
	active_special_attack = ""
	special_cast_remaining = 0.0
	special_cast_elapsed = 0.0
	special_cast_duration = 0.0
	flurry_target = null
	flurry_hit_count = 0
	stagger_pressure = 0.0
	grounded = false
	vulnerable_remaining = 0.0
	rupture_spawn_remaining = -1.0
	next_rupture_id = 1
	active_ruptures.clear()
	next_growth_id = 1
	cycle_count = 0
	last_grounding_time = -1.0
	last_cycle_interval = 0.0


func _clear_growths() -> void:
	for growth in growths:
		if growth == null or not is_instance_valid(growth):
			continue

		if growth.has_method("cleanup"):
			growth.cleanup()
		else:
			growth.queue_free()

	growths.clear()


func _tick_growths(delta: float) -> void:
	for growth in growths:
		if not _is_living(growth) or not growth.has_method("tick"):
			continue

		growth.tick(delta, party_members)


func _on_target_defeated(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	if target.has_method("get_encounter_target_descriptor"):
		var descriptor: Dictionary = target.get_encounter_target_descriptor()
		emit_roc_event(
			"roc_growth_lifespan_recorded",
			target,
			"carrion_growth",
			0,
			{
				"encounter": "carrion_roc",
				"growth_id": int(target.get("growth_id")),
				"side": String(descriptor.get("side", "")),
				"region": String(descriptor.get("region", "")),
				"lifespan_seconds": Time.get_ticks_msec() / 1000.0 - float(target.get("spawned_at_seconds")),
				"damage_taken": int(target.get("total_damage_received")),
				"raid_damage": int(target.get("total_raid_damage")),
				"destroyed": true
			}
		)


func _get_current_or_first_living_target() -> Node:
	if boss != null and boss.has_method("get_current_target"):
		var current = boss.get_current_target()
		if _is_living(current):
			return current

	for party_member in party_members:
		if _is_living(party_member):
			return party_member

	return null


func _get_front_region() -> String:
	var target := _get_current_or_first_living_target()
	if target is Node2D:
		return String(
			MovementSlotResolverScript.get_mini_region_from_position(
				boss,
				(target as Node2D).global_position
			).get("region", "north")
		)

	return MovementSlotResolverScript.REGION_NORTH


func _get_relative_region_index(front_region: String, region: String) -> int:
	var front_index := MovementSlotResolverScript.REGION_ORDER.find(front_region)
	var region_index := MovementSlotResolverScript.REGION_ORDER.find(region)
	if front_index < 0 or region_index < 0:
		return 0

	var relative := posmod(region_index - front_index, MovementSlotResolverScript.REGION_ORDER.size())
	return relative - 8 if relative > 4 else relative


func _get_stagger_weight(source: Node) -> float:
	if source == null or not is_instance_valid(source):
		return 0.0

	if source.has_method("has_role"):
		if bool(source.has_role("ranged")) or bool(source.has_role("ranged_dps")):
			return roc_definition.ranged_stagger_weight
		if bool(source.has_role("melee")) or bool(source.has_role("melee_dps")):
			return roc_definition.melee_stagger_weight

	var unit_class := String(source.get("unit_class"))
	if unit_class.to_lower() == "mage":
		return roc_definition.ranged_stagger_weight
	if unit_class.to_lower() in ["warrior", "rogue"]:
		return roc_definition.melee_stagger_weight

	return 0.0


func _get_stagger_source_type(source: Node) -> String:
	var weight := _get_stagger_weight(source)
	if is_equal_approx(weight, roc_definition.melee_stagger_weight):
		return "melee"
	if is_equal_approx(weight, roc_definition.ranged_stagger_weight):
		return "ranged"
	return "other"


func _get_formation_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for party_member in party_members:
		if not _is_living(party_member) or not party_member is Node2D:
			continue

		var region_data := MovementSlotResolverScript.get_mini_region_from_position(
			boss,
			(party_member as Node2D).global_position
		)
		snapshot.append({
			"member": party_member,
			"health": int(party_member.get("health")) if party_member.get("health") != null else 0,
			"max_health": int(party_member.get("max_health")) if party_member.get("max_health") != null else 0,
			"region": String(region_data.get("region", "")),
			"range": String(region_data.get("range", ""))
		})
	return snapshot


func _get_node_ids(nodes: Array) -> Array[String]:
	var result: Array[String] = []
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("get_member_id") and not String(node.get_member_id()).is_empty():
			result.append(String(node.get_member_id()))
		else:
			result.append(String(node.name))
	return result


func _get_current_health(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return 0

	if node.has_method("get_current_health"):
		return int(node.get_current_health())

	var health_value = node.get("health")
	return int(health_value) if health_value != null else 0


func _growth_at_slot(region: String, range_name: String) -> bool:
	for growth in growths:
		if not _is_living(growth):
			continue
		if String(growth.get("region")) == region and String(growth.get("range_name")) == range_name:
			return true
	return false


func _get_living_growth_count() -> int:
	var count := 0
	for growth in growths:
		if _is_living(growth):
			count += 1
	return count


func _format_rupture_status() -> String:
	var parts: Array[String] = []
	for rupture in active_ruptures:
		parts.append(
			"%s %s/%s %.1fs"
			% [
				String(rupture.get("side", "")).capitalize(),
				String(rupture.get("region", "")),
				String(rupture.get("range", "")),
				float(rupture.get("remaining", 0.0))
			]
		)
	return "Ruptures: " + ", ".join(parts)


func _special_attack_display_name(attack_id: String) -> String:
	match attack_id:
		"peck_flurry":
			return "Peck Flurry"
		"left_wing_swipe":
			return "Left Wing Swipe"
		"right_wing_swipe":
			return "Right Wing Swipe"
		"tail_swipe":
			return "Tail Swipe"
		"cyclone":
			return "Cyclone"
	return attack_id.capitalize()


func _publish_state() -> void:
	if boss == null or not is_instance_valid(boss) or not boss.has_method("set_mechanic_state"):
		return

	boss.set_mechanic_state("carrion_roc", {
		"encounter_id": "carrion_roc",
		"stagger": stagger_pressure,
		"stagger_threshold": roc_definition.stagger_threshold if roc_definition != null else 0,
		"grounded": grounded,
		"vulnerable_remaining": vulnerable_remaining,
		"rupture_spawn_remaining": rupture_spawn_remaining,
		"ruptures": active_ruptures.duplicate(true),
		"growth_count": _get_living_growth_count(),
		"cadence_opportunity_count": cadence_opportunity_count,
		"active_special_attack": active_special_attack
	})


func emit_roc_event(
	event_type: String,
	source: Node,
	ablitity_id: String,
	amount: int,
	metadata: Dictionary
) -> void:
	if boss != null and is_instance_valid(boss) and boss.has_method("emit_combat_event"):
		boss.emit_combat_event(event_type, source, ablitity_id, amount, metadata)


func _boss_is_alive() -> bool:
	return boss != null and is_instance_valid(boss) and (not boss.has_method("is_alive") or bool(boss.is_alive()))


func _is_living(candidate: Node) -> bool:
	return (
		candidate != null
		and is_instance_valid(candidate)
		and (not candidate.has_method("is_alive") or bool(candidate.is_alive()))
	)
