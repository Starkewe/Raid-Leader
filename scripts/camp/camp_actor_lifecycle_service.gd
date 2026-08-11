extends RefCounted
class_name CampActorLifecycleService


func create_actor(
	parent: Node, actor_scene: PackedScene, member: Dictionary,
	spawn_position: Vector2, idle_delay: float, timing_multiplier: float,
	callbacks: Dictionary
) -> Node:
	var actor = actor_scene.instantiate()
	if actor == null:
		return null
	parent.add_child(actor)
	actor.configure(member, spawn_position, idle_delay)
	actor.set_timing_multiplier(timing_multiplier)
	for signal_name in callbacks:
		var callback: Callable = callbacks[signal_name]
		if actor.has_signal(String(signal_name)) and not actor.is_connected(String(signal_name), callback):
			actor.connect(String(signal_name), callback)
	return actor


func destroy_actor(actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_method("hide_bubble"):
		actor.hide_bubble()
	if actor.has_method("interrupt_activity"):
		actor.interrupt_activity()
	actor.free()


func destroy_all(actors: Dictionary) -> void:
	for actor in actors.values():
		destroy_actor(actor)
	actors.clear()
