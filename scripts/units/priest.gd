extends BaseCombatUnit

class_name Priest

var cast_range_units: float = 40.0

var heal_amount: int = 15
var heal_cooldown: float = 1.0
var heal_cast_time: float = 1.5
var cure_range_units: float = 40.0
var cure_cooldown: float = 0.5
var cure_cast_time: float = 1.0
@export var show_world_cast_bar: bool = false

@onready var cast_bar = get_node_or_null("CastBar")

var heal_target: Node2D = null
var cure_target: Node2D = null

var cooldown_timer: float = 0.0
var cure_cooldown_timer: float = 0.0
var cast_timer: float = 0.0
var is_casting: bool = false
var active_cast_kind: String = ""
var heal_ability_id: String = "heal"
var heal_display_name: String = "Heal"
var cure_ability_id: String = "cure"
var cure_display_name: String = "Cure"


func configure_from_definition(definition: UnitDefinition) -> void:
	super.configure_from_definition(definition)

	if definition == null:
		return

	var action := definition.get_action(heal_ability_id)
	var cure_action := definition.get_action(cure_ability_id)

	if action != null:
		heal_display_name = action.display_name
		cast_range_units = action.range_units
		heal_amount = action.amount
		heal_cooldown = action.cooldown
		heal_cast_time = action.cast_time

	if cure_action != null:
		cure_display_name = cure_action.display_name
		cure_range_units = cure_action.range_units
		cure_cooldown = cure_action.cooldown
		cure_cast_time = cure_action.cast_time


func _ready():
	super._ready()
	update_cast_bar()
	print("Priest ready. HP:", health)


func _physics_process(delta):
	if is_dead:
		stop_movement()
		move_and_slide()
		return

	update_cooldown(delta)

	if update_forced_movement(delta):
		move_and_slide()
		return

	if update_manual_move_order():
		move_and_slide()
		return

	if is_casting:
		handle_active_cast(delta)
		move_and_slide()
		return

	if cure_target != null and not has_valid_cure_target():
		cure_target = null

	if has_valid_cure_target():
		handle_cure_positioning()
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

	if heal_target != new_target and active_cast_kind != "cure":
		cancel_current_cast()

	heal_target = new_target

	print(get_display_name(), "ordered to cast heals on:", get_node_display_name(heal_target))


func command_cure(new_target: Node2D) -> bool:
	if is_dead or not is_valid_living_node(new_target):
		return false

	if not new_target.has_method("has_dispellable_status"):
		return false

	if not bool(new_target.has_dispellable_status("cure")):
		return false

	cancel_current_cast()
	cure_target = new_target
	print(get_display_name(), "ordered to cure:", get_node_display_name(cure_target))
	return true


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)
	cure_cooldown_timer = max(cure_cooldown_timer - delta, 0.0)


func has_valid_heal_target() -> bool:
	return can_heal_target(heal_target)


func has_valid_cure_target() -> bool:
	if not is_valid_living_node(cure_target):
		return false

	if not cure_target.has_method("has_dispellable_status"):
		return false

	return bool(cure_target.has_dispellable_status("cure"))


func handle_active_cast(delta: float):
	stop_movement()

	if active_cast_kind == "cure" and not has_valid_cure_target():
		cure_target = null
		cancel_current_cast()
		return

	if active_cast_kind != "cure" and not has_valid_heal_target():
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


func handle_cure_positioning() -> void:
	if not is_valid_node(cure_target):
		cure_target = null
		stop_movement()
		return

	if cure_target != self and get_range_units_to_node(cure_target) > cure_range_units:
		move_toward_node(cure_target)
		return

	stop_movement()
	try_start_cure_cast()

func try_start_cast():
	if cooldown_timer > 0.0:
		return

	if not has_valid_heal_target():
		return

	if heal_target.has_method("is_full_health") and heal_target.is_full_health():
		return

	is_casting = true
	active_cast_kind = "heal"
	cast_timer = heal_cast_time

	update_cast_bar()

	print(get_display_name(), "begins casting ", heal_display_name)


func try_start_cure_cast() -> void:
	if cure_cooldown_timer > 0.0 or not has_valid_cure_target():
		return

	is_casting = true
	active_cast_kind = "cure"
	cast_timer = cure_cast_time
	update_cast_bar()
	print(get_display_name(), "begins casting ", cure_display_name)


func update_cast(delta: float):
	cast_timer = max(cast_timer - delta, 0.0)

	update_cast_bar()

	if cast_timer <= 0.0:
		finish_cast()


func finish_cast():
	is_casting = false

	if active_cast_kind == "cure":
		finish_cure_cast()
		return

	cooldown_timer = heal_cooldown

	update_cast_bar()

	print(get_display_name(), "finishes ", heal_display_name)

	if not has_valid_heal_target():
		print(get_display_name(), "finished ", heal_display_name, ", but the target is no longer valid.")
		active_cast_kind = ""
		return

	heal_target.receive_heal(heal_amount, self, heal_ability_id)
	active_cast_kind = ""


func finish_cure_cast() -> void:
	cure_cooldown_timer = cure_cooldown
	update_cast_bar()

	if not has_valid_cure_target():
		print(get_display_name(), "finished ", cure_display_name, ", but the target is no longer curable.")
		cure_target = null
		active_cast_kind = ""
		return

	var completed_target := cure_target
	var removed_effects: Array[String] = completed_target.clear_dispellable_statuses("cure", 1)
	print(
		get_display_name(),
		"cures ",
		get_node_display_name(completed_target),
		" of ",
		removed_effects
	)

	if completed_target.has_method("emit_combat_event"):
		completed_target.emit_combat_event(
			"dispel",
			self,
			cure_ability_id,
			removed_effects.size(),
			{"removed_effects": removed_effects}
		)

	cure_target = null
	active_cast_kind = ""


func cancel_current_cast():
	if not is_casting and cast_timer <= 0.0:
		return

	is_casting = false
	cast_timer = 0.0

	update_cast_bar()

	var cancelled_name := cure_display_name if active_cast_kind == "cure" else heal_display_name
	active_cast_kind = ""
	print(get_display_name(), "cancels ", cancelled_name)


func on_manual_move_started():
	cancel_current_cast()


func stop_action():
	heal_target = null
	cure_target = null
	cancel_current_cast()
	super.stop_action()


func on_reset_unit():
	heal_target = null
	cure_target = null
	cooldown_timer = 0.0
	cure_cooldown_timer = 0.0
	cast_timer = 0.0
	is_casting = false
	active_cast_kind = ""

	update_cast_bar()


func update_cast_bar():
	if cast_bar == null:
		return

	if not show_world_cast_bar:
		cast_bar.visible = false
		cast_bar.value = 0
		return

	var active_cast_time := cure_cast_time if active_cast_kind == "cure" else heal_cast_time
	cast_bar.max_value = active_cast_time

	if is_casting:
		cast_bar.visible = true
		cast_bar.value = active_cast_time - cast_timer
	else:
		cast_bar.visible = false
		cast_bar.value = 0


func is_casting_ability() -> bool:
	return is_casting


func get_cast_progress_percent() -> float:
	if not is_casting:
		return 0.0

	var active_cast_time := cure_cast_time if active_cast_kind == "cure" else heal_cast_time

	if active_cast_time <= 0.0:
		return 0.0

	return clamp(((active_cast_time - cast_timer) / active_cast_time) * 100.0, 0.0, 100.0)


func get_cast_name() -> String:
	if is_casting:
		return cure_display_name if active_cast_kind == "cure" else heal_display_name

	return ""


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if is_casting:
		return "Casting " + get_cast_name()

	if has_valid_cure_target():
		return "Curing " + get_node_display_name(cure_target)

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
