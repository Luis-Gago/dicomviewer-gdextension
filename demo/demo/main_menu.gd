extends Control

func _on_setup_mode_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/case_setup_ui.tscn")

func _on_study_mode_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/case_selector.tscn")

func _on_viewer_mode_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/dicom_viewer_ui.tscn")