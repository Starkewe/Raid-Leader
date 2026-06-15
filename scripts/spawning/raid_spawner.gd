extends Node2D
class_name RaidSpawner

@export var columns: int = 5
@export var rows: int = 4
@export var cell_spacing: Vector2 = Vector2(150, 150)
@export var add_to_party_group: bool = true

var spawned_units: Array = []

func spawn_raid_from_roster() -> Array:
	clear_spawned_raid()

	var roster = GameState.get_roster()
	var spawn_index := 0
	var max_slots := columns * rows

	for unit_class in GameState.get_available_classes():
		if not roster.has(unit_class):
			continue

		var count := int(roster[unit_class])

		for i in range(count):
			if spawn_index >= max_slots:
				print("RaidSpawner has no more grid slots. Max slots:", max_slots)
				return spawned_units

			var unit = spawn_unit(unit_class, i + 1, spawn_index)

			if unit != null:
				spawned_units.append(unit)
				spawn_index += 1

	print("RaidSpawner spawned raid count:", spawned_units.size())
	return spawned_units

func spawn_unit(unit_class: String, unit_number: int, spawn_index: int) -> Node2D:
	var scene_path := GameState.get_unit_scene_path(unit_class)

	if scene_path == "":
		print("No scene path found for unit class:", unit_class)
		return null

	var packed_scene = load(scene_path)

	if packed_scene == null:
		print("Could not load unit scene:", scene_path)
		return null

	if not packed_scene is PackedScene:
		print("Loaded resource is not a PackedScene:", scene_path)
		return null

	var unit = packed_scene.instantiate()

	if not unit is Node2D:
		print("Spawned unit is not a Node2D:", unit_class)
		unit.queue_free()
		return null

	get_parent().add_child(unit)

	unit.name = unit_class + "_" + str(unit_number)
	unit.global_position = get_spawn_position(spawn_index)

	if unit.has_method("setup_unit_identity"):
		unit.setup_unit_identity(unit_class, unit_number)

	if add_to_party_group:
		unit.add_to_group("party_member")

	return unit

func get_spawn_position(spawn_index: int) -> Vector2:
	var column := spawn_index % columns
	var row := floori(float(spawn_index) / float(columns))

	var grid_width := float(columns - 1) * cell_spacing.x
	var grid_height := float(rows - 1) * cell_spacing.y

	var x := float(column) * cell_spacing.x - grid_width / 2.0
	var y := float(row) * cell_spacing.y - grid_height / 2.0

	return global_position + Vector2(x, y)

func clear_spawned_raid():
	for unit in spawned_units:
		if unit != null and is_instance_valid(unit):
			unit.queue_free()

	spawned_units.clear()
