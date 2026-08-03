extends Node


class DummyAttackTarget:
	extends Node2D

	var health: int = 100
	var combat_radius: float = 128.0

	func is_alive() -> bool:
		return health > 0

	func get_combat_radius() -> float:
		return combat_radius

	func take_damage(
		amount: int,
		_source: Node = null,
		_ability_id: String = "",
		_metadata: Dictionary = {}
	) -> void:
		health -= amount


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := DummyAttackTarget.new()
	var rogue := Rogue.new()
	add_child(target)
	add_child(rogue)

	target.global_position = Vector2.ZERO
	rogue.global_position = Vector2(228.0, 0.0)
	rogue.command_attack(target)
	rogue.command_move_to_position(rogue.global_position)
	rogue._physics_process(0.016)

	if not rogue.is_attack_action_active():
		_fail("A normal positioning command replaced the active attack action.")
		return

	rogue.start_forced_movement(Vector2(528.0, 0.0), 0.1)
	rogue._physics_process(0.1)

	if rogue.attack_target_node != target:
		_fail("Forced movement cleared the active attack target.")
		return

	if not rogue.is_attack_action_active():
		_fail("Forced movement replaced the active attack action.")
		return

	if rogue.velocity.x >= 0.0:
		_fail("The displaced rogue did not immediately resume pursuit toward its attack target.")
		return

	rogue.command_attack(target)
	rogue.start_forced_movement(Vector2(528.0, 0.0), 0.1)
	rogue.command_move_to_position(Vector2(700.0, 0.0))
	rogue._physics_process(0.1)
	rogue._physics_process(0.016)

	if not rogue.is_attack_action_active():
		_fail("A movement command issued during knockback erased the combat assignment.")
		return

	if rogue.velocity.x <= 0.0:
		_fail("The queued movement command did not take priority after knockback.")
		return

	rogue.global_position = Vector2(700.0, 0.0)
	rogue._physics_process(0.016)

	if rogue.has_manual_move_order or rogue.velocity.x >= 0.0:
		_fail("Role pursuit did not resume after ordinary movement arrived.")
		return

	print("Attack pursuit after displacement regression test passed.")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
