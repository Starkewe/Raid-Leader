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
	var mage_scene := load("res://scenes/units/mage.tscn") as PackedScene

	if mage_scene == null:
		_fail("The mage combat scene could not be loaded.")
		return

	var mage := mage_scene.instantiate() as Mage
	var boss := DummyBoss.new()
	add_child(boss)
	add_child(mage)
	mage.set_combat_facing_target(boss)

	if not _test_direction_mapping(mage):
		return

	if not _test_direction_stability(mage):
		return

	if not _test_idle_boss_facing(mage, boss):
		return

	if not _test_displacement_and_recovery(mage, boss):
		return

	if not _test_teleport_facing(mage):
		return

	if not _test_sprite_alignment(mage):
		return

	print("Mage directional combat sprite regression test passed.")
	get_tree().quit(0)


func _test_direction_mapping(mage: Mage) -> bool:
	mage._update_combat_facing_from_displacement(Vector2.UP * 10.0)

	if mage.get_facing_direction() != Mage.FacingDirection.NORTH:
		_fail("Northward movement did not select the north sprite.")
		return false

	mage._update_combat_facing_from_displacement(Vector2(10.0, 10.0))

	if mage.get_facing_direction() != Mage.FacingDirection.SOUTHEAST:
		_fail("Southeast movement did not select the southeast sprite.")
		return false

	var sprite := mage.get_node_or_null("Sprite2D") as Sprite2D

	if (
		sprite == null
		or sprite.texture == null
		or sprite.texture.resource_path
		!= "res://assets/units/mage/mage_southeast.png"
	):
		_fail("The southeast direction did not use its authored texture.")
		return false

	return true


func _test_direction_stability(mage: Mage) -> bool:
	mage._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	mage._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(23.0)) * 10.0
	)

	if mage.get_facing_direction() != Mage.FacingDirection.EAST:
		_fail("Movement-facing flickered at an adjacent directional boundary.")
		return false

	mage._update_combat_facing_from_displacement(
		Vector2.RIGHT.rotated(deg_to_rad(30.0)) * 10.0
	)

	if mage.get_facing_direction() != Mage.FacingDirection.SOUTHEAST:
		_fail("Movement-facing did not leave hysteresis after a clear turn.")
		return false

	return true


func _test_idle_boss_facing(mage: Mage, boss: DummyBoss) -> bool:
	boss.global_position = Vector2.ZERO
	mage.global_position = Vector2(0.0, 300.0)
	mage._update_combat_facing_from_displacement(Vector2.RIGHT * 10.0)
	mage._update_combat_facing_from_displacement(Vector2.ZERO)

	if mage.get_facing_direction() != Mage.FacingDirection.NORTH:
		_fail("A stationary mage south of the boss did not face north.")
		return false

	mage.global_position = Vector2(-300.0, 0.0)
	mage._update_combat_facing_from_displacement(Vector2(0.01, 0.01))

	if mage.get_facing_direction() != Mage.FacingDirection.EAST:
		_fail("Tiny drift was treated as movement instead of idle boss-facing.")
		return false

	return true


func _test_displacement_and_recovery(mage: Mage, boss: DummyBoss) -> bool:
	boss.global_position = Vector2.ZERO
	mage.global_position = Vector2(1200.0, 0.0)
	mage.command_attack(boss)
	mage.start_forced_movement(Vector2(1700.0, 850.0), 0.1)
	mage._physics_process(0.05)

	if mage.get_facing_direction() != Mage.FacingDirection.SOUTHEAST:
		_fail("Forced displacement did not update movement-facing.")
		return false

	mage._physics_process(0.05)
	mage._physics_process(0.016)

	if mage.get_facing_direction() != Mage.FacingDirection.NORTHWEST:
		_fail(
			"Cast-range recovery did not update movement-facing. "
			+ "direction=%s position=%s velocity=%s range=%s active=%s"
			% [
				mage.get_facing_direction(),
				mage.global_position,
				mage.velocity,
				mage.get_range_units_to_node(boss),
				mage.has_valid_cast_target(),
			]
		)
		return false

	mage.stop_action()
	mage._physics_process(0.016)

	if mage.get_facing_direction() != Mage.FacingDirection.NORTHWEST:
		_fail("Stopping did not transition cleanly to boss-facing.")
		return false

	return true


func _test_teleport_facing(mage: Mage) -> bool:
	mage.global_position = Vector2(-600.0, 0.0)
	mage.dodge_base_class = "mage"
	mage.initialize_dodge_profile()
	mage.command_dodge_to_position(Vector2(600.0, 0.0))

	if mage.get_facing_direction() != Mage.FacingDirection.EAST:
		_fail("Mage teleport did not use its actual resolved displacement.")
		return false

	return true


func _test_sprite_alignment(mage: Mage) -> bool:
	var sprite := mage.get_node_or_null("Sprite2D") as Sprite2D

	if sprite == null:
		_fail("The mage combat sprite node is missing.")
		return false

	if not sprite.centered or sprite.position != Vector2.ZERO or sprite.scale != Vector2.ONE:
		_fail("Directional sprites do not share the expected centered, unscaled alignment.")
		return false

	for texture in Mage.FACING_TEXTURES.values():
		if texture == null or texture.get_size() != Vector2(53.0, 100.0):
			_fail("A directional texture does not use the shared 53x100 canvas.")
			return false

	return true


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
