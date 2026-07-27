extends SceneTree


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


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := DummyAttackTarget.new()
	var rogue := Rogue.new()
	root.add_child(target)
	root.add_child(rogue)

	target.global_position = Vector2.ZERO
	rogue.global_position = Vector2(228.0, 0.0)
	rogue.command_attack(target)
	rogue.commanded_hold_active = true
	rogue.start_forced_movement(Vector2(528.0, 0.0), 0.1)
	rogue.active_action_kind = BaseCombatUnit.ACTION_NONE
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

	if rogue.is_attack_action_active():
		_fail("A movement command issued during knockback did not replace the attack action.")
		return

	if rogue.velocity.x <= 0.0:
		_fail("The queued movement command did not take priority after knockback.")
		return

	print("Attack pursuit after displacement regression test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
