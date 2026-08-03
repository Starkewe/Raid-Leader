extends Node

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene_path in [
		"res://scenes/units/warrior.tscn",
		"res://scenes/units/priest.tscn",
		"res://scenes/units/rogue.tscn",
		"res://scenes/units/mage.tscn"
	]:
		_validate_scene(String(scene_path))

	if failures.is_empty():
		print("Raid death sprite visibility regression test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)

	get_tree().quit(1)


func _validate_scene(scene_path: String) -> void:
	var packed_scene := load(scene_path) as PackedScene

	if packed_scene == null:
		failures.append("Could not load " + scene_path)
		return

	var unit := packed_scene.instantiate() as BaseCombatUnit

	if unit == null:
		failures.append("Could not instantiate " + scene_path)
		return

	add_child(unit)
	var sprite := unit.get_node_or_null("Sprite2D") as CanvasItem

	if sprite == null:
		failures.append(scene_path + " is missing its combat Sprite2D.")
		unit.queue_free()
		return

	sprite.visible = true
	unit.die()
	_expect(
		unit.is_dead and not sprite.visible,
		scene_path + " did not hide its sprite on death."
	)

	unit.reset_unit(Vector2.ZERO)
	_expect(
		not unit.is_dead and sprite.visible,
		scene_path + " did not restore its sprite on reset."
	)

	unit.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
