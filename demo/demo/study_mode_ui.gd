extends Control

# UI References
@onready var dicom_viewer: DicomViewer = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/DicomViewer
@onready var question_label: Label = $HSplitContainer/RightPanel/QuestionLabel
@onready var answer_edit: TextEdit = $HSplitContainer/RightPanel/AnswerEdit
@onready var submit_button: Button = $HSplitContainer/RightPanel/SubmitButton
@onready var next_question_button: Button = $HSplitContainer/RightPanel/NextQuestionButton
@onready var feedback_label: Label = $HSplitContainer/RightPanel/FeedbackLabel
@onready var progress_label: Label = $HSplitContainer/RightPanel/ProgressLabel
@onready var image_index_label: Label = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ImageControls/ImageIndexLabel
@onready var answer_container: VBoxContainer = $HSplitContainer/RightPanel/AnswerContainer
@onready var explanation_container: VBoxContainer = $HSplitContainer/RightPanel/ExplanationContainer
@onready var explanation_scroll: ScrollContainer = $HSplitContainer/RightPanel/ExplanationContainer/ExplanationScroll
@onready var explanation_content: VBoxContainer = $HSplitContainer/RightPanel/ExplanationContainer/ExplanationScroll/ExplanationContent

# DICOM viewer controls
@onready var window_slider: HSlider = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/WindowControls/WindowSlider
@onready var level_slider: HSlider = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/WindowControls/LevelSlider
@onready var window_label: Label = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/WindowControls/WindowLabel
@onready var level_label: Label = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/WindowControls/LevelLabel
@onready var aspect_ratio_label: Label = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ImageInfo/AspectRatioLabel
@onready var modality_label: Label = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ImageInfo/ModalityLabel
@onready var zoom_mode_button: Button = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ViewControls/ZoomModeButton
@onready var arrow_annotation_button: Button = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ViewControls/ArrowAnnotationButton
@onready var circle_annotation_button: Button = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ViewControls/CircleAnnotationButton
@onready var reset_view_button: Button = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ViewControls/ResetViewButton

# Case data
var case_path: String = ""
var current_case: RadiologyCase
var current_question_index: int = 0
var current_image_index: int = 0
var dicom_files: Array = []
var user_answers: Array = []

# Multiple choice state
var mc_button_group: ButtonGroup
var mc_buttons: Array = []

# Systematic review state
var systematic_review_controls: Array = []  # Array of dictionaries with organ_system, button_group, buttons

# DICOM viewer state
var is_dragging: bool = false
var drag_start_pos: Vector2
var drag_start_window: float
var drag_start_level: float
var zoom_mode_active: bool = false
var is_zoomed_in: bool = false
var zoom_center: Vector2 = Vector2.ZERO
const ZOOM_FACTOR: float = 2.5
var user_adjusted_windowing: bool = false
var pan_gesture_accumulator: float = 0.0
var pan_gesture_threshold: float = 1.0

# Annotation state
var annotation_mode_active: bool = false
var annotation_type: String = ""  # "arrow" or "circle"
var is_drawing_arrow: bool = false
var arrow_start_pos: Vector2 = Vector2.ZERO
var arrow_end_pos: Vector2 = Vector2.ZERO
var is_drawing_circle: bool = false
var circle_center_pos: Vector2 = Vector2.ZERO
var circle_radius: float = 0.0
var annotations_per_image: Dictionary = {}  # key: image_index, value: Array of annotation dictionaries
var selected_annotation_index: int = -1
var annotation_overlay: Control

# Performance optimization
var is_loading: bool = false
var pending_image_index: int = -1

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    set_process_unhandled_input(true)
    
    dicom_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
    mc_button_group = ButtonGroup.new()
    
    setup_dicom_controls()
    setup_annotation_overlay()
    
    # Hide explanation container initially
    explanation_container.visible = false
    
    # Initialize aspect ratio display
    update_aspect_ratio_label()
    
    if case_path != "":
        load_case(case_path)

func setup_dicom_controls() -> void:
    window_slider.min_value = 1.0
    window_slider.max_value = 4000.0
    window_slider.value = 400.0
    window_slider.step = 1.0
    
    level_slider.min_value = -1000.0
    level_slider.max_value = 3000.0
    level_slider.value = 40.0
    level_slider.step = 1.0
    
    if not window_slider.value_changed.is_connected(_on_window_slider_value_changed):
        window_slider.value_changed.connect(_on_window_slider_value_changed)
    if not level_slider.value_changed.is_connected(_on_level_slider_value_changed):
        level_slider.value_changed.connect(_on_level_slider_value_changed)
    if not zoom_mode_button.toggled.is_connected(_on_zoom_mode_button_toggled):
        zoom_mode_button.toggled.connect(_on_zoom_mode_button_toggled)
    if not arrow_annotation_button.toggled.is_connected(_on_arrow_annotation_button_toggled):
        arrow_annotation_button.toggled.connect(_on_arrow_annotation_button_toggled)
    if not circle_annotation_button.toggled.is_connected(_on_circle_annotation_button_toggled):
        circle_annotation_button.toggled.connect(_on_circle_annotation_button_toggled)
    if not reset_view_button.pressed.is_connected(_on_reset_button_pressed):
        reset_view_button.pressed.connect(_on_reset_button_pressed)
    if not dicom_viewer.gui_input.is_connected(_on_dicom_viewer_gui_input):
        dicom_viewer.gui_input.connect(_on_dicom_viewer_gui_input)
    
    update_windowing_labels()

func setup_annotation_overlay() -> void:
    # Create a transparent overlay on top of the DICOM viewer for drawing annotations
    annotation_overlay = Control.new()
    annotation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    annotation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dicom_viewer.add_child(annotation_overlay)
    annotation_overlay.draw.connect(_on_annotation_overlay_draw)

func load_case(path: String) -> void:
    current_case = ResourceLoader.load(path) as RadiologyCase
    if current_case == null:
        push_error("Failed to load case: " + path)
        return
    
    dicom_files = current_case.get_dicom_file_paths()
    
    if dicom_files.size() > 0:
        current_image_index = 0
        load_current_image()
    
    current_question_index = 0
    display_current_question()

func load_current_image() -> void:
    # Prevent loading if already loading
    if is_loading:
        pending_image_index = current_image_index
        return
    
    if current_image_index >= 0 and current_image_index < dicom_files.size():
        is_loading = true
        
        var success = dicom_viewer.load_dicom(dicom_files[current_image_index])
        
        if success:
            image_index_label.text = "Image %d / %d" % [current_image_index + 1, dicom_files.size()]
            
            # Update aspect ratio display
            var aspect_ratio = dicom_viewer.get_pixel_aspect_ratio()
            if aspect_ratio == 1.0:
                aspect_ratio_label.text = "Aspect Ratio: 1:1"
            else:
                aspect_ratio_label.text = "Aspect Ratio: %.2f:1" % aspect_ratio
            
            # Update modality display
            var modality = dicom_viewer.get_modality()
            if modality != "":
                modality_label.text = "Modality: " + modality
            else:
                modality_label.text = "Modality: Unknown"
            
            if is_zoomed_in:
                dicom_viewer.reset_view()
                is_zoomed_in = false
            
            # Redraw annotations for new image
            selected_annotation_index = -1
            if annotation_overlay:
                annotation_overlay.queue_redraw()
            
            if not user_adjusted_windowing:
                # Use modality-specific preset
                dicom_viewer.apply_modality_preset()
                # Block signals to prevent redundant updates
                window_slider.set_block_signals(true)
                level_slider.set_block_signals(true)
                window_slider.value = dicom_viewer.get_window()
                level_slider.value = dicom_viewer.get_level()
                window_slider.set_block_signals(false)
                level_slider.set_block_signals(false)
                # Update labels without triggering value_changed
                window_label.text = "Window: %.0f" % window_slider.value
                level_label.text = "Level: %.0f" % level_slider.value
            else:
                dicom_viewer.set_window_level(window_slider.value, level_slider.value)
        else:
            push_error("Failed to load DICOM: " + dicom_files[current_image_index])
        
        is_loading = false
        
        # Handle pending load if any
        if pending_image_index != -1 and pending_image_index != current_image_index:
            current_image_index = pending_image_index
            pending_image_index = -1
            call_deferred("load_current_image")

func display_current_question() -> void:
    var questions = current_case.get_questions()
    if current_question_index >= questions.size():
        show_completion()
        return
    
    var question_dict = questions[current_question_index]
    var question_type = question_dict.get("type", "free_text")
    
    question_label.text = "Organ System: %s\n\nQuestion: %s" % [
        question_dict.get("organ_system", "Unknown"),
        question_dict.get("question", "")
    ]
    
    # Navigate to reference image if specified
    var ref_index = question_dict.get("image_index", -1)
    if ref_index >= 0 and ref_index < dicom_files.size():
        current_image_index = ref_index
        load_current_image()
    
    # Clear previous answer UI
    answer_edit.visible = false
    for btn in mc_buttons:
        btn.queue_free()
    mc_buttons.clear()
    
    # Clear systematic review controls
    for control_dict in systematic_review_controls:
        for btn in control_dict.get("buttons", []):
            btn.queue_free()
    systematic_review_controls.clear()
    
    # Hide explanation container
    explanation_container.visible = false
    clear_explanation()
    
    # Setup answer UI based on question type
    if question_type == "multiple_choice":
        setup_multiple_choice_ui(question_dict)
    elif question_type == "systematic_review":
        setup_systematic_review_ui(question_dict)
    elif question_type == "mark_target":
        setup_mark_target_ui(question_dict)
    else:
        setup_free_text_ui()
    
    feedback_label.text = "Answer the question above"
    submit_button.disabled = false
    next_question_button.disabled = true
    
    update_progress()

func setup_free_text_ui() -> void:
    answer_edit.visible = true
    answer_edit.text = ""

func setup_multiple_choice_ui(question_dict: Dictionary) -> void:
    var choices = question_dict.get("choices", [])
    
    for i in range(choices.size()):
        var radio_button = CheckBox.new()
        radio_button.text = choices[i]
        radio_button.button_group = mc_button_group
        answer_container.add_child(radio_button)
        mc_buttons.append(radio_button)

func get_finding_display_text(finding_type: String) -> String:
    match finding_type:
        "no-finding":
            return "No Finding"
        "benign":
            return "Benign Finding"
        "pathological":
            return "Pathological Finding"
        _:
            return "Unknown"

func setup_systematic_review_ui(question_dict: Dictionary) -> void:
    var organ_systems_findings = question_dict.get("organ_systems_findings", [])
    
    if organ_systems_findings.size() == 0:
        var error_label = Label.new()
        error_label.text = "No organ systems defined for this systematic review."
        answer_container.add_child(error_label)
        return
    
    # Title
    var title_label = Label.new()
    title_label.text = "Select findings for each organ system:"
    title_label.add_theme_font_size_override("font_size", 14)
    answer_container.add_child(title_label)
    
    var separator = HSeparator.new()
    answer_container.add_child(separator)
    
    # Create controls for each organ system
    for organ_finding in organ_systems_findings:
        var organ_name = organ_finding.get("organ_system", "Unknown")
        
        # Create panel for this organ system
        var panel = PanelContainer.new()
        var vbox = VBoxContainer.new()
        panel.add_child(vbox)
        
        # Organ system label
        var organ_label = Label.new()
        organ_label.text = organ_name
        organ_label.add_theme_font_size_override("font_size", 13)
        vbox.add_child(organ_label)
        
        # Button group for this organ system
        var button_group = ButtonGroup.new()
        var buttons = []
        
        # Create radio buttons for finding types
        var findings_hbox = HBoxContainer.new()
        vbox.add_child(findings_hbox)
        
        # No Finding
        var no_finding_btn = CheckBox.new()
        no_finding_btn.text = "No Finding"
        no_finding_btn.button_group = button_group
        findings_hbox.add_child(no_finding_btn)
        buttons.append(no_finding_btn)
        
        # Benign Finding
        var benign_btn = CheckBox.new()
        benign_btn.text = "Benign Finding"
        benign_btn.button_group = button_group
        findings_hbox.add_child(benign_btn)
        buttons.append(benign_btn)
        
        # Pathological Finding
        var pathological_btn = CheckBox.new()
        pathological_btn.text = "Pathological Finding"
        pathological_btn.button_group = button_group
        findings_hbox.add_child(pathological_btn)
        buttons.append(pathological_btn)
        
        answer_container.add_child(panel)
        
        # Store control information
        systematic_review_controls.append({
            "organ_system": organ_name,
            "button_group": button_group,
            "buttons": buttons,
            "expected_finding": organ_finding.get("finding_type", "no-finding")
        })

func setup_mark_target_ui(question_dict: Dictionary) -> void:
    # Get the required annotation type
    var target_annotation = question_dict.get("target_annotation", {})
    var required_type = target_annotation.get("type", "").to_lower()
    
    var instruction_label = Label.new()
    
    # Display specific instruction based on required annotation type
    if required_type == "circle":
        instruction_label.text = "Use the Circle tool (C) to mark the area described in the question."
        instruction_label.add_theme_color_override("font_color", Color.CYAN)
    elif required_type == "arrow":
        instruction_label.text = "Use the Arrow tool (A) to mark the area described in the question."
        instruction_label.add_theme_color_override("font_color", Color.CYAN)
    else:
        instruction_label.text = "Use the Circle tool (C) or Arrow tool (A) to mark the area described in the question."
    
    instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    answer_container.add_child(instruction_label)
    
    var hint_label = Label.new()
    hint_label.text = "Hint: Draw your annotation as close to the target area as possible."
    hint_label.add_theme_font_size_override("font_size", 10)
    hint_label.add_theme_color_override("font_color", Color.YELLOW)
    answer_container.add_child(hint_label)
    
    # Store target data for validation
    submit_button.set_meta("target_data", question_dict.get("target_annotation", {}))
    submit_button.set_meta("tolerance", question_dict.get("tolerance", 50.0))

func update_progress() -> void:
    var total = current_case.get_questions().size()
    progress_label.text = "Question %d / %d" % [current_question_index + 1, total]

func update_windowing_labels() -> void:
    window_label.text = "Window: %.0f" % window_slider.value
    level_label.text = "Level: %.0f" % level_slider.value

func update_aspect_ratio_label() -> void:
    var aspect_ratio = dicom_viewer.get_pixel_aspect_ratio()
    if aspect_ratio == 1.0:
        aspect_ratio_label.text = "Aspect Ratio: 1:1"
    else:
        aspect_ratio_label.text = "Aspect Ratio: %.2f:1" % aspect_ratio

func _on_submit_button_pressed() -> void:
    var questions = current_case.get_questions()
    var current_question = questions[current_question_index]
    var question_type = current_question.get("type", "free_text")
    
    var user_answer = ""
    var is_correct = false
    var expected_answer = ""
    
    if question_type == "multiple_choice":
        var selected_index = -1
        for i in range(mc_buttons.size()):
            if mc_buttons[i].button_pressed:
                selected_index = i
                user_answer = mc_buttons[i].text
                break
        
        if selected_index == -1:
            feedback_label.text = "Please select an answer"
            return
        
        var correct_index = current_question.get("correct_index", -1)
        is_correct = selected_index == correct_index
        
        if correct_index >= 0 and correct_index < mc_buttons.size():
            expected_answer = mc_buttons[correct_index].text
        
        if is_correct:
            feedback_label.text = "✓ Correct!"
        else:
            feedback_label.text = "✗ Incorrect\n\nCorrect Answer: %s" % expected_answer
    elif question_type == "systematic_review":
        # Check if all organ systems have been reviewed
        var all_answered = true
        for control_dict in systematic_review_controls:
            var button_group = control_dict["button_group"] as ButtonGroup
            if button_group.get_pressed_button() == null:
                all_answered = false
                break
        
        if not all_answered:
            feedback_label.text = "Please review all organ systems"
            return
        
        # Grade systematic review
        var correct_count = 0
        var total_count = systematic_review_controls.size()
        var user_findings = []
        var expected_findings_text = ""
        var feedback_text = "Systematic Review Results:\n\n"
        
        for control_dict in systematic_review_controls:
            var organ_name = control_dict["organ_system"]
            var expected_finding = control_dict["expected_finding"]
            var buttons = control_dict["buttons"]
            
            var user_finding = ""
            if buttons[0].button_pressed:
                user_finding = "no-finding"
            elif buttons[1].button_pressed:
                user_finding = "benign"
            elif buttons[2].button_pressed:
                user_finding = "pathological"
            
            var is_organ_correct = user_finding == expected_finding
            if is_organ_correct:
                correct_count += 1
                feedback_text += "✓ %s: Correct\n" % organ_name
            else:
                var expected_text = get_finding_display_text(expected_finding)
                feedback_text += "✗ %s: Incorrect (Expected: %s)\n" % [organ_name, expected_text]
            
            user_findings.append({
                "organ_system": organ_name,
                "finding": user_finding
            })
            
            expected_findings_text += "%s: %s\n" % [organ_name, get_finding_display_text(expected_finding)]
        
        is_correct = correct_count == total_count
        user_answer = JSON.stringify(user_findings)
        expected_answer = expected_findings_text
        
        feedback_text += "\nScore: %d / %d (%.1f%%)" % [correct_count, total_count, (float(correct_count) / total_count) * 100.0]
        feedback_label.text = feedback_text
    elif question_type == "mark_target":
        # Get user's annotation
        var user_annotations = annotations_per_image.get(current_image_index, [])
        
        if user_annotations.size() == 0:
            feedback_label.text = "Please draw an annotation to mark the target area"
            return
        
        # Get the most recent annotation
        var user_annotation = user_annotations[user_annotations.size() - 1]
        
        # Get target data
        var target_data = submit_button.get_meta("target_data")
        var tolerance = submit_button.get_meta("tolerance")
        
        # Validate annotation
        is_correct = validate_target_annotation(user_annotation, target_data, tolerance)
        
        if is_correct:
            feedback_label.text = "✓ Correct! Your annotation is within the target area.\n\nThe correct annotation is now displayed in GREEN."
            feedback_label.add_theme_color_override("font_color", Color.GREEN)
        else:
            feedback_label.text = "✗ Incorrect. Your annotation is not within the acceptable range of the target area.\n\nThe correct annotation is now displayed in GREEN for comparison."
            feedback_label.add_theme_color_override("font_color", Color.RED)
        
        # Add the correct annotation to the display (but don't save it to user's answers)
        # Store it with a special flag so it renders differently
        if not annotations_per_image.has(current_image_index):
            annotations_per_image[current_image_index] = []
        
        # Add correct annotation with a marker (keep original normalized format)
        var correct_annotation = target_data.duplicate(true)
        correct_annotation["is_correct_answer"] = true
        annotations_per_image[current_image_index].append(correct_annotation)
        annotation_overlay.queue_redraw()
        
        user_answer = JSON.stringify(user_annotation)
        expected_answer = "Target area marked correctly"
        
        user_answers.append({
            "question": current_question.get("question", ""),
            "user_answer": user_answer,
            "expected_answer": expected_answer,
            "type": question_type,
            "is_correct": is_correct
        })
    else:
        user_answer = answer_edit.text.strip_edges()
        expected_answer = current_question.get("expected_answer", "")
        feedback_label.text = "Expected Answer:\n\n%s" % expected_answer
    
    # Only append if not already appended (mark_target does it inline)
    if question_type != "mark_target":
        user_answers.append({
            "question": current_question.get("question", ""),
            "user_answer": user_answer,
            "expected_answer": expected_answer,
            "type": question_type,
            "is_correct": is_correct if question_type in ["multiple_choice", "systematic_review"] else null
        })
    
    # Show explanation if available
    show_explanation(current_question_index)
    
    submit_button.disabled = true
    next_question_button.disabled = false
    
func show_explanation(question_index: int) -> void:
    if not current_case.has_explanation(question_index):
        explanation_container.visible = false
        return
    
    var explanation = current_case.get_question_explanation(question_index)
    
    var explanation_text = explanation.get("text", "")
    var explanation_images = explanation.get("images", [])
    
    # Clear previous explanation content
    clear_explanation()
    
    # Add explanation text
    if explanation_text != "":
        var text_label = RichTextLabel.new()
        text_label.bbcode_enabled = true
        text_label.text = "[b]Extended Explanation:[/b]\n\n" + explanation_text
        text_label.fit_content = true
        text_label.scroll_active = false
        text_label.custom_minimum_size = Vector2(0, 150)
        text_label.size_flags_horizontal = Control.SIZE_FILL
        text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
        explanation_content.add_child(text_label)
    
    # Add explanation images
    for image_path in explanation_images:
        if FileAccess.file_exists(image_path):
            var image = Image.load_from_file(image_path)
            if image != null:
                var texture = ImageTexture.create_from_image(image)
                
                var texture_rect = TextureRect.new()
                texture_rect.texture = texture
                texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
                texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                texture_rect.custom_minimum_size = Vector2(0, 300)
                texture_rect.size_flags_horizontal = Control.SIZE_FILL
                texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
                
                # Add some spacing
                var spacer = Control.new()
                spacer.custom_minimum_size = Vector2(0, 10)
                explanation_content.add_child(spacer)
                
                explanation_content.add_child(texture_rect)
            else:
                push_error("Failed to load explanation image: " + image_path)
        else:
            push_error("Explanation image not found: " + image_path)
    
    # Show the explanation container
    explanation_container.visible = true
    explanation_container.show()
    explanation_scroll.visible = true
    explanation_scroll.show()
    
    # Single deferred layout update
    call_deferred("_force_layout_update")

func _force_layout_update() -> void:
    explanation_container.queue_sort()
    explanation_scroll.queue_sort()
    explanation_content.queue_sort()

func clear_explanation() -> void:
    for child in explanation_content.get_children():
        child.queue_free()

func _on_next_question_button_pressed() -> void:
    current_question_index += 1
    display_current_question()

func _on_prev_image_button_pressed() -> void:
    if is_loading:
        return
    if current_image_index > 0:
        current_image_index -= 1
        load_current_image()

func _on_next_image_button_pressed() -> void:
    if is_loading:
        return
    if current_image_index < dicom_files.size() - 1:
        current_image_index += 1
        load_current_image()

func _on_window_slider_value_changed(value: float) -> void:
    user_adjusted_windowing = true
    dicom_viewer.set_window_level(value, level_slider.value)
    update_windowing_labels()

func _on_level_slider_value_changed(value: float) -> void:
    user_adjusted_windowing = true
    dicom_viewer.set_window_level(window_slider.value, value)
    update_windowing_labels()

func _on_zoom_mode_button_toggled(button_pressed: bool) -> void:
    zoom_mode_active = button_pressed
    if button_pressed:
        # Disable annotation modes
        annotation_mode_active = false
        annotation_type = ""
        arrow_annotation_button.button_pressed = false
        circle_annotation_button.button_pressed = false
        dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_CROSS
    else:
        dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_ARROW
        if is_zoomed_in:
            dicom_viewer.reset_view()
            is_zoomed_in = false

func _on_reset_button_pressed() -> void:
    dicom_viewer.reset_view()
    is_zoomed_in = false

func _on_soft_tissue_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_soft_tissue_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_windowing_labels()

func _on_lung_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_lung_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_windowing_labels()

func _on_bone_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_bone_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_windowing_labels()

func _on_brain_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_brain_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_windowing_labels()

func _on_t2_brain_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_t2_brain_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_windowing_labels()

func _on_mammo_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_mammography_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_windowing_labels()

func _on_auto_button_pressed() -> void:
    user_adjusted_windowing = false
    dicom_viewer.apply_auto_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_windowing_labels()

func zoom_into_position(click_pos: Vector2, zoom_factor: float) -> void:
    if dicom_viewer.get_child_count() == 0:
        return
    
    var texture_rect = dicom_viewer.get_child(0) as TextureRect
    if not texture_rect or not texture_rect.texture:
        return
    
    var texture_point = (click_pos - texture_rect.position) / texture_rect.scale.x
    texture_rect.scale = Vector2(zoom_factor, zoom_factor)
    var new_position = click_pos - (texture_point * zoom_factor)
    texture_rect.position = new_position

func _on_annotation_overlay_draw() -> void:
    if not annotation_overlay:
        return
    
    # Draw annotations for current image
    var annotations = annotations_per_image.get(current_image_index, [])
    for i in range(annotations.size()):
        var annotation = annotations[i]
        
        # Denormalize annotation coordinates if needed
        var denorm_annotation = denormalize_annotation(annotation)
        
        # Check if this is the correct answer annotation
        var is_correct_answer = annotation.get("is_correct_answer", false)
        
        # Color logic: Green for correct answer, Yellow for selected, Red for user annotations
        var color = Color.GREEN if is_correct_answer else (Color.YELLOW if i == selected_annotation_index else Color.RED)
        var width = 4.0 if is_correct_answer else 3.0  # Make correct answer slightly thicker
        
        if denorm_annotation["type"] == "arrow":
            draw_arrow(annotation_overlay, denorm_annotation["start"], denorm_annotation["end"], color, width)
        elif denorm_annotation["type"] == "circle":
            draw_circle_annotation(annotation_overlay, denorm_annotation["center"], denorm_annotation["radius"], color, width)
    
    # Draw annotation being created
    if is_drawing_arrow:
        draw_arrow(annotation_overlay, arrow_start_pos, arrow_end_pos, Color.CYAN, 2.0)
    elif is_drawing_circle:
        draw_circle_annotation(annotation_overlay, circle_center_pos, circle_radius, Color.CYAN, 2.0)

func draw_arrow(canvas: Control, start: Vector2, end: Vector2, color: Color, width: float) -> void:
    # Draw line
    canvas.draw_line(start, end, color, width)
    
    # Draw arrowhead
    var direction = (end - start).normalized()
    var arrow_size = 20.0
    var arrow_angle = PI / 6.0  # 30 degrees
    
    var left_point = end - direction.rotated(arrow_angle) * arrow_size
    var right_point = end - direction.rotated(-arrow_angle) * arrow_size
    
    canvas.draw_line(end, left_point, color, width)
    canvas.draw_line(end, right_point, color, width)

func draw_circle_annotation(canvas: Control, center: Vector2, radius: float, color: Color, width: float) -> void:
    # Draw circle outline
    var num_segments = 64
    var angle_step = 2.0 * PI / num_segments
    
    for i in range(num_segments):
        var angle1 = i * angle_step
        var angle2 = (i + 1) * angle_step
        
        var point1 = center + Vector2(cos(angle1), sin(angle1)) * radius
        var point2 = center + Vector2(cos(angle2), sin(angle2)) * radius
        
        canvas.draw_line(point1, point2, color, width)

func _on_dicom_viewer_gui_input(event: InputEvent) -> void:
    if event is InputEventPanGesture:
        var pg = event as InputEventPanGesture
        pan_gesture_accumulator += pg.delta.y
        
        if pan_gesture_accumulator <= -pan_gesture_threshold:
            _on_prev_image_button_pressed()
            pan_gesture_accumulator = 0.0
        elif pan_gesture_accumulator >= pan_gesture_threshold:
            _on_next_image_button_pressed()
            pan_gesture_accumulator = 0.0
        return
    
    # Handle annotation mode input
    if annotation_mode_active and event is InputEventMouseButton:
        var mb = event as InputEventMouseButton
        
        # Right-click to delete selected annotation
        if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
            if selected_annotation_index >= 0:
                delete_selected_annotation()
                get_viewport().set_input_as_handled()
                return
            else:
                # Try to select an annotation
                select_annotation_at_position(mb.position)
                get_viewport().set_input_as_handled()
                return
        
        # Left-click to draw annotation
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                if annotation_type == "arrow":
                    is_drawing_arrow = true
                    arrow_start_pos = mb.position
                    arrow_end_pos = mb.position
                elif annotation_type == "circle":
                    is_drawing_circle = true
                    circle_center_pos = mb.position
                    circle_radius = 0.0
                selected_annotation_index = -1  # Deselect when starting new annotation
            else:
                if is_drawing_arrow:
                    # Finish drawing arrow
                    add_arrow_to_current_image(arrow_start_pos, arrow_end_pos)
                    is_drawing_arrow = false
                elif is_drawing_circle:
                    # Finish drawing circle
                    add_circle_to_current_image(circle_center_pos, circle_radius)
                    is_drawing_circle = false
            annotation_overlay.queue_redraw()
            get_viewport().set_input_as_handled()
            return
    
    if annotation_mode_active and event is InputEventMouseMotion:
        var mm = event as InputEventMouseMotion
        if is_drawing_arrow:
            arrow_end_pos = mm.position
            annotation_overlay.queue_redraw()
            get_viewport().set_input_as_handled()
            return
        elif is_drawing_circle:
            circle_radius = circle_center_pos.distance_to(mm.position)
            annotation_overlay.queue_redraw()
            get_viewport().set_input_as_handled()
            return
    
    if event is InputEventMouseButton:
        var mb = event as InputEventMouseButton
        
        if zoom_mode_active and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
            if is_zoomed_in:
                dicom_viewer.reset_view()
                is_zoomed_in = false
            else:
                zoom_center = mb.position
                zoom_into_position(zoom_center, ZOOM_FACTOR)
                is_zoomed_in = true
            get_viewport().set_input_as_handled()
            return
        
        if not zoom_mode_active:
            if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
                _on_prev_image_button_pressed()
                get_viewport().set_input_as_handled()
                return
            elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
                _on_next_image_button_pressed()
                get_viewport().set_input_as_handled()
                return
        
        if not zoom_mode_active and mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                is_dragging = true
                drag_start_pos = mb.position
                drag_start_window = window_slider.value
                drag_start_level = level_slider.value
            else:
                if is_dragging:
                    user_adjusted_windowing = true
                is_dragging = false
    
    elif event is InputEventMouseMotion and is_dragging and not zoom_mode_active:
        user_adjusted_windowing = true
        var mm = event as InputEventMouseMotion
        var delta = mm.position - drag_start_pos
        
        var new_window = drag_start_window + delta.x * 2.0
        var new_level = drag_start_level - delta.y * 2.0
        
        window_slider.value = clamp(new_window, window_slider.min_value, window_slider.max_value)
        level_slider.value = clamp(new_level, level_slider.min_value, level_slider.max_value)

func add_arrow_to_current_image(start: Vector2, end: Vector2) -> void:
    # Only add if arrow has meaningful length
    if start.distance_to(end) < 10.0:
        return
    
    if not annotations_per_image.has(current_image_index):
        annotations_per_image[current_image_index] = []
    
    annotations_per_image[current_image_index].append({
        "type": "arrow",
        "start": start,
        "end": end
    })
    annotation_overlay.queue_redraw()

func add_circle_to_current_image(center: Vector2, radius: float) -> void:
    # Only add if circle has meaningful radius
    if radius < 10.0:
        return
    
    if not annotations_per_image.has(current_image_index):
        annotations_per_image[current_image_index] = []
    
    annotations_per_image[current_image_index].append({
        "type": "circle",
        "center": center,
        "radius": radius
    })
    annotation_overlay.queue_redraw()

func select_annotation_at_position(pos: Vector2) -> void:
    var annotations = annotations_per_image.get(current_image_index, [])
    var selection_threshold = 15.0
    
    for i in range(annotations.size()):
        var annotation = annotations[i]
        
        # Denormalize annotation coordinates if needed
        var denorm_annotation = denormalize_annotation(annotation)
        
        var is_near = false
        
        if denorm_annotation["type"] == "arrow":
            # Check if click is near the arrow line
            is_near = point_to_line_distance(pos, denorm_annotation["start"], denorm_annotation["end"]) < selection_threshold
        elif denorm_annotation["type"] == "circle":
            # Check if click is near the circle outline
            var distance_from_center = pos.distance_to(denorm_annotation["center"])
            is_near = abs(distance_from_center - denorm_annotation["radius"]) < selection_threshold
        
        if is_near:
            selected_annotation_index = i
            annotation_overlay.queue_redraw()
            return
    
    # No annotation selected
    if selected_annotation_index >= 0:
        selected_annotation_index = -1
        annotation_overlay.queue_redraw()

func point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
    var line_vec = line_end - line_start
    var point_vec = point - line_start
    var line_len = line_vec.length()
    
    if line_len == 0:
        return point.distance_to(line_start)
    
    var t = clamp(point_vec.dot(line_vec) / (line_len * line_len), 0.0, 1.0)
    var projection = line_start + t * line_vec
    return point.distance_to(projection)

func delete_selected_annotation() -> void:
    if selected_annotation_index < 0:
        return
    
    var annotations = annotations_per_image.get(current_image_index, [])
    if selected_annotation_index < annotations.size():
        annotations.remove_at(selected_annotation_index)
        selected_annotation_index = -1
        annotation_overlay.queue_redraw()

# Helper function to denormalize annotation coordinates
# Converts normalized coordinates (0-1 range) back to screen space
func denormalize_annotation(annotation: Dictionary) -> Dictionary:
    # If annotation already has non-normalized coordinates, return as-is (backward compatibility)
    if annotation.has("start") or annotation.has("center"):
        return annotation
    
    # Get viewer size for coordinate conversion
    var viewer_size = dicom_viewer.size
    
    var denormalized = annotation.duplicate(true)
    
    if annotation["type"] == "arrow" and annotation.has("start_normalized") and annotation.has("end_normalized"):
        denormalized["start"] = Vector2(
            annotation["start_normalized"].x * viewer_size.x,
            annotation["start_normalized"].y * viewer_size.y
        )
        denormalized["end"] = Vector2(
            annotation["end_normalized"].x * viewer_size.x,
            annotation["end_normalized"].y * viewer_size.y
        )
    elif annotation["type"] == "circle" and annotation.has("center_normalized") and annotation.has("radius_normalized"):
        var avg_size = (viewer_size.x + viewer_size.y) / 2.0
        denormalized["center"] = Vector2(
            annotation["center_normalized"].x * viewer_size.x,
            annotation["center_normalized"].y * viewer_size.y
        )
        denormalized["radius"] = annotation["radius_normalized"] * avg_size
    
    return denormalized

func validate_target_annotation(user_annotation: Dictionary, target_annotation: Dictionary, tolerance: float) -> bool:
    # Denormalize both annotations to screen space for comparison
    var user_denorm = denormalize_annotation(user_annotation)
    var target_denorm = denormalize_annotation(target_annotation)
    
    if user_denorm["type"] != target_denorm["type"]:
        return false  # Must use same annotation type
    
    if user_denorm["type"] == "circle":
        # Check if user's circle center is close to target circle center
        var user_center = user_denorm["center"]
        var user_radius = user_denorm["radius"]
        var target_center = target_denorm["center"]
        var target_radius = target_denorm["radius"]
        
        var center_distance = user_center.distance_to(target_center)
        var radius_difference = abs(user_radius - target_radius)
        
        # Both the center must be within tolerance AND radius should be similar
        # Check if center is within tolerance and radius is within 50% of target radius or within tolerance
        return center_distance < tolerance and (radius_difference < tolerance or radius_difference < target_radius * 0.5)
        
    elif user_denorm["type"] == "arrow":
        # Check if user's arrow points to similar area as target arrow
        # The most important thing is that the arrowhead (endpoint) is in the right location
        var user_end = user_denorm["end"]
        var target_end = target_denorm["end"]
        
        # Check endpoint distance - this is where the arrow is pointing
        var end_distance = user_end.distance_to(target_end)
        
        # The arrowhead must be within tolerance
        # Direction doesn't matter as much - what matters is WHERE the arrow points to
        return end_distance < tolerance
    
    return false

func _on_arrow_annotation_button_toggled(button_pressed: bool) -> void:
    if button_pressed:
        annotation_mode_active = true
        annotation_type = "arrow"
        # Disable other modes
        zoom_mode_active = false
        zoom_mode_button.button_pressed = false
        circle_annotation_button.button_pressed = false
        dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_CROSS
    else:
        if not circle_annotation_button.button_pressed:
            annotation_mode_active = false
            annotation_type = ""
            # Cancel drawing if in progress
            is_drawing_arrow = false
            selected_annotation_index = -1
            annotation_overlay.queue_redraw()
            dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_circle_annotation_button_toggled(button_pressed: bool) -> void:
    if button_pressed:
        annotation_mode_active = true
        annotation_type = "circle"
        # Disable other modes
        zoom_mode_active = false
        zoom_mode_button.button_pressed = false
        arrow_annotation_button.button_pressed = false
        dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_CROSS
    else:
        if not arrow_annotation_button.button_pressed:
            annotation_mode_active = false
            annotation_type = ""
            # Cancel drawing if in progress
            is_drawing_circle = false
            selected_annotation_index = -1
            annotation_overlay.queue_redraw()
            dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_UP, KEY_W:
                _on_prev_image_button_pressed()
            KEY_DOWN, KEY_S:
                _on_next_image_button_pressed()
            KEY_R:
                _on_reset_button_pressed()
            KEY_Z:
                zoom_mode_button.button_pressed = not zoom_mode_button.button_pressed
            KEY_A:
                arrow_annotation_button.button_pressed = not arrow_annotation_button.button_pressed
            KEY_C:
                circle_annotation_button.button_pressed = not circle_annotation_button.button_pressed
            KEY_DELETE, KEY_BACKSPACE:
                if annotation_mode_active:
                    delete_selected_annotation()
            KEY_1:
                _on_soft_tissue_button_pressed()
            KEY_2:
                _on_lung_button_pressed()
            KEY_3:
                _on_bone_button_pressed()
            KEY_4:
                _on_brain_button_pressed()
            KEY_5:
                _on_t2_brain_button_pressed()
            KEY_6:
                _on_mammo_button_pressed()
            KEY_0:
                _on_auto_button_pressed()

func show_completion() -> void:
    question_label.text = "Case Complete!"
    answer_edit.visible = false
    submit_button.visible = false
    next_question_button.visible = false
    explanation_container.visible = false
    
    for btn in mc_buttons:
        btn.queue_free()
    mc_buttons.clear()
    
    var summary = "Review Summary:\n\n"
    var mc_score = 0
    var mc_total = 0
    var sr_score = 0
    var sr_total = 0
    
    for i in range(user_answers.size()):
        var answer_data = user_answers[i]
        summary += "Q%d: %s\n" % [i + 1, answer_data["question"]]
        
        if answer_data["type"] == "systematic_review":
            sr_total += 1
            if answer_data.get("is_correct", false):
                summary += "✓ All findings correct\n\n"
                sr_score += 1
            else:
                summary += "Partially correct - See details above\n"
                summary += "Expected:\n%s\n" % answer_data["expected_answer"]
        else:
            summary += "Your Answer: %s\n" % answer_data["user_answer"]
            
            if answer_data["type"] == "multiple_choice":
                mc_total += 1
                if answer_data.get("is_correct", false):
                    summary += "✓ Correct!\n\n"
                    mc_score += 1
                else:
                    summary += "✗ Incorrect - Correct Answer: %s\n\n" % answer_data["expected_answer"]
            else:
                summary += "Expected: %s\n\n" % answer_data["expected_answer"]
    
    if mc_total > 0:
        summary += "\nMultiple Choice Score: %d / %d (%.1f%%)" % [mc_score, mc_total, (float(mc_score) / mc_total) * 100.0]
    
    if sr_total > 0:
        summary += "\nSystematic Review Score: %d / %d (%.1f%%)" % [sr_score, sr_total, (float(sr_score) / sr_total) * 100.0]
    
    feedback_label.text = summary

func _on_back_to_menu_button_pressed() -> void:
    queue_free()
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")