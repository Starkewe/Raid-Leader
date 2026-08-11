extends Node2D
class_name CarrionGrowth

signal defeated(target: Node)
signal combat_event(event: Dictionary)

var boss: Node = null
var growth_id: int = 0
var side: String = "east"
var region: String = "east"
var range_name: String = "mid"
var max_health: int = 1000
var health: int = 1000
var pulse_damage: int = 3
var pulse_interval: float = 2.0
var pulse_timer: float = 2.0
var is_dead: bool = false
var is_cleaned: bool = false
var spawned_at_seconds: float = 0.0
var total_damage_received: int = 0
var total_raid_damage: int = 0


func configure(
	new_boss: Node,
	new_growth_id: int,
	new_side: String,
	new_region: String,
	new_range_name: String,
	new_max_health: int,
	new_pulse_damage: int,
	new_pulse_interval: float,
	new_spawned_at_seconds: float
) -> void:
	boss = new_boss
	growth_id = new_growth_id
	side = new_side
	region = new_region
	range_name = new_range_name
	max_health = maxi(new_max_health, 1)
	health = max_health
	pulse_damage = maxi(new_pulse_damage, 0)
	pulse_interval = maxf(new_pulse_interval, 0.1)
	pulse_timer = pulse_interval
	spawned_at_seconds = new_spawned_at_seconds
	is_dead = false
	is_cleaned = false
	total_damage_received = 0
	total_raid_damage = 0
	name = "CarrionGrowth_%d" % growth_id
	queue_redraw()


func tick(delta: float, living_party_members: Array) -> void:
	if is_dead:
		return

	pulse_timer = maxf(pulse_timer - maxf(delta, 0.0), 0.0)

	if pulse_timer > 0.0:
		return

	pulse_timer = pulse_interval
	var hit_count := 0

	for party_member in living_party_members:
		if not _is_living(party_member):
			continue

		if party_member.has_method("take_damage"):
			party_member.take_damage(
				pulse_damage,
				self,
				"carrion_growth_pulse",
				{
					"encounter": "carrion_roc",
					"growth_id": growth_id,
					"growth_side": side,
					"growth_region": region,
					"damage_type": "environmental",
					"growth_pulse": true
				}
			)
			total_raid_damage += pulse_damage
			hit_count += 1

	_emit_event(
		"roc_growth_pulse",
		self,
		"carrion_growth_pulse",
		pulse_damage * hit_count,
		{
			"encounter": "carrion_roc",
			"growth_id": growth_id,
			"growth_side": side,
			"growth_region": region,
			"hit_count": hit_count,
			"damage_type": "environmental"
		}
	)
	queue_redraw()


func take_damage(
	amount: int,
	source: Node = null,
	ability_id: String = "",
	metadata: Dictionary = {}
) -> void:
	if is_dead:
		return

	var previous_health := health
	health = max(health - maxi(amount, 0), 0)
	var actual_amount := previous_health - health
	total_damage_received += actual_amount
	var event_metadata := metadata.duplicate(true)
	event_metadata["encounter"] = "carrion_roc"
	event_metadata["growth_id"] = growth_id
	event_metadata["growth_side"] = side
	event_metadata["growth_region"] = region
	event_metadata["growth_damage"] = true

	_emit_event("damage", source, ability_id, actual_amount, event_metadata)
	queue_redraw()

	if health <= 0:
		die()


func die() -> void:
	if is_dead:
		return

	is_dead = true
	health = 0
	visible = false
	_emit_event(
		"roc_growth_defeated",
		self,
		"",
		0,
		{
			"encounter": "carrion_roc",
			"growth_id": growth_id,
			"growth_side": side,
			"growth_region": region,
			"lifespan_seconds": Time.get_ticks_msec() / 1000.0 - spawned_at_seconds,
			"damage_taken": total_damage_received,
			"raid_damage": total_raid_damage
		}
	)
	defeated.emit(self)


func cleanup() -> void:
	if is_cleaned:
		return

	is_cleaned = true
	if not is_dead:
		_emit_event(
			"roc_growth_cleanup",
			self,
			"carrion_growth_cleanup",
			0,
			{
				"encounter": "carrion_roc",
				"growth_id": growth_id,
				"growth_side": side,
				"growth_region": region,
				"lifespan_seconds": Time.get_ticks_msec() / 1000.0 - spawned_at_seconds,
				"damage_taken": total_damage_received,
				"raid_damage": total_raid_damage,
				"cleanup_damage": total_damage_received
			}
		)
	queue_free()


func is_alive() -> bool:
	return not is_dead


func get_current_health() -> int:
	return health


func get_max_health() -> int:
	return max_health


func get_display_name() -> String:
	return "%s Growth" % side.capitalize()


func get_encounter_target_descriptor() -> Dictionary:
	return {
		"target_id": "growth:%s:%d" % [side, growth_id],
		"display_name": get_display_name(),
		"kind": "carrion_growth",
		"encounter_id": "carrion_roc",
		"side": side,
		"region": region,
		"range": range_name,
		"node": self
	}


func get_status_text() -> String:
	return "%s Growth %d/%d | Pulse %.1fs" % [
		side.capitalize(),
		health,
		max_health,
		pulse_timer
	]


func _draw() -> void:
	if is_dead:
		return

	var pulse_alpha := 0.65 + 0.2 * sin(Time.get_ticks_msec() / 180.0)
	draw_circle(Vector2.ZERO, 20.0, Color(0.46, 0.88, 0.32, pulse_alpha))
	draw_circle(Vector2.ZERO, 14.0, Color(0.12, 0.25, 0.08, 0.95))
	draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, Color(0.75, 1.0, 0.32, 0.95), 3.0)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(
			font,
			Vector2(-44.0, -30.0),
			"%s Growth" % side.capitalize(),
			HORIZONTAL_ALIGNMENT_LEFT,
			100.0,
			13,
			Color(0.82, 1.0, 0.7, 0.95)
		)
		draw_string(
			font,
			Vector2(-30.0, 5.0),
			str(health),
			HORIZONTAL_ALIGNMENT_CENTER,
			60.0,
			12,
			Color.WHITE
		)


func _is_living(candidate: Node) -> bool:
	return (
		candidate != null
		and is_instance_valid(candidate)
		and (not candidate.has_method("is_alive") or bool(candidate.is_alive()))
	)


func _emit_event(
	event_type: String,
	source: Node,
	ability_id: String,
	amount: int,
	metadata: Dictionary
) -> void:
	combat_event.emit({
		"type": event_type,
		"source": source,
		"target": self,
		"ability_id": ability_id,
		"amount": amount,
		"metadata": metadata.duplicate(true)
	})
