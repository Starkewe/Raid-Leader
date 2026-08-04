extends CanvasLayer

const CommandDebugPanelScript := preload("res://scripts/ui/command_debug_panel.gd")

const RAID_GROUP_SIZE := 5
const RAID_GROUP_COUNT := 4
const RAID_GROUP_LABEL_FONT_SIZE := 10
const RAID_GROUP_LABEL_HEIGHT := 12.0

signal raid_frame_hovered(unit)
signal raid_frame_unhovered(unit)
signal command_panel_submitted(command_data: Dictionary)

@export var raid_member_frame_scene: PackedScene

@export var raid_panel_margin: Vector2 = Vector2(12, 8)
@export var raid_frame_size: Vector2 = Vector2(154, 50)
@export var raid_group_separation: int = 2
@export var raid_frame_separation: int = 0

@export var boss_overlay_size: Vector2 = Vector2(360.0, 92.0)
@export var boss_overlay_offset: Vector2 = Vector2(0.0, -176.0)
@export var show_command_debug_in_development: bool = true
@export var show_legacy_command_panel_in_development: bool = false

@onready var raid_frames_panel: Control = get_node_or_null("RaidFramesPanel")
@onready var raid_frame_stack: VBoxContainer = get_node_or_null(
	"RaidFramesPanel/RaidFrameStack"
) as VBoxContainer

@onready var boss_frame_panel: Control = get_node_or_null("BossFramePanel")
@onready var boss_name_label: Label = get_node_or_null("BossFramePanel/VBoxContainer/BossNameLabel")
@onready var boss_health_bar: ProgressBar = get_node_or_null("BossFramePanel/VBoxContainer/BossHealthBar")
@onready var boss_cast_bar: ProgressBar = get_node_or_null("BossFramePanel/VBoxContainer/BossCastBar")
@onready var boss_cast_label: Label = get_node_or_null(
	"BossFramePanel/VBoxContainer/BossCastBar/BossCastLabel"
)
@onready var boss_status_label: Label = get_node_or_null("BossFramePanel/VBoxContainer/BossStatusLabel")
@onready var command_panel = get_node_or_null("CommandPanel")
@onready var raid_command_bar: RaidCommandBar = get_node_or_null("RaidCommandBar") as RaidCommandBar

var command_debug_panel: Control = null
var frame_by_unit: Dictionary = {}
var boss: Node = null

func _ready():
	configure_command_interfaces()
	connect_command_panel_signals()
	setup_command_debug_panel()

	if boss_frame_panel != null:
		boss_frame_panel.visible = false

	position_ui_panels()

	if raid_frame_stack == null:
		print("ERROR: UI cannot find RaidFramesPanel/RaidFrameStack.")
	else:
		raid_frame_stack.add_theme_constant_override("separation", raid_group_separation)

	if boss_health_bar != null:
		boss_health_bar.show_percentage = false

	if boss_cast_bar != null:
		boss_cast_bar.show_percentage = false
		boss_cast_bar.visible = false

	get_tree().root.size_changed.connect(position_ui_panels)


func _process(_delta: float) -> void:
	position_boss_frame_panel()

func position_ui_panels():
	position_raid_frames_panel()
	position_boss_frame_panel()
	position_command_debug_panel()

func position_raid_frames_panel():
	if raid_frames_panel == null or raid_frame_stack == null:
		return

	var content_size := raid_frame_stack.get_combined_minimum_size()
	raid_frames_panel.size = content_size
	raid_frames_panel.position = raid_panel_margin

func position_boss_frame_panel():
	if boss_frame_panel == null:
		return

	if boss == null or not is_instance_valid(boss) or not boss is Node2D:
		boss_frame_panel.visible = false
		return

	var boss_world_position := (boss as Node2D).global_position
	var boss_screen_position := get_viewport().get_canvas_transform() * boss_world_position
	boss_frame_panel.size = boss_overlay_size
	boss_frame_panel.position = (
		boss_screen_position + boss_overlay_offset - boss_overlay_size * 0.5
	).round()
	boss_frame_panel.visible = true

func setup_raid_frames(units: Array):
	clear_raid_frames()

	if raid_frame_stack == null:
		print("ERROR: Cannot setup raid frames because RaidFrameStack is missing.")
		return

	if raid_member_frame_scene == null:
		print("ERROR: Raid member frame scene is not assigned on UI.")
		return

	for group_index in range(RAID_GROUP_COUNT):
		var group_start := group_index * RAID_GROUP_SIZE
		var group_end := mini(group_start + RAID_GROUP_SIZE, units.size())
		var group_units: Array = []

		for unit_index in range(group_start, group_end):
			var unit = units[unit_index]

			if unit != null and is_instance_valid(unit):
				group_units.append(unit)

		if group_units.is_empty():
			continue

		var group_number := group_index + 1
		var group_section := _create_raid_group_section(group_number)
		raid_frame_stack.add_child(group_section)
		var member_stack := group_section.get_node("MemberFrames") as VBoxContainer

		for unit in group_units:
			var frame = raid_member_frame_scene.instantiate()
			frame.custom_minimum_size = raid_frame_size
			member_stack.add_child(frame)

			var display_name = get_unit_display_name(unit)

			if frame.has_method("setup"):
				frame.setup(unit, display_name)
			else:
				print("ERROR: Raid frame scene root is missing setup(). Check raid_member_frame.gd.")

			if frame.has_signal("hovered"):
				frame.hovered.connect(_on_raid_member_frame_hovered)

			if frame.has_signal("unhovered"):
				frame.unhovered.connect(_on_raid_member_frame_unhovered)

			frame_by_unit[unit] = frame

	position_raid_frames_panel()


func _create_raid_group_section(group_number: int) -> VBoxContainer:
	var group_section := VBoxContainer.new()
	group_section.name = "Group%dSection" % group_number
	group_section.custom_minimum_size = Vector2(raid_frame_size.x, 0.0)
	group_section.add_theme_constant_override("separation", 0)

	var group_label := Label.new()
	group_label.name = "GroupLabel"
	group_label.text = "Group %d" % group_number
	group_label.custom_minimum_size = Vector2(raid_frame_size.x, RAID_GROUP_LABEL_HEIGHT)
	group_label.add_theme_font_size_override("font_size", RAID_GROUP_LABEL_FONT_SIZE)
	group_label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.56, 1.0))
	group_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.025, 0.96))
	group_label.add_theme_constant_override("outline_size", 2)
	group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	group_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	group_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group_section.add_child(group_label)

	var member_stack := VBoxContainer.new()
	member_stack.name = "MemberFrames"
	member_stack.add_theme_constant_override("separation", raid_frame_separation)
	group_section.add_child(member_stack)

	return group_section


func clear_raid_frames():
	if raid_frame_stack == null:
		return

	for child in raid_frame_stack.get_children():
		raid_frame_stack.remove_child(child)
		child.queue_free()

	frame_by_unit.clear()

func refresh_raid_frames(status_overrides: Dictionary = {}):
	for unit in frame_by_unit.keys():
		if unit == null or not is_instance_valid(unit):
			continue

		var frame = frame_by_unit[unit]

		if frame == null or not is_instance_valid(frame):
			continue

		var use_status_override = status_overrides.has(unit)

		if frame.has_method("update_from_unit"):
			frame.update_from_unit(not use_status_override)

		if use_status_override and frame.has_method("set_status_text"):
			frame.set_status_text(status_overrides[unit])

		if frame.has_method("set_boss_target"):
			frame.set_boss_target(unit == get_boss_target())

func set_unit_status(unit: Node, text: String):
	if unit == null:
		return

	if not frame_by_unit.has(unit):
		return

	var frame = frame_by_unit[unit]

	if frame.has_method("set_status_text"):
		frame.set_status_text(text)

func setup_boss_frame(new_boss: Node):
	boss = new_boss
	set_boss_target(get_boss_target())
	refresh_boss_frame()
	position_boss_frame_panel()


func set_boss_target(target: Node) -> void:
	for unit in frame_by_unit.keys():
		if unit == null or not is_instance_valid(unit):
			continue

		var frame = frame_by_unit[unit]

		if frame != null and is_instance_valid(frame) and frame.has_method("set_boss_target"):
			frame.set_boss_target(unit == target)


func get_boss_target() -> Node:
	if boss != null and is_instance_valid(boss) and boss.has_method("get_current_target"):
		return boss.get_current_target()

	return null

func refresh_boss_frame(update_status: bool = true):
	if boss == null or not is_instance_valid(boss):
		if boss_name_label != null:
			boss_name_label.text = "Boss"

		if boss_health_bar != null:
			boss_health_bar.value = 0

		if boss_cast_bar != null:
			boss_cast_bar.visible = false

		if boss_cast_label != null:
			boss_cast_label.text = ""

		if boss_status_label != null and update_status:
			boss_status_label.text = "Missing"

		return

	update_boss_health_bar()
	update_boss_cast_bar()

	if boss_status_label != null and update_status:
		if boss.has_method("get_status_text"):
			boss_status_label.text = boss.get_status_text()
		else:
			boss_status_label.text = "Idle"

func update_boss_health_bar():
	if boss_health_bar == null:
		return

	var current_health := get_boss_current_health()
	var max_health := get_boss_max_health()

	boss_health_bar.max_value = max(max_health, 1)
	boss_health_bar.value = clamp(current_health, 0, max_health)

	if boss_name_label != null:
		boss_name_label.text = get_boss_display_name() + "  " + str(current_health) + "/" + str(max_health)

func update_boss_cast_bar():
	if boss_cast_bar == null:
		return

	if boss == null or not is_instance_valid(boss):
		boss_cast_bar.visible = false

		if boss_cast_label != null:
			boss_cast_label.text = ""

		return

	if boss.has_method("is_casting_ability") and boss.is_casting_ability():
		boss_cast_bar.visible = true
		boss_cast_bar.max_value = 100

		if boss.has_method("get_cast_progress_percent"):
			boss_cast_bar.value = boss.get_cast_progress_percent()
		else:
			boss_cast_bar.value = 0

		if boss_cast_label != null:
			var cast_name := (
				String(boss.get_cast_name()) if boss.has_method("get_cast_name") else ""
			)
			boss_cast_label.text = cast_name if not cast_name.is_empty() else "Casting"
	else:
		boss_cast_bar.visible = false
		boss_cast_bar.value = 0

		if boss_cast_label != null:
			boss_cast_label.text = ""

func set_boss_status(text: String):
	if boss_status_label != null:
		boss_status_label.text = text

func get_boss_display_name() -> String:
	if boss == null or not is_instance_valid(boss):
		return "Boss"

	if boss.has_method("get_display_name"):
		return boss.get_display_name()

	return boss.name

func get_boss_current_health() -> int:
	if boss == null or not is_instance_valid(boss):
		return 0

	if boss.has_method("get_current_health"):
		return boss.get_current_health()

	var value = boss.get("health")

	if value == null:
		return 0

	return int(value)

func get_boss_max_health() -> int:
	if boss == null or not is_instance_valid(boss):
		return 1

	if boss.has_method("get_max_health"):
		return boss.get_max_health()

	var value = boss.get("max_health")

	if value == null:
		return 1

	return int(value)

func get_unit_display_name(unit: Node) -> String:
	if unit.has_method("get_display_name"):
		return unit.get_display_name()

	return unit.name
func _on_raid_member_frame_hovered(unit: Node):
	raid_frame_hovered.emit(unit)

func _on_raid_member_frame_unhovered(unit: Node):
	raid_frame_unhovered.emit(unit)
func connect_command_panel_signals() -> void:
	if command_panel == null or not command_panel.visible:
		return

	if not command_panel.has_signal("command_submitted"):
		return

	var callback := Callable(self, "_on_command_panel_submitted")

	if not command_panel.is_connected("command_submitted", callback):
		command_panel.connect("command_submitted", callback)
func setup_command_panel(party_members: Array) -> void:
	if command_panel != null and command_panel.has_method("setup_units"):
		command_panel.setup_units(party_members)

	if raid_command_bar != null:
		raid_command_bar.setup_units(party_members)
func _on_command_panel_submitted(command_data: Dictionary) -> void:
	command_panel_submitted.emit(command_data)
func setup_command_debug_panel() -> void:
	command_debug_panel = get_node_or_null("CommandDebugPanel") as Control

	if command_debug_panel == null:
		command_debug_panel = CommandDebugPanelScript.new()
		command_debug_panel.name = "CommandDebugPanel"
		add_child(command_debug_panel)

	GameState.register_raid_debug_content(
		command_debug_panel,
		show_command_debug_in_development and OS.is_debug_build()
	)

	position_command_debug_panel()


func position_command_debug_panel() -> void:
	if command_debug_panel == null:
		return

	command_debug_panel.position = Vector2(20, 20)


func set_command_debug_info(data: Dictionary) -> void:
	if command_debug_panel == null:
		return

	if command_debug_panel.has_method("set_debug_data"):
		command_debug_panel.set_debug_data(data)


func clear_command_debug_info() -> void:
	if command_debug_panel == null:
		return

	if command_debug_panel.has_method("clear_debug_data"):
		command_debug_panel.clear_debug_data()


func set_voice_status(text: String, is_error: bool = false) -> void:
	if command_panel != null and command_panel.has_method("set_voice_status"):
		command_panel.set_voice_status(text, is_error)


func notify_transcription_started() -> void:
	if raid_command_bar != null:
		raid_command_bar.notify_transcription_started()


func display_parsed_command(parsed_result: Dictionary) -> void:
	if raid_command_bar != null:
		raid_command_bar.display_parsed_command(parsed_result)


func clear_raid_command_transcription(immediate: bool = false) -> void:
	if raid_command_bar != null:
		raid_command_bar.clear_transcription(immediate)


func configure_command_interfaces() -> void:
	var show_legacy := show_legacy_command_panel_in_development and OS.is_debug_build()

	if command_panel != null:
		command_panel.visible = show_legacy

	if raid_command_bar != null:
		raid_command_bar.visible = not show_legacy
