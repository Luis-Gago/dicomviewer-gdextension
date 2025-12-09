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
@onready var zoom_mode_button: Button = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ViewControls/ZoomModeButton
@onready var reset_view_button: Button = $HSplitContainer/LeftPanel/VSplitContainer/TopSection/ViewControls/ResetViewButton
@onready var notes_text: TextEdit = $HSplitContainer/LeftPanel/VSplitContainer/NotesPanel/NotesEdit

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

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    set_process_unhandled_input(true)
    
    dicom_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
    mc_button_group = ButtonGroup.new()
    
    setup_dicom_controls()
    
    # Hide explanation container initially
    explanation_container.visible = false
    
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
    if not reset_view_button.pressed.is_connected(_on_reset_button_pressed):
        reset_view_button.pressed.connect(_on_reset_button_pressed)
    if not dicom_viewer.gui_input.is_connected(_on_dicom_viewer_gui_input):
        dicom_viewer.gui_input.connect(_on_dicom_viewer_gui_input)
    
    update_windowing_labels()

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
    if current_image_index >= 0 and current_image_index < dicom_files.size():
        var success = dicom_viewer.load_dicom(dicom_files[current_image_index])
        
        if success:
            image_index_label.text = "Image %d / %d" % [current_image_index + 1, dicom_files.size()]
            
            if is_zoomed_in:
                dicom_viewer.reset_view()
                is_zoomed_in = false
            
            if not user_adjusted_windowing:
                window_slider.set_block_signals(true)
                level_slider.set_block_signals(true)
                window_slider.value = dicom_viewer.get_window()
                level_slider.value = dicom_viewer.get_level()
                window_slider.set_block_signals(false)
                level_slider.set_block_signals(false)
                update_windowing_labels()
            else:
                dicom_viewer.set_window_level(window_slider.value, level_slider.value)
        else:
            push_error("Failed to load DICOM: " + dicom_files[current_image_index])

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
    
    # Hide explanation container
    explanation_container.visible = false
    clear_explanation()
    
    # Setup answer UI based on question type
    if question_type == "multiple_choice":
        setup_multiple_choice_ui(question_dict)
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

func update_progress() -> void:
    var total = current_case.get_questions().size()
    progress_label.text = "Question %d / %d" % [current_question_index + 1, total]

func update_windowing_labels() -> void:
    window_label.text = "Window: %.0f" % window_slider.value
    level_label.text = "Level: %.0f" % level_slider.value

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
    else:
        user_answer = answer_edit.text.strip_edges()
        expected_answer = current_question.get("expected_answer", "")
        feedback_label.text = "Expected Answer:\n\n%s" % expected_answer
    
    user_answers.append({
        "question": current_question.get("question", ""),
        "user_answer": user_answer,
        "expected_answer": expected_answer,
        "type": question_type,
        "is_correct": is_correct if question_type == "multiple_choice" else null
    })
    
    # Show explanation if available
    show_explanation(current_question_index)
    
    submit_button.disabled = true
    next_question_button.disabled = false
    
func show_explanation(question_index: int) -> void:
    print("=== show_explanation called ===")
    print("Question index: ", question_index)
    print("Has explanation: ", current_case.has_explanation(question_index))
    
    if not current_case.has_explanation(question_index):
        print("No explanation available")
        explanation_container.visible = false
        return
    
    var explanation = current_case.get_question_explanation(question_index)
    print("Explanation dictionary: ", explanation)
    
    var explanation_text = explanation.get("text", "")
    var explanation_images = explanation.get("images", [])
    
    print("Explanation text: ", explanation_text)
    print("Explanation images: ", explanation_images)
    
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
        print("Added text label to explanation_content")
    
    # Add explanation images
    for image_path in explanation_images:
        print("Processing image: ", image_path)
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
                print("Added image to explanation_content")
            else:
                push_error("Failed to load explanation image: " + image_path)
        else:
            push_error("Explanation image not found: " + image_path)
    
    # Show the explanation container and force update
    explanation_container.visible = true
    explanation_container.show()
    explanation_scroll.visible = true
    explanation_scroll.show()
    
    # Force multiple layout updates
    call_deferred("_force_layout_update")

func _force_layout_update() -> void:
    explanation_container.queue_sort()
    explanation_scroll.queue_sort()
    explanation_content.queue_sort()
    
    await get_tree().process_frame
    await get_tree().process_frame
    
    print("Final explanation_container size: ", explanation_container.size)
    print("Final explanation_scroll size: ", explanation_scroll.size)
    print("Final explanation_content size: ", explanation_content.size)
    print("explanation_content children: ", explanation_content.get_child_count())

func clear_explanation() -> void:
    for child in explanation_content.get_children():
        child.queue_free()

func _on_next_question_button_pressed() -> void:
    current_question_index += 1
    display_current_question()

func _on_prev_image_button_pressed() -> void:
    if current_image_index > 0:
        current_image_index -= 1
        load_current_image()

func _on_next_image_button_pressed() -> void:
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
            KEY_1:
                _on_soft_tissue_button_pressed()
            KEY_2:
                _on_lung_button_pressed()
            KEY_3:
                _on_bone_button_pressed()

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
    
    for i in range(user_answers.size()):
        var answer_data = user_answers[i]
        summary += "Q%d: %s\n" % [i + 1, answer_data["question"]]
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
    
    feedback_label.text = summary

func _on_back_to_menu_button_pressed() -> void:
    queue_free()
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")