extends RefCounted
class_name CampaignSaveManager

const SNAPSHOT_DIRECTORY := "user://raid_leader_saves"
const MAX_SNAPSHOTS := 20


static func has_current_save() -> bool:
	return FileAccess.file_exists(CampaignState.SAVE_PATH)


static func create_snapshot(label: String = "Manual") -> String:
	if not has_current_save():
		return ""

	CampaignState.save_campaign()
	_ensure_snapshot_directory()
	var timestamp := int(Time.get_unix_time_from_system())
	var safe_label := _safe_filename(label)
	var path := "%s/%d_%s.json" % [SNAPSHOT_DIRECTORY, timestamp, safe_label]
	var source := FileAccess.open(CampaignState.SAVE_PATH, FileAccess.READ)

	if source == null:
		return ""

	var target := FileAccess.open(path, FileAccess.WRITE)

	if target == null:
		return ""

	target.store_string(source.get_as_text())
	target.close()
	source.close()
	_trim_old_snapshots()
	return path


static func start_new_campaign() -> void:
	if has_current_save():
		create_snapshot("Before New Game")

	var absolute_path := ProjectSettings.globalize_path(CampaignState.SAVE_PATH)

	if FileAccess.file_exists(CampaignState.SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)

	CampaignState.load_campaign()
	CampaignState.state_changed.emit()


static func list_snapshots() -> Array[Dictionary]:
	_ensure_snapshot_directory()
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(SNAPSHOT_DIRECTORY)

	if directory == null:
		return result

	directory.list_dir_begin()
	var file_name := directory.get_next()

	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "json":
			var path := SNAPSHOT_DIRECTORY + "/" + file_name
			result.append(
				{
					"path": path,
					"file_name": file_name,
					"modified_time": FileAccess.get_modified_time(path),
					"display_name": _display_name(file_name)
				}
			)

		file_name = directory.get_next()

	directory.list_dir_end()
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("modified_time", 0)) > int(b.get("modified_time", 0))
	)
	return result


static func load_snapshot(path: String) -> bool:
	if not path.begins_with(SNAPSHOT_DIRECTORY + "/") or not FileAccess.file_exists(path):
		return false

	if has_current_save():
		create_snapshot("Before Load")

	var source := FileAccess.open(path, FileAccess.READ)

	if source == null:
		return false

	var target := FileAccess.open(CampaignState.SAVE_PATH, FileAccess.WRITE)

	if target == null:
		return false

	target.store_string(source.get_as_text())
	target.close()
	source.close()
	CampaignState.load_campaign()
	CampaignState.state_changed.emit()
	return true


static func _ensure_snapshot_directory() -> void:
	var absolute_path := ProjectSettings.globalize_path(SNAPSHOT_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(absolute_path)


static func _trim_old_snapshots() -> void:
	var snapshots := list_snapshots()

	for index in range(MAX_SNAPSHOTS, snapshots.size()):
		var snapshot: Dictionary = snapshots[index]
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(snapshot.get("path", ""))))


static func _safe_filename(value: String) -> String:
	var result := value.strip_edges().to_lower()

	for character in [" ", "/", "\\", ":", "*", "?", '"', "<", ">", "|"]:
		result = result.replace(character, "_")

	return "save" if result.is_empty() else result


static func _display_name(file_name: String) -> String:
	var stem := file_name.get_basename()
	var separator_index := stem.find("_")
	var label := stem.substr(separator_index + 1) if separator_index >= 0 else stem
	return label.replace("_", " ").capitalize()
