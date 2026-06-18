extends Node

const MAX_RAID_SIZE: int = 20

const TUTORIAL_BOSS_CLEAVE_CLOSE_REGION := "cleave_close_region"

const ABILITY_TARGET_REGION_CLOSE_CLEAVE := "target_region_close_cleave"

var selected_tutorial_boss_id: String = TUTORIAL_BOSS_CLEAVE_CLOSE_REGION

var tutorial_boss_catalog: Dictionary = {
	TUTORIAL_BOSS_CLEAVE_CLOSE_REGION: {
		"display_name": "Cleave: Close Region",
		"description": "A basic tutorial boss that cleaves the close-range region matching its current target.",
		"scene_path": "res://scenes/combat_scene.tscn",

		"boss_display_name": "Cleave Trainer",
		"max_health": 500,
		"attack_range_units": 5.0,
		"combat_radius": 128.0,
		"attack_damage": 20,
		"attack_cooldown": 1.5,

		"ability_ids": [
		ABILITY_TARGET_REGION_CLOSE_CLEAVE
		],

		"show_debug_region_guides": true,
		"show_debug_range_rings": true,
		"debug_max_range_units": 50.0
	}
}

var model_settings: Dictionary = {
	"speech_to_text_model": "whisper_local_default",
	"command_parser_model": "local_command_parser_default",
	"raid_leader_model": "local_raid_leader_default"
}
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
func get_tutorial_boss_ids() -> Array[String]:
	var ids: Array[String] = []

	for boss_id in tutorial_boss_catalog.keys():
		ids.append(String(boss_id))

	return ids


func get_tutorial_boss_data(boss_id: String) -> Dictionary:
	if not tutorial_boss_catalog.has(boss_id):
		return {}

	return tutorial_boss_catalog[boss_id].duplicate()


func set_selected_tutorial_boss(boss_id: String) -> void:
	if not tutorial_boss_catalog.has(boss_id):
		print("Unknown tutorial boss id:", boss_id)
		return

	selected_tutorial_boss_id = boss_id


func get_selected_tutorial_boss_id() -> String:
	return selected_tutorial_boss_id


func get_selected_tutorial_boss_data() -> Dictionary:
	return get_tutorial_boss_data(selected_tutorial_boss_id)


func get_selected_tutorial_scene_path() -> String:
	var boss_data := get_selected_tutorial_boss_data()

	if boss_data.is_empty():
		return "res://scenes/combat_scene.tscn"

	return String(boss_data.get("scene_path", "res://scenes/combat_scene.tscn"))


func get_model_setting(setting_name: String) -> String:
	return String(model_settings.get(setting_name, "default"))


func set_model_setting(setting_name: String, setting_value: String) -> void:
	if not model_settings.has(setting_name):
		print("Unknown model setting:", setting_name)
		return

	model_settings[setting_name] = setting_value


func get_model_settings() -> Dictionary:
	return model_settings.duplicate()
