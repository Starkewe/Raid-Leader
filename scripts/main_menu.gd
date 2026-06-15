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

var unit_class_order: Array[String] = []
var count_labels: Dictionary = {}

func _ready():
	unit_class_order = GameState.get_available_classes()

	start_fight_button.pressed.connect(_on_start_fight_pressed)
	manage_team_button.pressed.connect(_on_manage_team_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	start_fight_from_team_button.pressed.connect(_on_start_fight_pressed)
	back_button.pressed.connect(_on_back_pressed)

	build_team_rows()
	show_main_menu()

func show_main_menu():
	main_menu_container.visible = true
	team_panel.visible = false

func show_team_panel():
	main_menu_container.visible = false
	team_panel.visible = true
	refresh_team_panel()

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
	start_fight_button.disabled = not GameState.has_valid_team()

func _on_add_class_pressed(unit_class: String):
	GameState.add_class(unit_class)
	refresh_team_panel()

func _on_remove_class_pressed(unit_class: String):
	GameState.remove_class(unit_class)
	refresh_team_panel()

func _on_start_fight_pressed():
	if not GameState.has_valid_team():
		print("Cannot start fight. Team is empty.")
		return

	print("Starting fight with roster:", GameState.get_roster())
	print("Loading scene:", combat_scene_path)

	var result = get_tree().change_scene_to_file(combat_scene_path)

	if result != OK:
		print("Failed to load combat scene. Check combat_scene_path:", combat_scene_path)

func _on_manage_team_pressed():
	print("Opening team management")
	show_team_panel()

func _on_back_pressed():
	show_main_menu()

func _on_quit_pressed():
	get_tree().quit()
