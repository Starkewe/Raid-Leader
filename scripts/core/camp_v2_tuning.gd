extends RefCounted
class_name CampV2Tuning

# Camp V2 simulation values live here so content and lifecycle tuning can be reviewed
# without hunting through the event, memory, relationship, activity, and UI scripts.

const EVENT_LIMITS := {
	"notable_event_records": 200,
	"raid_chronicle": 100,
}

const MEMORY := {
	"day_seconds": 86400,
	"normal_reinforcement_ceiling_days": 120,
	"self_reinforcement_limit": 3,
	"rejection_limit": 120,
	"life_memory_capacity": 12,
	"latent_multiplier": 2,
	"duplicate_episode_window_days": 10,
	"diminishing_extension_rate": 0.85,
	"resolution_external_reinforcements": 4,
	"identity_promotion_strength": 0.88,
	"selection_state_weights": {"active": 1.0, "latent": 0.55, "permanent": 0.85},
	"selection_strength_weight": 1.4,
	"selection_reinforcement_weight": 0.12,
	"selection_recency_window_days": 90.0,
	"category_capacities": {
		"combat": 5,
		"social": 6,
		"roster": 3,
		"camp_life": 3,
		"personal_reflection": 4,
	},
	"category_active_days": {
		"combat": 28,
		"social": 42,
		"roster": 30,
		"camp_life": 32,
		"personal_reflection": 50,
	},
	"category_latent_days": {
		"combat": 90,
		"social": 130,
		"roster": 100,
		"camp_life": 95,
		"personal_reflection": 150,
	},
}

const RELATIONSHIPS := {
	"value_minimum": -100,
	"value_maximum": 100,
	"pair_memory_limit": 20,
	"permanent_pair_memory_limit": 8,
	"recent_conversation_limit": 8,
	"thresholds": [-75, -50, -25, 25, 50, 75],
	"routine_activity_changes_relationships": false,
	"maximum_normal_dimension_delta": 8,
}

const CONVERSATIONS := {
	"summary_limit": 160,
	"pressure_source_limit": 40,
	"initial_pressure": 18.0,
	"first_conversation_delay_seconds": 14.0,
	"minimum_cooldown_seconds": 14.0,
	"baseline_cooldown_seconds": 50.0,
	"maximum_cooldown_seconds": 80.0,
	"pressure_decay_per_second": 0.065,
	"focused_completion_pressure_reduction": 13.0,
	"embedded_completion_pressure_reduction": 7.0,
	"schedule_miss_pressure_reduction": 0.5,
	"schedule_miss_retry_seconds": 7.0,
	"bubble_duration_seconds": 3.8,
	"pause_between_bubbles_seconds": 0.8,
	"lore_schedule_chance": 0.16,
	"debug_history_limit": 100,
	"population_for_second_conversation": 25,
	"maximum_conversations_small_camp": 1,
	"maximum_conversations_large_camp": 2,
	"recent_frame_repetition_multiplier": 0.35,
	"recent_pair_repetition_multiplier": 0.55,
	"recent_context_repetition_multiplier": 0.65,
	"roommate_selection_multiplier": 1.25,
	"authored_connection_selection_multiplier": 1.35,
	"pressure_by_event": {
		"raider_recruited": 24.0,
		"raider_added_to_active_roster": 9.0,
		"raider_moved_to_reserve": 9.0,
		"boss_attempt_completed": 10.0,
		"boss_defeated": 26.0,
		"class_advanced": 18.0,
		"memory_promoted": 11.0,
		"relationship_threshold_reached": 15.0,
		"lore_learned": 12.0,
	},
	"pressure_by_visit": {
		"normal": 0.0,
		"wipe": 20.0,
		"first_victory": 32.0,
		"repeat_victory": 18.0,
		"recruitment": 26.0,
		"roster_change": 12.0,
		"apex_victory": 38.0,
	},
}

const ACTIVITIES := {
	"accelerated_timing_multiplier": 6.0,
	"ambient_bubble_cap": 3,
	"routine_memory_reinforcement_chance": 0.06,
	"shared_activity_chance": 0.68,
	"roommate_shared_activity_bonus": 0.65,
	"profile_refresh_seconds": 0.75,
}


static func get_summary() -> Dictionary:
	return {
		"event_limits": EVENT_LIMITS.duplicate(true),
		"memory": MEMORY.duplicate(true),
		"relationships": RELATIONSHIPS.duplicate(true),
		"conversations": CONVERSATIONS.duplicate(true),
		"activities": ACTIVITIES.duplicate(true),
	}
