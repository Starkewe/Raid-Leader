extends Node

const MAX_RAID_SIZE: int = 20

const TUTORIAL_BOSS_CLEAVE_CLOSE_REGION := "cleave_close_region"
const TUTORIAL_BOSS_LONG_REGION_CONE := "long_region_cone"

const ABILITY_TARGET_REGION_CLOSE_CLEAVE := "target_region_close_cleave"
const ABILITY_TARGET_REGION_FULL_CONE := "target_region_full_cone"

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
	},
		TUTORIAL_BOSS_LONG_REGION_CONE: {
		"display_name": "Cone: Full Region",
		"description": "A tutorial boss that locks onto its target's region and fires through the full close, mid, and far lane.",
		"scene_path": "res://scenes/combat_scene.tscn",

		"boss_display_name": "Cone Trainer",
		"max_health": 500,
		"attack_range_units": 5.0,
		"combat_radius": 128.0,
		"attack_damage": 20,
		"attack_cooldown": 1.5,

		"ability_ids": [
			ABILITY_TARGET_REGION_FULL_CONE
		],

		"show_debug_region_guides": true,
		"show_debug_range_rings": true,
		"debug_max_range_units": 50.0
	}
}

const SPEECH_TO_TEXT_MODEL_BASE_EN := "base_en"
const SPEECH_TO_TEXT_MODEL_SMALL_EN := "small_en"
const SPEECH_TO_TEXT_MODEL_SMALL_EN_Q4_0 := "small_en_q4_0"

const WHISPER_MODELS_DIR := "E:/Raid Leader/tools/whisper.cpp/models"

var speech_to_text_model_catalog: Dictionary = {
	SPEECH_TO_TEXT_MODEL_BASE_EN: {
		"display_name": "Whisper Base English",
		"file_name": "ggml-base.en.bin",
		"description": "Fast baseline model. Good for quick prototype testing."
	},
	SPEECH_TO_TEXT_MODEL_SMALL_EN: {
		"display_name": "Whisper Small English",
		"file_name": "ggml-small.en.bin",
		"description": "Better accuracy than base.en, but larger and slower."
	},
	SPEECH_TO_TEXT_MODEL_SMALL_EN_Q4_0: {
		"display_name": "Whisper Small English Q4_0",
		"file_name": "ggml-small.en-q4_0.bin",
		"description": "Quantized small.en model. Good candidate for command recognition."
	}
}

var model_settings: Dictionary = {
	"speech_to_text_model": SPEECH_TO_TEXT_MODEL_BASE_EN,
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

func get_speech_to_text_model_options() -> Array:
	var options: Array = []

	for model_key in speech_to_text_model_catalog.keys():
		var model_data: Dictionary = speech_to_text_model_catalog[model_key]
		options.append([
			String(model_data.get("display_name", model_key)),
			String(model_key)
		])

	return options


func get_speech_to_text_model_data(model_key: String) -> Dictionary:
	if not speech_to_text_model_catalog.has(model_key):
		return speech_to_text_model_catalog[SPEECH_TO_TEXT_MODEL_BASE_EN].duplicate()

	return speech_to_text_model_catalog[model_key].duplicate()


func get_selected_speech_to_text_model_key() -> String:
	var model_key := String(model_settings.get("speech_to_text_model", SPEECH_TO_TEXT_MODEL_BASE_EN))

	if not speech_to_text_model_catalog.has(model_key):
		return SPEECH_TO_TEXT_MODEL_BASE_EN

	return model_key


func get_selected_speech_to_text_model_path() -> String:
	var model_key := get_selected_speech_to_text_model_key()
	var model_data := get_speech_to_text_model_data(model_key)
	var file_name := String(model_data.get("file_name", "ggml-base.en.bin"))

	return WHISPER_MODELS_DIR.path_join(file_name)


func get_selected_speech_to_text_model_display_name() -> String:
	var model_key := get_selected_speech_to_text_model_key()
	var model_data := get_speech_to_text_model_data(model_key)

	return String(model_data.get("display_name", model_key))
func get_model_setting(setting_name: String) -> String:
	return String(model_settings.get(setting_name, "default"))


func set_model_setting(setting_name: String, setting_value: String) -> void:
	if not model_settings.has(setting_name):
		print("Unknown model setting:", setting_name)
		return

	if setting_name == "speech_to_text_model":
		if not speech_to_text_model_catalog.has(setting_value):
			print("Unknown speech-to-text model:", setting_value)
			return

	model_settings[setting_name] = setting_value

func get_model_settings() -> Dictionary:
	return model_settings.duplicate()
