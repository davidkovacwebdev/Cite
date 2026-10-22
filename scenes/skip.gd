extends Node2D

class_name Skip

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Area2D.input_event.connect(_on_area_input_event)
	$Area2D.mouse_entered.connect(_on_mouse_entered)
	$Area2D.mouse_exited.connect(_on_mouse_exited)
	
	# Start with description hidden
	$Description.modulate.a = 0.0

func _on_area_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		skip_round()

func skip_round(is_free: bool = false):
	skip_current_round(is_free)


# Also used by the single player board's skip buttons.
static func skip_current_round(is_free: bool = false):
	
		if Global.run.round_number == 1:
			Global.run.first_skipped = true
	# Only skip if we have skips available
#		Its important to end the round first due to the health and mana check for the first round
		Global.run.current_round.end_round()
		if is_free == false:
			Global.run.number_of_skips -= 1

func load_next_article():
	# Get the parent (Round node)
	var round_node = get_parent()
	
	# Find the current ArticleComponent sibling
	var current_article = round_node.get_node("ArticleComponent") # Direct child of Round
	
	# Remove the current article
	if current_article:
		current_article.queue_free()
	
	# Instantiate and add new article to the Round node
	var next_article_scene = load("res://components/ArticleComponent.tscn")
	var next_article = next_article_scene.instantiate()
	round_node.add_child(next_article)
	
	# Optionally: Increment round counter

func _on_mouse_entered():
	# Fade in description
	create_tween().tween_property($Description, "modulate:a", 1.0, 0.1)

func _on_mouse_exited():
	# Fade out description
	create_tween().tween_property($Description, "modulate:a", 0.0, 0.1)
