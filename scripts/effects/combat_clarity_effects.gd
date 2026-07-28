extends Node2D
class_name CombatClarityEffects

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")
const ProjectileEffectScript := preload("res://scripts/effects/combat_projectile_effect.gd")
const ImpactEffectScript := preload("res://scripts/effects/combat_impact_effect.gd")
const BossTargetIndicatorScript := preload("res://scripts/effects/boss_target_indicator.gd")

const MAX_PROJECTILE_POOL_SIZE := 64
const MAX_IMPACT_POOL_SIZE := 48

var party_member_ids: Dictionary = {}
var boss: Node2D = null
var ui: Node = null
var boss_target_indicator: Node2D = null
var last_boss_target: Node = null

var active_projectiles: Array[Node] = []
var projectile_pool: Array[Node] = []
var active_impacts: Array[Node] = []
var impact_pool: Array[Node] = []
var clearing_effects: bool = false


func setup(
	party_members: Array,
	new_boss: Node,
	new_ui: Node
) -> void:
	party_member_ids.clear()

	for party_member in party_members:
		if party_member != null and is_instance_valid(party_member):
			party_member_ids[party_member.get_instance_id()] = true

	boss = new_boss as Node2D
	ui = new_ui
	install_boss_target_indicator()
	sync_boss_target(true)


func _process(_delta: float) -> void:
	sync_boss_target(false)


func handle_combat_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	var source: Node = event.get("source") as Node
	var target: Node = event.get("target") as Node
	var metadata: Dictionary = event.get("metadata", {})

	if source == null or target == null:
		return

	if not is_instance_valid(source) or not is_instance_valid(target):
		return

	if not is_party_member(source):
		return

	match event_type:
		"damage":
			if bool(metadata.get("periodic", false)):
				return

			play_attack_visual(source, target)

		"healing":
			play_healing_visual(source, target)


func play_attack_visual(source: Node, target: Node) -> void:
	if not source is Node2D or not target is Node2D:
		return

	var source_2d := source as Node2D
	var target_2d := target as Node2D
	var target_point := get_target_point(source_2d, target_2d)
	var direction := source_2d.global_position.direction_to(target_point)
	var unit_class_name := get_unit_class(source).to_lower()

	if unit_class_name == "mage":
		spawn_projectile(
			source_2d,
			target_2d,
			target_point,
			CombatProjectileEffect.VisualStyle.MAGIC,
			0.24
		)
		return

	if get_attack_range_units(source, target_2d) > 8.0:
		spawn_projectile(
			source_2d,
			target_2d,
			target_point,
			CombatProjectileEffect.VisualStyle.PHYSICAL,
			0.18
		)
		return

	spawn_impact(
		target_point,
		direction,
		CombatImpactEffect.VisualStyle.MELEE
	)


func play_healing_visual(source: Node, target: Node) -> void:
	if not source is Node2D or not target is Node2D:
		return

	var source_2d := source as Node2D
	var target_2d := target as Node2D

	if source == target:
		spawn_impact(
			target_2d.global_position,
			Vector2.UP,
			CombatImpactEffect.VisualStyle.HEAL
		)
		return

	spawn_projectile(
		source_2d,
		target_2d,
		target_2d.global_position,
		CombatProjectileEffect.VisualStyle.HEAL,
		0.30
	)


func spawn_projectile(
	source: Node2D,
	target: Node2D,
	target_point: Vector2,
	style: CombatProjectileEffect.VisualStyle,
	duration: float
) -> void:
	var effect := acquire_projectile()
	var endpoint_offset := target_point - target.global_position
	active_projectiles.append(effect)
	effect.activate(
		source.global_position,
		target,
		style,
		duration,
		endpoint_offset
	)


func spawn_impact(
	impact_position: Vector2,
	direction: Vector2,
	style: CombatImpactEffect.VisualStyle
) -> void:
	var effect := acquire_impact()
	active_impacts.append(effect)
	effect.activate(impact_position, direction, style)


func acquire_projectile() -> Node:
	if not projectile_pool.is_empty():
		return projectile_pool.pop_back()

	var effect := ProjectileEffectScript.new()
	effect.finished.connect(_on_projectile_finished)
	add_child(effect)
	return effect


func acquire_impact() -> Node:
	if not impact_pool.is_empty():
		return impact_pool.pop_back()

	var effect := ImpactEffectScript.new()
	effect.finished.connect(_on_impact_finished)
	add_child(effect)
	return effect


func _on_projectile_finished(effect: Node) -> void:
	active_projectiles.erase(effect)

	if not clearing_effects and effect != null and is_instance_valid(effect):
		var impact_style := CombatImpactEffect.VisualStyle.PHYSICAL

		match int(effect.get("visual_style")):
			CombatProjectileEffect.VisualStyle.MAGIC:
				impact_style = CombatImpactEffect.VisualStyle.MAGIC
			CombatProjectileEffect.VisualStyle.HEAL:
				impact_style = CombatImpactEffect.VisualStyle.HEAL

		spawn_impact(
			(effect as Node2D).global_position,
			Vector2.RIGHT,
			impact_style
		)

	if projectile_pool.size() < MAX_PROJECTILE_POOL_SIZE:
		projectile_pool.append(effect)
	else:
		effect.queue_free()


func _on_impact_finished(effect: Node) -> void:
	active_impacts.erase(effect)

	if impact_pool.size() < MAX_IMPACT_POOL_SIZE:
		impact_pool.append(effect)
	else:
		effect.queue_free()


func clear_active_effects() -> void:
	clearing_effects = true

	for effect in active_projectiles.duplicate():
		if effect != null and is_instance_valid(effect) and effect.has_method("cancel"):
			effect.cancel()

	for effect in active_impacts.duplicate():
		if effect != null and is_instance_valid(effect) and effect.has_method("cancel"):
			effect.cancel()

	clearing_effects = false


func install_boss_target_indicator() -> void:
	if boss == null or not is_instance_valid(boss):
		return

	var existing := boss.get_node_or_null("TargetDirectionIndicator")

	if existing != null:
		boss_target_indicator = existing as Node2D
	else:
		boss_target_indicator = BossTargetIndicatorScript.new()
		boss_target_indicator.name = "TargetDirectionIndicator"
		boss_target_indicator.z_index = 15
		boss.add_child(boss_target_indicator)

	if boss_target_indicator != null and boss_target_indicator.has_method("setup"):
		boss_target_indicator.setup(boss)


func sync_boss_target(force_update: bool) -> void:
	var current_target: Node = null

	if boss != null and is_instance_valid(boss) and boss.has_method("get_current_target"):
		current_target = boss.get_current_target()

	if not force_update and current_target == last_boss_target:
		return

	last_boss_target = current_target

	if ui != null and is_instance_valid(ui) and ui.has_method("set_boss_target"):
		ui.set_boss_target(current_target)


func is_party_member(node: Node) -> bool:
	return (
		node != null
		and is_instance_valid(node)
		and party_member_ids.has(node.get_instance_id())
	)


func get_unit_class(unit: Node) -> String:
	var class_value = unit.get("unit_class")
	return "" if class_value == null else String(class_value)


func get_attack_range_units(source: Node, target: Node2D) -> float:
	if source.has_method("get_range_units_to_node"):
		return float(source.get_range_units_to_node(target))

	if not source is Node2D:
		return 0.0

	return (
		(source as Node2D).global_position.distance_to(target.global_position)
		/ CombatMeasurementsScript.PIXELS_PER_RANGE_UNIT
	)


func get_target_point(source: Node2D, target: Node2D) -> Vector2:
	var target_radius := 0.0

	if target.has_method("get_combat_radius"):
		target_radius = maxf(float(target.get_combat_radius()), 0.0)

	var direction := source.global_position.direction_to(target.global_position)
	return target.global_position - direction * target_radius * 0.82
