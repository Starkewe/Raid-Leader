extends RefCounted
class_name CampaignSaveManager

const SAVE_DIRECTORY := "user://raid_leader_saves"
const AUTOSAVE_PATH := SAVE_DIRECTORY + "/autosave.json"
const MANUAL_PREFIX := "manual_"
const INVALID_FILENAME_CHARACTERS := ["<", ">", ":", '"', "/", "\\", "|", "?", "*"]
const RESERVED_FILENAME_STEMS := [
	"con", "prn", "aux", "nul",
	"com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
	"lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
]


static func has_any_save() -> bool:
	return not list_saves().is_empty()


static func has_current_save() -> bool:
	# Compatibility alias for the existing main-menu call site.
	return has_any_save()


static func start_new_campaign(seed_override: int = 0) -> void:
	# Starting a campaign changes memory only. It neither overwrites nor manufactures a save.
	# Tests and developer tools may provide a seed; normal New Game generates one.
	CampaignState.reset_campaign(true, seed_override)


static func create_manual_save(display_name: String, overwrite: bool = false) -> Dictionary:
	var validation := validate_save_name(display_name)

	if not bool(validation.get("valid", false)):
		return {
			"ok": false,
			"status": "invalid",
			"message": String(validation.get("message", "Enter a valid save name.")),
		}

	_ensure_save_directory()
	var normalized_name := String(validation.get("normalized_name", ""))
	var path := _manual_path(normalized_name)

	if FileAccess.file_exists(path) and not overwrite:
		return {
			"ok": false,
			"status": "duplicate",
			"path": path,
			"display_name": String(validation.get("display_name", display_name)),
			"message": "A save with this name already exists.",
		}

	var player_name := String(validation.get("display_name", display_name))
	var metadata := _build_metadata("manual", player_name)
	var written := CampaignState.write_campaign(path, metadata)
	return {
		"ok": written,
		"status": "saved" if written else "error",
		"path": path,
		"display_name": player_name,
		"message": "Game saved." if written else "The save file could not be written.",
	}


static func write_combat_return_autosave(outcome: String, details: Dictionary = {}) -> bool:
	# This is the single autosave entry point. SceneFlow calls it only after a completed
	# campaign fight returns to camp, regardless of whether the result was a wipe or victory.
	_ensure_save_directory()
	var context_details := details.duplicate(true)
	context_details["outcome"] = outcome
	var metadata := _build_metadata("autosave", "Autosave", context_details)
	return CampaignState.write_campaign(AUTOSAVE_PATH, metadata)


static func validate_save_name(value: String) -> Dictionary:
	var display_name := value.strip_edges()

	if display_name.is_empty():
		return {
			"valid": false,
			"message": "Save names cannot be blank or contain only whitespace.",
		}

	var normalized_name := _safe_filename(display_name)

	if normalized_name.is_empty():
		return {
			"valid": false,
			"message": "The save name must contain at least one letter or number.",
		}

	return {
		"valid": true,
		"display_name": display_name,
		"normalized_name": normalized_name,
	}


static func list_saves() -> Array[Dictionary]:
	_ensure_save_directory()
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(SAVE_DIRECTORY)

	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()

		while not file_name.is_empty():
			if not directory.current_is_dir() and file_name.get_extension().to_lower() == "json":
				var entry := _read_save_entry(SAVE_DIRECTORY + "/" + file_name)

				if not entry.is_empty():
					result.append(entry)

			file_name = directory.get_next()

		directory.list_dir_end()

	# Preserve access to the pre-named-save campaign file without rewriting it.
	if FileAccess.file_exists(CampaignState.SAVE_PATH):
		var legacy_entry := _read_save_entry(CampaignState.SAVE_PATH)

		if not legacy_entry.is_empty():
			legacy_entry["kind"] = "legacy"
			legacy_entry["display_name"] = "Legacy Campaign"
			legacy_entry["deletable"] = false
			result.append(legacy_entry)

	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_is_autosave := String(a.get("kind", "")) == "autosave"
			var b_is_autosave := String(b.get("kind", "")) == "autosave"

			if a_is_autosave != b_is_autosave:
				return a_is_autosave

			var a_saved_time := int(a.get("saved_unix_time", 0))
			var b_saved_time := int(b.get("saved_unix_time", 0))

			if a_saved_time != b_saved_time:
				return a_saved_time > b_saved_time

			return String(a.get("display_name", "")).naturalnocasecmp_to(
				String(b.get("display_name", ""))
			) < 0
	)
	return result


static func list_snapshots() -> Array[Dictionary]:
	# Compatibility alias for callers from the previous snapshot implementation.
	return list_saves()


static func get_most_recent_save() -> Dictionary:
	var saves := list_saves()
	var latest: Dictionary = {}

	for save_entry in saves:
		if (
			latest.is_empty()
			or int(save_entry.get("saved_unix_time", 0))
			> int(latest.get("saved_unix_time", 0))
		):
			latest = save_entry

	return latest.duplicate(true)


static func load_most_recent_save() -> bool:
	var latest := get_most_recent_save()
	return false if latest.is_empty() else load_save(String(latest.get("path", "")))


static func load_save(path: String) -> bool:
	if not _is_managed_path(path) or not FileAccess.file_exists(path):
		push_warning("Rejected unmanaged or missing campaign save: " + path)
		return false

	return CampaignState.load_campaign(path)


static func load_snapshot(path: String) -> bool:
	return load_save(path)


static func delete_save(path: String) -> bool:
	if path == AUTOSAVE_PATH or not path.begins_with(SAVE_DIRECTORY + "/"):
		return false

	if not FileAccess.file_exists(path):
		return false

	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


static func _build_metadata(
	kind: String, display_name: String, extra_context: Dictionary = {}
) -> Dictionary:
	var context := CampaignState.get_save_context()
	context.merge(extra_context, true)
	return {
		"kind": kind,
		"display_name": display_name,
		"saved_unix_time": int(Time.get_unix_time_from_system()),
		"context": context,
	}


static func _read_save_entry(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		return {}

	var payload := parsed as Dictionary
	var campaign_value: Variant = payload.get("campaign", payload)

	if not campaign_value is Dictionary:
		return {}

	var metadata_value: Variant = payload.get("save_metadata", {})
	var metadata: Dictionary = (
		Dictionary(metadata_value).duplicate(true) if metadata_value is Dictionary else {}
	)
	var context_value: Variant = metadata.get("context", {})
	var context: Dictionary = (
		Dictionary(context_value).duplicate(true) if context_value is Dictionary else {}
	)
	var saved_time := int(
		metadata.get("saved_unix_time", FileAccess.get_modified_time(path))
	)
	var default_kind := "autosave" if path == AUTOSAVE_PATH else "manual"
	var kind := String(metadata.get("kind", default_kind))
	var display_name := String(metadata.get("display_name", "")).strip_edges()

	if display_name.is_empty():
		display_name = "Autosave" if path == AUTOSAVE_PATH else _legacy_display_name(path.get_file())

	var region_name := String(context.get("region_name", context.get("region_id", "Camp")))
	var encounter_name := String(
		context.get("encounter_name", context.get("encounter_id", "No target selected"))
	)
	return {
		"path": path,
		"kind": kind,
		"display_name": display_name,
		"saved_unix_time": saved_time,
		"context": context,
		"context_label": "%s · %s" % [region_name, encounter_name],
		"deletable": path != AUTOSAVE_PATH,
	}


static func _ensure_save_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))


static func _manual_path(normalized_name: String) -> String:
	return "%s/%s%s.json" % [SAVE_DIRECTORY, MANUAL_PREFIX, normalized_name]


static func _safe_filename(value: String) -> String:
	var result := ""
	var lowered := value.strip_edges().to_lower()

	for index in range(lowered.length()):
		var character := lowered.substr(index, 1)
		var codepoint := lowered.unicode_at(index)

		if codepoint < 32 or INVALID_FILENAME_CHARACTERS.has(character):
			result += "_"
		elif character == " " or character == ".":
			result += "_"
		else:
			result += character

	while result.contains("__"):
		result = result.replace("__", "_")

	while result.begins_with("_"):
		result = result.substr(1)

	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)

	result = result.substr(0, mini(result.length(), 64))

	if RESERVED_FILENAME_STEMS.has(result):
		result = "save_" + result

	return result


static func _legacy_display_name(file_name: String) -> String:
	var stem := file_name.get_basename()

	if stem.begins_with(MANUAL_PREFIX):
		stem = stem.trim_prefix(MANUAL_PREFIX)
	else:
		var separator_index := stem.find("_")

		if separator_index >= 0 and stem.left(separator_index).is_valid_int():
			stem = stem.substr(separator_index + 1)

	return stem.replace("_", " ").capitalize()


static func _is_managed_path(path: String) -> bool:
	return path == CampaignState.SAVE_PATH or path.begins_with(SAVE_DIRECTORY + "/")
