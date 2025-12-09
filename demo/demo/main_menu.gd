extends Control

func _on_cases_button_pressed() -> void:
    # Go to case selector which allows creating AND editing cases
    get_tree().change_scene_to_file("res://demo/case_selector_ui.tscn")

func _on_viewer_mode_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/dicom_viewer_ui.tscn")