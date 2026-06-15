extends CharacterBody2D

signal defeated(unit)

@export var max_health: int = 70
@export var speed: float = 150.0

@export var cast_range: float = 280.0
@export var preferred_range: float = 240.0
@export var spell_damage: int = 18
@export var spell_cooldown: float = 1.0
@export var spell_cast_time: float = 1.5

@export var show_world_cast_bar: bool = false

@onready var health_bar = get_node_or_null("HealthBar")
@onready var cast_bar = get_node_or_null("CastBar")

var health: int
var target: Node2D = null

var cooldown_timer: float = 0.0
var cast_timer: float = 0.0
var is_casting: bool = false
var is_dead: bool = false

var unit_class: String = ""
var unit_number: int = 0
var display_name: String = ""

func _ready():
	health = max_health
	update_health_bar()
	update_cast_bar()
	print("Mage ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		velocity = Vector2.ZERO
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

func stop_action():
	target = null
	is_casting = false
	cast_timer = 0.0
	velocity = Vector2.ZERO
	update_cast_bar()

func take_damage(amount: int):
	if is_dead:
		return

	health -= amount
	health = max(health, 0)
	update_health_bar()

	print(get_display_name(), "took", amount, "damage. HP:", health)

	if health <= 0:
		die()

func receive_heal(amount: int):
	if is_dead:
		return

	health += amount
	health = min(health, max_health)
	update_health_bar()

	print(get_display_name(), "healed for", amount, ". HP:", health)

func die():
	if is_dead:
		return

	is_dead = true
	health = 0
	update_health_bar()
	stop_action()

	print(get_display_name(), "defeated!")
	defeated.emit(self)

func reset_unit(new_position: Vector2):
	is_dead = false
	health = max_health

	target = null
	is_casting = false
	cooldown_timer = 0.0
	cast_timer = 0.0

	velocity = Vector2.ZERO
	global_position = new_position
	visible = true

	update_health_bar()
	update_cast_bar()

func update_health_bar():
	if health_bar == null:
		return

	health_bar.max_value = max_health
	health_bar.value = health

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

func is_alive() -> bool:
	return not is_dead

func is_full_health() -> bool:
	return health >= max_health

func get_current_health() -> int:
	return health

func get_max_health() -> int:
	return max_health

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
	if is_dead:
		return "Dead"

	if is_casting:
		return "Casting Fireball"

	if target != null and is_instance_valid(target):
		if target.has_method("is_alive") and target.is_alive():
			var distance := global_position.distance_to(target.global_position)

			if distance > cast_range:
				return "Moving to " + target.name

			return "Ready to Cast"

	return "Idle"

func setup_unit_identity(new_unit_class: String, new_unit_number: int):
	unit_class = new_unit_class
	unit_number = new_unit_number
	display_name = new_unit_class + " " + str(new_unit_number)

func get_display_name() -> String:
	if display_name != "":
		return display_name

	return name
