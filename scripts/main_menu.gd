extends Control

@export_file("*.tscn") var combat_scene_path: String = "res://scenes/combat_scene.tscn"

@onready var main_menu_container = $CenterContainer
@onready var start_fight_button: Button = $CenterContainer/VBoxContainer/StartFightButton
@onready var manage_team_button: Button = $CenterContainer/VBoxContainer/ManageTeamButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

@onready var team_panel: PanelContainer = $TeamPanel
@onready var back_button: Button = $TeamPanel/CenterContainer/VBoxContainer/BackButton

func _ready():
	start_fight_button.pressed.connect(_on_start_fight_pressed)
	manage_team_button.pressed.connect(_on_manage_team_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)

	show_main_menu()

func show_main_menu():
	main_menu_container.visible = true
	team_panel.visible = false

func show_team_panel():
	main_menu_container.visible = false
	team_panel.visible = true

func _on_start_fight_pressed():
	print("Starting fight:", combat_scene_path)

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
