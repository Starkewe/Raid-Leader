extends "res://scripts/ui/facility_page_presenter.gd"
class_name QuartersPagePresenter

func present(journal: Node) -> void:
	journal.build_quarters_page()
