extends RefCounted
class_name CriticalDebuffCatalog

const SLAM_VULNERABILITY_ICON := preload(
	"res://icons/debuffs/slam_vulnerability.png"
)

const PRESENTATIONS := {
	"slam_vulnerability": {
		"critical": true,
		"icon": SLAM_VULNERABILITY_ICON,
		"show_stack_count": true,
		"emphasize_stacking": true,
		"priority": 100,
		"accent_color": Color(1.0, 0.54, 0.16, 1.0)
	}
}


static func get_presentation(effect_id: String) -> Dictionary:
	var presentation: Dictionary = PRESENTATIONS.get(effect_id, {})

	if presentation.is_empty() or not bool(presentation.get("critical", false)):
		return {}

	return presentation


static func get_critical_debuffs(
	active_status_effects: Array
) -> Array[Dictionary]:
	var critical_debuffs: Array[Dictionary] = []

	for status_value in active_status_effects:
		if not status_value is Dictionary:
			continue

		var status: Dictionary = status_value

		if not bool(status.get("is_harmful", false)):
			continue

		var effect_id := String(status.get("effect_id", ""))
		var presentation := get_presentation(effect_id)

		if presentation.is_empty():
			continue

		var display_state := status.duplicate()

		for presentation_key in presentation.keys():
			display_state[presentation_key] = presentation[presentation_key]

		critical_debuffs.append(display_state)

	critical_debuffs.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_priority := int(a.get("priority", 0))
		var b_priority := int(b.get("priority", 0))

		if a_priority == b_priority:
			return String(a.get("effect_id", "")) < String(b.get("effect_id", ""))

		return a_priority > b_priority
	)

	return critical_debuffs
