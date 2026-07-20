extends CharacterBody2D
class_name CampPlayer

@export var speed: float = 360.0
@export var movement_bounds: Rect2 = Rect2(120, 120, 2760, 1860)

var movement_enabled: bool = true


func _ready() -> void:
	z_index = 900
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not movement_enabled:
		velocity = Vector2.ZERO
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * speed
	move_and_slide()
	global_position.x = clampf(global_position.x, movement_bounds.position.x, movement_bounds.end.x)
	global_position.y = clampf(global_position.y, movement_bounds.position.y, movement_bounds.end.y)
	global_position = global_position.round()
	z_index = clampi(int(global_position.y / 3.0), 0, 1000)


func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled

	if not enabled:
		velocity = Vector2.ZERO


func _draw() -> void:
	# Replaceable commander token: intentionally independent from camp logic.
	draw_rect(Rect2(-9, -19, 18, 8), Color("17212b"))
	draw_rect(Rect2(-12, -11, 24, 22), Color("283849"))
	draw_rect(Rect2(-7, -7, 14, 16), Color("31577a"))
	draw_rect(Rect2(-11, 11, 8, 8), Color("1a2026"))
	draw_rect(Rect2(3, 11, 8, 8), Color("1a2026"))
	draw_rect(Rect2(-7, -17, 14, 10), Color("c5a66a"))
	draw_rect(Rect2(-3, -3, 6, 6), Color("d1ab4c"))
