extends CanvasLayer

@onready var warrior_status = $StatusPanel/StatusList/WarriorStatus
@onready var priest_status = $StatusPanel/StatusList/PriestStatus
@onready var rogue_status = $StatusPanel/StatusList/RogueStatus
@onready var mage_status = $StatusPanel/StatusList/MageStatus
@onready var boss_status = $StatusPanel/StatusList/BossStatus

func set_warrior_status(text: String):
	warrior_status.text = "Warrior: " + text

func set_priest_status(text: String):
	priest_status.text = "Priest: " + text

func set_rogue_status(text: String):
	rogue_status.text = "Rogue: " + text

func set_mage_status(text: String):
	mage_status.text = "Mage: " + text

func set_boss_status(text: String):
	boss_status.text = "Boss: " + text
