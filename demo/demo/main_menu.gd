extends Control

func _on_cases_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/case_selector_ui.tscn")