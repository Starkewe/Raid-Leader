extends Node

const BossTargetControllerScript := preload(
	"res://scripts/combat/boss_target_controller.gd"
)


class DummyRaider:
	extends Node2D

	var base_class: String = ""
	var roles: Array[String] = []
	var alive: bool = true

	func get_base_class() -> String:
		return base_class

	func has_role(role_name: String) -> bool:
		return roles.has(role_name)

	func is_alive() -> bool:
		return alive


class DummyEnemy:
	extends Node2D

	var alive: bool = true
	var taunt_succeeds: bool = true
	var taunt_attempts: int = 0

	func is_alive() -> bool:
		return alive

	func taunt(_new_target: Node) -> bool:
		taunt_attempts += 1
		return taunt_succeeds


var failures: Array[String] = []
var owned_nodes: Array[Node] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var warrior := _new_raider("Warrior", ["tank"])
	var rogue := _new_raider("Rogue", ["melee_dps", "dps"])
	var mage := _new_raider("Mage", ["ranged_dps", "dps"])
	var priest := _new_raider("Priest", ["healer"])
	var party := [warrior, rogue, mage, priest]
	var first_enemy = BossTargetControllerScript.new()
	var second_enemy = BossTargetControllerScript.new()
	first_enemy.setup(party)
	second_enemy.setup(party)

	_expect_close(
		first_enemy.record_damage_threat(warrior, 10),
		26.0,
		"Warrior tank damage did not receive the 1.3 class and 2.0 role multipliers."
	)
	_expect_close(
		first_enemy.record_damage_threat(priest, 10),
		7.0,
		"Priest damage did not receive its 0.7 class multiplier."
	)
	_expect_close(
		second_enemy.record_damage_threat(rogue, 10),
		9.0,
		"Rogue damage did not receive its 0.9 class multiplier."
	)
	_expect(
		first_enemy.get_threat_for(rogue) == 0.0
		and second_enemy.get_threat_for(warrior) == 0.0,
		"Enemy threat tables were not independent."
	)

	first_enemy.reset_threat()
	first_enemy.set_target(warrior)
	first_enemy.record_damage_threat(warrior, 10)
	first_enemy.record_damage_threat(rogue, 28)
	_expect(
		first_enemy.get_target() == warrior,
		"Target changed before another raider reached 110% of current threat."
	)
	first_enemy.record_damage_threat(rogue, 4)
	_expect(
		first_enemy.get_target() == rogue,
		"Target did not change when another raider reached 110% of current threat."
	)

	first_enemy.reset_threat()
	first_enemy.record_damage_threat(rogue, 10)
	first_enemy.record_damage_threat(mage, 8)
	_expect(
		first_enemy.get_target() == rogue,
		"Target changed below the exact 110% boundary."
	)
	first_enemy.record_damage_threat(mage, 1)
	_expect(
		first_enemy.get_target() == mage,
		"Target did not change at the exact 110% boundary."
	)

	first_enemy.reset_threat()
	first_enemy.record_damage_threat(mage, 100)
	var highest_before_taunt := first_enemy.get_highest_valid_threat_value()
	_expect(
		first_enemy.taunt(warrior),
		"A valid living taunter could not force the enemy target."
	)
	_expect_close(
		first_enemy.get_threat_for(warrior),
		highest_before_taunt * 1.2,
		"Taunt did not place the taunter at 120% of the previous highest threat."
	)
	first_enemy.record_damage_threat(rogue, 200)
	first_enemy.update(2.99)
	_expect(
		first_enemy.get_target() == warrior,
		"Threat overrode the taunter before the forced-target duration expired."
	)
	first_enemy.update(0.02)
	_expect(
		first_enemy.get_target() == rogue,
		"Normal threshold evaluation did not resume after the taunt expired."
	)

	first_enemy.remove_threat(rogue)
	_expect(
		first_enemy.get_threat_for(rogue) == 0.0
		and first_enemy.get_target() == warrior,
		"Removing a raider's threat did not clean the table and select the next holder."
	)
	warrior.alive = false
	first_enemy.update(0.0)
	_expect(
		first_enemy.get_threat_for(warrior) == 0.0,
		"Dead-raider threat was not pruned from the enemy table."
	)
	warrior.alive = true
	_expect(
		first_enemy.get_threat_for(warrior) == 0.0,
		"A restored raider did not return with zero threat."
	)
	var mage_threat_before_update := first_enemy.get_threat_for(mage)
	first_enemy.update(30.0)
	_expect_close(
		first_enemy.get_threat_for(mage),
		mage_threat_before_update,
		"Threat decayed passively over time."
	)

	_validate_taunt_cooldown()
	_finish()


func _validate_taunt_cooldown() -> void:
	var warrior := Warrior.new()
	warrior.unit_class = "Warrior"
	warrior.unit_roles = ["tank", "melee"]
	get_tree().root.add_child(warrior)
	owned_nodes.append(warrior)

	var enemy := DummyEnemy.new()
	get_tree().root.add_child(enemy)
	owned_nodes.append(enemy)

	_expect(warrior.command_taunt(enemy), "A ready taunt failed against a valid enemy.")
	_expect_close(
		warrior.get_taunt_cooldown_remaining(),
		5.0,
		"A successful taunt did not start the five-second raider cooldown."
	)
	_expect(
		not warrior.command_taunt(enemy) and enemy.taunt_attempts == 1,
		"A taunt attempted on cooldown reached the enemy."
	)

	warrior.update_taunt_cooldown(5.0)
	enemy.alive = false
	_expect(
		not warrior.command_taunt(enemy)
		and warrior.get_taunt_cooldown_remaining() == 0.0,
		"An invalid enemy consumed the taunt cooldown."
	)


func _new_raider(base_class: String, roles: Array[String]) -> DummyRaider:
	var raider := DummyRaider.new()
	raider.base_class = base_class
	raider.roles = roles
	get_tree().root.add_child(raider)
	owned_nodes.append(raider)
	return raider


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _expect_close(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append(message + " Expected " + str(expected) + ", got " + str(actual) + ".")


func _finish() -> void:
	for node in owned_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()

	if failures.is_empty():
		print("Threat and taunt regressions passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)

	get_tree().quit(1)
