extends Node2D
class_name CampMemberActor

signal ready_for_activity(member_id: String)
signal activity_completed(member_id: String, activity_id: String)
signal navigation_failed(member_id: String, activity_id: String)
signal bubble_visibility_changed(visible_now: bool)

const CLASS_COLORS := {
	"Warrior": Color("9c5650"),
	"Priest": Color("d6c9a2"),
	"Rogue": Color("677d55"),
	"Mage": Color("5c6f9d")
}

var member: Dictionary = {}
var member_id: String = ""
var state: String = "idle"
var current_activity_id: String = ""
var current_activity_name: String = ""
var path: Array[Vector2] = []
var perform_time_remaining: float = 0.0
var idle_time_remaining: float = 0.0
var navigation_time_remaining: float = 0.0
var move_speed: float = 150.0
var label: Label = null
var bubble: Label = null
var bubble_time_remaining: float = 0.0
var last_activity_id: String = ""
var facing_left: bool = false
var step_phase: float = 0.0


func _ready() -> void:
	_create_labels()
	queue_redraw()


func configure(member_data: Dictionary, spawn_position: Vector2, start_delay: float) -> void:
	member = member_data.duplicate(true)
	member_id = String(member.get("member_id", ""))
	global_position = spawn_position.round()
	idle_time_remaining = start_delay
	state = "idle"
	queue_redraw()

	if label != null:
		label.text = (
			"%s · %s · %s"
			% [
				String(member.get("display_name", "Unknown")),
				String(member.get("unit_class", "")),
				"Active" if bool(member.get("active", false)) else "Reserve"
			]
		)


func start_activity(
	activity_id: String, activity_name: String, waypoints: Array[Vector2], duration: float
) -> void:
	current_activity_id = activity_id
	current_activity_name = activity_name
	path = waypoints.duplicate()
	perform_time_remaining = duration
	navigation_time_remaining = 24.0
	state = "walking" if not path.is_empty() else "performing"
	queue_redraw()


func interrupt_activity() -> void:
	path.clear()
	state = "idle"
	idle_time_remaining = randf_range(0.8, 2.0)
	current_activity_id = ""
	current_activity_name = ""
	queue_redraw()


func show_bubble(text: String, duration: float = 4.5) -> bool:
	if bubble == null or text.is_empty() or bubble.visible:
		return false

	bubble.text = text
	bubble.visible = true
	bubble_time_remaining = duration
	bubble_visibility_changed.emit(true)
	return true


func get_member_id() -> String:
	return member_id


func get_last_activity_id() -> String:
	return last_activity_id


func get_member_data() -> Dictionary:
	return member.duplicate(true)


func _process(delta: float) -> void:
	_update_hover_label()
	_update_bubble(delta)
	z_index = clampi(int(global_position.y / 3.0), 0, 1000)

	match state:
		"idle":
			idle_time_remaining -= delta

			if idle_time_remaining <= 0.0 and not member_id.is_empty():
				idle_time_remaining = 999.0
				ready_for_activity.emit(member_id)

		"walking":
			_update_walking(delta)

		"performing":
			perform_time_remaining -= delta

			if perform_time_remaining <= 0.0:
				var completed_activity := current_activity_id
				last_activity_id = completed_activity
				current_activity_id = ""
				current_activity_name = ""
				state = "idle"
				idle_time_remaining = randf_range(1.2, 3.5)
				activity_completed.emit(member_id, completed_activity)
				queue_redraw()


func _update_walking(delta: float) -> void:
	navigation_time_remaining -= delta

	if navigation_time_remaining <= 0.0:
		var failed_activity := current_activity_id
		path.clear()
		state = "idle"
		idle_time_remaining = 1.0
		navigation_failed.emit(member_id, failed_activity)
		return

	if path.is_empty():
		state = "performing"
		queue_redraw()
		return

	var destination := path[0]
	var distance := global_position.distance_to(destination)

	if distance <= 5.0:
		global_position = destination.round()
		path.remove_at(0)
		return

	var direction := global_position.direction_to(destination)
	facing_left = direction.x < 0.0
	global_position += direction * minf(move_speed * delta, distance)
	global_position = global_position.round()
	step_phase += delta * 9.0
	queue_redraw()


func _update_hover_label() -> void:
	if label == null:
		return

	var hovered := get_global_mouse_position().distance_to(global_position) <= 22.0
	label.visible = hovered


func _update_bubble(delta: float) -> void:
	if bubble == null or not bubble.visible:
		return

	bubble_time_remaining -= delta

	if bubble_time_remaining <= 0.0:
		bubble.visible = false
		bubble_visibility_changed.emit(false)


func _create_labels() -> void:
	label = Label.new()
	label.visible = false
	label.position = Vector2(-70, -54)
	label.size = Vector2(140, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("efe7d1"))
	label.add_theme_color_override("font_shadow_color", Color("0c1114"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)

	bubble = Label.new()
	bubble.visible = false
	bubble.position = Vector2(-90, -82)
	bubble.custom_minimum_size = Vector2(180, 30)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_theme_font_size_override("font_size", 13)
	bubble.add_theme_color_override("font_color", Color("e5dcc6"))
	var bubble_style := StyleBoxFlat.new()
	bubble_style.bg_color = Color("172027e8")
	bubble_style.border_color = Color("7f745f")
	bubble_style.set_border_width_all(1)
	bubble_style.set_corner_radius_all(3)
	bubble.add_theme_stylebox_override("normal", bubble_style)
	add_child(bubble)


func _draw() -> void:
	var unit_class := String(member.get("unit_class", "Mage"))
	var accent: Color = CLASS_COLORS.get(unit_class, Color("79818a"))
	var leg_offset := 0

	if state == "walking":
		leg_offset = int(round(sin(step_phase) * 2.0))

	draw_rect(Rect2(-8, -17, 16, 8), Color("b9a77e"))
	draw_rect(Rect2(-10, -9, 20, 21), Color("273038"))
	draw_rect(Rect2(-7, -7, 14, 15), accent.darkened(0.18))
	draw_rect(Rect2(-9, -2, 3, 8), accent)
	draw_rect(Rect2(6, -2, 3, 8), accent)

	if bool(member.get("active", false)):
		draw_rect(Rect2(-10, -8, 4, 4), Color("c1a45e"))
	draw_rect(Rect2(-7, 11 + leg_offset, 6, 7), Color("171c20"))
	draw_rect(Rect2(1, 11 - leg_offset, 6, 7), Color("171c20"))

	if state == "performing":
		match current_activity_id:
			"study_target", "prepare_plan":
				draw_rect(Rect2(10, -5, 8, 10), Color("bda978"))
			"smith_work":
				draw_line(Vector2(9, -5), Vector2(16, 5), Color("aab2b5"), 3)
			"apothecary_work":
				draw_rect(Rect2(10, -5, 6, 9), Color("688b72"))
			"rehearse", "train":
				draw_line(Vector2(10, -7), Vector2(18, 8), Color("8b7355"), 3)
			"victory_gather":
				draw_rect(Rect2(10, -7, 7, 10), Color("b89a52"))
				draw_rect(Rect2(11, -9, 5, 3), Color("d2c18b"))
