extends "res://scripts/ui/facility_page_presenter.gd"
class_name CommandTentPagePresenter

func present(journal: Node) -> void:
	journal.build_command_tent_page()
