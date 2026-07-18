extends RefCounted
class_name ForcedMovementController

var owner: CharacterBody2D = null
var active: bool = false
var start_position: Vector2 = Vector2.ZERO
var destination: Vector2 = Vector2.ZERO
var duration: float = 0.0
var elapsed: float = 0.0


func setup(new_owner: CharacterBody2D) -> void:
	owner = new_owner


func start(new_destination: Vector2, new_duration: float) -> void:
	if owner == null:
		return

	start_position = owner.global_position
	destination = new_destination
	duration = maxf(new_duration, 0.01)
	elapsed = 0.0
	active = true


func update(delta: float) -> bool:
	if not active or owner == null:
		return false

	elapsed = minf(elapsed + maxf(delta, 0.0), duration)
	owner.global_position = start_position.lerp(destination, elapsed / duration)
	owner.velocity = Vector2.ZERO

	if elapsed >= duration:
		finish()

	return true


func finish() -> void:
	if not active or owner == null:
		return

	owner.global_position = destination
	owner.velocity = Vector2.ZERO
	active = false
	elapsed = duration


func cancel() -> void:
	active = false
	elapsed = 0.0
	duration = 0.0

	if owner != null:
		owner.velocity = Vector2.ZERO
