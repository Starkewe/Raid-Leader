extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := BaseCombatUnit.new()
	var first_healer := Priest.new()
	var second_healer := Priest.new()
	root.add_child(target)
	root.add_child(first_healer)
	root.add_child(second_healer)

	target.take_damage(60)
	second_healer.heal_amount = 50
	first_healer.command_heal(target)
	second_healer.command_heal(target)
	first_healer.try_start_cast()
	second_healer.try_start_cast()

	if target.get_incoming_healing_total() != 60:
		_fail("Pending heals from multiple healers did not accumulate.")
		return

	first_healer.cancel_current_cast()

	if target.get_incoming_healing_total() != 50:
		_fail("Cancelling one cast did not remove only its pending heal.")
		return

	second_healer.finish_cast()

	if target.get_incoming_healing_total() != 0:
		_fail("A resolved heal remained in the incoming-healing prediction.")
		return

	var harmful := StatusEffectDefinition.new()
	harmful.effect_id = "harmful"
	harmful.is_harmful = true
	harmful.dispellable = false

	var curable := StatusEffectDefinition.new()
	curable.effect_id = "curable"
	curable.is_harmful = true
	curable.dispellable = true
	curable.dispel_category = "cure"

	target.apply_status_effect(harmful)

	if target.get_raid_frame_overlay_kind() != "harmful":
		_fail("A non-curable harmful effect did not select the red overlay.")
		return

	target.apply_status_effect(curable)

	if target.get_raid_frame_overlay_kind() != "curable":
		_fail("A curable effect did not take priority over a non-curable effect.")
		return

	target.clear_status_effect("curable")

	if target.get_raid_frame_overlay_kind() != "harmful":
		_fail("Removing the curable effect did not restore the harmful overlay.")
		return

	var health_before_absorb := target.get_current_health()
	target.grant_damage_absorb(20)
	target.take_damage(30)

	if target.get_damage_absorb() != 0:
		_fail("Damage did not consume the active absorb.")
		return

	if target.get_current_health() != health_before_absorb - 10:
		_fail("Only the damage beyond the absorb should reduce health.")
		return

	var indicator := BossTargetIndicator.new()
	indicator.rotation_speed = 15.0
	var smoothed_angle := indicator.get_smoothed_angle(
		deg_to_rad(179.0),
		deg_to_rad(-179.0),
		0.05
	)
	var angular_step := absf(
		wrapf(smoothed_angle - deg_to_rad(179.0), -PI, PI)
	)

	if angular_step > deg_to_rad(2.1):
		_fail("Boss target rotation did not use the shortest path across 0/360 degrees.")
		return

	print("Combat clarity state regression test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
