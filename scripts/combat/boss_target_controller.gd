extends RefCounted
class_name BossTargetController

signal target_changed(target: Node)

const NORMAL_SWITCH_THRESHOLD := 1.10
const TAUNT_THREAT_MULTIPLIER := 1.20
const TAUNT_FORCED_TARGET_DURATION := 3.0
const TANK_ROLE_MULTIPLIER := 2.0
const CLASS_THREAT_MULTIPLIERS := {
	"warrior": 1.3,
	"rogue": 0.9,
	"mage": 1.1,
	"priest": 0.7
}

var party_members: Array = []
var threat_table: Dictionary = {}
var current_target: Node = null
var forced_target: Node = null
var forced_target_remaining: float = 0.0


func setup(new_party_members: Array) -> void:
	party_members = new_party_members.duplicate()
	reset_threat()


func update(delta: float) -> void:
	_prune_invalid_threat_entries()

	if forced_target != null:
		if not is_valid_living_target(forced_target):
			_clear_forced_target()
		else:
			forced_target_remaining = maxf(forced_target_remaining - maxf(delta, 0.0), 0.0)

			if forced_target_remaining > 0.0:
				set_target(forced_target)
				return

			_clear_forced_target()

	_evaluate_normal_target()


func record_damage_threat(source: Node, actual_damage: int) -> float:
	if actual_damage <= 0 or not is_valid_living_target(source):
		return 0.0

	var threat_gained := calculate_damage_threat(source, actual_damage)

	if threat_gained <= 0.0:
		return 0.0

	threat_table[source] = get_threat_for(source) + threat_gained
	_evaluate_targeting()
	return threat_gained


func calculate_damage_threat(source: Node, actual_damage: int) -> float:
	if actual_damage <= 0 or source == null or not is_instance_valid(source):
		return 0.0

	var base_class := _get_source_base_class(source)
	var class_multiplier := float(CLASS_THREAT_MULTIPLIERS.get(base_class, 1.0))
	var role_multiplier := 1.0

	if source.has_method("has_role") and bool(source.has_role("tank")):
		role_multiplier = TANK_ROLE_MULTIPLIER

	return float(actual_damage) * class_multiplier * role_multiplier


func set_target(new_target: Node) -> bool:
	if not is_valid_living_target(new_target):
		return false

	if current_target == new_target:
		return true

	current_target = new_target
	target_changed.emit(current_target)
	return true


func taunt(new_target: Node) -> bool:
	_prune_invalid_threat_entries()

	if not is_valid_living_target(new_target):
		return false

	var highest_threat_before_taunt := get_highest_valid_threat_value()
	var taunt_threat_target := highest_threat_before_taunt * TAUNT_THREAT_MULTIPLIER

	if taunt_threat_target > get_threat_for(new_target):
		threat_table[new_target] = taunt_threat_target

	forced_target = new_target
	forced_target_remaining = TAUNT_FORCED_TARGET_DURATION
	return set_target(new_target)


func remove_threat(source: Node) -> void:
	if source == null:
		return

	threat_table.erase(source)

	if forced_target == source:
		_clear_forced_target()

	if current_target == source:
		clear_target()

	_evaluate_normal_target()


func reset_threat() -> void:
	threat_table.clear()
	_clear_forced_target()
	clear_target()


func clear_target() -> void:
	if current_target == null:
		return

	current_target = null
	target_changed.emit(null)


func get_target() -> Node:
	_prune_invalid_threat_entries()
	_evaluate_targeting()

	if is_valid_living_target(current_target):
		return current_target

	clear_target()
	return null


func get_threat_for(source: Node) -> float:
	if source == null:
		return 0.0

	return float(threat_table.get(source, 0.0))


func get_threat_table_snapshot() -> Dictionary:
	_prune_invalid_threat_entries()
	return threat_table.duplicate()


func get_highest_valid_threat_value() -> float:
	var highest_value := 0.0

	for party_member in party_members:
		if not is_valid_living_target(party_member):
			continue

		highest_value = maxf(highest_value, get_threat_for(party_member))

	return highest_value


func get_forced_target() -> Node:
	if forced_target != null and is_valid_living_target(forced_target):
		return forced_target

	return null


func get_forced_target_remaining() -> float:
	return forced_target_remaining


func acquire_fallback_target() -> Node:
	var target := get_target()

	if target != null:
		return target

	var highest_threat_holder := _get_highest_valid_threat_holder()

	if highest_threat_holder != null:
		set_target(highest_threat_holder)
		return highest_threat_holder

	for party_member in party_members:
		if is_valid_living_target(party_member):
			set_target(party_member)
			return party_member

	return null


func is_valid_living_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or not party_members.has(target):
		return false

	if target.has_method("is_alive"):
		return bool(target.is_alive())

	return true


func _evaluate_targeting() -> void:
	if forced_target != null and forced_target_remaining > 0.0:
		if is_valid_living_target(forced_target):
			set_target(forced_target)
			return

		_clear_forced_target()

	_evaluate_normal_target()


func _evaluate_normal_target() -> void:
	var highest_threat_holder := _get_highest_valid_threat_holder()

	if not is_valid_living_target(current_target):
		clear_target()

		if highest_threat_holder != null:
			set_target(highest_threat_holder)

		return

	if highest_threat_holder == null or highest_threat_holder == current_target:
		return

	var current_threat := get_threat_for(current_target)
	var highest_threat := get_threat_for(highest_threat_holder)

	if highest_threat >= current_threat * NORMAL_SWITCH_THRESHOLD:
		set_target(highest_threat_holder)


func _get_highest_valid_threat_holder() -> Node:
	var highest_holder: Node = null
	var highest_threat := -1.0

	for party_member in party_members:
		if not is_valid_living_target(party_member) or not threat_table.has(party_member):
			continue

		var party_member_threat := get_threat_for(party_member)

		if party_member_threat > highest_threat:
			highest_holder = party_member
			highest_threat = party_member_threat

	return highest_holder


func _prune_invalid_threat_entries() -> void:
	for source_value in threat_table.keys():
		var source = source_value

		if not source is Node or not is_valid_living_target(source):
			threat_table.erase(source_value)

	if forced_target != null and not is_valid_living_target(forced_target):
		_clear_forced_target()


func _clear_forced_target() -> void:
	forced_target = null
	forced_target_remaining = 0.0


func _get_source_base_class(source: Node) -> String:
	if source.has_method("get_base_class"):
		return String(source.get_base_class()).to_lower().strip_edges()

	return ""
