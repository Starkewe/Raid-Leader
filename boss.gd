extends CharacterBody2D

signal defeated

@export var max_health: int = 500
@export var speed: float = 120.0

@export var attack_range: float = 100.0
@export var attack_damage: int = 20
@export var attack_cooldown: float = 1.5

@export var special_cast_interval: float = 6.0
@export var special_cast_time: float = 2.5
@export var special_damage: int = 75

@onready var health_bar = get_node_or_null("HealthBar")
@onready var cast_bar = get_node_or_null("CastBar")

var health: int
var target: Node2D = null

var attack_timer: float = 0.0
var special_timer: float = 0.0
var cast_timer: float = 0.0
var is_casting: bool = false
var is_dead: bool = false

func _ready():
	health = max_health
	attack_timer = attack_cooldown
	special_timer = special_cast_interval
	update_health_bar()
	update_cast_bar()
	print("Boss ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		return

	if not has_valid_target():
		clear_target()
		move_and_slide()
		return

	attack_timer = max(attack_timer - delta, 0)
	special_timer = max(special_timer - delta, 0)

	if is_casting:
		velocity = Vector2.ZERO
		update_special_cast(delta)
	else:
		if special_timer <= 0:
			start_special_cast()

	var distance := global_position.distance_to(target.global_position)

	if distance > attack_range and not is_casting:
		chase_target()
	else:
		velocity = Vector2.ZERO
		auto_attack()

	move_and_slide()

func has_valid_target() -> bool:
	if target == null:
		return false

	if not is_instance_valid(target):
		return false

	if target.has_method("is_alive"):
		return target.is_alive()

	return true

func set_target(new_target: Node2D):
	if is_dead:
		return

	target = new_target

	if target != null:
		print("Boss target set to:", target.name)

func clear_target():
	target = null
	velocity = Vector2.ZERO

func get_current_target() -> Node2D:
	if has_valid_target():
		return target

	return null

func chase_target():
	if not has_valid_target():
		return

	var direction := global_position.direction_to(target.global_position)
	velocity = direction * speed

func auto_attack():
	if attack_timer > 0:
		return

	if not has_valid_target():
		return

	attack_timer = attack_cooldown
	print("Boss auto attacks:", target.name)

	if target.has_method("take_damage"):
		target.take_damage(attack_damage)

func start_special_cast():
	if is_casting:
		return

	is_casting = true
	cast_timer = special_cast_time
	update_cast_bar()
	print("Boss begins casting BIG SLAM! Interrupt now!")

func update_special_cast(delta):
	cast_timer -= delta
	update_cast_bar()

	if cast_timer <= 0:
		finish_special_cast()

func finish_special_cast():
	is_casting = false
	special_timer = special_cast_interval
	update_cast_bar()

	print("Boss finishes BIG SLAM!")

	if has_valid_target():
		if target.has_method("take_damage"):
			target.take_damage(special_damage)

func interrupt_cast() -> bool:
	if is_dead:
		return false

	if is_casting:
		is_casting = false
		special_timer = special_cast_interval
		update_cast_bar()
		print("Boss cast interrupted!")
		return true

	print("Boss is not casting anything interruptible.")
	return false

func take_damage(amount: int):
	if is_dead:
		return

	health -= amount
	health = max(health, 0)
	update_health_bar()

	print("Boss took", amount, "damage. HP:", health)

	if health <= 0:
		die()

func die():
	if is_dead:
		return

	is_dead = true
	health = 0
	update_health_bar()

	is_casting = false
	update_cast_bar()
	clear_target()

	print("Boss defeated!")
	defeated.emit()

func is_alive() -> bool:
	return not is_dead

func update_health_bar():
	if health_bar == null:
		return

	health_bar.max_value = max_health
	health_bar.value = health

func update_cast_bar():
	if cast_bar == null:
		return

	cast_bar.max_value = special_cast_time

	if is_casting:
		cast_bar.visible = true
		cast_bar.value = special_cast_time - cast_timer
	else:
		cast_bar.visible = false
		cast_bar.value = 0
func reset_boss(new_position: Vector2):
	is_dead = false
	health = max_health
	clear_target()

	is_casting = false
	attack_timer = attack_cooldown
	special_timer = special_cast_interval
	cast_timer = 0

	global_position = new_position

	update_health_bar()
	update_cast_bar()
	visible = true
func get_status_text() -> String:
	if is_dead:
		return "Defeated"

	if is_casting:
		return "Casting Big Slam"

	if target != null and is_instance_valid(target):
		if target.has_method("is_alive") and target.is_alive():
			return "Attacking " + target.name

	return "Idle"
