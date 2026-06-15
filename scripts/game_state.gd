extends Node

const MAX_RAID_SIZE: int = 20

var raid_roster: Dictionary = {
	"Warrior": 1,
	"Rogue": 1,
	"Mage": 1,
	"Priest": 1
}

func get_roster() -> Dictionary:
	return raid_roster.duplicate()

func get_class_count(unit_class: String) -> int:
	if not raid_roster.has(unit_class):
		return 0

	return int(raid_roster[unit_class])

func set_class_count(unit_class: String, count: int):
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
