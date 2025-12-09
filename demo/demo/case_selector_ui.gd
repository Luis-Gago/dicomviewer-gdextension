extends Control

@onready var cases_list: ItemList = $MarginContainer/VBoxContainer/CasesList
@onready var edit_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/EditButton
@onready var delete_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/DeleteButton
@onready var study_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/StudyButton

var cases: Array = []

func _ready() -> void:
	load_available_cases()
	edit_button.disabled = true
	delete_button.disabled = true
	study_button.disabled = true
	
	cases_list.item_selected.connect(_on_case_selected)

func load_available_cases() -> void:
	cases.clear()
	cases_list.clear()
	
	var cases_dir = "user://cases"
	var dir = DirAccess.open(cases_dir)
	
	if dir == null:
		print("No cases directory found")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			var full_path = cases_dir.path_join(file_name)
			var case_resource = ResourceLoader.load(full_path) as RadiologyCase
			if case_resource:
				cases.append({
					"path": full_path,
					"resource": case_resource
				})
				cases_list.add_item(case_resource.get_case_name())
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _on_case_selected(_index: int) -> void:
	edit_button.disabled = false
	delete_button.disabled = false
	study_button.disabled = false

func _on_edit_button_pressed() -> void:
	var selected = cases_list.get_selected_items()
	if selected.size() == 0:
		return
	
	var case_data = cases[selected[0]]
	
	# Load case setup UI with the case path
	var case_setup = load("res://demo/case_setup_ui.tscn").instantiate()
	case_setup.original_case_path = case_data["path"]
	get_tree().root.add_child(case_setup)
	queue_free()

func _on_delete_button_pressed() -> void:
	var selected = cases_list.get_selected_items()
	if selected.size() == 0:
		return
	
	var case_data = cases[selected[0]]
	
	# Confirm deletion
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Delete case '%s'? This cannot be undone." % case_data["resource"].get_case_name()
	dialog.confirmed.connect(func():
		DirAccess.remove_absolute(case_data["path"])
		load_available_cases()
		edit_button.disabled = true
		delete_button.disabled = true
		study_button.disabled = true
	)
	add_child(dialog)
	dialog.popup_centered()

func _on_study_button_pressed() -> void:
	var selected = cases_list.get_selected_items()
	if selected.size() == 0:
		return
	
	var case_data = cases[selected[0]]
	
	# Load study mode with the case
	var study_mode = load("res://demo/study_mode_ui.tscn").instantiate()
	study_mode.case_path = case_data["path"]
	get_tree().root.add_child(study_mode)
	queue_free()

func _on_new_case_button_pressed() -> void:
	get_tree().change_scene_to_file("res://demo/case_setup_ui.tscn")

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://demo/main_menu.tscn")
