extends Control

@onready var title_label: Label = $CenterContainer/MainVBox/TitleSection/Title
@onready var subtitle_label: Label = $CenterContainer/MainVBox/TitleSection/Subtitle
@onready var welcome_title: Label = $CenterContainer/MainVBox/WelcomePanel/WelcomeVBox/WelcomeTitle
@onready var welcome_text: Label = $CenterContainer/MainVBox/WelcomePanel/WelcomeVBox/WelcomeText
@onready var cases_button: Button = $CenterContainer/MainVBox/CasesButton
@onready var contact_title: Label = $CenterContainer/MainVBox/ContactPanel/ContactVBox/ContactTitle
@onready var contact_name: Label = $CenterContainer/MainVBox/ContactPanel/ContactVBox/ContactName
@onready var contact_email: Label = $CenterContainer/MainVBox/ContactPanel/ContactVBox/ContactEmail
@onready var decoration_labels: Array = [
	$XRayDecorations/TopLeftXRay,
	$XRayDecorations/TopRightXRay,
	$XRayDecorations/BottomLeftXRay,
	$XRayDecorations/BottomRightXRay
]

var base_viewport_width: float = 1152.0  # Reference size for scaling

func _ready() -> void:
	# Connect to viewport size changes
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# Initial scaling
	_on_viewport_size_changed()

func _on_viewport_size_changed() -> void:
	var viewport_size = get_viewport_rect().size
	var scale_factor = viewport_size.x / base_viewport_width
	scale_factor = clamp(scale_factor, 0.5, 2.0)  # Limit scaling range
	
	# Scale fonts dynamically
	title_label.add_theme_font_size_override("font_size", int(42 * scale_factor))
	subtitle_label.add_theme_font_size_override("font_size", int(16 * scale_factor))
	welcome_title.add_theme_font_size_override("font_size", int(20 * scale_factor))
	welcome_text.add_theme_font_size_override("font_size", int(14 * scale_factor))
	cases_button.add_theme_font_size_override("font_size", int(20 * scale_factor))
	contact_title.add_theme_font_size_override("font_size", int(14 * scale_factor))
	contact_name.add_theme_font_size_override("font_size", int(13 * scale_factor))
	contact_email.add_theme_font_size_override("font_size", int(13 * scale_factor))
	
	# Scale button minimum size
	cases_button.custom_minimum_size = Vector2(300 * scale_factor, 60 * scale_factor)
	
	# Scale decoration emojis
	for label in decoration_labels:
		label.add_theme_font_size_override("font_size", int(80 * scale_factor))

func _on_cases_button_pressed() -> void:
	get_tree().change_scene_to_file("res://demo/case_selector_ui.tscn")