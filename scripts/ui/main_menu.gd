extends Control

@export_file("*.tscn") var combat_scene_path: String = "res://scenes/combat_scene.tscn"

@onready var main_menu_container: CenterContainer = $CenterContainer
@onready var start_fight_button: Button = $CenterContainer/VBoxContainer/StartFightButton
@onready var manage_team_button: Button = $CenterContainer/VBoxContainer/ManageTeamButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

@onready var team_panel: PanelContainer = $TeamPanel
@onready var total_label: Label = $TeamPanel/CenterContainer/VBoxContainer/TotalLabel
@onready var roster_rows: VBoxContainer = $TeamPanel/CenterContainer/VBoxContainer/RosterRows
@onready var start_fight_from_team_button: Button = $TeamPanel/CenterContainer/VBoxContainer/StartFightFromTeamButton
@onready var back_button: Button = $TeamPanel/CenterContainer/VBoxContainer/BackButton
@onready var main_menu_vbox: VBoxContainer = $CenterContainer/VBoxContainer

var tutorial_button: Button = null
var settings_button: Button = null
var encounter_dropdown: OptionButton = null

var tutorial_panel: PanelContainer = null
var tutorial_grid: GridContainer = null
var tutorial_description_label: Label = null
var start_tutorial_button: Button = null

var settings_panel: PanelContainer = null
var speech_to_text_dropdown: OptionButton = null

var unit_class_order: Array[String] = []
var count_labels: Dictionary = {}

func _ready():
	unit_class_order = GameState.get_available_classes()
	start_fight_button.text = "Enter Camp"
	manage_team_button.text = "Tutorial Test Roster"
	start_fight_from_team_button.text = "Done"

	start_fight_button.pressed.connect(_on_start_fight_pressed)
	manage_team_button.pressed.connect(_on_manage_team_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	start_fight_from_team_button.pressed.connect(_on_back_pressed)
	back_button.pressed.connect(_on_back_pressed)

	build_main_menu_extra_buttons()
	build_tutorial_panel()
	build_settings_panel()
	build_team_rows()
	show_main_menu()

func build_main_menu_extra_buttons() -> void:
	tutorial_button = Button.new()
	tutorial_button.text = "Tutorial"
	tutorial_button.pressed.connect(_on_tutorial_pressed)

	settings_button = Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_on_settings_pressed)

	main_menu_vbox.add_child(tutorial_button)
	main_menu_vbox.add_child(settings_button)

	main_menu_vbox.move_child(tutorial_button, 2)
	main_menu_vbox.move_child(settings_button, 3)


func build_normal_encounter_selector() -> void:
	var label := Label.new()
	label.text = "Beast Crucible Encounter"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_menu_vbox.add_child(label)
	main_menu_vbox.move_child(label, 1)

	encounter_dropdown = OptionButton.new()
	main_menu_vbox.add_child(encounter_dropdown)
	main_menu_vbox.move_child(encounter_dropdown, 2)

	var selected_id := GameState.get_selected_normal_encounter_id()

	for encounter_id in GameState.get_normal_encounter_ids():
		var encounter_data: Dictionary = GameState.get_encounter_data(encounter_id)
		var option_index := encounter_dropdown.item_count
		encounter_dropdown.add_item(String(encounter_data.get("display_name", encounter_id)))
		encounter_dropdown.set_item_metadata(option_index, encounter_id)

		if encounter_id == selected_id:
			encounter_dropdown.select(option_index)

	encounter_dropdown.item_selected.connect(_on_normal_encounter_selected)


func _on_normal_encounter_selected(index: int) -> void:
	if encounter_dropdown == null or index < 0 or index >= encounter_dropdown.item_count:
		return

	GameState.set_selected_normal_encounter(
		String(encounter_dropdown.get_item_metadata(index))
	)


func build_tutorial_panel() -> void:
	tutorial_panel = PanelContainer.new()
	tutorial_panel.visible = false
	add_child(tutorial_panel)

	var center := CenterContainer.new()
	tutorial_panel.add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(700, 420)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var title := Label.new()
	title.text = "Tutorial Bosses"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	tutorial_grid = GridContainer.new()
	tutorial_grid.columns = 5
	root.add_child(tutorial_grid)

	build_tutorial_boss_buttons()

	tutorial_description_label = Label.new()
	tutorial_description_label.text = "Select a tutorial boss."
	tutorial_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(tutorial_description_label)

	start_tutorial_button = Button.new()
	start_tutorial_button.text = "Start Tutorial"
	start_tutorial_button.disabled = true
	start_tutorial_button.pressed.connect(_on_start_tutorial_pressed)
	root.add_child(start_tutorial_button)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	root.add_child(back)

	position_fullscreen_panel(tutorial_panel)


func build_tutorial_boss_buttons() -> void:
	for child in tutorial_grid.get_children():
		child.queue_free()

	var boss_ids: Array[String] = GameState.get_tutorial_boss_ids()

	for boss_id in boss_ids:
		var boss_data: Dictionary = GameState.get_tutorial_boss_data(boss_id)

		var button := Button.new()
		button.custom_minimum_size = Vector2(130, 60)
		button.text = String(boss_data.get("display_name", boss_id))
		button.pressed.connect(_on_tutorial_boss_selected.bind(boss_id))

		tutorial_grid.add_child(button)
func build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.visible = false
	add_child(settings_panel)

	var center := CenterContainer.new()
	settings_panel.add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(700, 420)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	speech_to_text_dropdown = add_model_dropdown(
	root,
	"Speech-to-Text Model",
	"speech_to_text_model",
	GameState.get_speech_to_text_model_options()
	)

	var apply_button := Button.new()
	apply_button.text = "Apply Settings"
	apply_button.pressed.connect(_on_apply_settings_pressed)
	root.add_child(apply_button)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	root.add_child(back)

	position_fullscreen_panel(settings_panel)

func add_model_dropdown(
	parent: Node,
	label_text: String,
	setting_name: String,
	options: Array
) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var dropdown := OptionButton.new()
	parent.add_child(dropdown)

	var current_value: String = GameState.get_model_setting(setting_name)

	for option_data in options:
		var option_label: String = String(option_data[0])
		var option_value: String = String(option_data[1])
		var index := dropdown.get_item_count()

		dropdown.add_item(option_label)
		dropdown.set_item_metadata(index, option_value)

		if option_value == current_value:
			dropdown.select(index)

	return dropdown
func show_main_menu():
	main_menu_container.visible = true
	team_panel.visible = false

	if tutorial_panel != null:
		tutorial_panel.visible = false

	if settings_panel != null:
		settings_panel.visible = false

func show_team_panel():
	main_menu_container.visible = false
	team_panel.visible = true

	if tutorial_panel != null:
		tutorial_panel.visible = false

	if settings_panel != null:
		settings_panel.visible = false

	refresh_team_panel()
func position_fullscreen_panel(panel: Control) -> void:
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0

func build_team_rows():
	clear_roster_rows()
	count_labels.clear()

	for unit_class in unit_class_order:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(360, 36)

		var unit_label := Label.new()
		unit_label.text = GameState.get_display_name_for_class(unit_class)
		unit_label.custom_minimum_size = Vector2(120, 30)

		var minus_button := Button.new()
		minus_button.text = "-"
		minus_button.custom_minimum_size = Vector2(40, 30)
		minus_button.pressed.connect(_on_remove_class_pressed.bind(unit_class))

		var count_label := Label.new()
		count_label.text = "0"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.custom_minimum_size = Vector2(60, 30)

		var plus_button := Button.new()
		plus_button.text = "+"
		plus_button.custom_minimum_size = Vector2(40, 30)
		plus_button.pressed.connect(_on_add_class_pressed.bind(unit_class))

		row.add_child(unit_label)
		row.add_child(minus_button)
		row.add_child(count_label)
		row.add_child(plus_button)

		roster_rows.add_child(row)
		count_labels[unit_class] = count_label

	refresh_team_panel()

func clear_roster_rows():
	for child in roster_rows.get_children():
		child.queue_free()

func refresh_team_panel():
	var total_count = GameState.get_total_count()

	total_label.text = "Raid Size: " + str(total_count) + " / " + str(GameState.MAX_RAID_SIZE)

	for unit_class in unit_class_order:
		if count_labels.has(unit_class):
			count_labels[unit_class].text = str(GameState.get_class_count(unit_class))

	start_fight_from_team_button.disabled = not GameState.has_valid_team()
	start_fight_button.disabled = false

func _on_add_class_pressed(unit_class: String):
	GameState.add_class(unit_class)
	refresh_team_panel()

func _on_remove_class_pressed(unit_class: String):
	GameState.remove_class(unit_class)
	refresh_team_panel()

func _on_start_fight_pressed():
	SceneFlow.enter_camp("normal")

func _on_manage_team_pressed():
	print("Opening team management")
	show_team_panel()
func _on_tutorial_pressed() -> void:
	main_menu_container.visible = false
	team_panel.visible = false

	if settings_panel != null:
		settings_panel.visible = false

	if tutorial_panel != null:
		tutorial_panel.visible = true


func _on_settings_pressed() -> void:
	main_menu_container.visible = false
	team_panel.visible = false

	if tutorial_panel != null:
		tutorial_panel.visible = false

	if settings_panel != null:
		settings_panel.visible = true


func _on_tutorial_boss_selected(boss_id: String) -> void:
	GameState.set_selected_tutorial_boss(boss_id)

	var boss_data: Dictionary = GameState.get_tutorial_boss_data(boss_id)

	if tutorial_description_label != null:
		tutorial_description_label.text = String(boss_data.get("description", ""))

	if start_tutorial_button != null:
		start_tutorial_button.disabled = not GameState.has_valid_team()


func _on_start_tutorial_pressed() -> void:
	SceneFlow.launch_tutorial(GameState.get_selected_tutorial_boss_id())


func _on_apply_settings_pressed() -> void:
	apply_model_dropdown_setting(speech_to_text_dropdown, "speech_to_text_model")

	print("Applied model settings:", GameState.get_model_settings())

func apply_model_dropdown_setting(dropdown: OptionButton, setting_name: String) -> void:
	if dropdown == null:
		return

	var selected_index := dropdown.selected

	if selected_index < 0:
		return

	var metadata = dropdown.get_item_metadata(selected_index)

	if metadata == null:
		return

	GameState.set_model_setting(setting_name, String(metadata))

func _on_back_pressed():
	show_main_menu()

func _on_quit_pressed():
	get_tree().quit()
