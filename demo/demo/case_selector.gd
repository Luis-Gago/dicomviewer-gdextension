extends Control

@onready var case_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/CaseList

func _ready() -> void:
    load_available_cases()

func load_available_cases() -> void:
    var cases_dir = "user://cases"
    var dir = DirAccess.open(cases_dir)
    
    if dir == null:
        var label = Label.new()
        label.text = "No cases found. Create one in Setup Mode first."
        case_list.add_child(label)
        return
    
    dir.list_dir_begin()
    var file_name = dir.get_next()
    var found_cases = false
    
    while file_name != "":
        if file_name.ends_with(".tres"):
            found_cases = true
            var case_path = cases_dir.path_join(file_name)
            var case_button = Button.new()
            case_button.text = file_name.get_basename()
            case_button.pressed.connect(_on_case_selected.bind(case_path))
            case_list.add_child(case_button)
        file_name = dir.get_next()
    
    dir.list_dir_end()
    
    if not found_cases:
        var label = Label.new()
        label.text = "No cases found. Create one in Setup Mode first."
        case_list.add_child(label)

func _on_case_selected(case_path: String) -> void:
    # Pass the case path to study mode
    var study_scene = load("res://demo/study_mode_ui.tscn").instantiate()
    study_scene.case_path = case_path
    get_tree().root.add_child(study_scene)
    get_tree().current_scene = study_scene
    queue_free()

func _on_back_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")