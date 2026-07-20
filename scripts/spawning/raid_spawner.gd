extends Node2D

class_name RaidSpawner

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

@export var columns: int = 5
@export var rows: int = 4
@export var cell_spacing: Vector2 = Vector2(150, 150)
@export var add_to_party_group: bool = true

var spawned_units: Array[Node2D] = []
var scene_cache: Dictionary = {}


func spawn_raid_from_roster() -> Array[Node2D]:
	clear_spawned_raid()

	if SceneFlow.is_campaign_combat():
		return spawn_campaign_raid()

	var roster: Dictionary = GameState.get_roster()
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

			var unit := spawn_unit(unit_class, i + 1, spawn_index)

			if unit != null:
				spawned_units.append(unit)
				spawn_index += 1

	print("RaidSpawner spawned raid count:", spawned_units.size())

	return spawned_units


func spawn_campaign_raid() -> Array[Node2D]:
	var active_members := CampaignState.get_active_members()
	var class_ordinals: Dictionary = {}
	var max_slots := columns * rows

	for spawn_index in range(active_members.size()):
		if spawn_index >= max_slots:
			push_warning("RaidSpawner has no more grid slots. Max slots: " + str(max_slots))
			break

		var member: Dictionary = active_members[spawn_index]
		var unit_class := String(member.get("unit_class", ""))
		var class_ordinal := int(class_ordinals.get(unit_class, 0)) + 1
		class_ordinals[unit_class] = class_ordinal
		var unit := spawn_unit(unit_class, class_ordinal, spawn_index, member)

		if unit != null:
			spawned_units.append(unit)

	apply_campaign_formation_positions()
	print("RaidSpawner spawned campaign raid count:", spawned_units.size())
	return spawned_units


func spawn_unit(
	unit_class: String,
	unit_number: int,
	spawn_index: int,
	member_data: Dictionary = {}
) -> Node2D:
	var scene_path: String = GameState.get_unit_scene_path(unit_class)

	if scene_path == "":
		print("No scene path found for unit class:", unit_class)
		return null

	var packed_scene := get_unit_packed_scene(scene_path)

	if packed_scene == null:
		return null

	var unit := packed_scene.instantiate()

	if not unit is Node2D:
		print("Spawned unit is not a Node2D:", unit_class)
		unit.queue_free()
		return null

	var spawn_parent := get_parent()

	if spawn_parent == null:
		print("RaidSpawner cannot spawn unit because it has no parent.")
		unit.queue_free()
		return null

	var definition := GameState.get_unit_definition(unit_class)

	if unit.has_method("configure_from_definition"):
		unit.configure_from_definition(definition)

	spawn_parent.add_child(unit)

	unit.name = (
		String(member_data.get("member_id", ""))
		if not member_data.is_empty()
		else unit_class + "_" + str(unit_number)
	)
	unit.global_position = get_spawn_position(spawn_index)

	if not member_data.is_empty() and unit.has_method("setup_campaign_identity"):
		unit.setup_campaign_identity(member_data, unit_number)
	elif unit.has_method("setup_unit_identity"):
		unit.setup_unit_identity(unit_class, unit_number)

	if add_to_party_group:
		unit.add_to_group("party_member")

	return unit


func apply_campaign_formation_positions() -> void:
	var boss := get_node_or_null("../Boss")

	if boss == null or not is_instance_valid(boss):
		return

	var formation := CampaignState.get_formation()
	var placements: Dictionary = formation.get("placements", {})
	var units_by_slot: Dictionary = {}

	for unit in spawned_units:
		if unit == null or not is_instance_valid(unit) or not unit.has_method("get_member_id"):
			continue

		var member_id := String(unit.get_member_id())
		var placement: Dictionary = placements.get(member_id, {})
		var region := String(placement.get("region", "south"))
		var range_name := String(placement.get("range", "mid"))
		var slot_key := MovementSlotResolverScript.get_mini_region_key(region, range_name)

		if not units_by_slot.has(slot_key):
			units_by_slot[slot_key] = {
				"region": region,
				"range": range_name,
				"units": []
			}

		var slot_entry: Dictionary = units_by_slot[slot_key]
		var slot_units: Array = slot_entry.get("units", [])
		slot_units.append(unit)
		slot_entry["units"] = slot_units
		units_by_slot[slot_key] = slot_entry

	for slot_data_value in units_by_slot.values():
		var slot_data: Dictionary = slot_data_value
		var units: Array = slot_data.get("units", [])
		var positions := MovementSlotResolverScript.get_slot_formation_positions(
			boss,
			String(slot_data.get("region", "south")),
			String(slot_data.get("range", "mid")),
			units.size(),
			30.0
		)

		for index in range(units.size()):
			if index < positions.size():
				units[index].global_position = positions[index]


func get_unit_packed_scene(scene_path: String) -> PackedScene:
	if scene_cache.has(scene_path):
		return scene_cache[scene_path] as PackedScene

	var loaded_resource: Resource = load(scene_path)

	if loaded_resource == null:
		print("Could not load unit scene:", scene_path)
		return null

	if not loaded_resource is PackedScene:
		print("Loaded resource is not a PackedScene:", scene_path)
		return null

	var packed_scene := loaded_resource as PackedScene
	scene_cache[scene_path] = packed_scene

	return packed_scene


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
