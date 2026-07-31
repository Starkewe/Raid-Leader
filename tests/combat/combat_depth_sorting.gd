extends Node


const COMBAT_SCENE_PATH := "res://scenes/combat_scene.tscn"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(COMBAT_SCENE_PATH) as PackedScene

	if packed_scene == null:
		_fail("The combat scene could not be loaded.")
		return

	var combat_world := packed_scene.instantiate() as Node2D

	if combat_world == null:
		_fail("The combat scene root is not a Node2D.")
		return

	if not combat_world.y_sort_enabled:
		combat_world.queue_free()
		_fail("The combat world does not have Y-sorting enabled.")
		return

	var boss := combat_world.get_node_or_null("Boss") as Node2D
	var raid_spawner := combat_world.get_node_or_null("RaidSpawner") as RaidSpawner
	var ui := combat_world.get_node_or_null("UI") as CanvasLayer
	var movement_visualizer := combat_world.get_node_or_null(
		"MovementDestinationVisualizer"
	) as Node2D

	if boss == null or boss.get_parent() != combat_world:
		combat_world.queue_free()
		_fail("The boss does not participate directly in combat-world Y-sorting.")
		return

	if raid_spawner == null:
		combat_world.queue_free()
		_fail("The combat scene is missing its raid spawner.")
		return

	var test_raider := Node2D.new()
	test_raider.name = "DepthSortTestRaider"
	combat_world.add_child(test_raider)

	if test_raider.get_parent() != boss.get_parent():
		combat_world.queue_free()
		_fail("Raiders and the boss do not share the Y-sorted combat world.")
		return

	if test_raider.z_index != boss.z_index:
		combat_world.queue_free()
		_fail("Raiders and the boss are not on the same Y-sort Z layer.")
		return

	boss.position = Vector2(0.0, 100.0)
	test_raider.position = Vector2(0.0, 200.0)

	if test_raider.position.y <= boss.position.y:
		combat_world.queue_free()
		_fail("The south-over-north depth test was not configured correctly.")
		return

	if ui == null:
		combat_world.queue_free()
		_fail("Combat UI is no longer isolated in a CanvasLayer.")
		return

	if movement_visualizer == null or movement_visualizer.z_index >= boss.z_index:
		combat_world.queue_free()
		_fail("Movement paths no longer remain below combatants.")
		return

	combat_world.queue_free()
	print("Combat Y-depth sorting regression test passed.")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
