extends Node2D
class_name TwinMauler

const BossTargetControllerScript := preload("res://scripts/combat/boss_target_controller.gd")

signal defeated(target: Node)
signal combat_event(event: Dictionary)
signal state_changed

var runtime: EncounterRuntime = null
var definition: TwinMaulersDefinition = null
var side: String = "west"
var display_name: String = "West Mauler"
var target_id: String = "twin_mauler:west"

var max_health: int = 30000
var health: int = 30000
var attack_damage: int = 14
var attack_cooldown: float = 2.4
var combat_radius: float = 92.0

var rage: float = 0.0
var exhaustion_level: int = 0
var exhausted_remaining: float = 0.0
var survivor_enraged: bool = false
var survivor_floor_bonus: float = 0.0

var rampage_warning_remaining: float = 0.0
var rampage_warning_duration: float = 0.0
var rampage_cast_remaining: float = 0.0
var rampage_cast_duration: float = 0.0

var attack_timer: float = 0.0
var is_dead: bool = false
var encounter_active: bool = false
var is_cleaned: bool = false
var active_attacker_count: int = 0
var active_group_count: int = 0
var last_rage_rate: float = 0.0
var total_damage_received: int = 0
var damage_during_exhaustion: int = 0
var damage_at_exhaustion_start: int = 0
var target_controller: BossTargetController = null


func configure(
	new_runtime: EncounterRuntime,
	new_definition: TwinMaulersDefinition,
	new_side: String,
	new_display_name: String,
	new_position: Vector2
) -> void:
	runtime = new_runtime
	definition = new_definition
	side = new_side
	display_name = new_display_name
	target_id = "twin_mauler:" + side
	name = "TwinMauler_" + side.capitalize()
	max_health = maxi(definition.mauler_max_health, 1)
	health = max_health
	attack_damage = maxi(definition.mauler_attack_damage, 0)
	attack_cooldown = maxf(definition.mauler_attack_cooldown, 0.1)
	combat_radius = maxf(definition.mauler_combat_radius, 1.0)
	global_position = new_position
	target_controller = BossTargetControllerScript.new()
	attack_timer = attack_cooldown
	is_dead = false
	encounter_active = false
	is_cleaned = false
	total_damage_received = 0
	damage_during_exhaustion = 0
	damage_at_exhaustion_start = 0
	add_to_group("enemy_threat_source")
	queue_redraw()


func set_party_members(new_party_members: Array) -> void:
	if target_controller == null:
		target_controller = BossTargetControllerScript.new()

	target_controller.setup(new_party_members)


func set_encounter_active(active: bool) -> void:
	encounter_active = active and not is_dead
	if not encounter_active:
		if target_controller != null:
			target_controller.reset_threat()
		attack_timer = get_effective_attack_cooldown()


func set_initial_target(target: Node) -> void:
	if target_controller != null and is_living_party_target(target):
		target_controller.set_target(target)


func tick_combat(delta: float, new_active_attacker_count: int, new_active_group_count: int) -> void:
	if is_dead:
		return

	active_attacker_count = maxi(new_active_attacker_count, 0)
	active_group_count = maxi(new_active_group_count, 0)
	if target_controller != null:
		target_controller.update(delta)
		if get_current_target() == null:
			target_controller.acquire_fallback_target()

	if not encounter_active:
		return

	if is_exhausted():
		exhausted_remaining = maxf(
			exhausted_remaining - maxf(delta, 0.0),
			0.0
		)
		var floor_value := get_rage_floor()
		rage = maxf(
			rage - definition.exhaustion_rage_decay_per_second * maxf(delta, 0.0),
			floor_value
		)
		if exhausted_remaining <= 0.0:
			emit_twin_event("twin_mauler_exhaustion_ended", "twin_mauler_exhaustion", 0, {
				"encounter": "twin_maulers",
				"side": side,
				"rage": rage,
				"rage_floor": floor_value,
				"next_exhaustion_threshold": get_exhaustion_threshold(),
				"damage_during_exhaustion": damage_during_exhaustion
			})
			damage_during_exhaustion = 0
			state_changed.emit()
		queue_redraw()
		return

	last_rage_rate = definition.get_rage_rate(active_attacker_count)
	var floor_value := get_rage_floor()
	var threshold := get_exhaustion_threshold()
	rage = clampf(
		rage + last_rage_rate * maxf(delta, 0.0),
		floor_value,
		threshold
	)

	if rage >= threshold - 0.0001:
		if runtime != null and is_instance_valid(runtime):
			runtime.request_target_exhaustion(self)
		return

	if rampage_cast_remaining <= 0.0:
		attack_timer = maxf(attack_timer - maxf(delta, 0.0), 0.0)
		if attack_timer <= 0.0:
			_attack_once()

	state_changed.emit()
	queue_redraw()


func _attack_once() -> void:
	var target := get_current_target()
	if target == null and target_controller != null:
		target = target_controller.acquire_fallback_target()

	if target == null or not is_living_party_target(target):
		attack_timer = 0.1
		return

	var metadata := {
		"encounter": "twin_maulers",
		"side": side,
		"rage": rage,
		"rage_floor": get_rage_floor(),
		"attack_speed_multiplier": get_attack_speed_multiplier(),
		"exhausted": false
	}
	var damage := int(round(float(attack_damage) * get_survivor_damage_multiplier()))
	target.take_damage(damage, self, "twin_mauler_bite", metadata)
	attack_timer = get_effective_attack_cooldown()


func take_damage(
	amount: int,
	source: Node = null,
	ablity_id: String = "",
	metadata: Dictionary = {}
) -> void:
	if is_dead:
		return

	var incoming_multiplier := (
		definition.exhaustion_damage_multiplier if is_exhausted() else 1.0
	)
	var resolved_amount := int(round(float(maxi(amount, 0)) * incoming_multiplier))
	var event_metadata := metadata.duplicate(true)
	event_metadata["encounter"] = "twin_maulers"
	event_metadata["side"] = side
	event_metadata["rage"] = rage
	event_metadata["rage_floor"] = get_rage_floor()
	event_metadata["exhausted"] = is_exhausted()
	if not is_equal_approx(incoming_multiplier, 1.0):
		event_metadata["base_amount"] = maxi(amount, 0)
		event_metadata["incoming_damage_multiplier"] = incoming_multiplier

	var previous_health := health
	health = max(health - resolved_amount, 0)
	var actual_amount := previous_health - health
	if actual_amount <= 0:
		return

	total_damage_received += actual_amount
	if is_exhausted():
		damage_during_exhaustion += actual_amount
	if target_controller != null:
		target_controller.record_damage_threat(source, actual_amount)

	emit_combat_event("damage", source, ablity_id, actual_amount, event_metadata)
	if runtime != null and is_instance_valid(runtime):
		runtime.on_target_damage(self, actual_amount, source, ablity_id, event_metadata)

	if health <= 0:
		die()
	else:
		state_changed.emit()
		queue_redraw()


func die() -> void:
	if is_dead:
		return

	is_dead = true
	health = 0
	encounter_active = false
	if target_controller != null:
		target_controller.reset_threat()
	clear_rampage_state()
	emit_twin_event("twin_mauler_defeated", "twin_mauler_defeated", 0, {
		"encounter": "twin_maulers",
		"side": side,
		"damage_taken": total_damage_received,
		"exhaustion_level": exhaustion_level,
		"rage": rage
	})
	defeated.emit(self)
	state_changed.emit()
	queue_redraw()


func reset_state(new_position: Vector2) -> void:
	is_dead = false
	encounter_active = false
	is_cleaned = false
	health = max_health
	rage = 0.0
	exhaustion_level = 0
	exhausted_remaining = 0.0
	survivor_enraged = false
	survivor_floor_bonus = 0.0
	clear_rampage_state()
	attack_timer = attack_cooldown
	active_attacker_count = 0
	active_group_count = 0
	last_rage_rate = 0.0
	total_damage_received = 0
	damage_during_exhaustion = 0
	damage_at_exhaustion_start = 0
	global_position = new_position
	visible = true
	if target_controller != null:
		target_controller.reset_threat()
	queue_redraw()


func start_exhaustion(duration: float, reactive: bool = false) -> void:
	if is_dead:
		return

	damage_at_exhaustion_start = total_damage_received
	exhausted_remaining = maxf(duration, 0.1)
	clear_rampage_state()
	exhaustion_level += 1
	attack_timer = get_effective_attack_cooldown()
	emit_twin_event("twin_mauler_exhausted", "twin_mauler_exhaustion", 0, {
		"encounter": "twin_maulers",
		"side": side,
		"rage": rage,
		"rage_floor": get_rage_floor(),
		"trigger_threshold": get_exhaustion_threshold() - definition.exhaustion_threshold_step,
		"next_exhaustion_threshold": get_exhaustion_threshold(),
		"attack_speed_multiplier": get_attack_speed_multiplier(),
		"damage_before_exhaustion": damage_at_exhaustion_start,
		"rampage_active": reactive,
		"reactive": reactive,
		"proactive": not reactive
	})
	state_changed.emit()
	queue_redraw()


func set_survivor_enraged() -> void:
	survivor_enraged = true
	survivor_floor_bonus = definition.survivor_floor_bonus
	exhaustion_level = 0
	emit_twin_event("twin_mauler_survivor_enrage", "twin_mauler_survivor_enrage", 0, {
		"encounter": "twin_maulers",
		"side": side,
		"threshold": definition.survivor_threshold,
		"rage_floor_bonus": survivor_floor_bonus,
		"attack_damage_multiplier": definition.survivor_attack_damage_multiplier,
		"rampage_interval_multiplier": definition.survivor_rampage_interval_multiplier
	})
	state_changed.emit()
	queue_redraw()


func set_rampage_warning(duration: float) -> void:
	rampage_warning_duration = maxf(duration, 0.1)
	rampage_warning_remaining = rampage_warning_duration
	rampage_cast_duration = 0.0
	rampage_cast_remaining = 0.0
	queue_redraw()


func set_rampage_cast(duration: float) -> void:
	rampage_warning_remaining = 0.0
	rampage_cast_duration = maxf(duration, 0.1)
	rampage_cast_remaining = rampage_cast_duration
	queue_redraw()


func tick_rampage(delta: float) -> String:
	if rampage_warning_remaining > 0.0:
		rampage_warning_remaining = maxf(rampage_warning_remaining - maxf(delta, 0.0), 0.0)
		queue_redraw()
		return "warning" if rampage_warning_remaining > 0.0 else "warning_finished"

	if rampage_cast_remaining > 0.0:
		rampage_cast_remaining = maxf(rampage_cast_remaining - maxf(delta, 0.0), 0.0)
		queue_redraw()
		return "cast" if rampage_cast_remaining > 0.0 else "cast_finished"

	return "none"


func clear_rampage_state() -> void:
	rampage_warning_remaining = 0.0
	rampage_warning_duration = 0.0
	rampage_cast_remaining = 0.0
	rampage_cast_duration = 0.0
	queue_redraw()


func is_exhausted() -> bool:
	return exhausted_remaining > 0.0 and not is_dead


func get_exhaustion_threshold() -> float:
	if survivor_enraged:
		return maxf(definition.survivor_threshold, 1.0) + maxf(exhaustion_level, 0) * definition.exhaustion_threshold_step

	return maxf(definition.base_exhaustion_threshold, 1.0) + maxf(exhaustion_level, 0) * definition.exhaustion_threshold_step


func get_rage_floor() -> float:
	if max_health <= 0:
		return survivor_floor_bonus

	var missing_ratio := 1.0 - float(health) / float(max_health)
	return definition.get_rage_floor(missing_ratio) + survivor_floor_bonus


func get_attack_speed_multiplier() -> float:
	return 1.0 + maxf(rage, 0.0) * definition.rage_attack_speed_percent_per_stack


func get_effective_attack_cooldown() -> float:
	return attack_cooldown / maxf(get_attack_speed_multiplier(), 0.01)


func get_survivor_damage_multiplier() -> float:
	return definition.survivor_attack_damage_multiplier if survivor_enraged else 1.0


func get_current_target() -> Node:
	if target_controller == null:
		return null

	return target_controller.get_target()


func taunt(new_target: Node) -> bool:
	if is_dead or target_controller == null:
		return false

	var success := target_controller.taunt(new_target)
	if success:
		emit_combat_event("taunt", new_target, "taunt", 0, {
			"encounter": "twin_maulers",
			"side": side
		})
		state_changed.emit()
	return success


func remove_threat(source: Node) -> void:
	if target_controller != null:
		target_controller.remove_threat(source)


func get_threat_table_snapshot() -> Dictionary:
	return target_controller.get_threat_table_snapshot() if target_controller != null else {}


func get_current_health() -> int:
	return health


func get_max_health() -> int:
	return max_health


func get_display_name() -> String:
	return display_name


func get_combat_radius() -> float:
	return combat_radius


func is_alive() -> bool:
	return not is_dead


func is_casting_ability() -> bool:
	return rampage_warning_remaining > 0.0 or rampage_cast_remaining > 0.0


func get_cast_progress_percent() -> float:
	if rampage_warning_remaining > 0.0:
		return clampf(
			(rampage_warning_duration - rampage_warning_remaining)
			/ maxf(rampage_warning_duration, 0.1) * 100.0,
			0.0,
			100.0
		)

	if rampage_cast_remaining > 0.0:
		return clampf(
			(rampage_cast_duration - rampage_cast_remaining)
			/ maxf(rampage_cast_duration, 0.1) * 100.0,
			0.0,
			100.0
		)

	return 0.0


func get_cast_name() -> String:
	if rampage_warning_remaining > 0.0:
		return "RAMPAGE WARNING %.1fs" % rampage_warning_remaining

	if rampage_cast_remaining > 0.0:
		return "RAMPAGE %.1fs" % rampage_cast_remaining

	return ""


func get_current_cast_time() -> float:
	if rampage_warning_remaining > 0.0:
		return rampage_warning_duration

	if rampage_cast_remaining > 0.0:
		return rampage_cast_duration

	return 0.0


func get_current_cast_bar_value() -> float:
	if rampage_warning_remaining > 0.0:
		return rampage_warning_duration - rampage_warning_remaining

	if rampage_cast_remaining > 0.0:
		return rampage_cast_duration - rampage_cast_remaining

	return 0.0


func get_status_text() -> String:
	if is_dead:
		return "Defeated"

	if rampage_warning_remaining > 0.0:
		return "RAMPAGE WARNING %.1fs" % rampage_warning_remaining

	if rampage_cast_remaining > 0.0:
		return "RAMPAGE CAST %.1fs" % rampage_cast_remaining

	if is_exhausted():
		return "EXHAUSTED %.1fs | %.1fx Vulnerable" % [
			exhausted_remaining,
			definition.exhaustion_damage_multiplier
		]

	var target := get_current_target()
	var target_text := "No target" if target == null else "Target " + _get_node_display_name(target)
	return "Rage %d/%d | Floor %d | %s" % [
		int(round(rage)),
		int(round(get_exhaustion_threshold())),
		int(round(get_rage_floor())),
		target_text
	]


func get_resource_state() -> Dictionary:
	return {
		"id": "rage",
		"label": "Rage",
		"value": rage,
		"max_value": get_exhaustion_threshold(),
		"floor": get_rage_floor(),
		"rate": last_rage_rate,
		"attacker_count": active_attacker_count,
		"group_count": active_group_count,
		"color": Color(0.82, 0.20, 0.12, 1.0) if side == "west" else Color(0.96, 0.50, 0.12, 1.0)
	}


func get_encounter_target_descriptor() -> Dictionary:
	return {
		"target_id": target_id,
		"display_name": display_name,
		"kind": "twin_mauler",
		"encounter_id": "twin_maulers",
		"side": side,
		"primary_boss_target": true,
		"node": self
	}


func cleanup() -> void:
	if is_cleaned:
		return

	is_cleaned = true
	queue_free()


func is_living_party_target(target: Node) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and target.has_method("is_alive")
		and bool(target.is_alive())
	)


func emit_twin_event(event_type: String, ability_id: String, amount: int, metadata: Dictionary) -> void:
	emit_combat_event(event_type, self, ability_id, amount, metadata)


func emit_combat_event(
	event_type: String,
	source: Node,
	ability_id: String,
	amount: int,
	metadata: Dictionary = {}
) -> void:
	combat_event.emit({
		"type": event_type,
		"source": source,
		"target": self,
		"ability_id": ability_id,
		"amount": amount,
		"metadata": metadata.duplicate(true)
	})


func _get_node_display_name(target: Node) -> String:
	if target != null and is_instance_valid(target) and target.has_method("get_display_name"):
		return String(target.get_display_name())

	return target.name if target != null else "Unknown"


func _draw() -> void:
	var body_color := Color(0.70, 0.18, 0.12, 1.0) if side == "west" else Color(0.84, 0.38, 0.08, 1.0)
	var accent_color := Color(1.0, 0.55, 0.18, 0.95) if side == "west" else Color(1.0, 0.82, 0.30, 0.95)

	if is_dead:
		body_color = Color(0.24, 0.22, 0.20, 0.9)
		accent_color = Color(0.52, 0.50, 0.46, 0.7)

	draw_circle(Vector2.ZERO, combat_radius * 0.58, Color(0.06, 0.04, 0.03, 0.45))
	draw_circle(Vector2.ZERO, combat_radius * 0.44, body_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-38.0, -20.0),
		Vector2(-20.0, -62.0),
		Vector2(-5.0, -28.0),
		Vector2(22.0, -62.0),
		Vector2(34.0, -18.0),
		Vector2(26.0, 34.0),
		Vector2(-28.0, 34.0)
	]), body_color.lightened(0.12))
	draw_arc(Vector2.ZERO, combat_radius * 0.55, 0.0, TAU, 32, accent_color, 4.0)

	if is_exhausted():
		draw_arc(Vector2.ZERO, combat_radius * 0.67, 0.0, TAU, 32, Color(0.35, 0.75, 1.0, 0.95), 6.0)

	if is_casting_ability():
		var pulse := 0.55 + 0.35 * sin(Time.get_ticks_msec() / 100.0)
		draw_arc(Vector2.ZERO, combat_radius * 0.78, 0.0, TAU, 40, Color(1.0, 0.08, 0.04, pulse), 7.0)

	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(
			font,
			Vector2(-80.0, -82.0),
			display_name,
			HORIZONTAL_ALIGNMENT_CENTER,
			160.0,
			15,
			Color(1.0, 0.90, 0.68, 0.98)
		)
		if is_casting_ability():
			draw_string(
				font,
				Vector2(-100.0, 78.0),
				"RAMPAGE",
				HORIZONTAL_ALIGNMENT_CENTER,
				200.0,
				16,
				Color(1.0, 0.25, 0.12, 1.0)
			)
