extends "res://scripts/ui/facility_page_presenter.gd"
class_name FormationYardPagePresenter

func present(journal: Node) -> void:
	journal.build_formation_yard_page()
