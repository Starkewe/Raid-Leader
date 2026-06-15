extends BaseCombatUnit

@export var attack_range: float = 165.0
@export var stop_distance: float = 145.0
@export var attack_damage: int = 8
@export var attack_cooldown: float = 0.8

@export var interrupt_range: float = 190.0
@export var interrupt_cooldown: float = 3.0

var attack_target_node: Node2D = null
var interrupt_target: Node2D = null

var attack_timer: float = 0.0
var interrupt_timer: float = 0.0

func _ready():
	max_health = 85
	speed = 220.0
	super._ready()
	print("Rogue ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if update_manual_move_order():
		move_and_slide()
		return

	attack_timer = max(attack_timer - delta, 0)
	interrupt_timer = max(interrupt_timer - delta, 0)

	if attack_target_node == null or not is_instance_valid(attack_target_node):
		stop_attack_only()
		move_and_slide()
		return

	if attack_target_node.has_method("is_alive") and not attack_target_node.is_alive():
		stop_attack_only()
		move_and_slide()
		return

	var distance := global_position.distance_to(attack_target_node.global_position)

	if distance > stop_distance:
		var direction := global_position.direction_to(attack_target_node.global_position)
		velocity = direction * speed
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

	attack_target_node = new_target
	interrupt_target = new_target
	print(get_display_name(), "attacking:", new_target.name)

func command_interrupt(new_target: Node2D):
	if is_dead:
		return

	if new_target == null or not is_instance_valid(new_target):
		interrupt_target = null
		print(get_display_name(), "received invalid interrupt target.")
		return

	interrupt_target = new_target
	print(get_display_name(), "ordered to interrupt:", new_target.name)

	var distance := global_position.distance_to(new_target.global_position)

	if distance > interrupt_range:
		print(get_display_name(), "is too far to interrupt.")
		return

	try_interrupt()

func try_interrupt():
	if is_dead:
		return

	if interrupt_timer > 0:
		print(get_display_name(), "interrupt is on cooldown.")
		return

	if interrupt_target == null or not is_instance_valid(interrupt_target):
		interrupt_target = null
		print("No valid interrupt target.")
		return

	if interrupt_target.has_method("is_alive") and not interrupt_target.is_alive():
		print("Interrupt target is dead.")
		return

	if not interrupt_target.has_method("interrupt_cast"):
		print("Target cannot be interrupted.")
		return

	interrupt_timer = interrupt_cooldown

	var success = interrupt_target.interrupt_cast()

	if success:
		print(get_display_name(), "successfully interrupted the cast!")
	else:
		print(get_display_name(), "used interrupt, but there was nothing to stop.")

func attack_target():
	if attack_timer > 0:
		return

	if attack_target_node == null or not is_instance_valid(attack_target_node):
		return

	attack_timer = attack_cooldown
	print(get_display_name(), "attacks target")

	if attack_target_node.has_method("take_damage"):
		attack_target_node.take_damage(attack_damage)

func stop_attack_only():
	attack_target_node = null
	velocity = Vector2.ZERO

func stop_action():
	attack_target_node = null
	interrupt_target = null
	super.stop_action()

func on_reset_unit():
	attack_target_node = null
	interrupt_target = null
	attack_timer = 0.0
	interrupt_timer = 0.0

func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if attack_target_node != null and is_instance_valid(attack_target_node):
		if attack_target_node.has_method("is_alive") and attack_target_node.is_alive():
			return "Attacking " + attack_target_node.name

	return "Idle"
