extends Control
class_name RaidCommandBar

const RaidCommandReferenceCatalogScript := preload(
	"res://scripts/ui/raid_command_reference_catalog.gd"
)

const HOVER_OVERLAY := preload(
	"res://assets/ui/raid_command_bar/raid_command_tab_hover.png"
)
const OPEN_OVERLAY := preload(
	"res://assets/ui/raid_command_bar/raid_command_tab_open.png"
)
const MUTED_OVERLAY := preload(
	"res://assets/ui/raid_command_bar/raid_command_tab_muted.png"
)

const CATEGORY_ORDER: Array[String] = ["who", "what", "where", "when"]
const CATEGORY_TITLES := {
	"who": "Who",
	"what": "What",
	"where": "Where",
	"when": "When"
}

const STAGGER_DELAY_SECONDS: float = 0.125
const ENTRANCE_DURATION_SECONDS: float = 0.18
const ENTRANCE_OFFSET_PIXELS: float = 8.0
const HOLD_DURATION_SECONDS: float = 1.0
const FADE_DURATION_SECONDS: float = 0.25
const FEEDBACK_HOLD_SECONDS: float = 1.5
const POPOVER_SIZE := Vector2(600.0, 356.0)
const POPOVER_TOP: float = 144.0

var party_members: Array = []
var _game_state: Node = null
var _open_category: String = ""
var _hovered_categories: Dictionary = {}
var _category_regions: Dictionary = {}
var _category_buttons: Dictionary = {}
var _category_overlays: Dictionary = {}
var _transcription_labels: Dictionary = {}
var _transcription_rest_y: Dictionary = {}
var _feedback_labels: Dictionary = {}
var _transcription_tweens: Dictionary = {}
var _clear_tween: Tween = null
var _feedback_tween: Tween = null
var _transcription_generation: int = 0
var _feedback_generation: int = 0
var _reference_context: Dictionary = {
	"has_explicit_who": false,
	"what": ""
}

@onready var _reference_panel: PanelContainer = $CommandReferencePopover
@onready var _reference_title: Label = null
@onready var _reference_entries: VBoxContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("escape_modal")
	_game_state = get_node_or_null("/root/GameState")
	_cache_scene_nodes()
	_connect_category_buttons()
	_build_reference_panel()
	_reset_transcription_labels()
	_reset_feedback_labels()
	_update_all_category_overlays()


func setup_units(new_party_members: Array) -> void:
	party_members = new_party_members.duplicate()

	if is_open():
		_rebuild_reference_entries()


func notify_transcription_started() -> void:
	clear_transcription(false)


func display_parsed_command(parsed_result: Dictionary) -> void:
	_transcription_generation += 1
	_cancel_transcription_animation()
	_reset_transcription_labels()
	_update_reference_context(parsed_result)

	var recognized_values := _extract_recognized_values(parsed_result)
	var stagger_index: int = 0

	for category in CATEGORY_ORDER:
		var value := String(recognized_values.get(category, "")).strip_edges()

		if value.is_empty():
			continue

		_animate_transcription_label(
			category,
			value,
			float(stagger_index) * STAGGER_DELAY_SECONDS,
			_transcription_generation
		)
		stagger_index += 1

	if is_open():
		_rebuild_reference_entries()


func clear_transcription(immediate: bool = false) -> void:
	_transcription_generation += 1
	_cancel_transcription_animation()

	if immediate:
		_reset_transcription_labels()
		return

	var visible_labels: Array[Label] = []

	for category in CATEGORY_ORDER:
		var label := _transcription_labels.get(category) as Label

		if label == null:
			continue

		if label.visible and label.modulate.a > 0.001:
			visible_labels.append(label)
		else:
			_reset_transcription_label(category, label)

	if visible_labels.is_empty():
		return

	var generation := _transcription_generation
	_clear_tween = create_tween()
	_clear_tween.set_parallel(true)

	for label in visible_labels:
		_clear_tween.tween_property(
			label,
			"modulate:a",
			0.0,
			FADE_DURATION_SECONDS
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_clear_tween.chain().tween_callback(_finish_clear.bind(generation))


func open_reference_category(category: String) -> void:
	if not CATEGORY_ORDER.has(category):
		return

	_open_category = category
	_reference_panel.visible = true
	_reference_title.text = String(CATEGORY_TITLES.get(category, category.capitalize()))
	_position_reference_popover(category)
	_rebuild_reference_entries()
	_update_all_category_overlays()

	if category == "when":
		show_dependency_feedback(category, "Timing commands are not yet available.")


func close_reference_panel() -> void:
	if _open_category.is_empty() and not _reference_panel.visible:
		return

	_open_category = ""
	_reference_panel.visible = false
	_update_all_category_overlays()


func is_open() -> bool:
	return _reference_panel != null and _reference_panel.visible


func close_for_escape() -> void:
	close_reference_panel()


func show_dependency_feedback(category: String, message: String) -> void:
	if not _feedback_labels.has(category):
		return

	_feedback_generation += 1
	_cancel_feedback_animation()
	_reset_feedback_labels()

	var label := _feedback_labels.get(category) as Label

	if label == null:
		return

	var generation := _feedback_generation
	label.text = message
	label.modulate.a = 1.0
	label.visible = true
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(FEEDBACK_HOLD_SECONDS)
	_feedback_tween.tween_property(
		label,
		"modulate:a",
		0.0,
		FADE_DURATION_SECONDS
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_callback(_finish_feedback.bind(generation))


func _input(event: InputEvent) -> void:
	if not is_open():
		return

	var mouse_event := event as InputEventMouseButton

	if mouse_event == null:
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	if _reference_panel.get_global_rect().has_point(mouse_event.position):
		return

	for category in CATEGORY_ORDER:
		var region := _category_regions.get(category) as Control

		if region != null and region.get_global_rect().has_point(mouse_event.position):
			return

	close_reference_panel()


func _cache_scene_nodes() -> void:
	for category in CATEGORY_ORDER:
		var title := String(CATEGORY_TITLES.get(category, category.capitalize()))
		var region := get_node("CategoryInteractionLayer/%sRegion" % title) as Control
		var button := region.get_node("HitRegion") as Button
		var overlay := region.get_node("StateOverlay") as TextureRect
		var transcription := get_node(
			"TranscriptionLayer/%sTranscription" % title
		) as Label
		var feedback := get_node(
			"DependencyFeedbackLayer/%sFeedback" % title
		) as Label

		_category_regions[category] = region
		_category_buttons[category] = button
		_category_overlays[category] = overlay
		_transcription_labels[category] = transcription
		_transcription_rest_y[category] = transcription.position.y
		_feedback_labels[category] = feedback
		_hovered_categories[category] = false


func _connect_category_buttons() -> void:
	var empty_style := StyleBoxEmpty.new()

	for category in CATEGORY_ORDER:
		var button := _category_buttons.get(category) as Button

		if button == null:
			continue

		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(style_name, empty_style)

		button.mouse_entered.connect(_on_category_hover_changed.bind(category, true))
		button.mouse_exited.connect(_on_category_hover_changed.bind(category, false))
		button.pressed.connect(_on_category_pressed.bind(category))


func _build_reference_panel() -> void:
	_reference_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_reference_panel.add_theme_stylebox_override("panel", _reference_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 13)
	margin.add_theme_constant_override("margin_bottom", 14)
	_reference_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_reference_title = Label.new()
	_reference_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reference_title.add_theme_font_size_override("font_size", 20)
	_reference_title.add_theme_color_override("font_color", Color("d5c18a"))
	root.add_child(_reference_title)
	root.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(568.0, 294.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	_reference_entries = VBoxContainer.new()
	_reference_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reference_entries.add_theme_constant_override("separation", 3)
	scroll.add_child(_reference_entries)
	_reference_panel.visible = false


func _reference_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("11191feF")
	style.border_color = Color("77694f")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _rebuild_reference_entries() -> void:
	if _reference_entries == null or _open_category.is_empty():
		return

	for child in _reference_entries.get_children():
		_reference_entries.remove_child(child)
		child.queue_free()

	var sections := RaidCommandReferenceCatalogScript.get_reference_sections(
		_open_category,
		party_members,
		_game_state
	)

	for section_value in sections:
		var section: Dictionary = section_value
		var heading := Label.new()
		heading.text = String(section.get("heading", "Options"))
		heading.add_theme_font_size_override("font_size", 15)
		heading.add_theme_color_override("font_color", Color("c9b37b"))
		heading.add_theme_constant_override("outline_size", 1)
		_reference_entries.add_child(heading)

		var entries: Array = section.get("entries", [])

		for entry_value in entries:
			_add_reference_entry(Dictionary(entry_value))


func _add_reference_entry(entry: Dictionary) -> void:
	var requirement := _get_entry_requirement(entry)
	var button := Button.new()
	button.text = String(entry.get("label", ""))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 30.0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 14)

	if requirement.is_empty():
		button.add_theme_color_override("font_color", Color("ded4bc"))
		button.add_theme_color_override("font_hover_color", Color("f0dfad"))
	else:
		button.add_theme_color_override("font_color", Color("817d72"))
		button.add_theme_color_override("font_hover_color", Color("aaa18b"))
		button.pressed.connect(
			_on_reference_entry_pressed.bind(_open_category, requirement)
		)

	_reference_entries.add_child(button)


func _get_entry_requirement(entry: Dictionary) -> String:
	if bool(entry.get("unavailable", false)):
		return "Timing commands are not yet available."

	if (
		bool(entry.get("requires_who", false))
		and not bool(_reference_context.get("has_explicit_who", false))
	):
		return "A Who target is required first."

	var required_action := String(entry.get("required_action", ""))

	if required_action.is_empty():
		return ""

	var current_action := String(_reference_context.get("what", ""))

	if current_action.is_empty():
		return "A What action is required first."

	if current_action != required_action:
		return "This option requires the %s action." % required_action.capitalize()

	return ""


func _on_reference_entry_pressed(category: String, requirement: String) -> void:
	if requirement.is_empty():
		return

	show_dependency_feedback(category, requirement)


func _on_category_pressed(category: String) -> void:
	if _open_category == category:
		close_reference_panel()
		return

	open_reference_category(category)


func _on_category_hover_changed(category: String, hovered: bool) -> void:
	_hovered_categories[category] = hovered
	_update_category_overlay(category)


func _update_all_category_overlays() -> void:
	for category in CATEGORY_ORDER:
		_update_category_overlay(category)


func _update_category_overlay(category: String) -> void:
	var overlay := _category_overlays.get(category) as TextureRect

	if overlay == null:
		return

	if category == "when":
		overlay.texture = MUTED_OVERLAY
		overlay.visible = true
	elif _open_category == category:
		overlay.texture = OPEN_OVERLAY
		overlay.visible = true
	elif bool(_hovered_categories.get(category, false)):
		overlay.texture = HOVER_OVERLAY
		overlay.visible = true
	else:
		overlay.texture = null
		overlay.visible = false


func _position_reference_popover(category: String) -> void:
	var region := _category_regions.get(category) as Control
	var desired_left := (size.x - POPOVER_SIZE.x) * 0.5

	if region != null:
		desired_left = region.position.x + region.size.x * 0.5 - POPOVER_SIZE.x * 0.5

	var left := floorf(clampf(desired_left, 0.0, size.x - POPOVER_SIZE.x))
	_reference_panel.position = Vector2(left, POPOVER_TOP)
	_reference_panel.size = POPOVER_SIZE


func _extract_recognized_values(parsed_result: Dictionary) -> Dictionary:
	if not bool(parsed_result.get("ok", false)):
		return {}

	var command_resolution: Dictionary = parsed_result.get("command_resolution", {})
	var slot_states: Dictionary = command_resolution.get("slot_states", {})
	var ownership: Array = command_resolution.get("slot_ownership", [])
	var command_data: Dictionary = parsed_result.get("command_data", {})
	var values: Dictionary = {}

	for category in CATEGORY_ORDER:
		if String(slot_states.get(category, "")) != "explicit":
			continue

		var value := _get_owned_slot_value(category, ownership)

		if value.is_empty():
			value = _get_explicit_fallback_value(category, parsed_result, command_data)

		if not value.is_empty():
			values[category] = _presentation_case(value)

	return values


func _get_owned_slot_value(category: String, ownership: Array) -> String:
	var best_value := ""

	for span_value in ownership:
		if not span_value is Dictionary:
			continue

		var span: Dictionary = span_value

		if String(span.get("slot", "")).to_lower() != category:
			continue

		var candidate := (
			String(span.get("text", ""))
			if category == "who"
			else String(span.get("canonical", span.get("text", "")))
		)

		if candidate.length() > best_value.length():
			best_value = candidate

	return best_value.strip_edges()


func _get_explicit_fallback_value(
	category: String,
	parsed_result: Dictionary,
	command_data: Dictionary
) -> String:
	match category:
		"who":
			var who_resolution: Dictionary = parsed_result.get("who_resolution", {})
			return String(who_resolution.get("who_text", ""))
		"what":
			return String(command_data.get("what", "")).capitalize()
		"where":
			return RaidCommandReferenceCatalogScript.get_where_display_label(command_data)
		"when":
			return "Now"

	return ""


func _presentation_case(value: String) -> String:
	var stripped := value.strip_edges()

	if stripped.is_empty():
		return ""

	return stripped.substr(0, 1).to_upper() + stripped.substr(1)


func _update_reference_context(parsed_result: Dictionary) -> void:
	var command_resolution: Dictionary = parsed_result.get("command_resolution", {})
	var slot_states: Dictionary = command_resolution.get("slot_states", {})
	var command_data: Dictionary = parsed_result.get("command_data", {})
	_reference_context = {
		"has_explicit_who": String(slot_states.get("who", "")) == "explicit",
		"what": String(command_data.get("what", ""))
	}


func _animate_transcription_label(
	category: String,
	value: String,
	delay_seconds: float,
	generation: int
) -> void:
	var label := _transcription_labels.get(category) as Label

	if label == null:
		return

	var final_y := float(_transcription_rest_y.get(category, label.position.y))
	label.text = value
	label.position.y = final_y - ENTRANCE_OFFSET_PIXELS
	label.modulate.a = 0.0
	label.visible = true

	var tween := create_tween()
	_transcription_tweens[category] = tween
	tween.tween_interval(delay_seconds)
	tween.tween_property(
		label,
		"position:y",
		final_y,
		ENTRANCE_DURATION_SECONDS
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(
		label,
		"modulate:a",
		1.0,
		ENTRANCE_DURATION_SECONDS
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_DURATION_SECONDS)
	tween.tween_property(
		label,
		"modulate:a",
		0.0,
		FADE_DURATION_SECONDS
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_transcription_label.bind(category, generation))


func _finish_transcription_label(category: String, generation: int) -> void:
	if generation != _transcription_generation:
		return

	var label := _transcription_labels.get(category) as Label

	if label != null:
		_reset_transcription_label(category, label)

	_transcription_tweens.erase(category)


func _finish_clear(generation: int) -> void:
	if generation != _transcription_generation:
		return

	_reset_transcription_labels()
	_clear_tween = null


func _finish_feedback(generation: int) -> void:
	if generation != _feedback_generation:
		return

	_reset_feedback_labels()
	_feedback_tween = null


func _cancel_transcription_animation() -> void:
	for tween_value in _transcription_tweens.values():
		var tween := tween_value as Tween

		if tween != null and tween.is_valid():
			tween.kill()

	_transcription_tweens.clear()

	if _clear_tween != null and _clear_tween.is_valid():
		_clear_tween.kill()

	_clear_tween = null


func _cancel_feedback_animation() -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()

	_feedback_tween = null


func _reset_transcription_labels() -> void:
	for category in CATEGORY_ORDER:
		var label := _transcription_labels.get(category) as Label

		if label != null:
			_reset_transcription_label(category, label)


func _reset_transcription_label(category: String, label: Label) -> void:
	label.visible = false
	label.text = ""
	label.modulate.a = 0.0
	label.position.y = float(_transcription_rest_y.get(category, label.position.y))


func _reset_feedback_labels() -> void:
	for category in CATEGORY_ORDER:
		var label := _feedback_labels.get(category) as Label

		if label == null:
			continue

		label.visible = false
		label.text = ""
		label.modulate.a = 0.0
