extends CanvasLayer

@export var steps: Array[TutorialStep] = []
var current_index: int = 0

@onready var display = $PanelContainer/VBoxContainer/ScreenshotDisplay
@onready var label = $PanelContainer/VBoxContainer/DescriptionText

func _ready():
	update_page()

func update_page():
	var step = steps[current_index]
	display.texture = step.screenshot
	label.text = step.description
	$PanelContainer/VBoxContainer/HBoxContainer/PageIndicator.text = str(current_index + 1) + "/" + str(steps.size())
func _on_next_btn_pressed():
	if current_index < steps.size() - 1:
		current_index += 1
		update_page()

func _on_prev_btn_pressed():
	if current_index > 0:
		current_index -= 1
		update_page()
		
		


func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://Main/Main.tscn")
