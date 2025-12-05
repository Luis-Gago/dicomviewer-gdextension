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
var pan_gesture_threshold: float = 1.0  # How much delta needed to trigger navigation

func _ready() -> void:
    # Make the control fill the entire screen
    set_anchors_preset(Control.PRESET_FULL_RECT)
    
    # Use unhandled input instead of input
    set_process_unhandled_input(true)
    
    # Ensure DicomViewer can receive mouse input
    dicom_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
    
    print("DicomViewer Metadata Check: ", dicom_viewer.get_metadata())
    setup_ui()
    setup_file_dialogs()
    
func setup_ui() -> void:
    # Window slider setup (typical range 1-4000)
    window_slider.min_value = 1.0
    window_slider.max_value = 4000.0
    window_slider.value = 400.0
    window_slider.step = 1.0
    
    # Level slider setup (typical range -1000 to +3000)
    level_slider.min_value = -1000.0
    level_slider.max_value = 3000.0
    level_slider.value = 40.0
    level_slider.step = 1.0
    
    update_labels()
    
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
    
func _on_open_files_button_pressed() -> void:
    file_dialog.popup_centered(Vector2i(800, 600))

func _on_open_folder_button_pressed() -> void:
    folder_dialog.popup_centered(Vector2i(800, 600))

func _on_file_dialog_files_selected(paths: PackedStringArray) -> void:
    print("Selected files: ", paths)
    load_files_from_paths(paths)

func _on_folder_dialog_dir_selected(dir_path: String) -> void:
    print("Selected folder: ", dir_path)
    status_label.text = "Scanning folder..."
    var files = scan_directory_for_dicom(dir_path)
    print("Found ", files.size(), " files")
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

func load_files_from_paths(paths: PackedStringArray) -> void:
    dicom_files.clear()
    
    status_label.text = "Loading files..."
    
    for path in paths:
        dicom_files.append(path)
    
    # Sort files alphabetically
    dicom_files.sort()
    
    print("Total files to load: ", dicom_files.size())
    
    if dicom_files.size() > 0:
        status_label.text = "Found %d files, loading first..." % dicom_files.size()
        current_file_index = 0
        load_current_file()
    else:
        status_label.text = "No files found"

func load_current_file() -> void:
    if current_file_index < 0 or current_file_index >= dicom_files.size():
        status_label.text = "No file selected"
        return
    
    var path = dicom_files[current_file_index]
    print("Attempting to load: ", path)
    
    # Check if file exists
    if not FileAccess.file_exists(path):
        status_label.text = "File not found: " + path.get_file()
        print("ERROR: File does not exist: ", path)
        return
    
    var success = dicom_viewer.load_dicom(path)
    
    if success:
        status_label.text = "Loaded: " + path.get_file()
        print("Successfully loaded: ", path)
        
        # Reset zoom when loading new file
        if is_zoomed_in:
            dicom_viewer.reset_view()
            is_zoomed_in = false
        
        # Only update sliders if user hasn't manually adjusted them
        if not user_adjusted_windowing:
            window_slider.value = dicom_viewer.get_window()
            level_slider.value = dicom_viewer.get_level()
            update_labels()
        else:
            # Apply the user's preferred window/level to the newly loaded image
            dicom_viewer.set_window_level(window_slider.value, level_slider.value)
        update_file_info()
    else:
        status_label.text = "Failed to load: " + path.get_file()
        print("ERROR: Failed to load DICOM file: ", path)
        print("This may not be a valid DICOM file, or DCMTK is not compiled in")

func update_file_info() -> void:
    if dicom_files.size() > 0:
        file_index_label.text = "File %d / %d" % [current_file_index + 1, dicom_files.size()]
    else:
        file_index_label.text = "No files loaded"

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
        # Reset zoom if mode is disabled while zoomed in
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
    if current_file_index > 0:
        current_file_index -= 1
        load_current_file()

func _on_next_file_button_pressed() -> void:
    if current_file_index < dicom_files.size() - 1:
        current_file_index += 1
        load_current_file()

# Windowing preset buttons
func _on_soft_tissue_button_pressed() -> void:
    user_adjusted_windowing = true
    dicom_viewer.apply_soft_tissue_preset()
    # Block signals while updating sliders to prevent feedback loop
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
    # Block signals while updating sliders to prevent feedback loop
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
    # Block signals while updating sliders to prevent feedback loop
    window_slider.set_block_signals(true)
    level_slider.set_block_signals(true)
    window_slider.value = dicom_viewer.get_window()
    level_slider.value = dicom_viewer.get_level()
    window_slider.set_block_signals(false)
    level_slider.set_block_signals(false)
    update_labels()
    status_label.text = "Applied Bone preset (W:1800 L:400)"

func zoom_into_position(click_pos: Vector2, zoom_factor: float) -> void:
    print("zoom_into_position called with position: ", click_pos, " factor: ", zoom_factor)
    
    # The DicomViewer C++ class creates a TextureRect as its first (and only) child
    # Let's check if DicomViewer has any children first
    print("DicomViewer children count: ", dicom_viewer.get_child_count())
    
    if dicom_viewer.get_child_count() == 0:
        print("ERROR: DicomViewer has no children!")
        return
    
    # Get the first child which should be the TextureRect
    var texture_rect = dicom_viewer.get_child(0) as TextureRect
    
    if not texture_rect:
        print("ERROR: First child is not a TextureRect!")
        print("First child type: ", dicom_viewer.get_child(0).get_class())
        return
    
    if not texture_rect.texture:
        print("ERROR: No texture loaded!")
        return
    
    print("TextureRect found, current scale: ", texture_rect.scale)
    print("TextureRect current position: ", texture_rect.position)
    
    # Get the texture size
    var texture_size = texture_rect.texture.get_size()
    
    print("Viewer size: ", dicom_viewer.size)
    print("Texture size: ", texture_size)
    print("Click position: ", click_pos)
    
    # Calculate the point in texture coordinates (before zoom)
    # This is the point on the texture that the user clicked on
    var texture_point = (click_pos - texture_rect.position) / texture_rect.scale.x
    
    print("Texture point (before zoom): ", texture_point)
    
    # Apply zoom
    texture_rect.scale = Vector2(zoom_factor, zoom_factor)
    
    # Calculate new position so that the clicked point stays under the cursor
    # new_position = click_pos - (texture_point * new_scale)
    var new_position = click_pos - (texture_point * zoom_factor)
    
    print("New scale: ", texture_rect.scale)
    print("New position: ", new_position)
    
    texture_rect.position = new_position
    
    print("Zoom applied successfully")

# Mouse input handling
func _on_dicom_viewer_gui_input(event: InputEvent) -> void:
    print("GUI Input received: ", event)
    
    # Handle pan gesture events (macOS trackpad scrolling)
    if event is InputEventPanGesture:
        var pg = event as InputEventPanGesture
        pan_gesture_accumulator += pg.delta.y
        
        # Navigate when accumulated delta crosses threshold
        if pan_gesture_accumulator <= -pan_gesture_threshold:
            _on_prev_file_button_pressed()
            pan_gesture_accumulator = 0.0
        elif pan_gesture_accumulator >= pan_gesture_threshold:
            _on_next_file_button_pressed()
            pan_gesture_accumulator = 0.0
        return
    
    # Handle traditional mouse wheel events (Windows/Linux)
    if event is InputEventMouseButton:
        var mb = event as InputEventMouseButton
        print("Mouse button event - Button: ", mb.button_index, " Pressed: ", mb.pressed, " Position: ", mb.position)
        print("Zoom mode active: ", zoom_mode_active, " Is zoomed in: ", is_zoomed_in)
        
        # Handle zoom mode clicks
        if zoom_mode_active and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
            print("Zoom mode click detected!")
            if is_zoomed_in:
                print("Zooming out...")
                # Zoom out - reset to original view
                dicom_viewer.reset_view()
                is_zoomed_in = false
                status_label.text = "Zoom Mode: Click on image to zoom in"
            else:
                print("Zooming in...")
                # Zoom in on clicked position
                zoom_center = mb.position
                zoom_into_position(zoom_center, ZOOM_FACTOR)
                is_zoomed_in = true
                status_label.text = "Zoom Mode: Click again to zoom out"
            get_viewport().set_input_as_handled()
            return
        
        # Handle mouse wheel for image navigation (only if not in zoom mode)
        if not zoom_mode_active:
            if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
                _on_prev_file_button_pressed()
                get_viewport().set_input_as_handled()
                return
            elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
                _on_next_file_button_pressed()
                get_viewport().set_input_as_handled()
                return
        
        # Left mouse button for dragging to adjust window/level (only if not in zoom mode)
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
        
        # Horizontal drag = window, Vertical drag = level
        var new_window = drag_start_window + delta.x * 2.0
        var new_level = drag_start_level - delta.y * 2.0
        
        window_slider.value = clamp(new_window, window_slider.min_value, window_slider.max_value)
        level_slider.value = clamp(new_level, level_slider.min_value, level_slider.max_value)

# Keyboard shortcuts - uses unhandled input to avoid conflicts with sliders
func _unhandled_input(event: InputEvent) -> void:
    # Handle keyboard shortcuts
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