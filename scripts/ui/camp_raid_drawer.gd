extends Control
class_name CampRaidDrawer

const CampRaidFrameScript := preload("res://scripts/ui/camp_raid_frame.gd")

const BASE_CONTENT_WIDTH := 160.0
const CONTEXT_CONTENT_WIDTH := 210.0
const HANDLE_WIDTH := 34.0
const HANDLE_HEIGHT := 76.0
const SLIDE_DURATION := 0.22
const REQUIRED_CONTEXTS := ["smith", "formation_yard"]

var menu_context: String = ""
var manual_open: bool = false
var open_now: bool = false
var locked: bool = false
var highlighted_member_id: String = ""
var refresh_queued: bool = false
var feedback_generation: int = 0
var slide_tween: Tween = null
var content_panel: Control = null
var stack: VBoxContainer = null
var handle: Button = null
var feedback: Label = null


func _ready() -> void:
	name = "CampRaidDrawer"
	add_to_group("camp_raid_drawer")
	z_index = 120
	# The drawer is the final CampHUD sibling so its interactive children receive
	# GUI input above the full-screen Journal. Keep the transparent shell inert.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	CampaignState.state_changed.connect(_queue_refresh)
	call_deferred("_finish_initial_layout")


func _finish_initial_layout() -> void:
	_layout_shell()
	_rebuild()
	_set_open(false, false)


func set_menu_context(facility_id: String) -> void:
	var required := REQUIRED_CONTEXTS.has(facility_id)
	var context_changed := menu_context != facility_id
	if required and not locked:
		locked = true
	elif not required and locked:
		locked = false
	menu_context = facility_id if required else ""
	if context_changed:
		_layout_shell()
		_rebuild()
	_update_handle()
	_set_open(true if locked else manual_open, true)


func is_open() -> bool:
	return open_now


func is_locked_open() -> bool:
	return locked


func get_menu_context() -> String:
	return menu_context


func set_open_for_test(value: bool, animate: bool = false) -> void:
	if locked:
		return
	manual_open = value
	_set_open(value, animate)


func _build_shell() -> void:
	content_panel = Control.new()
	content_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_panel)

	stack = VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	content_panel.add_child(stack)

	handle = Button.new()
	handle.name = "RaidDrawerHandle"
	handle.focus_mode = Control.FOCUS_ALL
	handle.pressed.connect(_on_handle_pressed)
	add_child(handle)

	feedback = Label.new()
	feedback.visible = false
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.custom_minimum_size = Vector2(330, 54)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback.add_theme_font_size_override("font_size", 13)
	feedback.add_theme_color_override("font_color", Color("f0e5c8"))
	var feedback_style := StyleBoxFlat.new()
	feedback_style.bg_color = Color("172027F2")
	feedback_style.border_color = Color("8e7951")
	feedback_style.set_border_width_all(1)
	feedback_style.set_corner_radius_all(3)
	feedback.add_theme_stylebox_override("normal", feedback_style)
	add_child(feedback)
	_update_handle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and content_panel != null:
		_layout_shell()


func _layout_shell() -> void:
	if content_panel == null:
		return
	var content_width := _content_width()
	content_panel.position = Vector2.ZERO
	content_panel.size = Vector2(content_width, size.y)
	stack.position = Vector2(3, 2)
	stack.size = Vector2(content_width - 6, maxf(size.y - 4, 1))
	stack.custom_minimum_size = Vector2(content_width - 8, 0)
	handle.position = Vector2(
		content_width,
		maxf((size.y - HANDLE_HEIGHT) * 0.5, 8.0)
	)
	handle.size = Vector2(HANDLE_WIDTH, HANDLE_HEIGHT)
	feedback.position = handle.position + Vector2(HANDLE_WIDTH + 8, 8)
	if slide_tween == null or not slide_tween.is_running():
		position.x = 0.0 if open_now else -content_width
	custom_minimum_size.x = content_width + HANDLE_WIDTH


func _rebuild() -> void:
	refresh_queued = false
	_clear_highlight()
	for child in stack.get_children():
		stack.remove_child(child)
		child.queue_free()
	var members := CampaignState.get_active_members()
	if members.is_empty():
		var empty := Label.new()
		empty.text = "No active raiders"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.custom_minimum_size = Vector2(_content_width() - 8, 60)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("8d9497"))
		stack.add_child(empty)
		return
	var formation := CampaignState.get_formation()
	var placements: Dictionary = formation.get("placements", {})
	var group_size := maxi(TuningCatalogAccess.get_raid_campaign().raid_group_size, 1)
	for member_index in range(members.size()):
		if member_index % group_size == 0:
			var group_label := Label.new()
			group_label.text = "Group %d" % (floori(float(member_index) / group_size) + 1)
			group_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group_label.custom_minimum_size = Vector2(_content_width() - 8, 12)
			group_label.add_theme_font_size_override("font_size", 9)
			group_label.add_theme_color_override("font_color", Color("aaa797"))
			stack.add_child(group_label)
		var member: Dictionary = members[member_index]
		var member_id := String(member.get("member_id", ""))
		var placement_value: Variant = placements.get(member_id, {})
		var member_placement := (
			Dictionary(placement_value) if placement_value is Dictionary else {}
		)
		var frame := CampRaidFrameScript.new() as CampRaidFrame
		frame.name = "CampRaidFrame_" + member_id
		frame.configure(member, menu_context, menu_context == "smith", member_placement)
		frame.member_hovered.connect(_on_member_hovered)
		frame.member_unhovered.connect(_on_member_unhovered)
		frame.equipment_action_completed.connect(_on_equipment_action_completed)
		stack.add_child(frame)


func _queue_refresh() -> void:
	if refresh_queued:
		return
	refresh_queued = true
	call_deferred("_rebuild")


func _on_handle_pressed() -> void:
	if locked:
		return
	manual_open = not manual_open
	_set_open(manual_open, true)


func _set_open(value: bool, animate: bool) -> void:
	open_now = value
	if not value:
		_clear_highlight()
	if slide_tween != null:
		slide_tween.kill()
	var target_x := 0.0 if value else -_content_width()
	if not animate or not is_inside_tree():
		position.x = target_x
		_update_handle()
		return
	slide_tween = create_tween()
	slide_tween.set_trans(Tween.TRANS_CUBIC)
	slide_tween.set_ease(Tween.EASE_OUT if value else Tween.EASE_IN)
	slide_tween.tween_property(self, "position:x", target_x, SLIDE_DURATION)
	_update_handle()


func _update_handle() -> void:
	if handle == null:
		return
	handle.disabled = locked
	handle.text = "X" if locked else "<" if open_now else ">"
	handle.tooltip_text = (
		"Raid drawer is required by %s." % menu_context.replace("_", " ").capitalize()
		if locked else "Close raid drawer" if open_now else "Open raid drawer"
	)


func _on_member_hovered(member_id: String) -> void:
	if highlighted_member_id == member_id:
		return
	_clear_highlight()
	highlighted_member_id = member_id
	var population := _population_controller()
	if population != null and population.has_method("set_raid_drawer_highlight"):
		population.call("set_raid_drawer_highlight", member_id, true)


func _on_member_unhovered(member_id: String) -> void:
	if member_id == highlighted_member_id:
		_clear_highlight()


func _clear_highlight() -> void:
	if highlighted_member_id.is_empty():
		return
	var population := _population_controller()
	if population != null and population.has_method("set_raid_drawer_highlight"):
		population.call("set_raid_drawer_highlight", highlighted_member_id, false)
	highlighted_member_id = ""


func _population_controller() -> Node:
	return get_tree().get_first_node_in_group("camp_population_controller")


func _on_equipment_action_completed(result: Dictionary) -> void:
	_show_feedback(result)


func show_equipment_feedback(result: Dictionary) -> void:
	_show_feedback(result)


func _show_feedback(result: Dictionary) -> void:
	feedback_generation += 1
	var generation := feedback_generation
	feedback.text = String(result.get("message", "Equipment action complete."))
	feedback.add_theme_color_override(
		"font_color", Color("a9d39d") if bool(result.get("ok", false)) else Color("e19a91")
	)
	feedback.visible = true
	get_tree().create_timer(2.8).timeout.connect(
		func() -> void:
			if generation == feedback_generation and feedback != null:
				feedback.visible = false
	)


func _content_width() -> float:
	return CONTEXT_CONTENT_WIDTH if menu_context in REQUIRED_CONTEXTS else BASE_CONTENT_WIDTH
