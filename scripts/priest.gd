extends BaseCombatUnit

@export var cast_range: float = 280.0
@export var preferred_range: float = 240.0
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
	speed = 160.0
	super._ready()
	update_cast_bar()
	print("Priest ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if update_manual_move_order():
		move_and_slide()
		return

	cooldown_timer = max(cooldown_timer - delta, 0)

	if heal_target == null or not is_instance_valid(heal_target):
		stop_action()
		move_and_slide()
		return

	if heal_target.has_method("is_alive") and not heal_target.is_alive():
		stop_action()
		move_and_slide()
		return

	if heal_target == self:
		velocity = Vector2.ZERO

		if is_casting:
			update_cast(delta)
		else:
			try_start_cast()

		move_and_slide()
		return

	var distance := global_position.distance_to(heal_target.global_position)

	if is_casting:
		velocity = Vector2.ZERO
		update_cast(delta)
		move_and_slide()
		return

	if distance > cast_range:
		move_toward_target(heal_target)
	elif distance < preferred_range - 40:
		move_away_from_target(heal_target)
	else:
		velocity = Vector2.ZERO
		try_start_cast()

	move_and_slide()

func command_heal(new_target: Node2D):
	if is_dead:
		return

	if new_target == null or not is_instance_valid(new_target):
		stop_action()
		print(get_display_name(), "received invalid heal target")
		return

	if heal_target != new_target:
		is_casting = false
		cast_timer = 0.0
		update_cast_bar()

	heal_target = new_target
	print(get_display_name(), "ordered to cast heals on:", new_target.name)

func try_start_cast():
	if cooldown_timer > 0:
		return

	if heal_target == null or not is_instance_valid(heal_target):
		return

	if heal_target.has_method("is_alive") and not heal_target.is_alive():
		return

	if heal_target.has_method("is_full_health"):
		if heal_target.is_full_health():
			return

	is_casting = true
	cast_timer = heal_cast_time
	update_cast_bar()
	print(get_display_name(), "begins casting Heal")

func update_cast(delta):
	cast_timer -= delta
	update_cast_bar()

	if cast_timer <= 0:
		finish_cast()

func finish_cast():
	is_casting = false
	cooldown_timer = heal_cooldown
	update_cast_bar()

	print(get_display_name(), "finishes Heal")

	if heal_target != null and is_instance_valid(heal_target):
		if heal_target.has_method("is_alive") and not heal_target.is_alive():
			return

		if heal_target.has_method("receive_heal"):
			heal_target.receive_heal(heal_amount)
		else:
			print("Target cannot receive healing")

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
	heal_target = null
	is_casting = false
	cast_timer = 0.0
	super.stop_action()
	update_cast_bar()

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

	if heal_cast_time <= 0:
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

	if heal_target != null and is_instance_valid(heal_target):
		if heal_target.has_method("is_alive") and heal_target.is_alive():
			if heal_target.has_method("is_full_health") and heal_target.is_full_health():
				return "Watching " + heal_target.name

			if heal_target == self:
				return "Healing Self"

			return "Healing " + heal_target.name

	return "Idle"
