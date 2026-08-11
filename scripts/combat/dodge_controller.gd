extends RefCounted
class_name DodgeController

var profile: Dictionary = {}
var base_class: String = ""
var charge_capacity: int = 0
var available_charges: int = 0
var recharge_remaining: float = 0.0
var flash_remaining: float = 0.0
var flash_segment: int = -1
var active: bool = false
var kind: String = ""
var elapsed: float = 0.0
var duration: float = 0.0
var start_position: Vector2 = Vector2.ZERO
var end_position: Vector2 = Vector2.ZERO
var source_command_id: int = -1
var pending_second_burst: bool = false
var trail: Line2D = null
var visual_node: CanvasItem = null
var visual_original_modulate: Color = Color.WHITE
var automatic_hazard_escape_active: bool = false
