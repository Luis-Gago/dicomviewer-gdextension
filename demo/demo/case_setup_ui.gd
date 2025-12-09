extends Control

@onready var case_name_edit: LineEdit = $MarginContainer/VBoxContainer/CaseNameEdit
@onready var case_description_edit: TextEdit = $MarginContainer/VBoxContainer/CaseDescriptionEdit
@onready var questions_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/QuestionsContainer
@onready var file_dialog: FileDialog = $FileDialog
@onready var folder_dialog: FileDialog = $FolderDialog
@onready var dicom_status: Label = $MarginContainer/VBoxContainer/DicomStatus
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title

var explanation_image_dialog: FileDialog
var current_case: RadiologyCase
var dicom_files: PackedStringArray = []
var is_editing: bool = false
var original_case_path: String = ""

func _ready() -> void:
    current_case = RadiologyCase.new()
    setup_file_dialogs()
    
    # Check if we're editing an existing case
    if original_case_path != "":
        load_existing_case(original_case_path)

func setup_file_dialogs() -> void:
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.use_native_dialog = true
    file_dialog.add_filter("*.dcm ; *.DCM", "DICOM Files")
    file_dialog.add_filter("*", "All Files")
    
    folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
    folder_dialog.use_native_dialog = true
    
    # Setup explanation image dialog
    explanation_image_dialog = FileDialog.new()
    add_child(explanation_image_dialog)
    explanation_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    explanation_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
    explanation_image_dialog.use_native_dialog = true
    explanation_image_dialog.add_filter("*.png ; *.jpg ; *.jpeg ; *.webp ; *.bmp", "Image Files")
    explanation_image_dialog.files_selected.connect(_on_explanation_image_dialog_files_selected)

func load_existing_case(path: String) -> void:
    current_case = ResourceLoader.load(path) as RadiologyCase
    if current_case == null:
        push_error("Failed to load case: " + path)
        return
    
    is_editing = true
    original_case_path = path
    title_label.text = "Edit Radiology Case"
    
    # Load case data into UI
    case_name_edit.text = current_case.get_case_name()
    case_description_edit.text = current_case.get_case_description()
    
    # Load DICOM files
    var paths = current_case.get_dicom_file_paths()
    if paths.size() > 0:
        dicom_files.clear()
        for path_str in paths:
            dicom_files.append(path_str)
        dicom_status.text = "Loaded %d DICOM files" % dicom_files.size()
    
    # Load questions
    var questions = current_case.get_questions()
    for question_dict in questions:
        var panel = create_question_panel()
        questions_container.add_child(panel)
        populate_question_panel(panel, question_dict)

func populate_question_panel(panel: PanelContainer, question_dict: Dictionary) -> void:
    var vbox = panel.get_child(0) as VBoxContainer
    
    # Set organ system
    var organ_dropdown = vbox.get_child(1) as OptionButton
    var organ_system = question_dict.get("organ_system", "Chest")
    for i in range(organ_dropdown.item_count):
        if organ_dropdown.get_item_text(i) == organ_system:
            organ_dropdown.selected = i
            break
    
    # Set question type
    var type_dropdown = vbox.get_child(3) as OptionButton
    var question_type = question_dict.get("type", "free_text")
    type_dropdown.selected = 0 if question_type == "free_text" else 1
    
    # Set question text
    var question_edit = vbox.get_child(5) as LineEdit
    question_edit.text = question_dict.get("question", "")
    
    # Set answer based on type
    if question_type == "free_text":
        var answer_edit = vbox.get_child(7) as TextEdit
        answer_edit.text = question_dict.get("expected_answer", "")
    else:
        # Trigger the visibility change for multiple choice
        type_dropdown.item_selected.emit(1)
        
        var mc_container = vbox.get_child(8) as VBoxContainer
        var choices_container = mc_container.get_child(1) as VBoxContainer
        var choices = question_dict.get("choices", [])
        var correct_index = question_dict.get("correct_index", -1)
        
        # Set choices
        for i in range(min(choices.size(), choices_container.get_child_count())):
            var choice_hbox = choices_container.get_child(i) as HBoxContainer
            var choice_radio = choice_hbox.get_child(0) as CheckBox
            var choice_edit = choice_hbox.get_child(1) as LineEdit
            
            choice_edit.text = choices[i]
            if i == correct_index:
                choice_radio.button_pressed = true
    
    # Set image index
    var image_ref_spin = vbox.get_child(10) as SpinBox
    image_ref_spin.value = question_dict.get("image_index", 0)
    
    # Set explanation text - UPDATED: Handle both old and new format
    var explanation_container = vbox.get_child(11) as VBoxContainer
    var explanation_edit = explanation_container.get_child(1) as TextEdit
    
    # Check if using new nested structure
    if question_dict.has("explanation"):
        var explanation = question_dict["explanation"]
        if typeof(explanation) == TYPE_DICTIONARY:
            explanation_edit.text = explanation.get("text", "")
            
            # Load explanation images from nested structure
            var explanation_images = explanation.get("images", [])
            if explanation_images.size() > 0:
                var images_list = explanation_container.get_child(3) as VBoxContainer
                for child in images_list.get_children():
                    child.queue_free()
                
                for image_path in explanation_images:
                    var image_item = create_explanation_image_item(image_path)
                    images_list.add_child(image_item)
    else:
        # Fallback to old format for backward compatibility
        explanation_edit.text = question_dict.get("explanation_text", "")
        
        var explanation_images = question_dict.get("explanation_images", [])
        if explanation_images.size() > 0:
            var images_list = explanation_container.get_child(3) as VBoxContainer
            for child in images_list.get_children():
                child.queue_free()
            
            for image_path in explanation_images:
                var image_item = create_explanation_image_item(image_path)
                images_list.add_child(image_item)

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
            if recursive:
                var sub_files = scan_directory_for_dicom(full_path, recursive)
                for sub_file in sub_files:
                    found_files.append(sub_file)
        else:
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
    
    # Question type
    var type_label = Label.new()
    type_label.text = "Question Type:"
    vbox.add_child(type_label)
    
    var type_dropdown = OptionButton.new()
    type_dropdown.add_item("Free Text")
    type_dropdown.add_item("Multiple Choice")
    type_dropdown.selected = 0
    vbox.add_child(type_dropdown)
    
    # Question
    var question_label = Label.new()
    question_label.text = "Question:"
    vbox.add_child(question_label)
    
    var question_edit = LineEdit.new()
    question_edit.placeholder_text = "e.g., Identify the abnormality in the right lung"
    vbox.add_child(question_edit)
    
    # Free text answer (initially visible)
    var answer_label = Label.new()
    answer_label.text = "Expected Answer:"
    vbox.add_child(answer_label)
    
    var answer_edit = TextEdit.new()
    answer_edit.custom_minimum_size = Vector2(0, 80)
    answer_edit.placeholder_text = "e.g., Pneumothorax in right upper lobe"
    vbox.add_child(answer_edit)
    
    # Multiple choice container (initially hidden)
    var mc_container = VBoxContainer.new()
    mc_container.visible = false
    vbox.add_child(mc_container)
    
    var mc_label = Label.new()
    mc_label.text = "Multiple Choice Options:"
    mc_container.add_child(mc_label)
    
    var choices_container = VBoxContainer.new()
    mc_container.add_child(choices_container)
    
    # Add 4 default choices
    for i in range(4):
        var choice_hbox = HBoxContainer.new()
        choices_container.add_child(choice_hbox)
        
        var choice_radio = CheckBox.new()
        choice_radio.text = "Correct"
        choice_radio.button_group = ButtonGroup.new() if i == 0 else choices_container.get_child(0).get_child(0).button_group
        choice_hbox.add_child(choice_radio)
        
        var choice_edit = LineEdit.new()
        choice_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        choice_edit.placeholder_text = "Option %d" % (i + 1)
        choice_hbox.add_child(choice_edit)
    
    # Image index
    var image_ref_label = Label.new()
    image_ref_label.text = "Reference Image Index (optional):"
    vbox.add_child(image_ref_label)
    
    var image_ref_spin = SpinBox.new()
    image_ref_spin.min_value = 0
    image_ref_spin.max_value = 999
    vbox.add_child(image_ref_spin)
    
    # Explanation section
    var explanation_container = VBoxContainer.new()
    explanation_container.add_theme_constant_override("separation", 5)
    vbox.add_child(explanation_container)
    
    var explanation_label = Label.new()
    explanation_label.text = "Extended Explanation (shown after answer):"
    explanation_container.add_child(explanation_label)
    
    var explanation_edit = TextEdit.new()
    explanation_edit.custom_minimum_size = Vector2(0, 100)
    explanation_edit.placeholder_text = "Provide detailed explanation of the correct answer..."
    explanation_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    explanation_container.add_child(explanation_edit)
    
    var explanation_images_label = Label.new()
    explanation_images_label.text = "Explanation Images:"
    explanation_container.add_child(explanation_images_label)
    
    var images_list_container = VBoxContainer.new()
    images_list_container.add_theme_constant_override("separation", 5)
    explanation_container.add_child(images_list_container)
    
    var add_image_btn = Button.new()
    add_image_btn.text = "Add Explanation Image"
    add_image_btn.pressed.connect(func(): _on_add_explanation_image_pressed(panel))
    explanation_container.add_child(add_image_btn)
    
    # Remove button
    var remove_btn = Button.new()
    remove_btn.text = "Remove Question"
    remove_btn.pressed.connect(func(): panel.queue_free())
    vbox.add_child(remove_btn)
    
    # Connect type dropdown to toggle visibility
    type_dropdown.item_selected.connect(func(index: int):
        var is_multiple_choice = index == 1
        answer_label.visible = not is_multiple_choice
        answer_edit.visible = not is_multiple_choice
        mc_container.visible = is_multiple_choice
    )
    
    return panel

func _on_add_explanation_image_pressed(panel: PanelContainer) -> void:
    explanation_image_dialog.set_meta("current_panel", panel)
    explanation_image_dialog.popup_centered(Vector2i(800, 600))

func _on_explanation_image_dialog_files_selected(paths: PackedStringArray) -> void:
    var panel = explanation_image_dialog.get_meta("current_panel") as PanelContainer
    if panel == null:
        return
    
    var vbox = panel.get_child(0) as VBoxContainer
    var explanation_container = vbox.get_child(11) as VBoxContainer
    var images_list = explanation_container.get_child(3) as VBoxContainer
    
    for path in paths:
        var image_item = create_explanation_image_item(path)
        images_list.add_child(image_item)

func create_explanation_image_item(image_path: String) -> HBoxContainer:
    var hbox = HBoxContainer.new()
    
    var label = Label.new()
    label.text = image_path.get_file()
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.tooltip_text = image_path
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    hbox.add_child(label)
    
    var remove_btn = Button.new()
    remove_btn.text = "Remove"
    remove_btn.pressed.connect(func(): hbox.queue_free())
    hbox.add_child(remove_btn)
    
    hbox.set_meta("image_path", image_path)
    return hbox

func _on_save_button_pressed() -> void:
    if case_name_edit.text.strip_edges() == "":
        push_error("Please enter a case name")
        dicom_status.text = "Error: Please enter a case name"
        return
    
    if dicom_files.size() == 0:
        push_error("Please select DICOM files")
        dicom_status.text = "Error: Please select DICOM files"
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
            var question_type_idx = (vbox.get_child(3) as OptionButton).selected
            question_dict["type"] = "free_text" if question_type_idx == 0 else "multiple_choice"
            question_dict["question"] = (vbox.get_child(5) as LineEdit).text
            
            if question_type_idx == 0:  # Free text
                question_dict["expected_answer"] = (vbox.get_child(7) as TextEdit).text
            else:  # Multiple choice
                var mc_container = vbox.get_child(8) as VBoxContainer
                var choices_container = mc_container.get_child(1) as VBoxContainer
                var choices = []
                var correct_index = -1
                
                for i in range(choices_container.get_child_count()):
                    var choice_hbox = choices_container.get_child(i) as HBoxContainer
                    var choice_radio = choice_hbox.get_child(0) as CheckBox
                    var choice_edit = choice_hbox.get_child(1) as LineEdit
                    
                    if choice_edit.text.strip_edges() != "":
                        choices.append(choice_edit.text)
                        if choice_radio.button_pressed:
                            correct_index = choices.size() - 1
                
                question_dict["choices"] = choices
                question_dict["correct_index"] = correct_index
            
            question_dict["image_index"] = int((vbox.get_child(10) as SpinBox).value)
            
            # Collect explanation data - FIXED: Create nested dictionary structure
            var explanation_container = vbox.get_child(11) as VBoxContainer
            var explanation_text = (explanation_container.get_child(1) as TextEdit).text
            
            var images_list = explanation_container.get_child(3) as VBoxContainer
            var explanation_images = []
            for image_item in images_list.get_children():
                if image_item.has_meta("image_path"):
                    explanation_images.append(image_item.get_meta("image_path"))
            
            # Create nested explanation dictionary (this is what the C++ code expects)
            var explanation_dict = {
                "text": explanation_text,
                "images": explanation_images
            }
            question_dict["explanation"] = explanation_dict
            
            questions_array.append(question_dict)
    
    current_case.set_questions(questions_array)
    
    # Save
    DirAccess.make_dir_recursive_absolute("user://cases")
    var save_path = "user://cases/%s.tres" % current_case.get_case_name()
    
    # Debug: Print absolute path
    var absolute_path = ProjectSettings.globalize_path(save_path)
    print("Saving case to: ", save_path)
    print("Absolute path: ", absolute_path)
    
    var err = ResourceSaver.save(current_case, save_path)
    
    if err == OK:
        print("Case saved successfully!")
        print("You can find it at: ", absolute_path)
        show_save_notification()
    else:
        push_error("Failed to save case")
        dicom_status.text = "Error: Failed to save case"

func show_save_notification() -> void:
    dicom_status.text = "✓ Case saved successfully!"
    dicom_status.add_theme_color_override("font_color", Color.GREEN)
    
    # Clear the notification after 3 seconds
    await get_tree().create_timer(3.0).timeout
    dicom_status.text = "Loaded %d DICOM files" % dicom_files.size()
    dicom_status.remove_theme_color_override("font_color")

func _on_back_button_pressed() -> void:
    queue_free()
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")