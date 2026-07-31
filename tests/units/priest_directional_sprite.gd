extends Node


class DummyBoss:
	extends Node2D
	pass


class DummyHealTarget:
	extends Node2D

	var health: int = 50
	var max_health: int = 100

	func is_alive() -> bool:
		return health > 0

	func get_current_health() -> int:
		return health

	func get_max_health() -> int:
		return max_health

	func get_incoming_healing_total(_excluded_healer: Node = null) -> int:
		return 0

	func receive_heal(amount: int, _source: Node = null, _ability_id: String = "") -> void:
		health = mini(health + amount, max_health)

	func get_display_name() -> String:
		return "Test Ally"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var priest_scene := load("res://scenes/units/priest.tscn") as PackedScene

	if priest_scene == null:
		_fail("The priest combat scene could not be loaded.")
		return

	var priest := priest_scene.instantiate() as Priest
	var boss := DummyBoss.new()
	add_child(boss)
	add_child(priest)
	priest.set_combat_facing_target(boss)

	if not _test_texture_contract(priest):
		return

	if not _test_direction_mapping(priest):
		return

	if not _test_direction_stability(priest):
		return

	if not _test_idle_boss_facing(priest, boss):
		return

	if not _test_displacement_and_heal_recovery(priest, boss):
		return

	if not _test_dash_facing(priest):
		return

	if not _test_sprite_alignment(priest):
		return

	print("Priest directional combat sprite regression test passed.")
	get_tree().quit(0)


func _test_texture_contract(priest: Priest) -> bool:
	if Priest.FACING_TEXTURE_PATHS.size() != 8:
		_fail("The priest directional texture map does not contain eight entries.")
		return false

	for direction in Priest.FACING_TEXTURE_PATHS:
		var texture_path: String = Priest.FACING_TEXTURE_PATHS[direction]

		if not ResourceLoader.exists(texture_path, "Texture2D"):
			_fail("A priest directional sprite is missing: " + texture_path)
			return false

		if priest.get_facing_texture(direction) == null:
			_fail("A priest directional sprite was not loaded: " + texture_path)
			return false

	return true


func _test_direction_mapping(priest: Priest) -> bool:
	priest._update_combat_facing_from_displacement(Vector2.UP * 10.0)

	if priest.get_facing_direction() != Priest.FacingDirection.NORTH:
		_fail("Northward movement did not select the north sprite.")
		return false

	priest._update_combat_facing_from_displacement(Vector2(10.0, 10.0))

	if priest.get_facing_direction() != Priest.FacingDirection.SOUTHEAST:
		_fail("Southeast movement did not select the southeast sprite.")
		return false

	var sprite := priest.get_node_or_null("Sprite2D") as Sprite2D

	if (
		sprite == null
		or sprite.texture == null
		or sprite.texture.resource_path
		!= "res://assets/units/priest/priest_southeast.png"
	):
		_fail("The southeast direction did not use its authored texture.")
		return false

	return true


func _test_direction_stability(priest: Priest) -> bool:
	priest._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	priest._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(23.0)) * 10.0
	)

	if priest.get_facing_direction() != Priest.FacingDirection.EAST:
		_fail("Movement-facing flickered at an adjacent directional boundary.")
		return false

	priest._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(30.0)) * 10.0
	)

	if priest.get_facing_direction() != Priest.FacingDirection.SOUTHEAST:
		_fail("Movement-facing did not leave hysteresis after a clear turn.")
		return false

	return true


func _test_idle_boss_facing(priest: Priest, boss: DummyBoss) -> bool:
	boss.global_position = Vector2.ZERO
	priest.global_position = Vector2(0.0, 300.0)
	priest._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	priest._update_combat_facing_from_displacement(Vector2.ZERO)

	if priest.get_facing_direction() != Priest.FacingDirection.NORTH:
		_fail("A stationary priest south of the boss did not face north.")
		return false

	priest.global_position = Vector2(-300.0, 0.0)
	priest._update_combat_facing_from_displacement(Vector2(0.01, 0.01))

	if priest.get_facing_direction() != Priest.FacingDirection.EAST:
		_fail("Tiny drift was treated as movement instead of idle boss-facing.")
		return false

	return true


func _test_displacement_and_heal_recovery(priest: Priest, boss: DummyBoss) -> bool:
	var heal_target := DummyHealTarget.new()
	add_child(heal_target)
	boss.global_position = Vector2.ZERO
	heal_target.global_position = Vector2.ZERO
	priest.global_position = Vector2(1200.0, 0.0)

	if not priest.command_heal(heal_target):
		_fail("The priest rejected the healing target used by the recovery test.")
		return false

	priest.start_forced_movement(Vector2(1700.0, 850.0), 0.1)
	priest._physics_process(0.05)

	if priest.get_facing_direction() != Priest.FacingDirection.SOUTHEAST:
		_fail("Forced displacement did not update movement-facing.")
		return false

	priest._physics_process(0.05)
	priest._physics_process(0.016)

	if priest.get_facing_direction() != Priest.FacingDirection.NORTHWEST:
		_fail("Heal-range recovery did not update movement-facing.")
		return false

	priest.stop_action()
	priest._physics_process(0.016)

	if priest.get_facing_direction() != Priest.FacingDirection.NORTHWEST:
		_fail("Stopping did not transition cleanly to boss-facing.")
		return false

	heal_target.queue_free()
	return true


func _test_dash_facing(priest: Priest) -> bool:
	priest.global_position = Vector2(-600.0, 0.0)
	priest.dodge_base_class = "priest"
	priest.initialize_dodge_profile()
	priest.command_dodge_to_position(Vector2(600.0, 0.0))
	priest._physics_process(0.05)

	if priest.get_facing_direction() != Priest.FacingDirection.EAST:
		_fail("Priest dash movement did not use its actual resolved displacement.")
		return false

	return true


func _test_sprite_alignment(priest: Priest) -> bool:
	var sprite := priest.get_node_or_null("Sprite2D") as Sprite2D

	if sprite == null:
		_fail("The priest combat sprite node is missing.")
		return false

	if not sprite.centered or sprite.position != Vector2.ZERO or sprite.scale != Vector2.ONE:
		_fail("Directional sprites do not share the expected centered, unscaled alignment.")
		return false

	for direction in Priest.FACING_TEXTURE_PATHS:
		var texture := priest.get_facing_texture(direction)

		if texture == null or texture.get_size() != Vector2(54.0, 107.0):
			_fail("A directional texture does not use the shared 54x107 canvas.")
			return false

	return true


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
