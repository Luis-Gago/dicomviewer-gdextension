extends Control

@onready var case_name_edit: LineEdit = $MarginContainer/VBoxContainer/CaseNameEdit
@onready var case_description_edit: TextEdit = $MarginContainer/VBoxContainer/CaseDescriptionEdit
@onready var questions_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/QuestionsContainer
@onready var file_dialog: FileDialog = $FileDialog
@onready var folder_dialog: FileDialog = $FolderDialog
@onready var dicom_status: Label = $MarginContainer/VBoxContainer/DicomStatus
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var warning_dialog: AcceptDialog = $WarningDialog

var explanation_image_dialog: FileDialog
var annotation_editor_popup: Window
var annotation_viewer: DicomViewer
var annotation_overlay: Control
var annotation_current_image_index: int = 0
var annotation_mode: String = ""  # "arrow" or "circle"
var is_drawing_annotation: bool = false
var temp_annotation_start: Vector2 = Vector2.ZERO
var temp_annotation_end: Vector2 = Vector2.ZERO
var temp_circle_center: Vector2 = Vector2.ZERO
var temp_circle_radius: float = 0.0
var current_annotation_panel: PanelContainer = null
var pan_gesture_accumulator: float = 0.0
var pan_gesture_threshold: float = 1.0
var annotation_window: float = 400.0
var annotation_level: float = 40.0
var annotation_windowing_set: bool = false

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
	var organ_system = question_dict.get("organ_system", "General")
	for i in range(organ_dropdown.item_count):
		if organ_dropdown.get_item_text(i) == organ_system:
			organ_dropdown.selected = i
			break
	
	# Set question type
	var type_dropdown = vbox.get_child(3) as OptionButton
	var question_type = question_dict.get("type", "free_text")
	match question_type:
		"free_text":
			type_dropdown.selected = 0
		"multiple_choice":
			type_dropdown.selected = 1
		"systematic_review":
			type_dropdown.selected = 2
		"mark_target":
			type_dropdown.selected = 3
	
	# Set question text
	var question_edit = vbox.get_child(5) as LineEdit
	question_edit.text = question_dict.get("question", "")
	
	# Set answer based on type
	if question_type == "free_text":
		var answer_edit = vbox.get_child(7) as TextEdit
		answer_edit.text = question_dict.get("expected_answer", "")
	elif question_type == "multiple_choice":
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
	elif question_type == "systematic_review":
		# Trigger the visibility change for systematic review
		type_dropdown.item_selected.emit(2)
		
		var systematic_container = vbox.get_child(9) as VBoxContainer
		var systems_list = systematic_container.get_child(1) as VBoxContainer
		var organ_systems_findings = question_dict.get("organ_systems_findings", [])
		
		# Populate organ systems
		for finding_dict in organ_systems_findings:
			var organ_name = finding_dict.get("organ_system", "")
			var finding_type = finding_dict.get("finding_type", "no-finding")
			_add_organ_system_item(systems_list, organ_name, finding_type)
	elif question_type == "mark_target":
		# Trigger the visibility change for mark target
		type_dropdown.item_selected.emit(3)
		
		var target_container = vbox.get_node("TargetAreaContainer") as VBoxContainer
		
		if target_container == null:
			push_error("Target container not found. VBox has %d children." % vbox.get_child_count())
			return
		
		# Set target annotation data if exists
		if question_dict.has("target_annotation"):
			panel.set_meta("target_annotation", question_dict["target_annotation"])
			var target_status = target_container.get_child(3) as Label
			if target_status:
				var annotation_type = question_dict["target_annotation"].get("type", "unknown")
				target_status.text = "✓ Target area set (%s)" % annotation_type
				target_status.add_theme_color_override("font_color", Color.GREEN)
		
		# Set tolerance
		var tolerance = question_dict.get("tolerance", 50.0)
		var tolerance_slider = target_container.get_node("ToleranceSlider") as HSlider
		if tolerance_slider:
			tolerance_slider.value = tolerance
		else:
			push_error("Tolerance slider not found. Target container has %d children." % target_container.get_child_count())
	
	# Set image index
	var image_ref_spin = vbox.get_node("ImageRefSpin") as SpinBox
	if image_ref_spin:
		image_ref_spin.value = question_dict.get("image_index", 0)
	
	# Set explanation text
	var explanation_container = vbox.get_node("ExplanationContainer") as VBoxContainer
	if not explanation_container:
		return
		
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
	
	# Ensure spacing is applied
	questions_container.add_theme_constant_override("separation", 20)
	
	# Ensure spacing is applied
	questions_container.add_theme_constant_override("separation", 20)

func create_question_panel() -> PanelContainer:
	var panel = PanelContainer.new()
	
	# Add visual styling to distinguish questions
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.15, 0.15, 0.18, 1.0)  # Slightly lighter background
	style_box.border_color = Color(0.4, 0.4, 0.5, 1.0)  # Border color
	style_box.set_border_width_all(2)
	style_box.set_corner_radius_all(8)
	style_box.content_margin_left = 15
	style_box.content_margin_right = 15
	style_box.content_margin_top = 15
	style_box.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style_box)
	
	# Add margin for spacing between questions
	panel.custom_minimum_size = Vector2(0, 0)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# Radiology subspecialty
	var organ_label = Label.new()
	organ_label.text = "Radiology Subspecialty:"
	organ_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(organ_label)
	
	var organ_dropdown = OptionButton.new()
	organ_dropdown.name = "OrganDropdown"
	organ_dropdown.add_theme_font_size_override("font_size", 22)
	organ_dropdown.add_item("General")
	organ_dropdown.add_item("Chest/Thoracic")
	organ_dropdown.add_item("Body/Abdominal")
	organ_dropdown.add_item("Neuroradiology")
	organ_dropdown.add_item("Musculoskeletal")
	organ_dropdown.add_item("Pediatric")
	organ_dropdown.add_item("Breast")
	organ_dropdown.add_item("Nuclear Medicine")
	organ_dropdown.add_item("Emergency Radiology")
	organ_dropdown.add_item("Other")
	var organ_popup = organ_dropdown.get_popup()
	organ_popup.add_theme_font_size_override("font_size", 22)
	vbox.add_child(organ_dropdown)
	
	# Question type
	var type_label = Label.new()
	type_label.text = "Question Type:"
	type_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(type_label)
	
	var type_dropdown = OptionButton.new()
	type_dropdown.name = "TypeDropdown"
	type_dropdown.add_theme_font_size_override("font_size", 22)
	type_dropdown.add_item("Free Text")
	type_dropdown.add_item("Multiple Choice")
	type_dropdown.add_item("Systematic Review")
	type_dropdown.add_item("Mark Target Area")
	type_dropdown.selected = 0
	var type_popup = type_dropdown.get_popup()
	type_popup.add_theme_font_size_override("font_size", 22)
	vbox.add_child(type_dropdown)
	
	# Question
	var question_label = Label.new()
	question_label.text = "Question:"
	question_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(question_label)
	
	var question_edit = LineEdit.new()
	question_edit.name = "QuestionEdit"
	question_edit.custom_minimum_size = Vector2(0, 48)
	question_edit.add_theme_font_size_override("font_size", 22)
	question_edit.placeholder_text = "Question Text Here"
	vbox.add_child(question_edit)
	
	# Free text answer (initially visible)
	var answer_label = Label.new()
	answer_label.text = "Expected Answer:"
	answer_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(answer_label)
	
	var answer_edit = TextEdit.new()
	answer_edit.name = "AnswerEdit"
	answer_edit.custom_minimum_size = Vector2(0, 125)
	answer_edit.add_theme_font_size_override("font_size", 22)
	answer_edit.placeholder_text = "Expected Answer Text Here"
	vbox.add_child(answer_edit)
	
	# Multiple choice container (initially hidden)
	var mc_container = VBoxContainer.new()
	mc_container.name = "MCContainer"
	mc_container.visible = false
	vbox.add_child(mc_container)
	
	var mc_label = Label.new()
	mc_label.text = "Multiple Choice Options:"
	mc_label.add_theme_font_size_override("font_size", 22)
	mc_container.add_child(mc_label)
	
	var choices_container = VBoxContainer.new()
	mc_container.add_child(choices_container)
	
	# Add 4 default choices
	for i in range(4):
		var choice_hbox = HBoxContainer.new()
		choices_container.add_child(choice_hbox)
		
		var choice_radio = CheckBox.new()
		choice_radio.text = "Correct"
		choice_radio.add_theme_font_size_override("font_size", 22)
		choice_radio.button_group = ButtonGroup.new() if i == 0 else choices_container.get_child(0).get_child(0).button_group
		choice_hbox.add_child(choice_radio)
		
		var choice_edit = LineEdit.new()
		choice_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice_edit.custom_minimum_size = Vector2(0, 48)
		choice_edit.add_theme_font_size_override("font_size", 22)
		choice_edit.placeholder_text = "Option %d" % (i + 1)
		choice_hbox.add_child(choice_edit)
	
	# Systematic review container (initially hidden)
	var systematic_container = VBoxContainer.new()
	systematic_container.name = "SystematicContainer"
	systematic_container.visible = false
	vbox.add_child(systematic_container)
	
	var systematic_label = Label.new()
	systematic_label.text = "Organ Systems to Review:"
	systematic_label.add_theme_font_size_override("font_size", 22)
	systematic_container.add_child(systematic_label)
	
	var systems_list_container = VBoxContainer.new()
	systems_list_container.add_theme_constant_override("separation", 5)
	systematic_container.add_child(systems_list_container)
	
	var add_system_btn = Button.new()
	add_system_btn.text = "Add Organ System"
	add_system_btn.custom_minimum_size = Vector2(0, 48)
	add_system_btn.add_theme_font_size_override("font_size", 22)
	add_system_btn.pressed.connect(func(): _add_organ_system_item(systems_list_container))
	systematic_container.add_child(add_system_btn)
	
	# Target Area container (initially hidden) - NEW
	var target_area_container = VBoxContainer.new()
	target_area_container.name = "TargetAreaContainer"
	target_area_container.visible = false
	vbox.add_child(target_area_container)
	
	var target_area_label = Label.new()
	target_area_label.text = "Target Area Annotation:"
	target_area_label.add_theme_font_size_override("font_size", 22)
	target_area_container.add_child(target_area_label)
	
	var target_instruction = Label.new()
	target_instruction.text = "Instructions:\n1. Ensure DICOM files are loaded\n2. Click 'Open Annotation Editor' to view images and draw annotation\n3. Draw a circle or arrow on the target area\n4. Click 'Save Annotation' to capture it"
	target_instruction.add_theme_font_size_override("font_size", 16)
	target_area_container.add_child(target_instruction)
	
	var set_target_btn = Button.new()
	set_target_btn.text = "Open Annotation Editor"
	set_target_btn.custom_minimum_size = Vector2(0, 48)
	set_target_btn.add_theme_font_size_override("font_size", 22)
	set_target_btn.pressed.connect(func(): _open_annotation_editor(panel))
	target_area_container.add_child(set_target_btn)
	
	var target_status = Label.new()
	target_status.text = "No target area set - Please use annotation tools"
	target_status.add_theme_font_size_override("font_size", 22)
	target_status.add_theme_color_override("font_color", Color.ORANGE)
	target_area_container.add_child(target_status)
	
	# Tolerance slider
	var tolerance_label = Label.new()
	tolerance_label.text = "Acceptance Tolerance (pixels):"
	tolerance_label.add_theme_font_size_override("font_size", 22)
	target_area_container.add_child(tolerance_label)
	
	var tolerance_slider = HSlider.new()
	tolerance_slider.name = "ToleranceSlider"
	tolerance_slider.min_value = 10.0
	tolerance_slider.max_value = 200.0
	tolerance_slider.value = 50.0
	tolerance_slider.step = 5.0
	tolerance_slider.custom_minimum_size = Vector2(0, 48)
	target_area_container.add_child(tolerance_slider)
	
	var tolerance_value_label = Label.new()
	tolerance_value_label.text = "50 pixels"
	tolerance_value_label.add_theme_font_size_override("font_size", 22)
	target_area_container.add_child(tolerance_value_label)
	
	tolerance_slider.value_changed.connect(func(value: float):
		tolerance_value_label.text = "%.0f pixels" % value
	)
	
	# Image index
	var image_ref_label = Label.new()
	image_ref_label.text = "Reference Image Index (optional):"
	image_ref_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(image_ref_label)
	
	var image_ref_spin = SpinBox.new()
	image_ref_spin.name = "ImageRefSpin"
	image_ref_spin.min_value = 0
	image_ref_spin.max_value = 999
	image_ref_spin.custom_minimum_size = Vector2(0, 48)
	image_ref_spin.add_theme_font_size_override("font_size", 22)
	vbox.add_child(image_ref_spin)
	
	# Explanation section
	var explanation_container = VBoxContainer.new()
	explanation_container.name = "ExplanationContainer"
	explanation_container.add_theme_constant_override("separation", 5)
	vbox.add_child(explanation_container)
	
	var explanation_label = Label.new()
	explanation_label.text = "Extended Explanation (shown after answer):"
	explanation_label.add_theme_font_size_override("font_size", 22)
	explanation_container.add_child(explanation_label)
	
	var explanation_edit = TextEdit.new()
	explanation_edit.custom_minimum_size = Vector2(0, 156)
	explanation_edit.add_theme_font_size_override("font_size", 22)
	explanation_edit.placeholder_text = "Provide detailed explanation of the correct answer..."
	explanation_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	explanation_container.add_child(explanation_edit)
	
	var explanation_images_label = Label.new()
	explanation_images_label.text = "Explanation Images:"
	explanation_images_label.add_theme_font_size_override("font_size", 22)
	explanation_container.add_child(explanation_images_label)
	
	var images_list_container = VBoxContainer.new()
	images_list_container.add_theme_constant_override("separation", 5)
	explanation_container.add_child(images_list_container)
	
	var add_image_btn = Button.new()
	add_image_btn.text = "Add Explanation Image"
	add_image_btn.custom_minimum_size = Vector2(0, 48)
	add_image_btn.add_theme_font_size_override("font_size", 22)
	add_image_btn.pressed.connect(func(): _on_add_explanation_image_pressed(panel))
	explanation_container.add_child(add_image_btn)
	
	# Remove button
	var remove_btn = Button.new()
	remove_btn.text = "Remove Question"
	remove_btn.custom_minimum_size = Vector2(0, 48)
	remove_btn.add_theme_font_size_override("font_size", 22)
	remove_btn.pressed.connect(func(): panel.queue_free())
	vbox.add_child(remove_btn)
	
	# Connect type dropdown to toggle visibility
	type_dropdown.item_selected.connect(func(index: int):
		var is_free_text = index == 0
		var is_multiple_choice = index == 1
		var is_systematic_review = index == 2
		var is_target_area = index == 3
		
		answer_label.visible = is_free_text
		answer_edit.visible = is_free_text
		mc_container.visible = is_multiple_choice
		systematic_container.visible = is_systematic_review
		target_area_container.visible = is_target_area
	)
	
	return panel

func _open_annotation_editor(panel: PanelContainer) -> void:
	if dicom_files.size() == 0:
		var vbox = panel.get_child(0) as VBoxContainer
		var target_area_container = vbox.get_node("TargetAreaContainer") as VBoxContainer
		if target_area_container:
			var target_status = target_area_container.get_child(3) as Label
			if target_status:
				target_status.text = "⚠ Please load DICOM files first"
				target_status.add_theme_color_override("font_color", Color.RED)
		return
	
	current_annotation_panel = panel
	annotation_current_image_index = 0
	annotation_mode = ""
	is_drawing_annotation = false
	annotation_windowing_set = false
	
	# Create annotation editor popup if it doesn't exist
	if annotation_editor_popup == null:
		_create_annotation_editor_popup()
	
	# Load first DICOM image
	_load_annotation_image(0)
	
	# Show popup
	annotation_editor_popup.popup_centered(Vector2i(1200, 800))

func _create_annotation_editor_popup() -> void:
	annotation_editor_popup = Window.new()
	annotation_editor_popup.title = "Annotation Editor"
	annotation_editor_popup.size = Vector2i(1200, 800)
	annotation_editor_popup.wrap_controls = true
	add_child(annotation_editor_popup)
	
	var main_container = VBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	annotation_editor_popup.add_child(main_container)
	
	# Title
	var title = Label.new()
	title.text = "Draw annotation on target area"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	main_container.add_child(title)
	
	# DICOM Viewer
	annotation_viewer = DicomViewer.new()
	annotation_viewer.custom_minimum_size = Vector2(800, 600)
	annotation_viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	annotation_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	main_container.add_child(annotation_viewer)
	
	# Setup annotation overlay
	annotation_overlay = Control.new()
	annotation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	annotation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	annotation_viewer.add_child(annotation_overlay)
	annotation_overlay.draw.connect(_on_annotation_overlay_draw)
	
	# Connect viewer input
	annotation_viewer.gui_input.connect(_on_annotation_viewer_input)
	
	# Windowing presets
	var preset_label = Label.new()
	preset_label.text = "Windowing Presets:"
	main_container.add_child(preset_label)
	
	var preset_container = HBoxContainer.new()
	main_container.add_child(preset_container)
	
	var soft_tissue_btn = Button.new()
	soft_tissue_btn.text = "Soft Tissue"
	soft_tissue_btn.pressed.connect(func(): 
		annotation_viewer.apply_soft_tissue_preset()
		annotation_window = 400.0
		annotation_level = 40.0
		annotation_windowing_set = true
	)
	preset_container.add_child(soft_tissue_btn)
	
	var lung_btn = Button.new()
	lung_btn.text = "Lung"
	lung_btn.pressed.connect(func(): 
		annotation_viewer.apply_lung_preset()
		annotation_window = 1500.0
		annotation_level = -600.0
		annotation_windowing_set = true
	)
	preset_container.add_child(lung_btn)
	
	var bone_btn = Button.new()
	bone_btn.text = "Bone"
	bone_btn.pressed.connect(func(): 
		annotation_viewer.apply_bone_preset()
		annotation_window = 1800.0
		annotation_level = 400.0
		annotation_windowing_set = true
	)
	preset_container.add_child(bone_btn)
	
	var brain_btn = Button.new()
	brain_btn.text = "Brain"
	brain_btn.pressed.connect(func(): 
		annotation_viewer.apply_brain_preset()
		annotation_window = 80.0
		annotation_level = 40.0
		annotation_windowing_set = true
	)
	preset_container.add_child(brain_btn)
	
	var t2_brain_btn = Button.new()
	t2_brain_btn.text = "T2 Brain"
	t2_brain_btn.pressed.connect(func(): 
		annotation_viewer.apply_t2_brain_preset()
		annotation_window = 160.0
		annotation_level = 80.0
		annotation_windowing_set = true
	)
	preset_container.add_child(t2_brain_btn)
	
	var mammo_btn = Button.new()
	mammo_btn.text = "Mammo"
	mammo_btn.pressed.connect(func(): 
		annotation_viewer.apply_mammography_preset()
		annotation_window = 4000.0
		annotation_level = 2000.0
		annotation_windowing_set = true
	)
	preset_container.add_child(mammo_btn)
	
	var auto_btn = Button.new()
	auto_btn.text = "Auto"
	auto_btn.pressed.connect(func(): 
		annotation_viewer.apply_auto_preset()
		annotation_windowing_set = false
	)
	preset_container.add_child(auto_btn)
	
	# Image navigation
	var nav_container = HBoxContainer.new()
	main_container.add_child(nav_container)
	
	var prev_btn = Button.new()
	prev_btn.text = "← Previous Image"
	prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_btn.pressed.connect(_on_annotation_prev_image)
	nav_container.add_child(prev_btn)
	
	var image_label = Label.new()
	image_label.name = "ImageIndexLabel"
	image_label.text = "Image 1 / 1"
	image_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	image_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_container.add_child(image_label)
	
	var next_btn = Button.new()
	next_btn.text = "Next Image →"
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.pressed.connect(_on_annotation_next_image)
	nav_container.add_child(next_btn)
	
	# Annotation tools
	var tools_container = HBoxContainer.new()
	main_container.add_child(tools_container)
	
	var arrow_btn = Button.new()
	arrow_btn.name = "ArrowButton"
	arrow_btn.text = "Draw Arrow"
	arrow_btn.toggle_mode = true
	arrow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrow_btn.toggled.connect(_on_arrow_annotation_toggled)
	tools_container.add_child(arrow_btn)
	
	var circle_btn = Button.new()
	circle_btn.name = "CircleButton"
	circle_btn.text = "Draw Circle"
	circle_btn.toggle_mode = true
	circle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	circle_btn.toggled.connect(_on_circle_annotation_toggled)
	tools_container.add_child(circle_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "Clear Annotation"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_on_clear_annotation)
	tools_container.add_child(clear_btn)
	
	# Action buttons
	var action_container = HBoxContainer.new()
	main_container.add_child(action_container)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): annotation_editor_popup.hide())
	action_container.add_child(cancel_btn)
	
	var save_btn = Button.new()
	save_btn.text = "Save Annotation"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save_annotation)
	action_container.add_child(save_btn)

func _load_annotation_image(index: int) -> void:
	if index < 0 or index >= dicom_files.size():
		return
	
	annotation_current_image_index = index
	
	if annotation_viewer:
		annotation_viewer.load_dicom(dicom_files[index])
		
		# Reapply windowing settings if user has set them
		if annotation_windowing_set:
			annotation_viewer.set_window_level(annotation_window, annotation_level)
		
		# Update image label
		var nav_container = annotation_editor_popup.get_child(0).get_child(4) as HBoxContainer
		if nav_container:
			var image_label = nav_container.get_node("ImageIndexLabel") as Label
			if image_label:
				image_label.text = "Image %d / %d" % [index + 1, dicom_files.size()]

func _on_annotation_prev_image() -> void:
	if annotation_current_image_index > 0:
		_load_annotation_image(annotation_current_image_index - 1)

func _on_annotation_next_image() -> void:
	if annotation_current_image_index < dicom_files.size() - 1:
		_load_annotation_image(annotation_current_image_index + 1)

func _on_arrow_annotation_toggled(pressed: bool) -> void:
	if pressed:
		annotation_mode = "arrow"
		# Uncheck circle button
		var tools_container = annotation_editor_popup.get_child(0).get_child(5) as HBoxContainer
		var circle_btn = tools_container.get_node("CircleButton") as Button
		circle_btn.button_pressed = false
	else:
		annotation_mode = ""

func _on_circle_annotation_toggled(pressed: bool) -> void:
	if pressed:
		annotation_mode = "circle"
		# Uncheck arrow button
		var tools_container = annotation_editor_popup.get_child(0).get_child(5) as HBoxContainer
		var arrow_btn = tools_container.get_node("ArrowButton") as Button
		arrow_btn.button_pressed = false
	else:
		annotation_mode = ""

func _on_clear_annotation() -> void:
	is_drawing_annotation = false
	temp_annotation_start = Vector2.ZERO
	temp_annotation_end = Vector2.ZERO
	temp_circle_center = Vector2.ZERO
	temp_circle_radius = 0.0
	if annotation_overlay:
		annotation_overlay.queue_redraw()

func _on_annotation_viewer_input(event: InputEvent) -> void:
	# Handle pan gestures for trackpad scrolling
	if event is InputEventPanGesture:
		var pg = event as InputEventPanGesture
		pan_gesture_accumulator += pg.delta.y
		
		if pan_gesture_accumulator <= -pan_gesture_threshold:
			_on_annotation_next_image()
			pan_gesture_accumulator = 0.0
		elif pan_gesture_accumulator >= pan_gesture_threshold:
			_on_annotation_prev_image()
			pan_gesture_accumulator = 0.0
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		# Handle mouse wheel scrolling
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_on_annotation_prev_image()
			return
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_on_annotation_next_image()
			return
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if annotation_mode == "arrow":
					is_drawing_annotation = true
					temp_annotation_start = mouse_event.position
					temp_annotation_end = mouse_event.position
				elif annotation_mode == "circle":
					is_drawing_annotation = true
					temp_circle_center = mouse_event.position
					temp_circle_radius = 0.0
			else:
				if is_drawing_annotation:
					is_drawing_annotation = false
					if annotation_overlay:
						annotation_overlay.queue_redraw()
	
	elif event is InputEventMouseMotion and is_drawing_annotation:
		var mouse_motion = event as InputEventMouseMotion
		
		if annotation_mode == "arrow":
			temp_annotation_end = mouse_motion.position
		elif annotation_mode == "circle":
			temp_circle_radius = temp_circle_center.distance_to(mouse_motion.position)
		
		if annotation_overlay:
			annotation_overlay.queue_redraw()

func _on_annotation_overlay_draw() -> void:
	if not annotation_overlay:
		return
	
	if annotation_mode == "arrow" and (is_drawing_annotation or temp_annotation_start != Vector2.ZERO):
		_draw_arrow_on_canvas(annotation_overlay, temp_annotation_start, temp_annotation_end, Color.YELLOW, 3.0)
	elif annotation_mode == "circle" and (is_drawing_annotation or temp_circle_radius > 0):
		annotation_overlay.draw_arc(temp_circle_center, temp_circle_radius, 0, TAU, 32, Color.YELLOW, 3.0)

func _draw_arrow_on_canvas(canvas: Control, start: Vector2, end: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(start, end, color, width)
	
	# Draw arrowhead
	var direction = (end - start).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	var arrow_size = 15.0
	
	var arrow_point1 = end - direction * arrow_size + perpendicular * (arrow_size * 0.5)
	var arrow_point2 = end - direction * arrow_size - perpendicular * (arrow_size * 0.5)
	
	canvas.draw_line(end, arrow_point1, color, width)
	canvas.draw_line(end, arrow_point2, color, width)

func _on_save_annotation() -> void:
	if current_annotation_panel == null:
		return
	
	# Get image dimensions for normalization
	var image_width = annotation_viewer.get_image_width()
	var image_height = annotation_viewer.get_image_height()
	
	if image_width <= 0 or image_height <= 0:
		push_error("Invalid image dimensions. Cannot save annotation.")
		return
	
	# Get the viewer size for coordinate conversion
	var viewer_size = annotation_viewer.size
	
	var annotation_data = {}
	
	if annotation_mode == "arrow" and temp_annotation_start != Vector2.ZERO and temp_annotation_end != Vector2.ZERO:
		# Normalize coordinates to 0-1 range relative to viewer size
		# This makes them independent of the viewer's display size
		annotation_data = {
			"type": "arrow",
			"start_normalized": Vector2(
				temp_annotation_start.x / viewer_size.x,
				temp_annotation_start.y / viewer_size.y
			),
			"end_normalized": Vector2(
				temp_annotation_end.x / viewer_size.x,
				temp_annotation_end.y / viewer_size.y
			),
			"image_index": annotation_current_image_index
		}
	elif annotation_mode == "circle" and temp_circle_radius > 0:
		# Normalize center position and radius
		# Radius is normalized by the average of width and height to be scale-independent
		var avg_size = (viewer_size.x + viewer_size.y) / 2.0
		annotation_data = {
			"type": "circle",
			"center_normalized": Vector2(
				temp_circle_center.x / viewer_size.x,
				temp_circle_center.y / viewer_size.y
			),
			"radius_normalized": temp_circle_radius / avg_size,
			"image_index": annotation_current_image_index
		}
	else:
		push_error("No annotation drawn. Please draw an arrow or circle.")
		return
	
	# Save to panel metadata
	current_annotation_panel.set_meta("target_annotation", annotation_data)
	
	# Update status label
	var vbox = current_annotation_panel.get_child(0) as VBoxContainer
	var target_area_container = vbox.get_node("TargetAreaContainer") as VBoxContainer
	if not target_area_container:
		return
		
	var target_status = target_area_container.get_child(3) as Label
	
	if target_status:
		var annotation_type = annotation_data.get("type", "unknown")
		var img_idx = annotation_data.get("image_index", 0)
		target_status.text = "✓ %s annotation set on image %d" % [annotation_type.capitalize(), img_idx + 1]
		target_status.add_theme_color_override("font_color", Color.GREEN)
	
	# Update image index spinner
	var image_ref_spin = vbox.get_node("ImageRefSpin") as SpinBox
	if image_ref_spin:
		image_ref_spin.value = annotation_current_image_index
	
	# Close popup
	annotation_editor_popup.hide()
	
	# Clear annotation state
	_on_clear_annotation()

func _on_add_explanation_image_pressed(panel: PanelContainer) -> void:
	explanation_image_dialog.set_meta("current_panel", panel)
	explanation_image_dialog.popup_centered(Vector2i(800, 600))

func _on_explanation_image_dialog_files_selected(paths: PackedStringArray) -> void:
	var panel = explanation_image_dialog.get_meta("current_panel") as PanelContainer
	if panel == null:
		return
	
	var vbox = panel.get_child(0) as VBoxContainer
	var explanation_container = vbox.get_node("ExplanationContainer") as VBoxContainer
	if not explanation_container:
		return
		
	var images_list = explanation_container.get_child(3) as VBoxContainer
	
	for path in paths:
		var image_item = create_explanation_image_item(path)
		images_list.add_child(image_item)

func _add_organ_system_item(container: VBoxContainer, organ_name: String = "", finding_type: String = "no-finding") -> void:
	var system_panel = PanelContainer.new()
	var system_hbox = HBoxContainer.new()
	system_hbox.add_theme_constant_override("separation", 10)
	system_panel.add_child(system_hbox)
	
	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "Organ System (e.g., Lungs, Heart, Liver)"
	name_edit.text = organ_name
	name_edit.custom_minimum_size = Vector2(200, 0)
	system_hbox.add_child(name_edit)
	
	var finding_label = Label.new()
	finding_label.text = "Finding:"
	system_hbox.add_child(finding_label)
	
	var finding_dropdown = OptionButton.new()
	finding_dropdown.add_item("No Finding")
	finding_dropdown.add_item("Benign Finding")
	finding_dropdown.add_item("Pathological Finding")
	finding_dropdown.custom_minimum_size = Vector2(180, 0)
	var finding_popup = finding_dropdown.get_popup()
	finding_popup.add_theme_font_size_override("font_size", 22)
	
	# Set initial selection based on finding_type
	match finding_type:
		"no-finding":
			finding_dropdown.selected = 0
		"benign":
			finding_dropdown.selected = 1
		"pathological":
			finding_dropdown.selected = 2
	
	system_hbox.add_child(finding_dropdown)
	
	var remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func(): system_panel.queue_free())
	system_hbox.add_child(remove_btn)
	
	container.add_child(system_panel)

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
		warning_dialog.dialog_text = "Please enter a case name before saving."
		warning_dialog.popup_centered()
		return
	
	if dicom_files.size() == 0:
		push_error("Please select DICOM files")
		warning_dialog.dialog_text = "Please select DICOM files before saving."
		warning_dialog.popup_centered()
		return
	
	current_case.set_case_name(case_name_edit.text)
	current_case.set_case_description(case_description_edit.text)
	
	# Collect questions
	var questions_array = Array()
	for child in questions_container.get_children():
		if child is PanelContainer:
			var vbox = child.get_child(0) as VBoxContainer
			var question_dict = Dictionary()
			
			var organ_dropdown = vbox.get_node("OrganDropdown") as OptionButton
			question_dict["organ_system"] = organ_dropdown.get_item_text(organ_dropdown.selected)
			var type_dropdown = vbox.get_node("TypeDropdown") as OptionButton
			var question_type_idx = type_dropdown.selected
			
			if question_type_idx == 0:
				question_dict["type"] = "free_text"
			elif question_type_idx == 1:
				question_dict["type"] = "multiple_choice"
			elif question_type_idx == 2:
				question_dict["type"] = "systematic_review"
			else:  # question_type_idx == 3
				question_dict["type"] = "mark_target"
			
			var question_edit = vbox.get_node("QuestionEdit") as LineEdit
			question_dict["question"] = question_edit.text
			
			if question_type_idx == 0:  # Free text
				var answer_edit = vbox.get_node("AnswerEdit") as TextEdit
				question_dict["expected_answer"] = answer_edit.text
			elif question_type_idx == 1:  # Multiple choice
				var mc_container = vbox.get_node("MCContainer") as VBoxContainer
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
			elif question_type_idx == 2:  # Systematic review
				var systematic_container = vbox.get_node("SystematicContainer") as VBoxContainer
				var systems_list = systematic_container.get_child(1) as VBoxContainer
				var organ_systems_findings = []
				
				for system_panel in systems_list.get_children():
					if system_panel is PanelContainer:
						var system_hbox = system_panel.get_child(0) as HBoxContainer
						var name_edit = system_hbox.get_child(0) as LineEdit
						var finding_dropdown = system_hbox.get_child(2) as OptionButton
						
						if name_edit.text.strip_edges() != "":
							var finding_type = ""
							match finding_dropdown.selected:
								0: finding_type = "no-finding"
								1: finding_type = "benign"
								2: finding_type = "pathological"
							
							organ_systems_findings.append({
								"organ_system": name_edit.text,
								"finding_type": finding_type
							})
				
				question_dict["organ_systems_findings"] = organ_systems_findings
			else:  # Mark target area
				# Get target annotation data
				if child.has_meta("target_annotation"):
					var target_data = child.get_meta("target_annotation")
					question_dict["target_annotation"] = target_data
					
					# Get tolerance with proper null checks
					var target_container = vbox.get_node("TargetAreaContainer") as VBoxContainer
					var tolerance_value = 50.0  # Default value
					
					if target_container:
						var tolerance_slider = target_container.get_node("ToleranceSlider") as HSlider
						if tolerance_slider:
							tolerance_value = tolerance_slider.value
					
					question_dict["tolerance"] = tolerance_value
				else:
					push_error("Target area question must have a target annotation set")
					warning_dialog.dialog_text = "Error: Target annotation not set for mark_target question."
					warning_dialog.popup_centered()
					return
			
			var image_ref_spin = vbox.get_node("ImageRefSpin") as SpinBox
			question_dict["image_index"] = int(image_ref_spin.value) if image_ref_spin else 0
			
			# Collect explanation data
			var explanation_container = vbox.get_node("ExplanationContainer") as VBoxContainer
			var explanation_text = (explanation_container.get_child(1) as TextEdit).text if explanation_container else ""
			
			var explanation_images = []
			if explanation_container:
				var images_list = explanation_container.get_child(3) as VBoxContainer
				if images_list:
					for image_item in images_list.get_children():
						if image_item.has_meta("image_path"):
							explanation_images.append(image_item.get_meta("image_path"))
			
			# Create nested explanation dictionary
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
		warning_dialog.dialog_text = "Failed to save case. Please check the console for more details."
		warning_dialog.popup_centered()

func show_save_notification() -> void:
	dicom_status.text = "✓ Case saved successfully!"
	dicom_status.add_theme_color_override("font_color", Color.GREEN)
	
	await get_tree().create_timer(3.0).timeout
	dicom_status.text = "Loaded %d DICOM files" % dicom_files.size()
	dicom_status.remove_theme_color_override("font_color")

func _on_back_button_pressed() -> void:
	queue_free()
	get_tree().change_scene_to_file("res://demo/main_menu.tscn")
