extends CanvasLayer

const CommandDebugPanelScript := preload("res://scripts/ui/command_debug_panel.gd")

signal raid_frame_hovered(unit)
signal raid_frame_unhovered(unit)
signal command_panel_submitted(command_data: Dictionary)

@export var raid_member_frame_scene: PackedScene

@export var raid_panel_margin: Vector2 = Vector2(20, 20)
@export var raid_panel_size: Vector2 = Vector2(1200, 320)
@export var command_panel_reserved_width: float = 340.0

@export var boss_panel_top_margin: float = 20.0
@export var boss_panel_size: Vector2 = Vector2(520, 90)
@export var show_command_debug_in_development: bool = true

@onready var raid_frames_panel: Control = get_node_or_null("RaidFramesPanel")
@onready var raid_frame_grid: GridContainer = get_node_or_null("RaidFramesPanel/RaidFrameGrid")

@onready var boss_frame_panel: Control = get_node_or_null("BossFramePanel")
@onready var boss_name_label: Label = get_node_or_null("BossFramePanel/VBoxContainer/BossNameLabel")
@onready var boss_health_bar: ProgressBar = get_node_or_null("BossFramePanel/VBoxContainer/BossHealthBar")
@onready var boss_cast_bar: ProgressBar = get_node_or_null("BossFramePanel/VBoxContainer/BossCastBar")
@onready var boss_status_label: Label = get_node_or_null("BossFramePanel/VBoxContainer/BossStatusLabel")
@onready var command_panel = get_node_or_null("CommandPanel")

var command_debug_panel: Control = null
var frame_by_unit: Dictionary = {}
var boss: Node = null

func _ready():
	connect_command_panel_signals()
	setup_command_debug_panel()
	position_ui_panels()

	if raid_frame_grid == null:
		print("ERROR: UI cannot find RaidFramesPanel/RaidFrameGrid.")

	if boss_health_bar != null:
		boss_health_bar.show_percentage = false

	if boss_cast_bar != null:
		boss_cast_bar.show_percentage = false
		boss_cast_bar.visible = false

	get_tree().root.size_changed.connect(position_ui_panels)

func position_ui_panels():
	position_raid_frames_panel()
	position_boss_frame_panel()
	position_command_debug_panel()

func position_raid_frames_panel():
	if raid_frames_panel == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var available_width := maxf(
		viewport_size.x - raid_panel_margin.x * 2.0 - command_panel_reserved_width,
		320.0
	)
	var responsive_width := minf(raid_panel_size.x, available_width)
	var column_count := clampi(floori(responsive_width / 220.0), 1, 5)
	var frame_count := frame_by_unit.size()
	var row_count := ceili(float(maxi(frame_count, 1)) / float(column_count))
	var content_height := float(row_count * 72)
	var responsive_size := Vector2(
		responsive_width,
		minf(maxf(raid_panel_size.y, content_height), maxf(viewport_size.y * 0.55, 180.0))
	)

	if raid_frame_grid != null:
		raid_frame_grid.columns = column_count

	raid_frames_panel.size = responsive_size
	raid_frames_panel.position = Vector2(
		raid_panel_margin.x,
		viewport_size.y - responsive_size.y - raid_panel_margin.y
	)

func position_boss_frame_panel():
	if boss_frame_panel == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size

	var responsive_size := Vector2(
		minf(boss_panel_size.x, maxf(viewport_size.x - 40.0, 240.0)),
		boss_panel_size.y
	)

	boss_frame_panel.size = responsive_size
	boss_frame_panel.position = Vector2(
		(viewport_size.x - responsive_size.x) / 2.0,
		boss_panel_top_margin
	)

func setup_raid_frames(units: Array):
	clear_raid_frames()

	if raid_frame_grid == null:
		print("ERROR: Cannot setup raid frames because RaidFrameGrid is missing.")
		return

	if raid_member_frame_scene == null:
		print("ERROR: Raid member frame scene is not assigned on UI.")
		return

	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue

		var frame = raid_member_frame_scene.instantiate()
		raid_frame_grid.add_child(frame)

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

func clear_raid_frames():
	if raid_frame_grid == null:
		return

	for child in raid_frame_grid.get_children():
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
	refresh_boss_frame()

func refresh_boss_frame(update_status: bool = true):
	if boss == null or not is_instance_valid(boss):
		if boss_name_label != null:
			boss_name_label.text = "Boss"

		if boss_health_bar != null:
			boss_health_bar.value = 0

		if boss_cast_bar != null:
			boss_cast_bar.visible = false

		if boss_status_label != null and update_status:
			boss_status_label.text = "Missing"

		return

	update_boss_health_bar()
	update_boss_cast_bar()

	if boss_name_label != null:
		boss_name_label.text = get_boss_display_name()

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
		return

	if boss.has_method("is_casting_ability") and boss.is_casting_ability():
		boss_cast_bar.visible = true
		boss_cast_bar.max_value = 100

		if boss.has_method("get_cast_progress_percent"):
			boss_cast_bar.value = boss.get_cast_progress_percent()
		else:
			boss_cast_bar.value = 0
	else:
		boss_cast_bar.visible = false
		boss_cast_bar.value = 0

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
	if command_panel == null:
		return

	if not command_panel.has_signal("command_submitted"):
		return

	var callback := Callable(self, "_on_command_panel_submitted")

	if not command_panel.is_connected("command_submitted", callback):
		command_panel.connect("command_submitted", callback)
func setup_command_panel(party_members: Array) -> void:
	if command_panel == null:
		return

	if command_panel.has_method("setup_units"):
		command_panel.setup_units(party_members)
func _on_command_panel_submitted(command_data: Dictionary) -> void:
	command_panel_submitted.emit(command_data)
func setup_command_debug_panel() -> void:
	command_debug_panel = get_node_or_null("CommandDebugPanel") as Control

	if command_debug_panel == null:
		command_debug_panel = CommandDebugPanelScript.new()
		command_debug_panel.name = "CommandDebugPanel"
		add_child(command_debug_panel)

	command_debug_panel.visible = show_command_debug_in_development and OS.is_debug_build()

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
