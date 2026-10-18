extends Node2D

class_name DifficultyReveal

var used:bool = false
var sway_tween: Tween
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Area2D.input_event.connect(_on_area_input_event)
	$Area2D.mouse_entered.connect(_on_mouse_entered)
	$Area2D.mouse_exited.connect(_on_mouse_exited)
	
	# Start with description hidden
	$Description.modulate.a = 0
	if Global.run.current_game_mode == 1:
		$DifficultyIndicator.text = ""
		$Sprite2D.visible = false
		$Description.text = ""
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_area_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Global.run.current_game_mode == 0:
			if used != true:
				if Global.run.current_mana >= 10:
					Global.run.Mana.spend_mana(10)
					$DifficultyIndicator.text = str(Global.run.current_round.article_difficulty)
		
					used = true
					if has_node("Sprite2D"):
						$Sprite2D.visible = false
					# Hide the description
					$Description.visible = false
					# Hide the Area2D (so it's no longer clickable/hoverable)
					$Area2D.visible = false
					# Make sure CategoryName stays visible
					$DifficultyIndicator.visible = true
		else:
			pass
				
			
			
			
func _on_mouse_entered():
	# Fade in description
	create_tween().tween_property($Description, "modulate:a", 1.0, 0.1)
	
	# Start sway animation - faster version (only affect specific nodes)
	if sway_tween:
		sway_tween.kill()

	sway_tween = create_tween().set_loops()
	sway_tween.tween_property($DifficultyIndicator, "rotation_degrees", 3, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway_tween.parallel().tween_property($Sprite2D, "rotation_degrees", 3, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway_tween.parallel().tween_property($Area2D, "rotation_degrees", 3, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	sway_tween.tween_property($DifficultyIndicator, "rotation_degrees", -3, 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway_tween.parallel().tween_property($Sprite2D, "rotation_degrees", -3, 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway_tween.parallel().tween_property($Area2D, "rotation_degrees", -3, 0.8)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_mouse_exited():
	# Fade out description
	create_tween().tween_property($Description, "modulate:a", 0.0, 0.1)
	
	# Stop sway animation and return to normal rotation
	if sway_tween:
		sway_tween.kill()
	
	var return_tween = create_tween()
	return_tween.tween_property($DifficultyIndicator, "rotation_degrees", 0, 0.15)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return_tween.parallel().tween_property($Sprite2D, "rotation_degrees", 0, 0.15)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return_tween.parallel().tween_property($Area2D, "rotation_degrees", 0, 0.15)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
