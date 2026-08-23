extends Control
class_name CampRaidFrame

signal member_hovered(member_id: String)
signal member_unhovered(member_id: String)
signal equipment_action_completed(result: Dictionary)

const BASE_SIZE := Vector2(154, 45)
const ACCESSORY_SIZE := 44.0
const ACCESSORY_GAP := 4.0
const FULL_WIDTH := BASE_SIZE.x + ACCESSORY_GAP + ACCESSORY_SIZE
const RaiderClassCatalogScript := preload(
	"res://scripts/data/raider_class_catalog.gd"
)

const DIRECTION_IDS := [
	"east", "southeast", "south", "southwest",
	"west", "northwest", "north", "northeast",
]
const DIRECTION_LABELS := {
	"east": "E", "southeast": "SE", "south": "S", "southwest": "SW",
	"west": "W", "northwest": "NW", "north": "N", "northeast": "NE",
}
const RANGE_LABELS := {"close": "C", "mid": "M", "far": "F"}

var member: Dictionary = {}
var member_id: String = ""
var display_name: String = ""
var context: String = ""
var equipment_enabled: bool = false
var placement: Dictionary = {}
var visual_definition: ClassVisualDefinition = null
var hovered: bool = false
var drop_allowed: bool = false
var drop_reason: String = ""
var selected_family_id: String = ""
var smith_family_filter_id: String = ""
var family_compatible: bool = true
var compatible_with_selected_family: bool = true
var smith_drop_target_enabled: bool = false
var smith_family_compatibility_state: String = "neutral"
func _ready() -> void:
	add_to_group("camp_raid_frames")
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func configure(
	member_data: Dictionary, new_context: String, new_equipment_enabled: bool,
	formation_placement: Dictionary = {}, new_smith_family_id: String = ""
) -> void:
	member = member_data.duplicate(true)
	member_id = String(member.get("member_id", ""))
	display_name = String(member.get("display_name", member_id))
	context = new_context
	equipment_enabled = new_equipment_enabled
	placement = formation_placement.duplicate(true)
	selected_family_id = new_smith_family_id
	smith_family_filter_id = new_smith_family_id
	var base_class_id := RaiderClassCatalogScript.normalize_class_id(
		String(member.get("unit_class", ""))
	)
	var advanced_class_id := String(member.get("advanced_class_id", ""))
	visual_definition = RaiderClassCatalogScript.resolve_visual(
		base_class_id, advanced_class_id
	)
	family_compatible = (
		new_smith_family_id.is_empty()
		or ProgressionCatalog.is_family_compatible(_effective_class_id(), new_smith_family_id)
	)
	compatible_with_selected_family = family_compatible
	smith_drop_target_enabled = (
		context == "smith"
		and equipment_enabled
		and not new_smith_family_id.is_empty()
		and family_compatible
	)
	smith_family_compatibility_state = (
		"neutral" if new_smith_family_id.is_empty()
		else "compatible" if family_compatible else "incompatible"
	)
	modulate = (
		Color(0.58, 0.61, 0.63, 1.0)
		if context == "smith" and not new_smith_family_id.is_empty() and not family_compatible
		else Color.WHITE
	)
	custom_minimum_size = Vector2(
		FULL_WIDTH if context in ["smith", "formation_yard"] else BASE_SIZE.x,
		BASE_SIZE.y
	)
	size = custom_minimum_size
	tooltip_text = _base_tooltip()
	queue_redraw()


func is_compatible_with_smith_family() -> bool:
	return compatible_with_selected_family


func can_receive_smith_weapon() -> bool:
	return smith_drop_target_enabled


func _draw() -> void:
	_draw_base_frame()
	if context == "smith":
		_draw_weapon_slot()
		_draw_smith_family_state()
		_draw_equipment_drop_highlight()
	elif context == "formation_yard":
		_draw_formation_badge()


func _draw_base_frame() -> void:
	var icon_rect := Rect2(2, 0.5, 44, 44)
	var bar_rect := Rect2(48, 0.5, 104, 44)
	var class_color := (
		visual_definition.main_color
		if visual_definition != null
		else Color("474c54")
	)
	draw_rect(Rect2(Vector2.ZERO, BASE_SIZE), Color("07090aFA"))
	draw_rect(icon_rect, Color("050607"))
	draw_rect(bar_rect, class_color.darkened(0.08))
	if visual_definition != null and visual_definition.icon_resource != null:
		draw_texture_rect(visual_definition.icon_resource, icon_rect.grow(-1), false)
	draw_rect(icon_rect, class_color, false, 1.0)
	if hovered:
		draw_rect(bar_rect, Color(1, 1, 1, 0.12))
		draw_rect(Rect2(Vector2.ONE, BASE_SIZE - Vector2(2, 2)), Color("f2d27c"), false, 2.0)
	else:
		draw_rect(Rect2(Vector2(0.5, 0.5), BASE_SIZE - Vector2.ONE), Color("050506"), false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(50, 27),
		display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		100,
		10,
		Color.WHITE
	)


func _draw_weapon_slot() -> void:
	var slot_rect := _accessory_rect()
	var inner := slot_rect.grow(-2)
	var weapon_id := String(member.get("equipped_weapon_id", ""))
	var texture: Texture2D = null
	var border_color := Color("7b704f")
	draw_rect(slot_rect, Color("090d10F5"))
	if weapon_id.is_empty():
		texture = RaiderClassCatalogScript.get_default_weapon_icon(_effective_class_id())
		border_color = Color("5d6467")
	elif ProgressionCatalog.get_weapon(weapon_id) != null:
		texture = ProgressionCatalog.get_weapon(weapon_id).icon_resource
		border_color = Color("c3a961")
	if texture != null:
		draw_texture_rect(texture, inner, false)
	elif not weapon_id.is_empty():
		draw_rect(inner, Color("391f25"))
		draw_line(inner.position + Vector2(7, 7), inner.end - Vector2(7, 7), Color("e08b85"), 3)
		draw_line(Vector2(inner.end.x - 7, inner.position.y + 7), Vector2(inner.position.x + 7, inner.end.y - 7), Color("e08b85"), 3)
	if not equipment_enabled:
		draw_rect(inner, Color(0.03, 0.04, 0.05, 0.36))
	if not drop_reason.is_empty():
		border_color = Color("78bd7c") if drop_allowed else Color("d36f68")
	draw_rect(slot_rect, border_color, false, 2.0)


func _draw_smith_family_state() -> void:
	if context != "smith" or smith_family_filter_id.is_empty() or family_compatible:
		return
	var overlay := Color(0.02, 0.025, 0.03, 0.22)
	draw_rect(Rect2(Vector2.ZERO, BASE_SIZE), overlay)
	draw_rect(_accessory_rect(), overlay)


func _draw_equipment_drop_highlight() -> void:
	if drop_reason.is_empty():
		return
	var state_color := Color("78bd7c") if drop_allowed else Color("d36f68")
	var fill_color := state_color
	fill_color.a = 0.14
	draw_rect(_smith_drop_rect(), fill_color)
	draw_rect(_smith_drop_rect().grow(-1), state_color, false, 2.0)
	draw_rect(_accessory_rect().grow(-1), state_color, false, 3.0)


func _draw_formation_badge() -> void:
	var slot_rect := _accessory_rect()
	draw_rect(slot_rect, Color("090d10F5"))
	var region := String(placement.get("region", ""))
	var range_name := String(placement.get("range", ""))
	if DIRECTION_IDS.has(region) and RANGE_LABELS.has(range_name):
		var direction_index := DIRECTION_IDS.find(region)
		var center := slot_rect.get_center()
		var ring_index := ["close", "mid", "far"].find(range_name)
		var inner_radius := 6.0 + float(ring_index) * 5.0
		var outer_radius := inner_radius + 5.0
		var center_angle := float(direction_index) * PI / 4.0
		var polygon := _sector_polygon(
			center, inner_radius, outer_radius,
			center_angle - PI / 8.0, center_angle + PI / 8.0
		)
		draw_colored_polygon(polygon, Color("a94343"))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, Color("ed9a83"), 1.5, true)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(slot_rect.position.x + 1, slot_rect.position.y + 27),
			"%s - %s" % [DIRECTION_LABELS[region], RANGE_LABELS[range_name]],
			HORIZONTAL_ALIGNMENT_CENTER,
			42,
			9,
			Color.WHITE
		)
	else:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(slot_rect.position.x + 1, slot_rect.position.y + 27),
			"--",
			HORIZONTAL_ALIGNMENT_CENTER,
			42,
			11,
			Color("a7aaad")
		)
	draw_rect(slot_rect, Color("b35f58"), false, 2.0)


func _get_drag_data(at_position: Vector2) -> Variant:
	var payload := get_drag_payload(at_position)
	if payload.is_empty():
		return null
	if String(payload.get("type", "")) == "formation_member":
		var preview := Label.new()
		_configure_drag_preview(preview)
		preview.text = display_name
		preview.add_theme_font_size_override("font_size", 16)
		preview.add_theme_color_override("font_color", Color("f0e5c8"))
		preview.add_theme_constant_override("outline_size", 5)
		preview.add_theme_color_override("font_outline_color", Color("11171c"))
		set_drag_preview(preview)
		return payload
	var weapon_id := String(payload.get("weapon_id", ""))
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	var preview: Control
	if weapon != null and weapon.icon_resource != null:
		var texture_preview := TextureRect.new()
		_configure_drag_preview(texture_preview)
		texture_preview.custom_minimum_size = Vector2.ONE * ACCESSORY_SIZE
		texture_preview.texture = weapon.icon_resource
		texture_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview = texture_preview
	else:
		var recovery_preview := Label.new()
		_configure_drag_preview(recovery_preview)
		recovery_preview.text = "Missing weapon\nReturn to Armory"
		recovery_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		recovery_preview.add_theme_color_override("font_color", Color("e08b85"))
		preview = recovery_preview
	set_drag_preview(preview)
	return payload


func get_drag_payload(at_position: Vector2) -> Dictionary:
	if context == "formation_yard" and Rect2(Vector2.ZERO, BASE_SIZE).has_point(at_position):
		return {"type": "formation_member", "member_id": member_id}
	if context != "smith" or not equipment_enabled or not _accessory_rect().has_point(at_position):
		return {}
	var weapon_id := String(member.get("equipped_weapon_id", ""))
	if weapon_id.is_empty():
		return {}
	return {
		"type": "smith_equipped_weapon",
		"weapon_id": weapon_id,
		"source_raider_id": member_id,
	}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	clear_drop_feedback()
	if (
		context != "smith"
		or not equipment_enabled
		or not smith_drop_target_enabled
		or not _smith_drop_rect().has_point(at_position)
		or not data is Dictionary
	):
		return false
	_clear_other_frame_drop_feedback()
	var drag_type := String(data.get("type", ""))
	var validation: Dictionary = {}
	if drag_type == "smith_armory_weapon":
		if not _payload_matches_selected_family(data):
			validation = {
				"ok": false,
				"message": "This weapon belongs to another weapon type.",
			}
		else:
			validation = CampaignState.check_equip_weapon(
				member_id, String(data.get("weapon_id", ""))
			)
	elif drag_type == "smith_equipped_weapon":
		validation = CampaignState.check_move_or_swap_equipped_weapon(
			String(data.get("source_raider_id", "")), member_id
		)
	elif drag_type == "smith_reserve_weapon":
		if not _payload_matches_selected_family(data):
			validation = {
				"ok": false,
				"message": "This weapon belongs to another weapon type.",
			}
		else:
			validation = CampaignState.check_reclaim_reserve_weapon(
				String(data.get("source_raider_id", "")), member_id
			)
	else:
		return false
	drop_allowed = bool(validation.get("ok", false))
	drop_reason = String(validation.get("message", "Unavailable."))
	tooltip_text = drop_reason
	queue_redraw()
	return drop_allowed


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	var result: Dictionary
	if String(data.get("type", "")) == "smith_armory_weapon":
		result = CampaignState.equip_weapon(member_id, String(data.get("weapon_id", "")))
	elif String(data.get("type", "")) == "smith_reserve_weapon":
		result = CampaignState.reclaim_reserve_weapon(
			String(data.get("source_raider_id", "")), member_id
		)
	else:
		result = CampaignState.move_or_swap_equipped_weapon(
			String(data.get("source_raider_id", "")), member_id
		)
	drop_reason = ""
	drop_allowed = false
	tooltip_text = _base_tooltip()
	equipment_action_completed.emit(result)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not drop_reason.is_empty():
		clear_drop_feedback()


func _on_mouse_entered() -> void:
	hovered = true
	member_hovered.emit(member_id)
	queue_redraw()


func _on_mouse_exited() -> void:
	hovered = false
	clear_drop_feedback()
	member_unhovered.emit(member_id)
	queue_redraw()


func clear_drop_feedback() -> void:
	if drop_reason.is_empty() and not drop_allowed:
		return
	drop_reason = ""
	drop_allowed = false
	tooltip_text = _base_tooltip()
	queue_redraw()


func _clear_other_frame_drop_feedback() -> void:
	for node in get_tree().get_nodes_in_group("camp_raid_frames"):
		if node != self and node is CampRaidFrame:
			(node as CampRaidFrame).clear_drop_feedback()


func _accessory_rect() -> Rect2:
	return Rect2(BASE_SIZE.x + ACCESSORY_GAP, 0.5, ACCESSORY_SIZE, ACCESSORY_SIZE)


func _smith_drop_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(FULL_WIDTH, BASE_SIZE.y))


func _configure_drag_preview(preview: Control) -> void:
	preview.z_as_relative = false
	preview.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _effective_class_id() -> String:
	var advanced_id := String(member.get("advanced_class_id", ""))
	return RaiderClassCatalogScript.normalize_class_id(
		advanced_id if not advanced_id.is_empty() else String(member.get("unit_class", ""))
	)


func _base_tooltip() -> String:
	var class_id := _effective_class_id()
	var class_definition := RaiderClassCatalogScript.get_definition(class_id)
	var result := "%s\nClass: %s" % [
		display_name,
		String(class_definition.get("display_name", class_id.capitalize())),
	]
	if context == "formation_yard":
		result += "\nDrag this frame onto the formation map."
	elif context == "smith":
		var weapon_id := String(member.get("equipped_weapon_id", ""))
		if weapon_id.is_empty():
			result += "\nDefault weapon"
		elif ProgressionCatalog.get_weapon(weapon_id) == null:
			result += "\n%s [Missing Content]" % weapon_id
		else:
			result += "\n%s" % ProgressionCatalog.get_weapon(weapon_id).display_name
		if equipment_enabled:
			if context == "smith" and smith_family_filter_id.is_empty():
				result += "\nSelect a weapon type to enable equipment targets."
			elif context == "smith" and not family_compatible:
				result += "\nThis raider cannot receive the selected weapon type."
			else:
				result += "\nDrop a compatible weapon here or drag this equipped weapon to another frame."
	return result


func _payload_matches_selected_family(data: Dictionary) -> bool:
	if smith_family_filter_id.is_empty():
		return false
	var weapon := ProgressionCatalog.get_weapon(String(data.get("weapon_id", "")))
	return weapon != null and weapon.family_id == smith_family_filter_id


func _sector_polygon(
	center: Vector2, inner_radius: float, outer_radius: float,
	start_angle: float, end_angle: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in range(6):
		var weight := float(step) / 5.0
		points.append(center + Vector2.from_angle(lerpf(start_angle, end_angle, weight)) * outer_radius)
	for step in range(5, -1, -1):
		var weight := float(step) / 5.0
		points.append(center + Vector2.from_angle(lerpf(start_angle, end_angle, weight)) * inner_radius)
	return points
