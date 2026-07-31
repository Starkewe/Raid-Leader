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
	var warrior_scene := load("res://scenes/units/warrior.tscn") as PackedScene

	if warrior_scene == null:
		_fail("The warrior combat scene could not be loaded.")
		return

	var warrior := warrior_scene.instantiate() as Warrior
	var boss := DummyBoss.new()
	add_child(boss)
	add_child(warrior)
	warrior.set_combat_facing_target(boss)

	if not _test_texture_contract(warrior):
		return

	if not _test_direction_mapping(warrior):
		return

	if not _test_direction_stability(warrior):
		return

	if not _test_idle_boss_facing(warrior, boss):
		return

	if not _test_displacement_and_recovery(warrior, boss):
		return

	if not _test_sprite_alignment(warrior):
		return

	print("Warrior directional combat sprite regression test passed.")
	get_tree().quit(0)


func _test_texture_contract(warrior: Warrior) -> bool:
	if Warrior.FACING_TEXTURE_PATHS.size() != 8:
		_fail("The warrior directional texture map does not contain eight entries.")
		return false

	for direction in Warrior.FACING_TEXTURE_PATHS:
		var texture_path: String = Warrior.FACING_TEXTURE_PATHS[direction]

		if not ResourceLoader.exists(texture_path, "Texture2D"):
			_fail("A warrior directional sprite is missing: " + texture_path)
			return false

		if warrior.get_facing_texture(direction) == null:
			_fail("A warrior directional sprite was not loaded: " + texture_path)
			return false

	return true


func _test_direction_mapping(warrior: Warrior) -> bool:
	warrior._update_combat_facing_from_displacement(Vector2.UP * 10.0)

	if warrior.get_facing_direction() != Warrior.FacingDirection.NORTH:
		_fail("Northward movement did not select the north sprite.")
		return false

	warrior._update_combat_facing_from_displacement(Vector2(10.0, 10.0))

	if warrior.get_facing_direction() != Warrior.FacingDirection.SOUTHEAST:
		_fail("Southeast movement did not select the southeast sprite.")
		return false

	var sprite := warrior.get_node_or_null("Sprite2D") as Sprite2D

	if (
		sprite == null
		or sprite.texture == null
		or sprite.texture.resource_path
		!= "res://assets/units/warrior/warrior_southeast.png"
	):
		_fail("The southeast direction did not use its authored texture.")
		return false

	return true


func _test_direction_stability(warrior: Warrior) -> bool:
	warrior._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	warrior._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(23.0)) * 10.0
	)

	if warrior.get_facing_direction() != Warrior.FacingDirection.EAST:
		_fail("Movement-facing flickered at an adjacent directional boundary.")
		return false

	warrior._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(30.0)) * 10.0
	)

	if warrior.get_facing_direction() != Warrior.FacingDirection.SOUTHEAST:
		_fail("Movement-facing did not leave hysteresis after a clear turn.")
		return false

	return true


func _test_idle_boss_facing(warrior: Warrior, boss: DummyBoss) -> bool:
	boss.global_position = Vector2.ZERO
	warrior.global_position = Vector2(0.0, 300.0)
	warrior._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	warrior._update_combat_facing_from_displacement(Vector2.ZERO)

	if warrior.get_facing_direction() != Warrior.FacingDirection.NORTH:
		_fail("A stationary warrior south of the boss did not face north.")
		return false

	warrior.global_position = Vector2(-300.0, 0.0)
	warrior._update_combat_facing_from_displacement(Vector2(0.01, 0.01))

	if warrior.get_facing_direction() != Warrior.FacingDirection.EAST:
		_fail("Tiny drift was treated as movement instead of idle boss-facing.")
		return false

	return true


func _test_displacement_and_recovery(warrior: Warrior, boss: DummyBoss) -> bool:
	boss.global_position = Vector2.ZERO
	warrior.global_position = Vector2(300.0, 0.0)
	warrior.command_attack(boss)
	warrior.start_forced_movement(Vector2(500.0, 300.0), 0.1)
	warrior._physics_process(0.05)

	if warrior.get_facing_direction() != Warrior.FacingDirection.SOUTHEAST:
		_fail("Forced displacement did not update movement-facing.")
		return false

	warrior._physics_process(0.05)
	warrior._physics_process(0.016)

	if warrior.get_facing_direction() != Warrior.FacingDirection.NORTHWEST:
		_fail("Attack-range recovery did not update movement-facing.")
		return false

	warrior.stop_action()
	warrior._physics_process(0.016)

	if warrior.get_facing_direction() != Warrior.FacingDirection.NORTHWEST:
		_fail("Stopping did not transition cleanly to boss-facing.")
		return false

	return true


func _test_sprite_alignment(warrior: Warrior) -> bool:
	var sprite := warrior.get_node_or_null("Sprite2D") as Sprite2D

	if sprite == null:
		_fail("The warrior combat sprite node is missing.")
		return false

	if not sprite.centered or sprite.position != Vector2.ZERO or sprite.scale != Vector2.ONE:
		_fail("Directional sprites do not share the expected centered, unscaled alignment.")
		return false

	for direction in Warrior.FACING_TEXTURE_PATHS:
		var texture := warrior.get_facing_texture(direction)

		if texture == null or texture.get_size() != Vector2(60.0, 97.0):
			_fail("A directional texture does not use the shared 60x97 canvas.")
			return false

	return true


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
