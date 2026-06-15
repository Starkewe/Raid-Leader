extends BaseCombatUnit

@export var cast_range: float = 280.0
@export var preferred_range: float = 240.0
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
	speed = 150.0
	super._ready()
	update_cast_bar()
	print("Mage ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if update_manual_move_order():
		move_and_slide()
		return

	cooldown_timer = max(cooldown_timer - delta, 0)

	if target == null or not is_instance_valid(target):
		stop_action()
		move_and_slide()
		return

	if target.has_method("is_alive") and not target.is_alive():
		stop_action()
		move_and_slide()
		return

	var distance := global_position.distance_to(target.global_position)

	if is_casting:
		velocity = Vector2.ZERO
		update_cast(delta)
		move_and_slide()
		return

	if distance > cast_range:
		move_toward_target(target)
	elif distance < preferred_range - 40:
		move_away_from_target(target)
	else:
		velocity = Vector2.ZERO
		try_start_cast()

	move_and_slide()

func command_attack(new_target: Node2D):
	if is_dead:
		return

	if new_target == null or not is_instance_valid(new_target):
		stop_action()
		return

	target = new_target
	print(get_display_name(), "ordered to cast at:", new_target.name)

func try_start_cast():
	if cooldown_timer > 0:
		return

	if target == null or not is_instance_valid(target):
		return

	if target.has_method("is_alive") and not target.is_alive():
		return

	is_casting = true
	cast_timer = spell_cast_time
	update_cast_bar()
	print(get_display_name(), "begins casting Fireball")

func update_cast(delta):
	cast_timer -= delta
	update_cast_bar()

	if cast_timer <= 0:
		finish_cast()

func finish_cast():
	is_casting = false
	cooldown_timer = spell_cooldown
	update_cast_bar()

	print(get_display_name(), "finishes Fireball and deals damage")

	if target != null and is_instance_valid(target):
		if target.has_method("is_alive") and not target.is_alive():
			return

		if target.has_method("take_damage"):
			target.take_damage(spell_damage)

func move_toward_target(target_node: Node2D):
	var direction := global_position.direction_to(target_node.global_position)
	velocity = direction * speed

func move_away_from_target(target_node: Node2D):
	var direction := target_node.global_position.direction_to(global_position)
	velocity = direction * speed

func on_manual_move_started():
	if is_casting:
		is_casting = false
		cast_timer = 0.0
		update_cast_bar()

func stop_action():
	target = null
	is_casting = false
	cast_timer = 0.0
	super.stop_action()
	update_cast_bar()

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

	if spell_cast_time <= 0:
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

	if target != null and is_instance_valid(target):
		if target.has_method("is_alive") and target.is_alive():
			var distance := global_position.distance_to(target.global_position)

			if distance > cast_range:
				return "Moving to " + target.name

			return "Ready to Cast"

	return "Idle"
