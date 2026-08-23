extends Control
class_name TrainingProgressionTree

signal lineage_cycle_requested(direction: int)
signal lineage_lock_requested(lineage_id: String)

const TrainingProgressionCatalogScript := preload(
	"res://scripts/data/training_progression_catalog.gd"
)
const RaiderClassCatalogScript := preload("res://scripts/data/raider_class_catalog.gd")

const TREE_HEIGHT := 500.0
const NODE_HALF_SIZE := 25.0
const FEATURE_NODE_HALF_SIZE := 31.0
const COMPLETED_COLOR := Color("d5b75e")
const AVAILABLE_COLOR := Color("62b8dc")
const LOCKED_COLOR := Color("4b555b")
const INCOMING_COLOR := Color("81d7c3")

var base_class_id: String = ""
var status: Dictionary = {}
var preview_lineage_id: String = ""
var preview_lineage: Dictionary = {}
var node_statuses: Array[Dictionary] = []
var _node_rects: Dictionary = {}
var _left_button: Button = null
var _right_button: Button = null
var _lock_button: Button = null
var _glow_time := 0.0
var _navigation_main_color := Color("27a8d6")
var _navigation_accent_color := Color("67d4f2")


func _ready() -> void:
	custom_minimum_size = Vector2(460, TREE_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ensure_controls()
	set_process(true)
	queue_redraw()


func configure(new_base_class_id: String, new_status: Dictionary) -> void:
	base_class_id = RaiderClassCatalogScript.normalize_class_id(new_base_class_id)
	status = new_status.duplicate(true)
	preview_lineage_id = String(status.get("preview_lineage_id", ""))
	preview_lineage = Dictionary(status.get("preview_lineage", {})).duplicate(true)
	_update_navigation_colors()
	node_statuses.clear()
	for node_value in status.get("node_statuses", []):
		node_statuses.append(Dictionary(node_value).duplicate(true))
	_ensure_controls()
	_update_controls()
	set_meta("branch_count", Array(status.get("eligible_lineages", [])).size())
	set_meta("selected_lineage_id", preview_lineage_id)
	set_meta("node_count", node_statuses.size())
	set_meta("uses_full_resolution_icon", true)
	set_meta("has_connectors", false)
	set_meta("talent_labels_visible", false)
	set_meta("inactive_nodes_quiet", true)
	set_meta("row_completion_glow_secondary", true)
	set_meta("node_effects_contained", true)
	set_meta("navigation_uses_class_colors", true)
	queue_redraw()


func _update_navigation_colors() -> void:
	_navigation_main_color = Color("27a8d6")
	_navigation_accent_color = Color("67d4f2")
	var visual := RaiderClassCatalogScript.resolve_visual(base_class_id, preview_lineage_id)
	if visual == null:
		return
	_navigation_main_color = visual.main_color
	_navigation_accent_color = (
		visual.accent_color if visual.accent_color.a > 0.0 else visual.main_color.lightened(0.25)
	)


func _ensure_controls() -> void:
	if _left_button != null:
		return
	_left_button = Button.new()
	_left_button.name = "TrainingPreviousLineage"
	_left_button.text = "‹"
	_left_button.tooltip_text = "Previous lineage"
	_left_button.custom_minimum_size = Vector2(52, 44)
	_left_button.pressed.connect(func() -> void: lineage_cycle_requested.emit(-1))
	add_child(_left_button)
	_right_button = Button.new()
	_right_button.name = "TrainingNextLineage"
	_right_button.text = "›"
	_right_button.tooltip_text = "Next lineage"
	_right_button.custom_minimum_size = Vector2(52, 44)
	_right_button.pressed.connect(func() -> void: lineage_cycle_requested.emit(1))
	add_child(_right_button)
	_lock_button = Button.new()
	_lock_button.name = "TrainingLockLineage"
	_lock_button.custom_minimum_size = Vector2(300, 44)
	_lock_button.pressed.connect(
		func() -> void: lineage_lock_requested.emit(preview_lineage_id)
	)
	add_child(_lock_button)
	_style_navigation_buttons()
	_update_controls()


func _update_controls() -> void:
	if _lock_button == null:
		return
	_style_navigation_buttons()
	var token_spent := bool(status.get("lineage_token_spent", false))
	var active_id := String(status.get("secondary_lineage_id", ""))
	if preview_lineage_id.is_empty():
		_lock_button.text = "Begin Lineage"
		_lock_button.disabled = true
	elif preview_lineage_id == active_id:
		_lock_button.text = "Current Lineage"
		_lock_button.disabled = true
	elif token_spent:
		_lock_button.text = "Change Lineage"
		_lock_button.disabled = false
	else:
		_lock_button.disabled = String(status.get("matching_token_id", "")).is_empty()
		_lock_button.text = "Begin Lineage"
		_lock_button.tooltip_text = (
			"A matching class token is required."
			if _lock_button.disabled
			else "Consume the token and begin this lineage."
		)
	var lineage_count := Array(status.get("eligible_lineages", [])).size()
	_left_button.disabled = lineage_count <= 1
	_right_button.disabled = lineage_count <= 1


func _style_navigation_buttons() -> void:
	if _left_button == null or _right_button == null:
		return
	var main_color := _navigation_main_color
	var accent_color := _navigation_accent_color
	for button in [_left_button, _right_button]:
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(main_color.darkened(0.70), 0.96)
		normal.border_color = accent_color
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(3)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(accent_color.darkened(0.58), 0.98)
		hover.border_color = accent_color.lightened(0.20)
		hover.set_border_width_all(2)
		hover.set_corner_radius_all(3)
		var disabled := StyleBoxFlat.new()
		disabled.bg_color = Color(main_color.darkened(0.82), 0.78)
		disabled.border_color = Color(accent_color.darkened(0.52), 0.82)
		disabled.set_border_width_all(1)
		disabled.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("disabled", disabled)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_controls()
		queue_redraw()


func _layout_controls() -> void:
	if _left_button == null:
		return
	var center_x := size.x * 0.5
	var action_y := size.y - 50.0
	_left_button.position = Vector2(18, action_y)
	_left_button.size = Vector2(52, 44)
	_right_button.position = Vector2(size.x - 70, action_y)
	_right_button.size = Vector2(52, 44)
	_lock_button.position = Vector2(center_x - 160, size.y - 50)
	_lock_button.size = Vector2(320, 42)


func _process(delta: float) -> void:
	_glow_time += delta
	if not bool(status.get("preview_is_active", false)):
		queue_redraw()


func _draw() -> void:
	_node_rects.clear()
	var center_x := size.x * 0.5
	var advanced := RaiderClassCatalogScript.get_definition(preview_lineage_id)
	var visual := advanced.get("visual") as ClassVisualDefinition
	var class_color := visual.main_color if visual != null else AVAILABLE_COLOR
	var accent_color := visual.accent_color if visual != null else INCOMING_COLOR
	var preview_active := bool(status.get("preview_is_active", false))
	var pulse := 0.55 + sin(_glow_time * 1.8) * 0.18
	var panel_rect := Rect2(Vector2(4, 8), Vector2(maxf(size.x - 8, 356), 392))
	_draw_tree_panel(panel_rect, class_color, accent_color, preview_active)
	var positions := _node_positions(center_x, panel_rect)
	for node in node_statuses:
		var node_id := String(node.get("node_id", ""))
		if not positions.has(node_id):
			continue
		var point: Vector2 = positions[node_id]
		var half_size := (
			FEATURE_NODE_HALF_SIZE
			if node_id in [
				TrainingProgressionCatalogScript.ENTRY_NODE_ID,
				TrainingProgressionCatalogScript.CAPSTONE_NODE_ID,
			]
			else NODE_HALF_SIZE
		)
		_draw_node(node, point, half_size, preview_active, pulse, class_color)
		_node_rects[node_id] = Rect2(
			point - Vector2(half_size, half_size),
			Vector2(half_size * 2.0, half_size * 2.0)
		)


func _draw_tree_panel(
	panel_rect: Rect2, class_color: Color, accent_color: Color, preview_active: bool
) -> void:
	draw_rect(panel_rect.grow(5), Color("070b0d"))
	draw_rect(panel_rect, Color("121a1f"))
	draw_rect(panel_rect, class_color.darkened(0.08), false, 3.0)
	var band_height := 74.0
	var band_top := panel_rect.position.y + 8.0
	var band_labels: Array[String] = ["CAPSTONE", "TIER III", "TIER II", "TIER I", "ENTRY"]
	var row_node_ids: Dictionary = {
		"TIER III": ["tier_3_left", "tier_3_center", "tier_3_right"],
		"TIER II": ["tier_2_left", "tier_2_center", "tier_2_right"],
		"TIER I": ["tier_1_left", "tier_1_center", "tier_1_right"],
	}
	for band_index in range(band_labels.size()):
		var band_rect := Rect2(
			Vector2(panel_rect.position.x + 8, band_top + float(band_index) * band_height),
			Vector2(panel_rect.size.x - 16, band_height - 5)
		)
		var band_color := class_color.darkened(0.76 if band_index % 2 == 0 else 0.82)
		draw_rect(band_rect, Color(band_color, 0.58))
		draw_rect(band_rect, Color(accent_color, 0.34), false, 1.0)
		var row_id := band_labels[band_index]
		if preview_active and row_node_ids.has(row_id) and _is_row_complete(row_node_ids[row_id]):
			var completed_row_color := accent_color if accent_color.a > 0.0 else class_color
			draw_rect(band_rect.grow(-2), Color(completed_row_color, 0.20))
			draw_rect(band_rect.grow(-2), Color(completed_row_color, 0.72), false, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			band_rect.position + Vector2(8, 16),
			band_labels[band_index],
			HORIZONTAL_ALIGNMENT_LEFT,
			82,
			9,
			Color(class_color.lightened(0.35), 0.86)
		)


func _node_positions(center_x: float, panel_rect: Rect2) -> Dictionary:
	var spread := minf(maxf(size.x * 0.19, 78.0), 112.0)
	var panel_top := panel_rect.position.y
	return {
		"capstone": Vector2(center_x, panel_top + 42.5),
		"tier_3_left": Vector2(center_x - spread, panel_top + 116.5),
		"tier_3_center": Vector2(center_x, panel_top + 116.5),
		"tier_3_right": Vector2(center_x + spread, panel_top + 116.5),
		"tier_2_left": Vector2(center_x - spread, panel_top + 190.5),
		"tier_2_center": Vector2(center_x, panel_top + 190.5),
		"tier_2_right": Vector2(center_x + spread, panel_top + 190.5),
		"tier_1_left": Vector2(center_x - spread, panel_top + 264.5),
		"tier_1_center": Vector2(center_x, panel_top + 264.5),
		"tier_1_right": Vector2(center_x + spread, panel_top + 264.5),
		"entry": Vector2(center_x, panel_top + 338.5),
	}


func _draw_node(
	node: Dictionary, point: Vector2, half_size: float,
	preview_active: bool, pulse: float, class_color: Color
) -> void:
	var state_id := String(node.get("status", "locked"))
	var state_color := LOCKED_COLOR
	if preview_active:
		if state_id == "completed":
			state_color = COMPLETED_COLOR
		elif state_id == "available":
			state_color = AVAILABLE_COLOR
	var slot_rect := Rect2(
		point - Vector2(half_size, half_size),
		Vector2(half_size * 2.0, half_size * 2.0)
	)
	if preview_active and state_id == "available":
		draw_rect(slot_rect.grow(-1), Color(state_color, 0.10 + pulse * 0.10))
	draw_rect(slot_rect, Color("070a0c"))
	draw_rect(slot_rect.grow(-3), class_color.darkened(0.76) if state_id != "locked" else Color("20272b"))
	draw_rect(slot_rect.grow(-5), Color(state_color, 0.16))
	draw_rect(slot_rect.grow(-1), state_color, false, 2.0)
	var mark := "✓" if state_id == "completed" else "?" if state_id == "available" else "•"
	_draw_centered_text(
		point + Vector2(0, 7), mark, 19,
		Color("fff3d0") if preview_active and state_id != "locked" else Color("7b858a")
	)


func _is_row_complete(node_ids: Array) -> bool:
	for node_id_value in node_ids:
		var node_id := String(node_id_value)
		var found := false
		for node in node_statuses:
			if String(node.get("node_id", "")) == node_id:
				found = String(node.get("status", "")) == "completed"
				break
		if not found:
			return false
	return true


func _draw_centered_text(point: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font,
		point,
		value,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		color
	)


func _get_tooltip(at_position: Vector2) -> String:
	for node_id in _node_rects.keys():
		var node_rect: Rect2 = _node_rects[node_id]
		if not node_rect.has_point(at_position):
			continue
		for node in node_statuses:
			if String(node.get("node_id", "")) == String(node_id):
				return _node_tooltip(node)
	return ""


func _node_tooltip(node: Dictionary) -> String:
	var lines: Array[String] = [String(node.get("title", "Talent"))]
	lines.append("Status: %s" % String(node.get("status", "locked")).capitalize())
	lines.append(String(node.get("reward_summary", "")))
	if not bool(status.get("preview_is_active", false)):
		lines.append("Preview only: quest progress is dormant until this lineage is active.")
	if String(node.get("status", "")) == "locked":
		lines.append("Complete all three quests in the preceding tier to open this node.")
	for objective_value in node.get("objectives", []):
		var objective: Dictionary = objective_value
		if String(node.get("status", "")) == "locked":
			lines.append("Quest preview: %s" % String(objective.get("description", "Quest placeholder")))
		else:
			lines.append(
				"%s (%d/%d)" % [
					String(objective.get("description", "Quest placeholder")),
					int(objective.get("current", 0)),
					int(objective.get("target", 1)),
				]
			)
	return "\n".join(lines)
