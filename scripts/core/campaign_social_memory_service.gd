extends RefCounted
class_name CampaignSocialMemoryService

const RaiderMemoryStoreScript := preload("res://scripts/data/raider_memory_store.gd")
const RaiderRelationshipStoreScript := preload(
	"res://scripts/data/raider_relationship_store.gd"
)
const RaiderLoreKnowledgeStoreScript := preload(
	"res://scripts/data/raider_lore_knowledge_store.gd"
)


func get_memories(campaign: Dictionary, raider_id: String) -> Dictionary:
	return RaiderMemoryStoreScript.get_raider_memory(
		Dictionary(campaign.get("memory_store", {})), raider_id
	)


func get_relationship(
	campaign: Dictionary, first_id: String, second_id: String
) -> Dictionary:
	return RaiderRelationshipStoreScript.get_pair(
		Dictionary(campaign.get("relationship_store", {})), first_id, second_id
	)


func get_lore(campaign: Dictionary, raider_id: String) -> Dictionary:
	return RaiderLoreKnowledgeStoreScript.get_raider_knowledge(
		Dictionary(campaign.get("lore_knowledge_store", {})), raider_id
	)
