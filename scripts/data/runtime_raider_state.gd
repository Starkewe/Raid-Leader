extends RefCounted
class_name RuntimeRaiderState


static func create(raider_id: String) -> Dictionary:
	# Runtime state deliberately lives on scene controllers and is never placed in CampaignState.
	return {
		"raider_id": raider_id,
		"current_activity_id": "",
		"destination": Vector2.ZERO,
		"animation_state": "idle",
		"conversation_partner_id": "",
		"activity_reservation_id": "",
		"pending_interaction": {},
		"temporary_scene_reference": null,
	}
