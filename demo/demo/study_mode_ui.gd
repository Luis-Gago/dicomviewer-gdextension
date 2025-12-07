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
    
    # Ensure DicomViewer can receive mouse input
    dicom_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
    
    setup_dicom_controls()
    
    if case_path != "":
        load_case(case_path)

func setup_dicom_controls() -> void:
    # Window slider setup
    window_slider.min_value = 1.0
    window_slider.max_value = 4000.0
    window_slider.value = 400.0
    window_slider.step = 1.0
    
    # Level slider setup
    level_slider.min_value = -1000.0
    level_slider.max_value = 3000.0
    level_slider.value = 40.0
    level_slider.step = 1.0
    
    # Connect signals only if not already connected
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
            
            # Reset zoom when loading new file
            if is_zoomed_in:
                dicom_viewer.reset_view()
                is_zoomed_in = false
            
            # Update sliders if user hasn't manually adjusted windowing
            if not user_adjusted_windowing:
                window_slider.set_block_signals(true)
                level_slider.set_block_signals(true)
                window_slider.value = dicom_viewer.get_window()
                level_slider.value = dicom_viewer.get_level()
                window_slider.set_block_signals(false)
                level_slider.set_block_signals(false)
                update_windowing_labels()
            else:
                # Apply user's preferred window/level
                dicom_viewer.set_window_level(window_slider.value, level_slider.value)
        else:
            push_error("Failed to load DICOM: " + dicom_files[current_image_index])

func display_current_question() -> void:
    var questions = current_case.get_questions()
    if current_question_index >= questions.size():
        show_completion()
        return
    
    var question_dict = questions[current_question_index]
    question_label.text = "Organ System: %s\n\nQuestion: %s" % [
        question_dict.get("organ_system", "Unknown"),
        question_dict.get("question", "")
    ]
    
    # Navigate to reference image if specified
    var ref_index = question_dict.get("image_index", -1)
    if ref_index >= 0 and ref_index < dicom_files.size():
        current_image_index = ref_index
        load_current_image()
    
    answer_edit.text = ""
    feedback_label.text = "Answer the question above"
    submit_button.disabled = false
    next_question_button.disabled = true
    
    update_progress()

func update_progress() -> void:
    var total = current_case.get_questions().size()
    progress_label.text = "Question %d / %d" % [current_question_index + 1, total]

func update_windowing_labels() -> void:
    window_label.text = "Window: %.0f" % window_slider.value
    level_label.text = "Level: %.0f" % level_slider.value

# Question/Answer handling
func _on_submit_button_pressed() -> void:
    var user_answer = answer_edit.text.strip_edges()
    var questions = current_case.get_questions()
    var current_question = questions[current_question_index]
    var expected_answer = current_question.get("expected_answer", "")
    
    user_answers.append({
        "question": current_question.get("question", ""),
        "user_answer": user_answer,
        "expected_answer": expected_answer
    })
    
    feedback_label.text = "Expected Answer:\n\n%s" % expected_answer
    
    submit_button.disabled = true
    next_question_button.disabled = false

func _on_next_question_button_pressed() -> void:
    current_question_index += 1
    display_current_question()

# Image navigation
func _on_prev_image_button_pressed() -> void:
    if current_image_index > 0:
        current_image_index -= 1
        load_current_image()

func _on_next_image_button_pressed() -> void:
    if current_image_index < dicom_files.size() - 1:
        current_image_index += 1
        load_current_image()

# DICOM viewer controls
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

# Windowing preset buttons
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

# Mouse input handling
func _on_dicom_viewer_gui_input(event: InputEvent) -> void:
    # Handle pan gesture events (macOS trackpad)
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
        
        # Zoom mode clicks
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
        
        # Mouse wheel for image navigation
        if not zoom_mode_active:
            if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
                _on_prev_image_button_pressed()
                get_viewport().set_input_as_handled()
                return
            elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
                _on_next_image_button_pressed()
                get_viewport().set_input_as_handled()
                return
        
        # Left mouse drag for window/level adjustment
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

# Keyboard shortcuts
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
    
    var summary = "Review Summary:\n\n"
    for i in range(user_answers.size()):
        summary += "Q%d: %s\n" % [i + 1, user_answers[i]["question"]]
        summary += "Your Answer: %s\n" % user_answers[i]["user_answer"]
        summary += "Expected: %s\n\n" % user_answers[i]["expected_answer"]
    
    feedback_label.text = summary

func _on_back_to_menu_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")