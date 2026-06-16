extends BaseCombatUnit

class_name Warrior

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
		stop_movement()
		move_and_slide()
		return

	update_cooldown(delta)

	if update_manual_move_order():
		move_and_slide()
		return

	if not has_valid_attack_target():
		stop_action()
		move_and_slide()
		return

	handle_attack_movement()

	move_and_slide()


func command_attack(new_target: Node2D):
	if is_dead:
		return

	if not can_damage_target(new_target):
		stop_action()
		return

	target = new_target

	print(get_display_name(), "attacking:", get_node_display_name(target))


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)


func has_valid_attack_target() -> bool:
	return can_damage_target(target)


func handle_attack_movement():
	var distance := get_distance_to_node(target)

	if distance > stop_distance:
		move_toward_node(target)
		return

	stop_movement()

	if distance <= attack_range:
		attack_target()


func attack_target():
	if cooldown_timer > 0.0:
		return

	if not can_damage_target(target):
		return

	cooldown_timer = attack_cooldown

	print(get_display_name(), "attacks", get_node_display_name(target))

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

	if has_valid_attack_target():
		return "Attacking " + get_node_display_name(target)

	return "Idle"
