# dicom_viewer_ui.gd
extends Control

# UI References
@onready var dicom_viewer: DicomViewer = $HSplitContainer/LeftPanel/DicomViewer
@onready var file_dialog: FileDialog = $FileDialog
@onready var folder_dialog: FileDialog = $FolderDialog
@onready var window_slider: HSlider = $HSplitContainer/VBoxContainer/WindowControl/WindowSlider
@onready var level_slider: HSlider = $HSplitContainer/VBoxContainer/LevelControl/LevelSlider
@onready var window_label: Label = $HSplitContainer/VBoxContainer/WindowControl/WindowLabel
@onready var level_label: Label = $HSplitContainer/VBoxContainer/LevelControl/LevelLabel
@onready var file_index_label: Label = $HSplitContainer/VBoxContainer/FileInfo/FileIndexLabel
@onready var status_label: Label = $HSplitContainer/VBoxContainer/StatusLabel
@onready var aspect_ratio_label: Label = $HSplitContainer/VBoxContainer/ImageInfo/AspectRatioLabel
@onready var modality_label: Label = $HSplitContainer/VBoxContainer/ImageInfo/ModalityLabel
@onready var notes_text: TextEdit = $HSplitContainer/LeftPanel/BottomPanel/MarginContainer/VBoxContainer/TextEdit
@onready var zoom_mode_button: Button = $HSplitContainer/VBoxContainer/ZoomControls/ZoomModeButton

# DICOM series management
var dicom_files: Array[String] = []
var current_file_index: int = -1

# Mouse dragging for window/level adjustment
var is_dragging: bool = false
var drag_start_pos: Vector2
var drag_start_window: float
var drag_start_level: float

# Zoom mode state
var zoom_mode_active: bool = false
var is_zoomed_in: bool = false
var zoom_center: Vector2 = Vector2.ZERO
const ZOOM_FACTOR: float = 2.5

# Track if user has manually adjusted window/level
var user_adjusted_windowing: bool = false

# Pan gesture accumulation for macOS trackpad
var pan_gesture_accumulator: float = 0.0
var pan_gesture_threshold: float = 1.0

# Performance optimization
var is_loading: bool = false
var pending_file_index: int = -1

func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    set_process_unhandled_input(true)
    
    dicom_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
    dicom_viewer.gui_input.connect(_on_dicom_viewer_gui_input)
    
    setup_ui()
    setup_file_dialogs()
    
func setup_ui() -> void:
    window_slider.min_value = 1.0
    window_slider.max_value = 4000.0
    window_slider.value = 400.0
    window_slider.step = 1.0
    
    level_slider.min_value = -1000.0
    level_slider.max_value = 3000.0
    level_slider.value = 40.0
    level_slider.step = 1.0
    
    update_aspect_ratio_label()
    update_labels()
    
func setup_file_dialogs() -> void:
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.use_native_dialog = true
    file_dialog.add_filter("*.dcm ; *.DCM", "DICOM Files")
    file_dialog.add_filter("*", "All Files")
    
    folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
    folder_dialog.use_native_dialog = true
    
func _on_open_files_button_pressed() -> void:
    file_dialog.popup_centered(Vector2i(800, 600))

func _on_open_folder_button_pressed() -> void:
    folder_dialog.popup_centered(Vector2i(800, 600))

func _on_file_dialog_files_selected(paths: PackedStringArray) -> void:
    load_files_from_paths(paths)

func _on_folder_dialog_dir_selected(dir_path: String) -> void:
    status_label.text = "Scanning folder..."
    var files = scan_directory_for_dicom(dir_path)
    if files.size() > 0:
        load_files_from_paths(files)
    else:
        status_label.text = "No files found in folder"

func scan_directory_for_dicom(dir_path: String, recursive: bool = true) -> PackedStringArray:
    var found_files = PackedStringArray()
    
    var dir = DirAccess.open(dir_path)
    if dir == null:
        push_error("Failed to open directory: " + dir_path)
        status_label.text = "Failed to open directory"
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

func load_files_from_paths(paths: PackedStringArray) -> void:
    dicom_files.clear()
    status_label.text = "Loading files..."
    
    for path in paths:
        dicom_files.append(path)
    
    dicom_files.sort()
    
    if dicom_files.size() > 0:
        status_label.text = "Found %d files, loading first..." % dicom_files.size()
        current_file_index = 0
        load_current_file()
    else:
        status_label.text = "No files found"

func load_current_file() -> void:
    if is_loading:
        pending_file_index = current_file_index
        return
    
    if current_file_index < 0 or current_file_index >= dicom_files.size():
        status_label.text = "No file selected"
        return
    
    var path = dicom_files[current_file_index]
    
    if not FileAccess.file_exists(path):
        status_label.text = "File not found: " + path.get_file()
        return
    
    is_loading = true
    
    var success = dicom_viewer.load_dicom(path)
    
    if success:
        status_label.text = "Loaded: " + path.get_file()
        
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
        
        if not user_adjusted_windowing:
            # Use modality-specific preset
            dicom_viewer.apply_modality_preset()
            window_slider.set_block_signals(true)
            level_slider.set_block_signals(true)
            window_slider.value = dicom_viewer.get_window()
            level_slider.value = dicom_viewer.get_level()
            window_slider.set_block_signals(false)
            level_slider.set_block_signals(false)
            window_label.text = "Window: %.0f" % window_slider.value
            level_label.text = "Level: %.0f" % level_slider.value
        else:
            dicom_viewer.set_window_level(window_slider.value, level_slider.value)
        update_file_info()
    else:
        status_label.text = "Failed to load: " + path.get_file()
    
    is_loading = false
    
    if pending_file_index != -1 and pending_file_index != current_file_index:
        current_file_index = pending_file_index
        pending_file_index = -1
        call_deferred("load_current_file")

func update_file_info() -> void:
    if dicom_files.size() > 0:
        file_index_label.text = "File %d / %d" % [current_file_index + 1, dicom_files.size()]
    else:
        file_index_label.text = "No files loaded"

func update_aspect_ratio_label() -> void:
    var aspect_ratio = dicom_viewer.get_pixel_aspect_ratio()
    if aspect_ratio == 1.0:
        aspect_ratio_label.text = "Aspect Ratio: 1:1"
    else:
        aspect_ratio_label.text = "Aspect Ratio: %.2f:1" % aspect_ratio

func _on_window_slider_value_changed(value: float) -> void:
    user_adjusted_windowing = true
    dicom_viewer.set_window_level(value, level_slider.value)
    update_labels()

func _on_level_slider_value_changed(value: float) -> void:
    user_adjusted_windowing = true
    dicom_viewer.set_window_level(window_slider.value, value)
    update_labels()

func update_labels() -> void:
    window_label.text = "Window: %.0f" % window_slider.value
    level_label.text = "Level: %.0f" % level_slider.value

func _on_zoom_mode_button_toggled(button_pressed: bool) -> void:
    zoom_mode_active = button_pressed
    if button_pressed:
        status_label.text = "Zoom Mode: Click on image to zoom in"
        dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_CROSS
    else:
        status_label.text = "Zoom Mode disabled"
        dicom_viewer.mouse_default_cursor_shape = Control.CURSOR_ARROW
        if is_zoomed_in:
            dicom_viewer.reset_view()
            is_zoomed_in = false

func _on_reset_button_pressed() -> void:
    dicom_viewer.reset_view()
    is_zoomed_in = false
    if zoom_mode_active:
        status_label.text = "Zoom Mode: Click on image to zoom in"
    else:
        status_label.text = "View reset"

func _on_prev_file_button_pressed() -> void:
    if is_loading:
        return
    if current_file_index > 0:
        current_file_index -= 1
        load_current_file()

func _on_next_file_button_pressed() -> void:
    if is_loading:
        return
    if current_file_index < dicom_files.size() - 1:
        current_file_index += 1
        load_current_file()

func _on_soft_tissue_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_soft_tissue_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Soft Tissue preset (W:400 L:40)"

func _on_lung_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_lung_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Lung preset (W:1500 L:-600)"

func _on_bone_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_bone_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Bone preset (W:1800 L:400)"

func _on_brain_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_brain_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Brain T1 preset (W:80 L:40)"

func _on_t2_brain_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_t2_brain_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Brain T2 preset (W:160 L:80)"

func _on_mammo_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_mammography_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Mammography preset (W:4000 L:2000)"

func _on_auto_button_pressed() -> void:
    user_adjusted_windowing = false
    dicom_viewer.apply_auto_preset()
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Auto preset from DICOM metadata"

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
            _on_prev_file_button_pressed()
            pan_gesture_accumulator = 0.0
        elif pan_gesture_accumulator >= pan_gesture_threshold:
            _on_next_file_button_pressed()
            pan_gesture_accumulator = 0.0
        return
    
    if event is InputEventMouseButton:
        var mb = event as InputEventMouseButton
        
        if zoom_mode_active and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
            if is_zoomed_in:
                dicom_viewer.reset_view()
                is_zoomed_in = false
                status_label.text = "Zoom Mode: Click on image to zoom in"
            else:
                zoom_center = mb.position
                zoom_into_position(zoom_center, ZOOM_FACTOR)
                is_zoomed_in = true
                status_label.text = "Zoom Mode: Click again to zoom out"
            get_viewport().set_input_as_handled()
            return
        
        if not zoom_mode_active:
            if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
                _on_prev_file_button_pressed()
                get_viewport().set_input_as_handled()
                return
            elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
                _on_next_file_button_pressed()
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
                _on_prev_file_button_pressed()
            KEY_DOWN, KEY_S:
                _on_next_file_button_pressed()
            KEY_R:
                _on_reset_button_pressed()
            KEY_Z:
                zoom_mode_button.button_pressed = not zoom_mode_button.button_pressed
            KEY_O:
                _on_open_files_button_pressed()
            KEY_F:
                _on_open_folder_button_pressed()
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


func _on_back_to_menu_button_pressed() -> void:
    get_tree().change_scene_to_file("res://demo/main_menu.tscn")