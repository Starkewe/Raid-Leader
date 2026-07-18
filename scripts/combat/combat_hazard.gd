extends Area2D
class_name CombatHazard

signal expired(hazard: CombatHazard)

var definition: HazardDefinition = null
var source: Node = null
var elapsed: float = 0.0
var tick_elapsed: float = 0.0
var tracked_targets: Array[Node] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func configure(new_definition: HazardDefinition, new_source: Node = null) -> void:
	definition = new_definition
	source = new_source
	elapsed = 0.0
	tick_elapsed = 0.0


func _process(delta: float) -> void:
	if definition == null:
		return

	elapsed += delta
	tick_elapsed += delta

	var interval := maxf(definition.tick_interval, 0.01)

	while tick_elapsed >= interval:
		tick_elapsed -= interval
		apply_tick()

	if elapsed >= maxf(definition.duration, 0.0):
		expired.emit(self)
		queue_free()


func apply_tick() -> void:
	var invalid_targets: Array[Node] = []

	for target in tracked_targets:
		if target == null or not is_instance_valid(target):
			invalid_targets.append(target)
			continue

		if target.has_method("is_alive") and not target.is_alive():
			continue

		if definition.damage_per_tick > 0 and target.has_method("take_damage"):
			target.take_damage(
				definition.damage_per_tick,
				source,
				definition.hazard_id,
				{"hazard": true}
			)

		if definition.status_effect != null and target.has_method("apply_status_effect"):
			target.apply_status_effect(definition.status_effect, source)

	for invalid_target in invalid_targets:
		tracked_targets.erase(invalid_target)


func _on_body_entered(body: Node) -> void:
	register_target(body)


func _on_body_exited(body: Node) -> void:
	unregister_target(body)


func register_target(body: Node) -> void:
	if not tracked_targets.has(body):
		tracked_targets.append(body)


func unregister_target(body: Node) -> void:
	tracked_targets.erase(body)
