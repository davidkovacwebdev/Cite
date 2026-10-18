extends Control

var points:int
var number_of_rounds:int
var number_of_played_cards:int
var number_of_total_cards:int
var number_of_wrong_guesses:int
var number_of_combos: int
var min_blink_time: int
var max_blink_time: int


var quote:String
var quote_author:String


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_random_menu_quote()

	if Global.is_multiplayer_match:
		if Global.multiplayer_match_outcome == "won":
			%Title.text = "You Won!"
		else:
			%Title.text = "You Lost!"

	%Quote.text = "\"" + quote + "\"\n-" + quote_author
	number_of_rounds = Global.run.round_number
	min_blink_time = number_of_rounds * 15
	max_blink_time = number_of_rounds * 20
	var blink_time = randi_range(min_blink_time, max_blink_time)
	
	number_of_played_cards = Global.run.number_of_played_cards
	number_of_total_cards = Global.run.number_of_total_cards
	number_of_wrong_guesses = Global.run.number_of_wrong_guesses
	number_of_combos = Global.run.number_of_combos
	#points =  calculate_points()
	if not %Button.pressed.is_connected(_on_button_pressed):
		%Button.connect("pressed", _on_button_pressed)
	
	SoundManagerScript.stop_music()
	
	#%Points.text = "Total Points: " + str(calculate_points()) + " in " + str(number_of_rounds) + " rounds"
	%CardStats.text = "You played " + str(number_of_played_cards)+ " out of "+ str(number_of_total_cards) +" cards"
	%ComboNumber.text = "You had " + str(number_of_combos) + " Tripple x Combos"
	%WrongGuesses.text = "You had " + str(number_of_wrong_guesses) + " wrong guesses"
	$%BlinkTime.text = "You blinked " + str(blink_time) + " times, you should check that"
	%LastArticle.text = "Your demise was sealed when you failed miserably at guessing the "+ Global.run.current_round.article_title +" article"
	Global.selected_categories = []
	Global.selected_playsets = []
	Global.run.wikipedia_ids = []

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


#func calculate_points() -> int:
	## Base points
	#var round_points = number_of_rounds * 100
	#for i in range(1, number_of_rounds + 1):
		#round_points += (i * 150)
	#var combo_points = number_of_combos * 1000
	#var wrong_guess_penalty = number_of_wrong_guesses * 10
	#
	## Efficiency multiplier (avoid division by zero)
	#if number_of_played_cards == 0:
		#number_of_played_cards = 1
	#
	#var efficiency_multiplier = 1.0 + (float(number_of_total_cards - number_of_played_cards) / number_of_total_cards)
	#
	## Calculate total
	#var base_score = round_points + combo_points - wrong_guess_penalty
	#points = int(base_score * efficiency_multiplier)
	#
	#return max(points, 0)
	
	
func _on_button_pressed():
	get_tree().change_scene_to_file("res://Main/Main.tscn")
	
func get_random_menu_quote():
	var file_path = "res://assets/data/end_quotes.json"
	if FileAccess.file_exists(file_path):
		var content = FileAccess.get_file_as_string(file_path)
		var json_data = JSON.parse_string(content)
		
		if json_data is Array and json_data.size() > 0:
			var entry = json_data.pick_random() # Pick the whole object once
			quote = entry.get("text", "")
			quote_author = entry.get("author", "Unknown")
