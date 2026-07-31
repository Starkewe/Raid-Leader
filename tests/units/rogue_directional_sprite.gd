extends Node


class DummyBoss:
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
	var rogue_scene := load("res://scenes/units/rogue.tscn") as PackedScene

	if rogue_scene == null:
		_fail("The rogue combat scene could not be loaded.")
		return

	var rogue := rogue_scene.instantiate() as Rogue
	var boss := DummyBoss.new()
	add_child(boss)
	add_child(rogue)
	rogue.set_combat_facing_target(boss)

	if not _test_direction_mapping(rogue):
		return

	if not _test_direction_stability(rogue):
		return

	if not _test_idle_boss_facing(rogue, boss):
		return

	if not _test_displacement_and_recovery(rogue, boss):
		return

	if not _test_sprite_alignment(rogue):
		return

	print("Rogue directional combat sprite regression test passed.")
	get_tree().quit(0)


func _test_direction_mapping(rogue: Rogue) -> bool:
	rogue._update_combat_facing_from_displacement(Vector2.UP * 10.0)

	if rogue.get_facing_direction() != Rogue.FacingDirection.NORTH:
		_fail("Northward movement did not select the north sprite.")
		return false

	rogue._update_combat_facing_from_displacement(Vector2(10.0, 10.0))

	if rogue.get_facing_direction() != Rogue.FacingDirection.SOUTHEAST:
		_fail("Southeast movement did not select the southeast sprite.")
		return false

	var sprite := rogue.get_node_or_null("Sprite2D") as Sprite2D

	if (
		sprite == null
		or sprite.texture == null
		or sprite.texture.resource_path
		!= "res://assets/units/rogue/rogue_southeast.png"
	):
		_fail("The southeast direction did not use its authored texture.")
		return false

	return true


func _test_direction_stability(rogue: Rogue) -> bool:
	rogue._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	rogue._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(23.0)) * 10.0
	)

	if rogue.get_facing_direction() != Rogue.FacingDirection.EAST:
		_fail("Movement-facing flickered at an adjacent directional boundary.")
		return false

	rogue._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(30.0)) * 10.0
	)

	if rogue.get_facing_direction() != Rogue.FacingDirection.SOUTHEAST:
		_fail("Movement-facing did not leave hysteresis after a clear turn.")
		return false

	return true


func _test_idle_boss_facing(rogue: Rogue, boss: DummyBoss) -> bool:
	boss.global_position = Vector2.ZERO
	rogue.global_position = Vector2(0.0, 300.0)
	rogue._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	rogue._update_combat_facing_from_displacement(Vector2.ZERO)

	if rogue.get_facing_direction() != Rogue.FacingDirection.NORTH:
		_fail("A stationary rogue south of the boss did not face north.")
		return false

	rogue.global_position = Vector2(-300.0, 0.0)
	rogue._update_combat_facing_from_displacement(Vector2(0.01, 0.01))

	if rogue.get_facing_direction() != Rogue.FacingDirection.EAST:
		_fail("Tiny drift was treated as movement instead of idle boss-facing.")
		return false

	return true


func _test_displacement_and_recovery(rogue: Rogue, boss: DummyBoss) -> bool:
	boss.global_position = Vector2.ZERO
	rogue.global_position = Vector2(300.0, 0.0)
	rogue.command_attack(boss)
	rogue.start_forced_movement(Vector2(500.0, 300.0), 0.1)
	rogue._physics_process(0.05)

	if rogue.get_facing_direction() != Rogue.FacingDirection.SOUTHEAST:
		_fail("Forced displacement did not update movement-facing.")
		return false

	rogue._physics_process(0.05)
	rogue._physics_process(0.016)

	if rogue.get_facing_direction() != Rogue.FacingDirection.NORTHWEST:
		_fail("Attack-range recovery did not update movement-facing.")
		return false

	rogue.stop_action()
	rogue._physics_process(0.016)

	if rogue.get_facing_direction() != Rogue.FacingDirection.NORTHWEST:
		_fail("Stopping did not transition cleanly to boss-facing.")
		return false

	return true


func _test_sprite_alignment(rogue: Rogue) -> bool:
	var sprite := rogue.get_node_or_null("Sprite2D") as Sprite2D

	if sprite == null:
		_fail("The rogue combat sprite node is missing.")
		return false

	if not sprite.centered or sprite.position != Vector2.ZERO or sprite.scale != Vector2.ONE:
		_fail("Directional sprites do not share the expected centered, unscaled alignment.")
		return false

	for texture in Rogue.FACING_TEXTURES.values():
		if texture == null or texture.get_size() != Vector2(62.0, 90.0):
			_fail("A directional texture does not use the shared 62x90 canvas.")
			return false

	return true


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
