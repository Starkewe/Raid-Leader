extends BaseCombatUnit

class_name Priest

@export var cast_range_units: float = 40.0

@export var heal_amount: int = 15
@export var heal_cooldown: float = 1.0
@export var heal_cast_time: float = 1.5
@export var show_world_cast_bar: bool = false

@onready var cast_bar = get_node_or_null("CastBar")

var heal_target: Node2D = null

var cooldown_timer: float = 0.0
var cast_timer: float = 0.0
var is_casting: bool = false


func _ready():
	max_health = 80
	super._ready()
	update_cast_bar()
	print("Priest ready. HP:", health)


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

	if not has_valid_heal_target():
		stop_action()
		move_and_slide()
		return

	handle_heal_positioning()

	move_and_slide()


func command_heal(new_target: Node2D):
	if is_dead:
		return

	if not can_heal_target(new_target):
		stop_action()
		print(get_display_name(), "received invalid heal target.")
		return

	if heal_target != new_target:
		cancel_current_cast()

	heal_target = new_target

	print(get_display_name(), "ordered to cast heals on:", get_node_display_name(heal_target))


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)


func has_valid_heal_target() -> bool:
	return can_heal_target(heal_target)


func handle_active_cast(delta: float):
	stop_movement()

	if not has_valid_heal_target():
		cancel_current_cast()
		return

	update_cast(delta)


func handle_heal_positioning() -> void:
	if not is_valid_node(heal_target):
		stop_movement()
		return

	if heal_target == self:
		stop_movement()
		try_start_cast()
		return

	var distance_units: float = get_range_units_to_node(heal_target)

	if distance_units > cast_range_units:
		move_toward_node(heal_target)
		return

	stop_movement()
	try_start_cast()

func try_start_cast():
	if cooldown_timer > 0.0:
		return

	if not has_valid_heal_target():
		return

	if heal_target.has_method("is_full_health") and heal_target.is_full_health():
		return

	is_casting = true
	cast_timer = heal_cast_time

	update_cast_bar()

	print(get_display_name(), "begins casting Heal")


func update_cast(delta: float):
	cast_timer = max(cast_timer - delta, 0.0)

	update_cast_bar()

	if cast_timer <= 0.0:
		finish_cast()


func finish_cast():
	is_casting = false
	cooldown_timer = heal_cooldown

	update_cast_bar()

	print(get_display_name(), "finishes Heal")

	if not has_valid_heal_target():
		print(get_display_name(), "finished Heal, but the target is no longer valid.")
		return

	heal_target.receive_heal(heal_amount)


func cancel_current_cast():
	if not is_casting and cast_timer <= 0.0:
		return

	is_casting = false
	cast_timer = 0.0

	update_cast_bar()

	print(get_display_name(), "cancels Heal")


func on_manual_move_started():
	cancel_current_cast()


func stop_action():
	heal_target = null
	cancel_current_cast()
	super.stop_action()


func on_reset_unit():
	heal_target = null
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

	cast_bar.max_value = heal_cast_time

	if is_casting:
		cast_bar.visible = true
		cast_bar.value = heal_cast_time - cast_timer
	else:
		cast_bar.visible = false
		cast_bar.value = 0


func is_casting_ability() -> bool:
	return is_casting


func get_cast_progress_percent() -> float:
	if not is_casting:
		return 0.0

	if heal_cast_time <= 0.0:
		return 0.0

	return clamp(((heal_cast_time - cast_timer) / heal_cast_time) * 100.0, 0.0, 100.0)


func get_cast_name() -> String:
	if is_casting:
		return "Heal"

	return ""


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if is_casting:
		return "Casting Heal"

	if has_valid_heal_target():
		if heal_target.has_method("is_full_health") and heal_target.is_full_health():
			return "Watching " + get_node_display_name(heal_target)

		if heal_target == self:
			return "Healing Self"

		var distance_units: float = get_range_units_to_node(heal_target)

		if distance_units > cast_range_units:
			return "Moving to " + get_node_display_name(heal_target)

		if cooldown_timer > 0.0:
			return "Recovering"

		return "Healing " + get_node_display_name(heal_target)

	return "Idle"
