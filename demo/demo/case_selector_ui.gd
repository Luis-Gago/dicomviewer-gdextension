extends Control

@onready var cases_list: ItemList = $MarginContainer/VBoxContainer/CasesList
@onready var edit_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/EditButton
@onready var delete_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/DeleteButton
@onready var study_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer/StudyButton
@onready var export_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer2/ExportButton
@onready var import_button: Button = $MarginContainer/VBoxContainer/ButtonsContainer2/ImportButton

var cases: Array = []
var export_dialog: FileDialog
var import_dialog: FileDialog

func _ready() -> void:
    setup_dialogs()
    load_available_cases()
    edit_button.disabled = true
    delete_button.disabled = true
    study_button.disabled = true
    export_button.disabled = true
    
    cases_list.item_selected.connect(_on_case_selected)

func setup_dialogs() -> void:
    # Export dialog
    export_dialog = FileDialog.new()
    add_child(export_dialog)
    export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    export_dialog.access = FileDialog.ACCESS_FILESYSTEM
    export_dialog.use_native_dialog = true
    export_dialog.add_filter("*.radcase", "Radiology Case")
    export_dialog.file_selected.connect(_on_export_dialog_file_selected)
    
    # Import dialog
    import_dialog = FileDialog.new()
    add_child(import_dialog)
    import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    import_dialog.access = FileDialog.ACCESS_FILESYSTEM
    import_dialog.use_native_dialog = true
    import_dialog.add_filter("*.radcase", "Radiology Case")
    import_dialog.file_selected.connect(_on_import_dialog_file_selected)

func load_available_cases() -> void:
    cases.clear()
    cases_list.clear()
    
    var cases_dir = "user://cases"
    var dir = DirAccess.open(cases_dir)
    
    if dir == null:
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
    export_button.disabled = false

func _on_edit_button_pressed() -> void:
    var selected = cases_list.get_selected_items()
    if selected.size() == 0:
        return
    
    var case_data = cases[selected[0]]
    var case_setup = load("res://demo/case_setup_ui.tscn").instantiate()
    case_setup.original_case_path = case_data["path"]
    get_tree().root.add_child(case_setup)
    queue_free()

func _on_delete_button_pressed() -> void:
    var selected = cases_list.get_selected_items()
    if selected.size() == 0:
        return
    
    var case_data = cases[selected[0]]
    
    var dialog = ConfirmationDialog.new()
    dialog.dialog_text = "Delete case '%s'? This cannot be undone." % case_data["resource"].get_case_name()
    dialog.confirmed.connect(func():
        DirAccess.remove_absolute(case_data["path"])
        load_available_cases()
        edit_button.disabled = true
        delete_button.disabled = true
        study_button.disabled = true
        export_button.disabled = true
    )
    add_child(dialog)
    dialog.popup_centered()

func _on_study_button_pressed() -> void:
    var selected = cases_list.get_selected_items()
    if selected.size() == 0:
        return
    
    var case_data = cases[selected[0]]
    var study_mode = load("res://demo/study_mode_ui.tscn").instantiate()
    study_mode.case_path = case_data["path"]
    get_tree().root.add_child(study_mode)
    queue_free()

func _on_new_case_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/case_setup_ui.tscn")

func _on_back_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")

func _on_export_button_pressed() -> void:
    var selected = cases_list.get_selected_items()
    if selected.size() == 0:
        return
    
    var case_data = cases[selected[0]]
    export_dialog.current_file = case_data["resource"].get_case_name() + ".radcase"
    export_dialog.popup_centered(Vector2i(800, 600))

func _on_export_dialog_file_selected(path: String) -> void:
    var selected = cases_list.get_selected_items()
    if selected.size() == 0:
        return
    
    var case_data = cases[selected[0]]
    var case_dict = case_data["resource"].to_dict()
    
    var export_package = {
        "version": 1,
        "case_data": case_dict,
        "dicom_files": {},
        "explanation_images": {}
    }
    
    # Embed DICOM files
    for dicom_path in case_dict["dicom_file_paths"]:
        var file = FileAccess.open(dicom_path, FileAccess.READ)
        if file:
            var bytes = file.get_buffer(file.get_length())
            export_package["dicom_files"][dicom_path.get_file()] = Marshalls.raw_to_base64(bytes)
            file.close()
    
    # Embed explanation images
    for question in case_dict["questions"]:
        if question.has("explanation") and question["explanation"].has("images"):
            for img_path in question["explanation"]["images"]:
                var img_file = FileAccess.open(img_path, FileAccess.READ)
                if img_file:
                    var img_bytes = img_file.get_buffer(img_file.get_length())
                    export_package["explanation_images"][img_path.get_file()] = Marshalls.raw_to_base64(img_bytes)
                    img_file.close()
    
    var json_string = JSON.stringify(export_package, "\t")
    var export_file = FileAccess.open(path, FileAccess.WRITE)
    if export_file:
        export_file.store_string(json_string)
        export_file.close()
        show_notification("Case exported successfully!")
    else:
        show_notification("Export failed!", true)

func _on_import_button_pressed() -> void:
    import_dialog.popup_centered(Vector2i(800, 600))

func _on_import_dialog_file_selected(path: String) -> void:
    var import_file = FileAccess.open(path, FileAccess.READ)
    if not import_file:
        show_notification("Failed to open import file!", true)
        return
    
    var json_string = import_file.get_as_text()
    import_file.close()
    
    var json = JSON.new()
    if json.parse(json_string) != OK:
        show_notification("Invalid case file format!", true)
        return
    
    var import_package = json.data
    if not import_package.has("case_data") or not import_package.has("dicom_files"):
        show_notification("Invalid case file structure!", true)
        return
    
    var new_case = RadiologyCase.new()
    new_case.from_dict(import_package["case_data"])
    
    var import_id = "%d" % Time.get_unix_time_from_system()
    
    # Create necessary directories
    DirAccess.make_dir_recursive_absolute("user://cases")
    DirAccess.make_dir_recursive_absolute("user://imported_dicom")
    
    # Extract DICOM files
    var new_dicom_paths = []
    for filename in import_package["dicom_files"].keys():
        var dicom_data = Marshalls.base64_to_raw(import_package["dicom_files"][filename])
        
        var extension = filename.get_extension()
        var base_name = filename.get_basename()
        var unique_filename = "%s_%s.%s" % [base_name, import_id, extension] if extension != "" else "%s_%s" % [filename, import_id]
        var dicom_save_path = "user://imported_dicom/" + unique_filename
        
        var dicom_file = FileAccess.open(dicom_save_path, FileAccess.WRITE)
        if dicom_file:
            dicom_file.store_buffer(dicom_data)
            dicom_file.close()
            new_dicom_paths.append(dicom_save_path)
    
    new_case.set_dicom_file_paths(new_dicom_paths)
    
    # Extract explanation images
    if import_package.has("explanation_images"):
        DirAccess.make_dir_recursive_absolute("user://imported_images")
        
        var questions = new_case.get_questions()
        for i in range(questions.size()):
            var question = questions[i]
            if question.has("explanation") and question["explanation"].has("images"):
                var new_image_paths = []
                for old_img_path in question["explanation"]["images"]:
                    var img_filename = old_img_path.get_file()
                    if import_package["explanation_images"].has(img_filename):
                        var img_data = Marshalls.base64_to_raw(import_package["explanation_images"][img_filename])
                        
                        var img_extension = img_filename.get_extension()
                        var img_base_name = img_filename.get_basename()
                        var unique_img_filename = "%s_%s.%s" % [img_base_name, import_id, img_extension] if img_extension != "" else "%s_%s" % [img_filename, import_id]
                        var img_save_path = "user://imported_images/" + unique_img_filename
                        
                        var img_file = FileAccess.open(img_save_path, FileAccess.WRITE)
                        if img_file:
                            img_file.store_buffer(img_data)
                            img_file.close()
                            new_image_paths.append(img_save_path)
                
                question["explanation"]["images"] = new_image_paths
        
        new_case.set_questions(questions)
    
    # Save the imported case
    var case_name = new_case.get_case_name()
    var case_save_path = "user://cases/%s.tres" % case_name
    
    # Handle name conflicts
    var counter = 1
    while FileAccess.file_exists(case_save_path):
        case_save_path = "user://cases/%s_%d.tres" % [case_name, counter]
        counter += 1
    
    if ResourceSaver.save(new_case, case_save_path) == OK:
        show_notification("Case imported successfully!")
        load_available_cases()
    else:
        show_notification("Failed to save imported case!", true)

func show_notification(message: String, is_error: bool = false) -> void:
    var label = Label.new()
    label.text = message
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.add_theme_color_override("font_color", Color.RED if is_error else Color.GREEN)
    
    var panel = PanelContainer.new()
    panel.add_child(label)
    panel.position = Vector2(get_viewport_rect().size.x / 2 - 150, 50)
    panel.custom_minimum_size = Vector2(300, 50)
    add_child(panel)
    
    await get_tree().create_timer(3.0).timeout
    panel.queue_free()