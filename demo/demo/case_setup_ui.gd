extends Control

@onready var case_name_edit: LineEdit = $MarginContainer/VBoxContainer/CaseNameEdit
@onready var case_description_edit: TextEdit = $MarginContainer/VBoxContainer/CaseDescriptionEdit
@onready var questions_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/QuestionsContainer
@onready var file_dialog: FileDialog = $FileDialog
@onready var folder_dialog: FileDialog = $FolderDialog
@onready var dicom_status: Label = $MarginContainer/VBoxContainer/DicomStatus

var current_case: RadiologyCase
var dicom_files: PackedStringArray = []

func _ready() -> void:
    current_case = RadiologyCase.new()
    setup_file_dialogs()

func setup_file_dialogs() -> void:
    # File dialog for selecting multiple files
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.use_native_dialog = true  # Use native OS file picker
    # Accept all files - DICOM files often have no extension or various extensions
    file_dialog.add_filter("*.dcm ; *.DCM", "DICOM Files")
    file_dialog.add_filter("*", "All Files")
    
    # Folder dialog for selecting entire directories
    folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
    folder_dialog.use_native_dialog = true  # Use native OS folder picker

func _on_add_dicom_files_button_pressed() -> void:
    file_dialog.popup_centered(Vector2i(800, 600))

func _on_add_dicom_button_pressed() -> void:
    folder_dialog.popup_centered(Vector2i(800, 600))

func _on_file_dialog_files_selected(paths: PackedStringArray) -> void:
    print("Selected files: ", paths)
    load_files_from_paths(paths)

func _on_folder_dialog_dir_selected(dir_path: String) -> void:
    print("Selected folder: ", dir_path)
    dicom_status.text = "Scanning folder..."
    var files = scan_directory_for_dicom(dir_path)
    print("Found ", files.size(), " files")
    if files.size() > 0:
        load_files_from_paths(files)
    else:
        dicom_status.text = "No files found in folder"

func load_files_from_paths(paths: PackedStringArray) -> void:
    dicom_files.clear()
    
    dicom_status.text = "Loading files..."
    
    for path in paths:
        dicom_files.append(path)
    
    # Sort files alphabetically
    dicom_files.sort()
    
    print("Total files to load: ", dicom_files.size())
    
    if dicom_files.size() > 0:
        var paths_array = Array()
        for path in dicom_files:
            paths_array.append(path)
        current_case.set_dicom_file_paths(paths_array)
        
        dicom_status.text = "Loaded %d DICOM files" % dicom_files.size()
    else:
        dicom_status.text = "No files found"

func scan_directory_for_dicom(dir_path: String, recursive: bool = true) -> PackedStringArray:
    var found_files = PackedStringArray()
    
    var dir = DirAccess.open(dir_path)
    if dir == null:
        push_error("Failed to open directory: " + dir_path)
        dicom_status.text = "Failed to open directory"
        return found_files
    
    dir.list_dir_begin()
    var file_name = dir.get_next()
    
    while file_name != "":
        if file_name == "." or file_name == "..":
            file_name = dir.get_next()
            continue
            
        var full_path = dir_path.path_join(file_name)
        
        if dir.current_is_dir():
            # Recursively scan subdirectories if enabled
            if recursive:
                var sub_files = scan_directory_for_dicom(full_path, recursive)
                for sub_file in sub_files:
                    found_files.append(sub_file)
        else:
            # Include all files - let DCMTK determine if they're valid DICOM
            # Common DICOM naming: IM00001, 1.2.840..., *.dcm, no extension, etc.
            found_files.append(full_path)
        
        file_name = dir.get_next()
    
    dir.list_dir_end()
    return found_files

func _on_add_question_button_pressed() -> void:
    var question_panel = create_question_panel()
    questions_container.add_child(question_panel)

func create_question_panel() -> PanelContainer:
    var panel = PanelContainer.new()
    var vbox = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 10)
    panel.add_child(vbox)
    
    # Organ system
    var organ_label = Label.new()
    organ_label.text = "Organ System:"
    vbox.add_child(organ_label)
    
    var organ_dropdown = OptionButton.new()
    organ_dropdown.add_item("Chest")
    organ_dropdown.add_item("Abdomen")
    organ_dropdown.add_item("Brain")
    organ_dropdown.add_item("Musculoskeletal")
    organ_dropdown.add_item("Other")
    vbox.add_child(organ_dropdown)
    
    # Question
    var question_label = Label.new()
    question_label.text = "Question:"
    vbox.add_child(question_label)
    
    var question_edit = LineEdit.new()
    question_edit.placeholder_text = "e.g., Identify the abnormality in the right lung"
    vbox.add_child(question_edit)
    
    # Answer
    var answer_label = Label.new()
    answer_label.text = "Expected Answer:"
    vbox.add_child(answer_label)
    
    var answer_edit = TextEdit.new()
    answer_edit.custom_minimum_size = Vector2(0, 80)
    answer_edit.placeholder_text = "e.g., Pneumothorax in right upper lobe"
    vbox.add_child(answer_edit)
    
    # Image index
    var image_ref_label = Label.new()
    image_ref_label.text = "Reference Image Index (optional):"
    vbox.add_child(image_ref_label)
    
    var image_ref_spin = SpinBox.new()
    image_ref_spin.min_value = 0
    image_ref_spin.max_value = 999
    vbox.add_child(image_ref_spin)
    
    # Remove button
    var remove_btn = Button.new()
    remove_btn.text = "Remove Question"
    remove_btn.pressed.connect(func(): panel.queue_free())
    vbox.add_child(remove_btn)
    
    return panel

func _on_save_button_pressed() -> void:
    if case_name_edit.text.strip_edges() == "":
        push_error("Please enter a case name")
        return
    
    if dicom_files.size() == 0:
        push_error("Please select DICOM files")
        return
    
    current_case.set_case_name(case_name_edit.text)
    current_case.set_case_description(case_description_edit.text)
    
    # Collect questions
    var questions_array = Array()
    for child in questions_container.get_children():
        if child is PanelContainer:
            var vbox = child.get_child(0) as VBoxContainer
            var question_dict = Dictionary()
            question_dict["organ_system"] = (vbox.get_child(1) as OptionButton).get_item_text((vbox.get_child(1) as OptionButton).selected)
            question_dict["question"] = (vbox.get_child(3) as LineEdit).text
            question_dict["expected_answer"] = (vbox.get_child(5) as TextEdit).text
            question_dict["image_index"] = int((vbox.get_child(7) as SpinBox).value)
            questions_array.append(question_dict)
    
    current_case.set_questions(questions_array)
    
    # Save
    DirAccess.make_dir_recursive_absolute("user://cases")
    var save_path = "user://cases/%s.tres" % current_case.get_case_name()
    var err = ResourceSaver.save(current_case, save_path)
    
    if err == OK:
        print("Case saved to: ", save_path)
        get_tree().change_scene_to_file("res://demo/main_menu.tscn")
    else:
        push_error("Failed to save case")

func _on_back_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")