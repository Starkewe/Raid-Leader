extends BaseCombatUnit

class_name Mage

@export var cast_range_units: float = 40.0

@export var spell_damage: int = 18
@export var spell_cooldown: float = 1.0
@export var spell_cast_time: float = 1.5
@export var show_world_cast_bar: bool = false

@onready var cast_bar = get_node_or_null("CastBar")

var target: Node2D = null

var cooldown_timer: float = 0.0
var cast_timer: float = 0.0
var is_casting: bool = false


func _ready():
	max_health = 70
	super._ready()
	update_cast_bar()
	print("Mage ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		stop_movement()
		move_and_slide()
		return

	update_cooldown(delta)

	if update_manual_move_order():
		move_and_slide()
		return

	if is_casting:
		handle_active_cast(delta)
		move_and_slide()
		return

	if not has_valid_cast_target():
		stop_action()
		move_and_slide()
		return

	handle_cast_positioning()

	move_and_slide()


func command_attack(new_target: Node2D):
	if is_dead:
		return

	if not can_damage_target(new_target):
		stop_action()
		return

	target = new_target

	print(get_display_name(), "ordered to cast at:", get_node_display_name(target))


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)


func has_valid_cast_target() -> bool:
	return can_damage_target(target)


func handle_active_cast(delta: float):
	stop_movement()

	if not has_valid_cast_target():
		cancel_current_cast()
		return

	update_cast(delta)


func handle_cast_positioning() -> void:
	if not is_valid_node(target):
		stop_movement()
		return

	var distance_units: float = get_range_units_to_node(target)

	if distance_units > cast_range_units:
		move_toward_node(target)
		return

	stop_movement()
	try_start_cast()


func try_start_cast():
	if cooldown_timer > 0.0:
		return

	if not has_valid_cast_target():
		return

	is_casting = true
	cast_timer = spell_cast_time

	update_cast_bar()

	print(get_display_name(), "begins casting Fireball")


func update_cast(delta: float):
	cast_timer = max(cast_timer - delta, 0.0)

	update_cast_bar()

	if cast_timer <= 0.0:
		finish_cast()


func finish_cast():
	is_casting = false
	cooldown_timer = spell_cooldown

	update_cast_bar()

	if not has_valid_cast_target():
		print(get_display_name(), "finishes Fireball, but the target is no longer valid.")
		return

	print(get_display_name(), "finishes Fireball and deals damage to", get_node_display_name(target))

	target.take_damage(spell_damage)


func cancel_current_cast():
	if not is_casting and cast_timer <= 0.0:
		return

	is_casting = false
	cast_timer = 0.0

	update_cast_bar()

	print(get_display_name(), "cancels Fireball")


func on_manual_move_started():
	cancel_current_cast()


func stop_action():
	target = null
	cancel_current_cast()
	super.stop_action()


func on_reset_unit():
	target = null
	cooldown_timer = 0.0
	cast_timer = 0.0
	is_casting = false

	update_cast_bar()


func update_cast_bar():
	if cast_bar == null:
		return

	if not show_world_cast_bar:
		cast_bar.visible = false
		cast_bar.value = 0
		return

	cast_bar.max_value = spell_cast_time

	if is_casting:
		cast_bar.visible = true
		cast_bar.value = spell_cast_time - cast_timer
	else:
		cast_bar.visible = false
		cast_bar.value = 0


func is_casting_ability() -> bool:
	return is_casting


func get_cast_progress_percent() -> float:
	if not is_casting:
		return 0.0

	if spell_cast_time <= 0.0:
		return 0.0

	return clamp(((spell_cast_time - cast_timer) / spell_cast_time) * 100.0, 0.0, 100.0)


func get_cast_name() -> String:
	if is_casting:
		return "Fireball"

	return ""


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if is_casting:
		return "Casting Fireball"

	if has_valid_cast_target():
		var distance_units: float = get_range_units_to_node(target)

		if distance_units > cast_range_units:
			return "Moving to " + get_node_display_name(target)

		if cooldown_timer > 0.0:
			return "Recovering"

		return "Ready to Cast"

	return "Idle"
