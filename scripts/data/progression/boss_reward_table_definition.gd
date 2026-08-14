extends Resource
class_name BossRewardTableDefinition

@export var reward_table_id: String = ""
@export var encounter_id: String = ""
@export var revision: int = 1
@export var layers: Array[RewardRollLayerDefinition] = []
