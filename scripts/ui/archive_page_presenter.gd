extends "res://scripts/ui/facility_page_presenter.gd"
class_name ArchivePagePresenter

func present(journal: Node) -> void:
	journal.build_archive_page()
