extends Node

const MAX_RAID_SIZE: int = 20

var unit_class_order: Array[String] = [
	"Warrior",
	"Rogue",
	"Mage",
	"Priest"
]

var unit_catalog: Dictionary = {
	"Warrior": {
		"display_name": "Warrior",
		"scene_path": "res://scenes/units/warrior.tscn"
	},
	"Rogue": {
		"display_name": "Rogue",
		"scene_path": "res://scenes/units/rogue.tscn"
	},
	"Mage": {
		"display_name": "Mage",
		"scene_path": "res://scenes/units/mage.tscn"
	},
	"Priest": {
		"display_name": "Priest",
		"scene_path": "res://scenes/units/priest.tscn"
	}
}

var raid_roster: Dictionary = {
	"Warrior": 1,
	"Rogue": 1,
	"Mage": 1,
	"Priest": 1
}

func get_available_classes() -> Array[String]:
	return unit_class_order.duplicate()

func get_roster() -> Dictionary:
	return raid_roster.duplicate()

func get_unit_scene_path(unit_class: String) -> String:
	if not unit_catalog.has(unit_class):
		print("GameState missing unit catalog entry for:", unit_class)
		return ""

	return String(unit_catalog[unit_class]["scene_path"])

func get_display_name_for_class(unit_class: String) -> String:
	if not unit_catalog.has(unit_class):
		return unit_class

	return String(unit_catalog[unit_class]["display_name"])

func get_class_count(unit_class: String) -> int:
	if not raid_roster.has(unit_class):
		return 0

	return int(raid_roster[unit_class])

func set_class_count(unit_class: String, count: int):
	if not unit_catalog.has(unit_class):
		print("Cannot set count. Unknown unit class:", unit_class)
		return

	count = max(count, 0)

	var current_count = get_class_count(unit_class)
	var total_without_class = get_total_count() - current_count
	var max_allowed_for_class = MAX_RAID_SIZE - total_without_class

	raid_roster[unit_class] = clamp(count, 0, max_allowed_for_class)

func add_class(unit_class: String):
	if get_total_count() >= MAX_RAID_SIZE:
		return

	set_class_count(unit_class, get_class_count(unit_class) + 1)

func remove_class(unit_class: String):
	set_class_count(unit_class, get_class_count(unit_class) - 1)

func get_total_count() -> int:
	var total := 0

	for unit_class in raid_roster.keys():
		total += int(raid_roster[unit_class])

	return total

func has_valid_team() -> bool:
	return get_total_count() > 0

func reset_default_roster():
	raid_roster = {
		"Warrior": 1,
		"Rogue": 1,
		"Mage": 1,
		"Priest": 1
	}
