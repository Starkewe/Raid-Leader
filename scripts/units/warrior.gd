extends BaseCombatUnit

@export var attack_range: float = 175.0
@export var stop_distance: float = 155.0
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.0

var target: Node2D = null
var cooldown_timer: float = 0.0

func _ready():
	max_health = 100
	speed = 180.0
	super._ready()
	print("Warrior ready. HP:", health)

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

	if distance > stop_distance:
		move_toward_target(target)
	else:
		velocity = Vector2.ZERO

	if distance <= attack_range:
		attack_target()

	move_and_slide()

func command_attack(new_target: Node2D):
	if is_dead:
		return

	if new_target == null or not is_instance_valid(new_target):
		stop_action()
		return

	target = new_target
	print(get_display_name(), "attacking:", new_target.name)

func move_toward_target(target_node: Node2D):
	var direction := global_position.direction_to(target_node.global_position)
	velocity = direction * speed

func attack_target():
	if cooldown_timer > 0:
		return

	if target == null or not is_instance_valid(target):
		return

	cooldown_timer = attack_cooldown
	print(get_display_name(), "attacks target")

	if target.has_method("take_damage"):
		target.take_damage(attack_damage)

func stop_action():
	target = null
	super.stop_action()

func on_reset_unit():
	cooldown_timer = 0.0
	target = null

func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if target != null and is_instance_valid(target):
		if target.has_method("is_alive") and target.is_alive():
			return "Attacking " + target.name

	return "Idle"
