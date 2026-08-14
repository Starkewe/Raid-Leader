extends RefCounted
class_name CampaignPersistenceService


func read_payload(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "missing", "campaign": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "open_failed", "campaign": {}}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return {"ok": false, "error": "invalid_json", "campaign": {}}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"ok": false, "error": "invalid_json", "campaign": {}}
	var payload: Dictionary = parsed
	if not payload.get("campaign") is Dictionary:
		return {"ok": false, "error": "missing_campaign", "campaign": {}}
	return {
		"ok": true,
		"error": "",
		"campaign": Dictionary(payload["campaign"]).duplicate(true),
		"save_metadata": Dictionary(payload.get("save_metadata", {})).duplicate(true),
	}


func write_payload(path: String, campaign: Dictionary, metadata: Dictionary) -> bool:
	if path.is_empty():
		return false
	var directory_result := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_result != OK and directory_result != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"save_metadata": metadata.duplicate(true),
		"campaign": campaign.duplicate(true),
	}, "\t"))
	file.close()
	return true
