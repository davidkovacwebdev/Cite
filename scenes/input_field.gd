extends LineEdit

var styleBox: StyleBoxFlat

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Create a unique copy of the normal stylebox
	var original_stylebox = get_theme_stylebox("normal")
	styleBox = original_stylebox.duplicate()
	
	# Apply the copied stylebox to this specific node
	add_theme_stylebox_override("normal", styleBox)
	add_theme_stylebox_override("focus", styleBox)

func reset_border():
	styleBox.border_color = Color.TRANSPARENT
	set_border_width(0, 0, 0, 0)

func success_border():
	styleBox.border_color = Color.SEA_GREEN
	set_border_width(5, 5, 5, 5)

func wrong_border():
	styleBox.border_color = Color.DARK_RED
	set_border_width(5, 5, 5, 5)
	
func set_border_width(top, right, bottom, left):
	styleBox.border_width_top = top
	styleBox.border_width_right = right
	styleBox.border_width_bottom = bottom
	styleBox.border_width_left = left
