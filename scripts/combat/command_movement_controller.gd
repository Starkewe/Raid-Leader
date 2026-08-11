extends RefCounted
class_name CommandMovementController

var has_manual_move_order: bool = false
var manual_move_destination: Vector2 = Vector2.ZERO
var manual_move_waypoints: Array[Vector2] = []
var movement_command_id: int = 0
var active_action_kind: String = ""
var action_command_id: int = 0
var forced_movement_action_kind: String = ""
var forced_movement_action_command_id: int = -1
var command_destination_boss: Node = null
var command_destination_region: String = ""
var command_destination_range: String = ""
var command_destination_key: String = ""
var command_destination_flag_position: Vector2 = Vector2.ZERO
var command_path_active: bool = false
var positioning_checkpoint_boss: Node = null
var positioning_checkpoint_token: int = 0
var positioning_checkpoint_ability_id: String = ""
var positioning_checkpoint_ability_name: String = ""
var positioning_checkpoint_destination: Vector2 = Vector2.ZERO


func reset() -> void:
	has_manual_move_order = false
	manual_move_destination = Vector2.ZERO
	manual_move_waypoints.clear()
	movement_command_id += 1
	active_action_kind = ""
	forced_movement_action_kind = ""
	forced_movement_action_command_id = -1
	command_destination_boss = null
	command_destination_region = ""
	command_destination_range = ""
	command_destination_key = ""
	command_destination_flag_position = Vector2.ZERO
	command_path_active = false
	positioning_checkpoint_boss = null
	positioning_checkpoint_token = 0
	positioning_checkpoint_ability_id = ""
	positioning_checkpoint_ability_name = ""
	positioning_checkpoint_destination = Vector2.ZERO
