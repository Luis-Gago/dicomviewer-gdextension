extends Control

@onready var dicom_viewer: DicomViewer = $HSplitContainer/LeftPanel/DicomViewer
@onready var question_label: Label = $HSplitContainer/RightPanel/QuestionLabel
@onready var answer_edit: TextEdit = $HSplitContainer/RightPanel/AnswerEdit
@onready var submit_button: Button = $HSplitContainer/RightPanel/SubmitButton
@onready var next_question_button: Button = $HSplitContainer/RightPanel/NextQuestionButton
@onready var feedback_label: Label = $HSplitContainer/RightPanel/FeedbackLabel
@onready var progress_label: Label = $HSplitContainer/RightPanel/ProgressLabel
@onready var image_index_label: Label = $HSplitContainer/LeftPanel/ImageControls/ImageIndexLabel

var case_path: String = ""
var current_case: RadiologyCase
var current_question_index: int = 0
var current_image_index: int = 0
var dicom_files: Array = []
var user_answers: Array = []

func _ready() -> void:
    if case_path != "":
        load_case(case_path)

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
        dicom_viewer.load_dicom(dicom_files[current_image_index])
        image_index_label.text = "Image %d / %d" % [current_image_index + 1, dicom_files.size()]

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

func _on_prev_image_button_pressed() -> void:
    if current_image_index > 0:
        current_image_index -= 1
        load_current_image()

func _on_next_image_button_pressed() -> void:
    if current_image_index < dicom_files.size() - 1:
        current_image_index += 1
        load_current_image()

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