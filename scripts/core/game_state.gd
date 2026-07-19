extends Node

const MAX_RAID_SIZE: int = 20
const SETTINGS_PATH := "user://raid_leader_settings.cfg"

const TUTORIAL_BOSS_CLEAVE_CLOSE_REGION := "cleave_close_region"
const TUTORIAL_BOSS_LONG_REGION_CONE := "long_region_cone"
const TUTORIAL_BOSS_TWIN_SWEEPING_PULL := "twin_sweeping_pull"
const ENCOUNTER_OGRE := "ogre"
const DEFAULT_ENCOUNTER_ID := ENCOUNTER_OGRE

const ABILITY_TARGET_REGION_CLOSE_CLEAVE := "target_region_close_cleave"
const ABILITY_TARGET_REGION_FULL_CONE := "target_region_full_cone"
const ABILITY_TWIN_SWEEPING_PULL := "twin_sweeping_pull"

const SPEECH_TO_TEXT_MODEL_BASE_EN := "base_en"
const SPEECH_TO_TEXT_MODEL_SMALL_EN := "small_en"
const SPEECH_TO_TEXT_MODEL_SMALL_EN_Q4_0 := "small_en_q4_0"

const UNIT_WARRIOR: UnitDefinition = preload("res://data/units/warrior.tres")
const UNIT_ROGUE: UnitDefinition = preload("res://data/units/rogue.tres")
const UNIT_MAGE: UnitDefinition = preload("res://data/units/mage.tres")
const UNIT_PRIEST: UnitDefinition = preload("res://data/units/priest.tres")

const ENCOUNTER_CLEAVE: EncounterDefinition = preload("res://data/encounters/cleave_close_region.tres")
const ENCOUNTER_CONE: EncounterDefinition = preload("res://data/encounters/full_region_cone.tres")
const ENCOUNTER_TWIN_SWEEP: EncounterDefinition = preload("res://data/encounters/twin_sweeping_pull.tres")
const ENCOUNTER_OGRE_DEFINITION: EncounterDefinition = preload("res://data/encounters/ogre.tres")

var selected_tutorial_boss_id: String = DEFAULT_ENCOUNTER_ID

var encounter_order: Array[String] = [
	TUTORIAL_BOSS_CLEAVE_CLOSE_REGION,
	TUTORIAL_BOSS_LONG_REGION_CONE,
	TUTORIAL_BOSS_TWIN_SWEEPING_PULL
]

var encounter_catalog: Dictionary = {
	ENCOUNTER_OGRE: ENCOUNTER_OGRE_DEFINITION,
	TUTORIAL_BOSS_CLEAVE_CLOSE_REGION: ENCOUNTER_CLEAVE,
	TUTORIAL_BOSS_LONG_REGION_CONE: ENCOUNTER_CONE,
	TUTORIAL_BOSS_TWIN_SWEEPING_PULL: ENCOUNTER_TWIN_SWEEP
}

var unit_class_order: Array[String] = [
	"Warrior",
	"Rogue",
	"Mage",
	"Priest"
]

var unit_catalog: Dictionary = {
	"Warrior": UNIT_WARRIOR,
	"Rogue": UNIT_ROGUE,
	"Mage": UNIT_MAGE,
	"Priest": UNIT_PRIEST
}

var role_catalog: Dictionary = {
	"tank": {
		"display_name": "Main Tank",
		"match_role": "tank",
		"selection": "first",
		"aliases": ["tank", "main tank"]
	},
	"offtank": {
		"display_name": "Off Tank",
		"match_role": "tank",
		"selection": "second",
		"aliases": ["offtank", "off tank"]
	},
	"tank_group": {
		"display_name": "Tanks",
		"match_role": "tank",
		"selection": "all",
		"aliases": ["tanks"]
	},
	"melee": {
		"display_name": "Melee",
		"match_role": "melee",
		"selection": "all",
		"aliases": ["melee"]
	},
	"melee_dps": {
		"display_name": "Melee DPS",
		"match_role": "melee_dps",
		"selection": "all",
		"aliases": ["melee dps"]
	},
	"dps": {
		"display_name": "DPS",
		"match_role": "dps",
		"selection": "all",
		"aliases": ["dps", "damage"]
	},
	"ranged_dps": {
		"display_name": "Ranged DPS",
		"match_role": "ranged_dps",
		"selection": "all",
		"aliases": ["ranged", "ranged dps"]
	},
	"caster": {
		"display_name": "Casters",
		"match_role": "caster",
		"selection": "all",
		"aliases": ["caster", "casters"]
	},
	"healer": {
		"display_name": "Healers",
		"match_role": "healer",
		"selection": "all",
		"aliases": ["healer", "healers"]
	}
}

var raid_roster: Dictionary = {
	"Warrior": 1,
	"Rogue": 1,
	"Mage": 1,
	"Priest": 1
}

var speech_to_text_model_catalog: Dictionary = {
	SPEECH_TO_TEXT_MODEL_BASE_EN: {
		"display_name": "Whisper Base English",
		"file_name": "ggml-base.en.bin",
		"description": "Fast baseline model for quick prototype testing."
	},
	SPEECH_TO_TEXT_MODEL_SMALL_EN: {
		"display_name": "Whisper Small English",
		"file_name": "ggml-small.en.bin",
		"description": "Higher accuracy than base.en, with a larger runtime cost."
	},
	SPEECH_TO_TEXT_MODEL_SMALL_EN_Q4_0: {
		"display_name": "Whisper Small English Q4_0",
		"file_name": "ggml-small.en-q4_0.bin",
		"description": "Quantized small.en model intended for command recognition."
	}
}

var model_settings: Dictionary = {
	"speech_to_text_model": SPEECH_TO_TEXT_MODEL_SMALL_EN_Q4_0
}

var voice_settings: Dictionary = {
	"whisper_cli_path_override": "",
	"whisper_models_dir_override": ""
}


func _ready() -> void:
	load_persistent_settings()


func get_available_classes() -> Array[String]:
	return unit_class_order.duplicate()


func get_unit_definition(unit_class: String) -> UnitDefinition:
	return unit_catalog.get(unit_class) as UnitDefinition


func get_unit_scene_path(unit_class: String) -> String:
	var definition := get_unit_definition(unit_class)

	if definition == null:
		push_warning("GameState is missing unit definition: " + unit_class)
		return ""

	return definition.scene_path


func get_display_name_for_class(unit_class: String) -> String:
	var definition := get_unit_definition(unit_class)
	return unit_class if definition == null else definition.display_name


func get_voice_class_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	for unit_class in unit_class_order:
		var definition := get_unit_definition(unit_class)

		if definition == null:
			continue

		entries.append({
			"unit_class": definition.unit_class,
			"aliases": definition.get_all_voice_aliases()
		})

	return entries


func get_role_data(role_name: String) -> Dictionary:
	var normalized := normalize_role_name(role_name)

	if not role_catalog.has(normalized):
		return {}

	return role_catalog[normalized].duplicate(true)


func get_role_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	for role_name in role_catalog.keys():
		var role_data: Dictionary = role_catalog[role_name]
		var aliases: Array = role_data.get("aliases", [])
		options.append({
			"role": String(role_name),
			"display_name": String(role_data.get("display_name", role_name)),
			"aliases": aliases.duplicate()
		})

	return options


func normalize_role_name(role_name: String) -> String:
	var normalized := role_name.to_lower().strip_edges().replace(" ", "_")

	for catalog_role in role_catalog.keys():
		if normalized == String(catalog_role):
			return normalized

		var aliases: Array = role_catalog[catalog_role].get("aliases", [])

		for alias in aliases:
			if normalized == String(alias).to_lower().replace(" ", "_"):
				return String(catalog_role)

	return normalized


func get_roster() -> Dictionary:
	return raid_roster.duplicate()


func get_class_count(unit_class: String) -> int:
	return int(raid_roster.get(unit_class, 0))


func set_class_count(unit_class: String, count: int) -> void:
	if not unit_catalog.has(unit_class):
		push_warning("Cannot set count for unknown unit class: " + unit_class)
		return

	var current_count := get_class_count(unit_class)
	var total_without_class := get_total_count() - current_count
	var max_allowed_for_class := MAX_RAID_SIZE - total_without_class

	raid_roster[unit_class] = clampi(count, 0, max_allowed_for_class)
	save_persistent_settings()


func add_class(unit_class: String) -> void:
	if get_total_count() < MAX_RAID_SIZE:
		set_class_count(unit_class, get_class_count(unit_class) + 1)


func remove_class(unit_class: String) -> void:
	set_class_count(unit_class, get_class_count(unit_class) - 1)


func get_total_count() -> int:
	var total := 0

	for count in raid_roster.values():
		total += int(count)

	return total


func has_valid_team() -> bool:
	return get_total_count() > 0


func reset_default_roster() -> void:
	raid_roster = {
		"Warrior": 1,
		"Rogue": 1,
		"Mage": 1,
		"Priest": 1
	}
	save_persistent_settings()


func get_tutorial_boss_ids() -> Array[String]:
	return encounter_order.duplicate()


func get_encounter_definition(encounter_id: String) -> EncounterDefinition:
	return encounter_catalog.get(encounter_id) as EncounterDefinition


func get_tutorial_boss_data(boss_id: String) -> Dictionary:
	var definition := get_encounter_definition(boss_id)

	if definition == null:
		return {}

	return {
		"display_name": definition.display_name,
		"description": definition.description,
		"scene_path": definition.scene_path,
		"boss_display_name": definition.boss_display_name,
		"max_health": definition.max_health,
		"attack_range_units": definition.attack_range_units,
		"combat_radius": definition.combat_radius,
		"attack_damage": definition.attack_damage,
		"attack_cooldown": definition.attack_cooldown,
		"ability_ids": definition.get_ability_ids(),
		"show_debug_region_guides": definition.show_debug_region_guides,
		"show_debug_range_rings": definition.show_debug_range_rings,
		"debug_max_range_units": definition.debug_max_range_units
	}


func set_selected_tutorial_boss(boss_id: String) -> void:
	if get_encounter_definition(boss_id) == null:
		push_warning("Unknown encounter id: " + boss_id)
		return

	selected_tutorial_boss_id = boss_id


func select_default_encounter() -> void:
	selected_tutorial_boss_id = DEFAULT_ENCOUNTER_ID


func get_selected_tutorial_boss_id() -> String:
	return selected_tutorial_boss_id


func get_selected_encounter_definition() -> EncounterDefinition:
	return get_encounter_definition(selected_tutorial_boss_id)


func get_selected_tutorial_boss_data() -> Dictionary:
	return get_tutorial_boss_data(selected_tutorial_boss_id)


func get_selected_tutorial_scene_path() -> String:
	var definition := get_selected_encounter_definition()
	return "res://scenes/combat_scene.tscn" if definition == null else definition.scene_path


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
		model_key = SPEECH_TO_TEXT_MODEL_BASE_EN

	return speech_to_text_model_catalog[model_key].duplicate()


func get_selected_speech_to_text_model_key() -> String:
	var model_key := String(model_settings.get("speech_to_text_model", SPEECH_TO_TEXT_MODEL_BASE_EN))
	return model_key if speech_to_text_model_catalog.has(model_key) else SPEECH_TO_TEXT_MODEL_BASE_EN


func get_default_whisper_models_dir() -> String:
	return "res://tools/whisper.cpp/models"


func get_default_whisper_cli_path() -> String:
	match OS.get_name():
		"Windows":
			return "res://tools/whisper.cpp/build/bin/Release/whisper-cli.exe"
		"macOS":
			return "res://tools/whisper.cpp/build/bin/whisper-cli"
		_:
			return "res://tools/whisper.cpp/build/bin/whisper-cli"


func get_whisper_models_dir() -> String:
	var override_path := String(voice_settings.get("whisper_models_dir_override", "")).strip_edges()
	return get_default_whisper_models_dir() if override_path.is_empty() else override_path


func get_whisper_cli_path() -> String:
	var override_path := String(voice_settings.get("whisper_cli_path_override", "")).strip_edges()
	return get_default_whisper_cli_path() if override_path.is_empty() else override_path


func get_selected_speech_to_text_model_path() -> String:
	var model_data := get_speech_to_text_model_data(get_selected_speech_to_text_model_key())
	return get_whisper_models_dir().path_join(String(model_data.get("file_name", "ggml-base.en.bin")))


func get_selected_speech_to_text_model_display_name() -> String:
	var model_key := get_selected_speech_to_text_model_key()
	return String(get_speech_to_text_model_data(model_key).get("display_name", model_key))


func get_model_setting(setting_name: String) -> String:
	return String(model_settings.get(setting_name, ""))


func set_model_setting(setting_name: String, setting_value: String) -> void:
	if setting_name != "speech_to_text_model":
		push_warning("Unknown model setting: " + setting_name)
		return

	if not speech_to_text_model_catalog.has(setting_value):
		push_warning("Unknown speech-to-text model: " + setting_value)
		return

	model_settings[setting_name] = setting_value
	save_persistent_settings()


func get_model_settings() -> Dictionary:
	return model_settings.duplicate()


func set_voice_path_override(setting_name: String, path: String) -> void:
	if not voice_settings.has(setting_name):
		push_warning("Unknown voice path setting: " + setting_name)
		return

	voice_settings[setting_name] = path.strip_edges()
	save_persistent_settings()


func load_persistent_settings() -> void:
	var config := ConfigFile.new()

	if config.load(SETTINGS_PATH) != OK:
		return

	var saved_model := String(config.get_value(
		"voice",
		"speech_to_text_model",
		model_settings["speech_to_text_model"]
	))

	if speech_to_text_model_catalog.has(saved_model):
		model_settings["speech_to_text_model"] = saved_model

	for setting_name in voice_settings.keys():
		voice_settings[setting_name] = String(config.get_value(
			"voice",
			setting_name,
			voice_settings[setting_name]
		))

	for unit_class in unit_class_order:
		raid_roster[unit_class] = clampi(
			int(config.get_value("roster", unit_class, raid_roster.get(unit_class, 0))),
			0,
			MAX_RAID_SIZE
		)

	trim_roster_to_maximum()


func save_persistent_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("voice", "speech_to_text_model", get_selected_speech_to_text_model_key())

	for setting_name in voice_settings.keys():
		config.set_value("voice", setting_name, voice_settings[setting_name])

	for unit_class in unit_class_order:
		config.set_value("roster", unit_class, get_class_count(unit_class))

	var error := config.save(SETTINGS_PATH)

	if error != OK:
		push_warning("Could not save Raid Leader settings. Error: " + str(error))


func trim_roster_to_maximum() -> void:
	var remaining := MAX_RAID_SIZE

	for unit_class in unit_class_order:
		var count := mini(get_class_count(unit_class), remaining)
		raid_roster[unit_class] = count
		remaining -= count
