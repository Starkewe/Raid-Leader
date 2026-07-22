extends RefCounted
class_name RuntimeRaiderState


static func create(raider_id: String) -> Dictionary:
	# Runtime state deliberately lives on scene controllers and is never placed in CampaignState.
	return {
		"raider_id": raider_id,
		"primary_activity": {},
		"social_interaction": {},
		"context_channel": {},
		"reservation_level": "free",
		"station_id": "",
		"activity_instance_id": "",
		"current_activity_id": "",
		"destination": Vector2.ZERO,
		"animation_state": "idle",
		"conversation_partner_id": "",
		"activity_reservation_id": "",
		"pending_interaction": {},
		"temporary_scene_reference": null,
	}


static func set_primary_activity(
	state: Dictionary,
	activity_id: String,
	category: String,
	station_id: String,
	instance_id: String,
	destination: Vector2,
	context: Dictionary
) -> void:
	state["primary_activity"] = {
		"activity_id": activity_id,
		"category": category,
		"station_id": station_id,
		"instance_id": instance_id,
	}
	state["context_channel"] = context.duplicate(true)
	state["station_id"] = station_id
	state["activity_instance_id"] = instance_id
	state["current_activity_id"] = activity_id
	state["destination"] = destination
	state["activity_reservation_id"] = station_id
	state["reservation_level"] = "station_reserved"
	state["animation_state"] = "walking"


static func clear_primary_activity(state: Dictionary) -> void:
	state["primary_activity"] = {}
	state["context_channel"] = {}
	state["station_id"] = ""
	state["activity_instance_id"] = ""
	state["current_activity_id"] = ""
	state["destination"] = Vector2.ZERO
	state["activity_reservation_id"] = ""
	state["reservation_level"] = "free" if Dictionary(state.get("social_interaction", {})).is_empty() else "socially_or_partially_reserved"
	state["animation_state"] = "idle"


static func set_social_interaction(
	state: Dictionary,
	conversation_id: String,
	role: String,
	secondary_interaction: String,
	delivery: String
) -> void:
	state["social_interaction"] = {
		"conversation_id": conversation_id,
		"role": role,
		"interaction": secondary_interaction,
		"delivery": delivery,
	}
	state["conversation_partner_id"] = ""
	state["pending_interaction"] = {"type": "conversation", "conversation_id": conversation_id}
	state["reservation_level"] = "exclusively_reserved" if delivery == "focused" else "socially_or_partially_reserved"


static func clear_social_interaction(state: Dictionary) -> void:
	state["social_interaction"] = {}
	state["conversation_partner_id"] = ""
	state["pending_interaction"] = {}
	state["reservation_level"] = "station_reserved" if not Dictionary(state.get("primary_activity", {})).is_empty() else "free"
