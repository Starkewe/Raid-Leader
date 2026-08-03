extends Resource
class_name BossAbilityDefinition

@export var runtime_script: Script = null
@export var ability_id: String = ""
@export var display_name: String = "Unnamed Ability"
@export_multiline var windup_text: String = ""
@export_multiline var impact_text: String = ""

@export_group("Initiative")
## Coordinated is deliberately the default: authored mechanics never become
## automatic raider behavior merely by being added to an encounter.
@export_enum("player_coordinated", "raider_personal")
var reaction_owner: String = "player_coordinated"
@export_enum("none", "avoid_area")
var automatic_response: String = "none"
@export var positioning_checkpoint: PositioningCheckpointDefinition = null

@export_group("Timing and Power")
@export var cast_time: float = 1.0
@export var cooldown: float = 5.0
@export var damage: int = 0
@export_enum("physical", "magic", "environmental") var damage_type: String = "physical"

@export_group("Cast Rules")
@export var interruptible: bool = true
@export var requires_active_target: bool = true
